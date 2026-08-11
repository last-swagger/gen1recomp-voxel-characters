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

# Round 3: the palette was not the missing thing

The cheapest of the three experiments the handoff proposed. The critic was given
the art's tone system before judging: the source pair 229 / 133 / black, the
non-front tones at 0.91x that pair, `OBJ_SHADE` at front 0.90, back 0.68, side
0.78, top 1.0, bottom 0.55, and the fact that top, side and bottom faces carry
0% of the artist's work. No per-pair hints: nothing about which options were on.

```
pairs                 15
critic (with palette) 60.0%   (9 of 15)
always-commonest      53.3%   (key: 7 A, 8 B)
margin                +6.7 points
standard error        +/- 12.6 points
95% interval          35% .. 85%, which contains the baseline
```

**Inconclusive, and the number is the least interesting part.**

## Seeing the difference did not help

The pairs were scored for how well the difference could be resolved at all,
before the answers were revealed:

```
high confidence   3/5 = 60%
medium            1/2 = 50%
low               5/8 = 62%
```

Being able to see what differed made no difference to being right. If the
palette were the missing knowledge, the pairs that could be seen clearly should
have been the ones it helped on.

## The critic answered 13 A and 2 B; Kim answered 7 A and 8 B

That is the finding. The palette rule, applied honestly, is heavily one-sided:
it prefers whichever side manufactures fewer tones on invented surface, and that
lands on one side far more often than Kim's choices do. Kim's picks are close to
even.

So this measured what round 2's notes already suspected. Giving the critic the
art's own system makes it more consistent with that system and no better at
predicting the person. **They are answering different questions, and more
context about the art does not close the gap.**

The remaining untried experiment is the third one, and it is now the only one
with a reason to expect anything: show the critic a pair Kim decided TOGETHER
WITH HIS REASON. That is the only one of the three that adds information about
the person rather than about the pixels.

## How this was run, including its weakness

The verdicts were written and checksummed before the answer key was fetched, so
the order cannot be argued with afterwards. The weakness is that a no-context
arm could not be run cleanly by the same critic on the same pairs: having formed
one set of judgements contaminates the second. Round 2's 62.5% against a 62.5%
baseline is the closest no-context reference and it is a different pair set.

`gabarito_r3.txt`, `veredito_r3.txt` and `confianca_r3.txt` hold the run.
