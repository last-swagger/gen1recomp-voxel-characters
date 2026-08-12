#!/usr/bin/env python3
"""Every sprite's alpha is 0 or 255, and nothing in between.

    python3 mods/voxel_characters/tools/alpha_gate.py

From the repo root. Standard library only, no LOVE and no display.

WHY THIS EXISTS, and the source is worth naming: it comes from an outside
specification, the "Kanto HD-Voxel Engine Pipeline v2.0", which proposed
upscaling the art and then binarising the alpha channel because "semitransparent
edges become ghost blocks on the Z axis". That observation is correct and it is
the one thing in that document this project did not already have covered.

A voxel builder extrudes geometry from a texture's opaque region. A pixel at
alpha 128 is neither in nor out: depending on how each face is sampled it can
produce a face that is drawn but see-through, which reads as a hole in a solid
body, or a face that is skipped on one side and kept on the other, which reads
as a one-pixel crack. Neither is a bug in the builder. Both are a bug in the
input.

IT IS ALREADY TRUE, BY ACCIDENT AND NOT BY CONTRACT. Measured across the whole
sprite set the day this was written: alpha takes exactly the values 0 and 255,
and nothing else. The extractor produces that because it decodes a 2bpp source
where a pixel is either the transparent index or one of three tones -- there is
no partial coverage to represent.

So this gate does not fix anything. It stops something: the day an anti-aliased
sprite arrives, from an upscaler or a hand-edited sheet or a different importer,
the failure would appear as geometry artifacts far from the cause, and whoever
saw it would go looking in the mesh builder.
"""

import os
import struct
import sys
import zlib

SPRITES = os.path.join("assets", "generated", "sprites")


def load_alpha(path):
    """Every alpha byte of an 8-bit PNG, whatever its colour type.

    Deliberately narrow: it reads alpha and nothing else, so it cannot be
    quietly repurposed into a second half-built image reader. The full decoder
    lives in measure_regions.py.
    """
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos, idat, hdr, trns = 8, b"", None, None
    while pos < len(data):
        (ln,) = struct.unpack(">I", data[pos:pos + 4])
        typ = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
        if typ == b"IHDR":
            hdr = struct.unpack(">IIBBBBB", body)
        elif typ == b"IDAT":
            idat += body
        elif typ == b"tRNS":
            trns = body
        pos += 12 + ln
    w, h, depth, ctype, _, _, interlace = hdr
    canais = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}
    if depth != 8 or interlace != 0 or ctype not in canais:
        raise ValueError("depth %d colour type %d interlace %d is outside what "
                         "this reader will guess at" % (depth, ctype, interlace))
    bpp = canais[ctype]
    stride = w * bpp
    raw = zlib.decompress(idat)
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

    if ctype == 6:      # RGBA
        return [out[i] for i in range(3, len(out), 4)]
    if ctype == 4:      # grey + alpha
        return [out[i] for i in range(1, len(out), 2)]
    if ctype == 3:      # palette: alpha comes from tRNS, absent entries opaque
        if trns is None:
            return [255] * (w * h)
        return [trns[p] if p < len(trns) else 255 for p in out]
    return [255] * (w * h)   # 0 and 2 carry no alpha at all


def main():
    if not os.path.isdir(SPRITES):
        print("  no sprite directory at %s; nothing to check" % SPRITES)
        print("ALPHA GATE SKIPPED: the sprite cache is derived from the ROM and "
              "is not in the repository")
        return 0

    folhas = sorted(n for n in os.listdir(SPRITES) if n.endswith(".png"))
    if not folhas:
        print("ALPHA GATE FAILED: the sprite directory exists and is empty, so "
              "this gate would pass by having nothing to look at")
        return 1

    problemas, lidas, valores = [], 0, {}
    for n in folhas:
        try:
            alphas = load_alpha(os.path.join(SPRITES, n))
        except Exception as e:
            problemas.append("%s could not be read: %s" % (n, e))
            continue
        lidas += 1
        ruins = 0
        for a in alphas:
            valores[a] = valores.get(a, 0) + 1
            if a not in (0, 255):
                ruins += 1
        if ruins:
            problemas.append(
                "%s has %d pixel(s) with partial alpha. A voxel builder extrudes "
                "from the opaque region, so a half-transparent pixel is neither "
                "in nor out: it becomes a face that is drawn and see-through, or "
                "one kept on one side and skipped on the other. The artifact "
                "shows up in the geometry, far from this file" % (n, ruins))

    if problemas:
        for p in problemas[:8]:
            print("  " + p)
        if len(problemas) > 8:
            print("  ... and %d more" % (len(problemas) - 8))
        print("ALPHA GATE FAILED: %d problem(s)" % len(problemas))
        return 1

    print("alpha gate ok: %d sheet(s), alpha takes only %s"
          % (lidas, " and ".join(str(v) for v in sorted(valores))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
