#!/usr/bin/env python3
"""Measures authored regions against the real sprite (roadmap T2.1, slice 2).

    python3 mods/voxel_characters/tools/measure_regions.py red
    python3 mods/voxel_characters/tools/measure_regions.py --check

From the repo root. Standard library only, no LOVE and no display: it decodes
the PNG itself with zlib, because the whole value of this file is being able to
run on every commit rather than only on a machine with a screen.

WHY THIS EXISTS. Slice 1 declared Ash's regions by name and deliberately did not
say where they were, on the grounds that pixel bounds written before anything
can check them are invented numbers. This is the thing that can check them.

WHAT IT MEASURES, and the list is short on purpose. Only facts that follow from
the pixels without interpretation:

  bbox        first and last opaque row and column, per frame
  lightFree   the run of rows from the top whose opaque pixels contain no
              light tone at all. FROM THE FRONT that is exactly the cap crown,
              because the light tone is the face. FROM BEHIND there is no face,
              so the same measurement runs down to the hands, and the number is
              still a fact but is no longer the cap. The field is named for what
              it measures rather than what it means, and the sheet says which
              frames it may be read as hair
  footSplit   the lowest row whose silhouette is two separated horizontal runs.
              That is the gap between the legs reaching the floor
  bob         how far a frame's figure sits below the standing frame's

WHAT IT REFUSES TO MEASURE. Anything that needs interpreting a shape rather than
reading it. The head/shoulder line resolves cleanly from the front and the back,
where the shirt tone reaches the central columns, and does not resolve from the
side, where it never does; a rule tuned until the side frame agreed would be a
rule fitted to one sheet. The bag is worse: at 16x16 it is only arguably present
at all, and only in the back views. Both are left declared and unmeasured, which
claims less than a wrong number does.
"""

import os
import re
import struct
import sys
import zlib

RAIZ = os.path.join("mods", "voxel_characters")
SPRITES = os.path.join("assets", "generated", "sprites")
CELL = 16


def load_png(path):
    """Decode an 8-bit RGBA non-interlaced PNG. Refuses anything else loudly."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("%s is not a PNG" % path)
    pos, idat, hdr = 8, b"", None
    while pos < len(data):
        (ln,), typ = struct.unpack(">I", data[pos:pos + 4]), data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
        if typ == b"IHDR":
            hdr = struct.unpack(">IIBBBBB", body)
        elif typ == b"IDAT":
            idat += body
        pos += 12 + ln
    w, h, depth, ctype, _, _, interlace = hdr
    if (depth, ctype, interlace) != (8, 6, 0):
        raise ValueError(
            "%s is depth %d colour type %d interlace %d; this reader handles "
            "8-bit RGBA non-interlaced only, and guessing at the rest would "
            "produce a measurement nobody could trust"
            % (path, depth, ctype, interlace))
    raw = zlib.decompress(idat)
    stride, bpp = w * 4, 4
    out, prev, i = bytearray(), bytearray(stride), 0
    for _ in range(h):
        ft = raw[i]; i += 1
        line = bytearray(raw[i:i + stride]); i += stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if ft == 1:
                line[x] = (line[x] + a) & 255
            elif ft == 2:
                line[x] = (line[x] + b) & 255
            elif ft == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif ft == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        out += line
        prev = line
    return w, h, bytes(out)


def frame_rows(w, px, frame):
    """One frame as a list of rows; each row is a list of (tone or None)."""
    rows = []
    for y in range(CELL):
        gy = frame * CELL + y
        row = []
        for x in range(CELL):
            o = (gy * w + x) * 4
            row.append(None if px[o + 3] == 0 else (px[o], px[o + 1], px[o + 2]))
        rows.append(row)
    return rows


def runs(row):
    """Horizontal runs of opaque pixels."""
    out, start = [], None
    for x, p in enumerate(row):
        if p is not None and start is None:
            start = x
        elif p is None and start is not None:
            out.append((start, x - 1)); start = None
    if start is not None:
        out.append((start, len(row) - 1))
    return out


def measure(w, h, px):
    """Every frame of one sheet."""
    tones = {}
    for gy in range(h):
        for x in range(w):
            o = (gy * w + x) * 4
            if px[o + 3]:
                t = (px[o], px[o + 1], px[o + 2])
                tones[t] = tones.get(t, 0) + 1
    if not tones:
        raise ValueError("the sheet is entirely transparent")
    # The lightest tone present is the skin/highlight. On this art that is what
    # separates the cap from the face, and it is read from the sheet rather than
    # hardcoded so a repalette does not silently move every boundary.
    lightest = max(tones, key=lambda c: sum(c[:3]))

    out = {}
    for f in range(h // CELL):
        rows = frame_rows(w, px, f)
        ocupadas = [y for y, r in enumerate(rows) if any(p is not None for p in r)]
        if not ocupadas:
            out[f] = None
            continue
        top, bottom = ocupadas[0], ocupadas[-1]
        cols = [x for x in range(CELL)
                if any(rows[y][x] is not None for y in range(CELL))]

        # Rows from the top with no lightest-tone pixel. From the front this
        # stops where the face begins; from behind, where the hands appear.
        cap_fim = None
        for y in range(top, bottom + 1):
            if any(p == lightest for p in rows[y] if p is not None):
                break
            cap_fim = y

        # The feet: the lowest row split into two runs. Read from the bottom up
        # so a gap higher in the figure, between an arm and the body, is not
        # mistaken for the legs parting.
        split = None
        for y in range(bottom, top - 1, -1):
            if len(runs(rows[y])) >= 2:
                split = y
                break
            if len(runs(rows[y])) == 1 and y < bottom:
                break

        # MAY `lightFreeBottom` BE READ AS THE CAP ON THIS FRAME? That is a
        # measurable question, not a judgement, and leaving it unanswered was a
        # real hole: a sheet could claim the back view's number as the cap and
        # nothing would object.
        #
        # From the front the first light pixels are the FACE, which sits in the
        # middle of the cell. From behind there is no face, so the first light
        # pixels are the hands, at the edges. So: central means face means cap.
        cap_legivel = False
        if cap_fim is not None and cap_fim + 1 <= bottom:
            primeira = rows[cap_fim + 1]
            claras = [x for x, p in enumerate(primeira) if p == lightest]
            meio0, meio1 = CELL // 4, CELL - CELL // 4 - 1
            cap_legivel = bool(claras) and all(meio0 <= x <= meio1 for x in claras)

        out[f] = {
            "top": top, "bottom": bottom,
            "left": cols[0], "right": cols[-1],
            "lightFreeTop": top, "lightFreeBottom": cap_fim,
            "footSplit": split, "capReadable": cap_legivel,
        }
    base = out.get(0)
    for f, m in out.items():
        if m and base:
            m["bob"] = m["top"] - base["top"]
    return out


def declared(sheet):
    """The `measured` block out of an authored sheet, without running Lua."""
    path = os.path.join(RAIZ, "authored", "sheets", sheet + ".lua")
    if not os.path.exists(path):
        return None
    texto = open(path).read()
    bloco = re.search(r"measured\s*=\s*\{(.*?)\n  \}", texto, re.S)
    if not bloco:
        return None
    got = {}
    for m in re.finditer(
            r"\[(\d+)\]\s*=\s*\{([^}]*)\}", bloco.group(1)):
        f = int(m.group(1))
        campos = {}
        for k, v in re.findall(r"(\w+)\s*=\s*(-?\d+|nil)", m.group(2)):
            campos[k] = None if v == "nil" else int(v)
        got[f] = campos
    return got


CAMPOS = ["top", "bottom", "left", "right", "lightFreeBottom", "footSplit", "bob"]


def main():
    args = sys.argv[1:]
    modo_check = "--check" in args
    alvos = [a for a in args if not a.startswith("-")] or ["red"]
    problemas = 0

    for sheet in alvos:
        caminho = os.path.join(SPRITES, sheet + ".png")
        if not os.path.exists(caminho):
            print("  no sprite at %s" % caminho)
            return 1
        w, h, px = load_png(caminho)
        medido = measure(w, h, px)

        if not modo_check:
            print("%s: %d frames of %dx%d" % (sheet, h // CELL, CELL, CELL))
            for f in sorted(medido):
                m = medido[f]
                if not m:
                    print("  frame %d  empty" % f); continue
                print("  frame %d  rows %2d..%-2d  cols %2d..%-2d  lightFree %2d..%-4s "
                      "footSplit %-4s bob %+d  cap readable %s"
                      % (f, m["top"], m["bottom"], m["left"], m["right"],
                         m["lightFreeTop"], m["lightFreeBottom"], m["footSplit"],
                         m["bob"], "yes" if m["capReadable"] else "no"))
            continue

        esperado = declared(sheet)
        if esperado is None:
            print("  %s declares no measured block, so nothing was compared. A "
                  "sheet with regions and no measurements is the state this "
                  "gate exists to end" % sheet)
            problemas += 1
            continue
        for f in sorted(medido):
            m = medido[f]
            if m is None:
                continue
            d = esperado.get(f)
            if d is None:
                print("  %s frame %d is measurable and undeclared" % (sheet, f))
                problemas += 1
                continue
            for campo in CAMPOS:
                if campo not in d:
                    continue
                if d[campo] != m[campo]:
                    print("  %s frame %d: %s is declared %s and measures %s. The "
                          "sprite moved, or the number was hand-written"
                          % (sheet, f, campo, d[campo], m[campo]))
                    problemas += 1
        # hairFrames is a CLAIM about which frames' lightFreeBottom is the cap,
        # and it is checkable rather than a matter of opinion.
        texto = open(os.path.join(RAIZ, "authored", "sheets", sheet + ".lua")).read()
        mh = re.search(r"hairFrames\s*=\s*\{([^}]*)\}", texto)
        if mh:
            pedidos = [int(x) for x in re.findall(r"\d+", mh.group(1))]
            legiveis = sorted(f for f, m in medido.items() if m and m["capReadable"])
            for f in pedidos:
                if f not in legiveis:
                    print("  %s claims frame %d reads as the cap, and it does not: "
                          "the first light pixels there are at the edges of the "
                          "cell, which are hands, not a face. Readable frames are %s"
                          % (sheet, f, legiveis))
                    problemas += 1

        extra = [f for f in esperado if f not in medido]
        if extra:
            print("  %s declares frames %s that the sprite does not have"
                  % (sheet, extra))
            problemas += len(extra)

    if modo_check:
        if problemas:
            print("REGIONS FAILED: %d disagreement(s) with the real sprite"
                  % problemas)
            return 1
        n = sum(1 for s in alvos)
        print("regions ok: %d sheet(s) measured against the real sprite, every "
              "declared bound matches" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
