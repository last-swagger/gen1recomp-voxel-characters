# Execution state

Durable state for autonomous execution of `ROADMAP_V2.md`. Written so that a
session that starts cold, or a second orchestrator, can pick up without asking
anyone. Updated as work lands, not as work is planned.

**Started 2026-08-10.** Branch `vida-v2`, nothing pushed.

## The two constraints that shape all scheduling

1. **LOVE is exclusive per machine.** `tools/tools_bin.sh` holds a lock, so only
   one tool per machine can render at a time. Two workstreams that both need
   LOVE must be on different machines, or serialised.
2. **A file has one owner at a time.** Isolated file scope is what made three
   parallel batches land with zero conflicts before. Every dispatch says
   explicitly what it may NOT touch.

## Compute pool

| Resource | Has LOVE | Used for |
|---|---|---|
| Mac Studio (this session) | yes | orchestration, LOVE work, integration |
| MacBook Pro (`ssh mbp`) | yes | second LOVE workstream, full battery |
| Subagents (Studio) | no | text-only work: translation, tests, scripts |
| `codex`, `gemini` CLI | no | independent review, second opinion |

MBP dispatch goes through the GUI session (`osascript` into Terminal), never
plain ssh: the CLI keeps credentials in the login Keychain and an ssh session
cannot unlock it. Symptom is "OAuth session expired", which is not an expired
token.

## Blocked on Kim, not worked around

| Item | What is needed | Why nobody else can |
|---|---|---|
| 1. Feed the judge | 30 A/B picks | It is his preference. That is the whole input. |
| 3. Release identity | PAT for `last-swagger` | Credential. `release_check.sh` is red on purpose. |
| Visual judgement | His eye on FOOTFALL, CAMERA FIT, FRONT SHAPE, TOP DOME, STEP WEIGHT | Taste, and he is the one who ships it. |

Everything else in the roadmap is executable without him.

## Workstreams

| # | Item | Owner | State | Gate |
|---|---|---|---|---|
| A | 19. Split the harness | MBP | dispatched | `check.sh` REGUA OK, 19 checks, output line-identical to before |
| B | 2. en-US, `main.lua` | subagent | dispatched | 603/603 + comments-only diff |
| C | 2. en-US, tests | subagent | dispatched | 603/603 + comments-only diff |
| D | 14/18. mutation command + battery skill | this session | in progress | new scripts, must catch a real mutation |
| E | 4. Trailer polish | this session | queued behind D | `trailer.sh` runs, shot list grows |

## Decisions taken without asking

- **Item 2 starts with `main.lua` and the tests, not the harness**, because
  workstream A is rewriting the harness and two owners on one file is the one
  thing that reliably produces conflicts. The roadmap already recommended this
  order for a different reason.
- **A comments-only diff is verified mechanically, not by review.**
  `tools/so_comentarios.lua` strips comments and string literals from both
  sides and requires the remainder to be byte identical. A translation that
  touches code fails the gate rather than depending on someone noticing.
- **The harness split is graded by output equality, not by structure.** The
  ruler's 19 result lines before and after must match. A split that is tidy and
  changes a number is a regression.

## Assumptions logged

- The MBP's git identity is fixed, but commits arriving from it are still
  amended to `last-swagger` before being kept, because old commits are not.
- Nothing is pushed, tagged or released. Local commits on `vida-v2` are routine
  and are what every workstream produces.
