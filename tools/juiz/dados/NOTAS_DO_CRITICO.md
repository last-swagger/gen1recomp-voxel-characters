# What the critic saw, round 2

Kept because the prose was worth more than the number, and because one claim in
it is verifiable and turned out to be right.

## It reverse engineered the mod's tone system from pixels alone

The critic never saw the code. From the rendered PNGs it reported:

> source sprite is 229 / 133 / black, and the standard non-front face tones are
> 209 and 121, exactly 0.91x the source pair. That is a coherent two-level
> system.

`main.lua` line 424:

    local OBJ_SHADE = { front = 0.90, back = 0.68, side = 0.78,
                        top = 1.0, bottom = 0.55 }

It read 0.91 where the constant is 0.90, off by one percent, having only ever
looked at images.

## Its objection, which is a design argument and not a preference

Every option it disliked spends tones OUTSIDE that two-level system:

- **run-step shading** (FRONT SHAPE, TOP DOME) manufactures 216, 204, 179,
  125, 117, 104: up to six invented tones, all on surface the artist never
  drew. Its counterexample is the pair where the same faces are painted flat
  in 209/121, which it called the best-looking image in the set.
- **top-face brightening** pushes to 255,132,132, BRIGHTER than the source
  sprite's lightest colour, so the brightest pixel on the character becomes
  invented surface rather than art.
- **gradients** put 13 distinct tones across 16 rows: invisible at gameplay
  scale, and continuous where this art is stepped.

## Why this is worth keeping next to the judge, which disagrees

The judge, fitted on Kim's own 106 choices, ranks FRONT SHAPE and TOP DOME
ABOVE off. The critic argues against both, for a reason that is checkable in
the source. They are not answering the same question: the judge reports what
Kim picked, the critic reports what is consistent with the art's own system.

That disagreement is data, and it is the most interesting thing either of them
has produced. It is also exactly the case the calibration gate exists to keep
out of an automated loop until somebody decides which one is right, and that
somebody is Kim.
