# Handoff, 2026-08-10

For a session starting with none of this context. Where the work is, what is
proven, what is waiting on a person, and how to run everything.

## State in one paragraph

**v1.6.0 is released and installable from inside the game.** Branch `vida-v2`
carries 100 unreleased commits on top of it, none of them pushed. **24 of the
27 roadmap items are closed**, and the three that remain are open for reasons
outside the code. Two new player-facing options landed today, both OFF by
default: `PART LAG` and `ATTENTION`. Everything else was tooling, tests, and
the defects that tooling found.

Read `docs/EXECUTION_STATE.md` for what landed and `docs/TRAPS.md` before
debugging anything. This file is the orientation; those two are the detail.

## Run everything

From the **repo root**, never from the mod directory.

```
bash mods/voxel_characters/tools/bateria.sh              ALL OF IT, in order
bash mods/voxel_characters/tools/bateria.sh --rapido     the half with no game
bash mods/voxel_characters/tools/mutantes.sh             are the checks checking?
bash mods/voxel_characters/tools/instala_hooks.sh        pre-commit runs the fast half
```

Green as of this handoff: **620/620 offline, REGUA OK with 20 checks, BATTERY
OK across every in-game gate, MUTANTES 5/5, chunk-local headroom 74.**

`release_check.sh` is RED on purpose. The core repo's own suite is red with 18
pre-existing failures, verified against a baseline without this mod; ignore it.

## What is waiting on Kim

1. **A personal access token for `last-swagger`.** All nine releases are signed
   by the personal account and a release author cannot be edited after
   creation. `tools/release.sh` is built and rehearsed end to end: it refuses a
   dirty tree, requires the battery AND the mutants green, takes the release
   body from CHANGELOG.md, and renames the package to `.zip` because the
   in-game updater cannot see a `.modpkg`. The day the token exists it is one
   command. **Rehearsal is the default; `--publicar` is required to publish.**
2. **His eye on two new options that ship OFF**, `PART LAG` and `ATTENTION`,
   plus the older FOOTFALL, CAMERA FIT, FRONT SHAPE and TOP DOME.
3. **One question that is genuinely his**, below.

## The question that is his to answer

**The judge and the critic disagree, and both are measured.**

The judge, fitted on his own 106 A/B choices, ranks `FRONT SHAPE` and
`TOP DOME` ABOVE off (78.7% out of sample against a 69.6% best-single-column
baseline, five-fold cross validated, margin more than twice the spread).

The critic, shown only rendered PNGs, argues against both. It reverse
engineered the mod's tone system from pixels alone, reporting non-front faces
at "0.91x the source pair" where `main.lua:424` says `front = 0.90`, and its
objection follows from that: those options manufacture up to six tones outside
that two-level system, all on surface the artist never drew.

They are not answering the same question. The judge reports what Kim picked;
the critic reports what is consistent with the art's own system. Kept in
`tools/juiz/dados/NOTAS_DO_CRITICO.md`. **This is deliberately not resolved by
any automated loop.**

## The generator loop is built and its critic does not pass its gate

`tools/juiz/gera.sh` proposes combinations of existing options, ranks them with
the judge, renders finalists. `tools/juiz/calibra.sh` grades a critic against
pairs Kim already decided and prints the baseline beside the agreement.

```
round 1   7 pairs   critic 42.9%   always-B 57.1%
round 2  16 pairs   critic 62.5%   always-B 62.5%
```

Round 1's pair set was broken and the CRITIC found it. Round 2 is clean and the
answer is a tie; with 16 pairs the standard error is about 12 points, so a tie
is all that can honestly be claimed. **The critic cannot drive anything yet,
and the gate is what says so.**

The cheapest next experiments, in order: the critic sees a PNG with no context.
It does not know the palette, does not know which surfaces are invented, and
has never been shown a pair Kim decided together with his reason. Any of those
three costs less than collecting more pairs.

## The rule this repository keeps re-learning

**A gate is not verification until it has been run against input that should
fail.** Today produced eight instances, and the two most useful are:

- **The comment-only gate had three separate defects**, all found by different
  means: a bare CR let a comment swallow real code (found by a different model
  family), a documented path spelling exited 0 without comparing a byte (found
  by an agent following the docs literally), and comparing line k to line k
  reported 2697 false changes on a correct translation (found by running it on
  real data).
- **The clip's negative gate was a coin flip**, proven against the ORIGINAL
  committed code: run twice on a key the mod does not have, it published once
  and refused once.

And the corollary that cost the most: **a gate that cries wolf on CORRECT input
is more dangerous than one that misses**, because it gets waived by the second
day and then it is not there at all.

## Four gates were intermittent, and running things in parallel is what exposed them

| Gate | Rate | Cause | Fix |
|---|---|---|---|
| menu M8 | 3 of 5 | measured PHASE: two photos a fixed interval apart | sweep a full period, keep the largest |
| probe_fp P4 | 2 of 4 | used samples whose own control floor was half the frame | discard those samples |
| the ruler | once | took no LOVE lock, ran beside another tool | it takes the lock |
| probe_fp again | once | **not reproduced**, recorded rather than chased | none yet |

**No threshold was lowered in any of them.** The number was never the problem.

Running the pieces by hand hides intermittency, because a human who sees a red
re-runs it and a green rerun ends the investigation. The first time three
things ran at once, three of these surfaced within an hour.

## Two machines and the lock

`ssh mbp` reaches the MacBook Pro, which runs the whole battery. Dispatch goes
through the GUI session, never plain ssh:

```
osascript -e 'tell application "Terminal" to do script "bash /tmp/mbp_runner.sh"'
```

The CLI keeps credentials in the login Keychain and an ssh session cannot
unlock it. The symptom is "OAuth session expired", which is not an expired
token. Code moves by `git bundle --all` plus `scp` plus `git fetch`, so nothing
is pushed. Any spec must say explicitly that the git repo IS
`mods/voxel_characters`, a nested repo with its own remote.

**LOVE is exclusive per machine** and the lock is now REENTRANT across a
process tree: whoever creates it exports `VC_TRAVA_DONO`, and a child that sees
an inherited value proceeds without taking anything. That fix exists because
giving the ruler a lock deadlocked it against its own call to `card.sh`.

## Standing rules that are not obvious from the code

- **Kim posts to Discord. Never me.** I prepare drafts.
- **Everything that is a project artefact is en-US.** Roadmap item 2 is DONE:
  a sweep for Portuguese function words in comments across every `.lua` and
  `.sh` returns nothing.
- **Every visual change new to the mod ships OFF.** Once the community has seen
  and approved one, on by default becomes the conservative choice.
- **Releases credit reporters by name and public text has no em dashes.**
- Local commits on a feature branch are routine. **Push, tag and release need
  Kim's word.**
- **Do not raise a threshold to make a light green.**
- **Never rotate a character in Y.** Side faces carry 0.0% art. `ATTENTION` is
  built entirely around this.
