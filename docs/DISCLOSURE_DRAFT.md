# Disclosure draft: the authored character layer

**Status: DRAFT, not published, and nothing it describes has shipped yet.**
Roadmap T2.1 requires that "a release-note disclosure draft says exactly what is
now authored, in plain words, before any of it ships". This is that draft,
written while the honest answer is still *nothing*, on the grounds that it is
much easier to write an honest disclosure before there is anything to defend.

Kim publishes it or rewrites it. It is not published by any tool.

---

## The version for a release note

> **This mod still builds every character out of your own game's pixels.**
>
> Voxel Characters reads the sprites your copy of the ROM already contains and
> gives them depth. It does not ship replacement art, and turning the mod off
> leaves your game exactly as it was.
>
> Starting with this release the mod also carries a small **authored layer**:
> material we wrote rather than derived. Right now that layer contains
> **descriptions only and no pixels** — a list of which parts of each character
> sheet are the head, the bag, the feet, so that effects can follow the shape of
> a character instead of cutting it into equal bands.
>
> If that ever changes, this note changes with it, and the number below tells
> you the truth regardless of what any note says.

## The number that cannot be spun

The render harness reports provenance at the visible pixel level, and since
T2.1 it splits three ways instead of two:

```
  art%    pixels sampling the original sprite art
  auth%   pixels shipped WITH THE MOD
  top% / side% / base%   surface the mod computed
```

`auth%` prints on every line even though it is `0.0%` everywhere today. That is
deliberate: a number that shows up only once it is non-zero teaches nobody to
look for it, and the release that ships the first authored texel is exactly the
release where somebody should already know where to look.

`tools/authored_gate.lua` fails the battery if the authored layer's pixel count
is anything but zero, so this claim cannot quietly stop being true. When it is
meant to stop being true, that gate has to be edited on purpose, and the edit is
the moment this document gets rewritten.

## What the authored layer may and may not contain

Written now, while there is nothing to argue about.

**May:**

- **Region descriptions** — which rows and columns of a sheet are head, hair,
  body, bag, feet. This is the piece most likely to pay for itself: `PART LAG`
  currently cuts a character into four equal vertical bands found from cap rows,
  and a region map would let it cut along a bag strap instead.
- **Responsiveness** — a single number saying this character reads stiffer or
  livelier than average, so a sheet can be tuned without editing amplitudes that
  everyone shares.
- **Small guiding overlays** — eyes, a rim accent, a mask that steers where
  shading falls. Texels, not artwork.

**May not, and this is the line:**

- **Sprite replacement.** Not a redrawn character, not a higher-resolution
  version, not a "cleaned up" one. The schema has three overlay types and none
  of them can cover a sheet. Adding a fourth that could is not a code change, it
  is a change to what this mod is, and it needs Kim and a new disclosure.
- **Anything that makes an object alive.** Item balls, boulders, fossils and the
  Pokédex are pinned to zero life in the runtime because a general rule once
  made them pulse. The authored schema refuses living metadata on an object
  sheet, and the gate cross-checks every sheet's kind against that runtime list,
  so the two cannot drift into disagreeing.

## What has not been decided

- Whether the authored path ships as its own mode beside pure runtime, or
  eventually becomes the default. **Current assumption: its own mode, off by
  default, with pure runtime as the control.** Logged as reversible.
- Whether any authored pixel ships at all. That is Kim's call and this slice
  does not make it for him.
- How authored material interacts with the judge's features and the critic's
  objection about the art's two-level tone system. Open question, recorded in
  `tools/juiz/dados/NOTAS_DO_CRITICO.md`.
