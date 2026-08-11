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

# Round 4 could not be run, and the reason is not a shortage of pairs

The third experiment is "show the critic a pair Kim decided TOGETHER WITH HIS
REASON". It needs an input that does not exist.

**No reason was ever recorded.** The laboratory writes a choice as

```
t=... folha=... pose=... frame=... clock=... rung=... yaw=... opcao=...
a=... b=... escolha=B | A: <state> | B: <state>
```

(`tools/render/lab.lua:571`). Timestamp, sheet, pose, frame, clock, camera rung,
yaw, which option was varied, its two values, the pick, and the two full option
states. A grep for any reason-like word across all 106 choices returns zero. The
pick is the entire record: Kim pressed a key and the tool wrote which side.

So the missing information cannot be recovered from the dataset, and the only
place it exists is Kim. Asking him was outside this round's contract, so the
honest outcome is a protocol rather than a number.

**Held-out pairs were NOT the blocker.** 76 of the 106 choices were never
selected by round 3's sampling (`prepara 30` steps by 3 through the file, taking
30, of which 15 survived the drops). There is more than enough unseen material
for a clean test set whenever there is something to test.

**And there is a second blocker worth naming, which is me.** After round 3 the
critic knows its own palette rule over-picks A and that Kim's picks are close to
even. Any improvement it shows now cannot be separated into "the exemplar
taught it something" and "it corrected a bias it had just been told about". A
critic that has seen a key is spent for that key's question. The next round
needs a critic that has not, which means a fresh session or a different model.

## The protocol for round 4, so it is turnkey when a reason exists

1. **Record the reason at the moment of choice.** One free-text field written by
   the laboratory alongside the pick. It has to avoid `|`, because
   `calibra.sh:132` splits the two states on that character, and it has to be
   optional so the 106 existing choices keep parsing. This is the only code
   change the experiment needs and it deserves its own gate: a parser test over
   the existing file plus one with a reason attached.
2. **Choose the exemplar from a pair whose key is already spent**, such as one
   from round 3 where the critic was wrong. A contaminated pair is exactly the
   right thing to teach with and exactly the wrong thing to test on.
3. **Test only on held-out**, drawn from the 76 never-sampled choices, via
   `VC_ESCOLHAS` pointing at a filtered file.
4. **Pre-register the decision rule in writing and checksum it** before seeing
   any test pair, so "the rule changed because of the exemplar" is auditable
   rather than asserted afterwards.
5. **Checksum the verdicts before fetching the key**, as round 3 did.
6. **Report the margin against always-commonest with its standard error**, and
   keep the critic out of the loop unless the margin clears it.
