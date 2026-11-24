# NIGHTMARES 5,000-request stress test

## Method

Godot 4.7.2 calls the same NIGHTMARES generation service as playable Free Play, using one uninterrupted in-memory exclusion set. Requests alternate 8×8, 9×9 and 10×10 in that order, with seed 850000 plus the zero-based request index. Each request keeps the existing budget of at most eight fresh boundary edits. On fresh exhaustion, the service scans the existing reserve for that exact size and revalidates the first unused qualifying board. Every returned layout is excluded up to relabeling, rotation and reflection. There is no reserve replenishment or reset in this run.

The request timing excludes the independent audit, scene rendering and UI. Fresh and reserve validation use the current NIGHTMARES gate. Instrumentation records candidate rejection counts and time without changing construction, budgets or difficulty rules.

The prior 360-request benchmark used different seeds and an isolated construction prototype. It fulfilled 254 requests with fresh edits and 106 with reserve boards. Its augmented-root trial fulfilled 283 fresh and 77 from reserve. The first 120 requests at each size in this run provide a like-sized prefix for comparison. These are descriptive comparisons because their inventories, starting roots and seeds differ.

## Verification and metrics

Python independently flood-fills each region and counts solutions up to two with a separate most-constrained-row search. The Godot analyzer is rerun from the layout alone. The accepted solution is supplied only to post-proof assertions, to compare the result and make sure no legitimate bear was excluded. All sixteen chain-free masks are tested from scratch per board. Reflection with reversed region IDs changes the scan order and supplies one alternative ordering. The Hall-only and bounded-contradiction variants are experimental and do not determine benchmark acceptance.

Opening means the trace up to the first confirmed bear. Midgame starts with that placement and ends when at least half the bears are confirmed. The rest is endgame. The initial move count refers to the first applicable analyzer tier. A second count checks each existing family independently, plus adjacency triples and one Hall witness. It deduplicates options by eliminated cells. These are demonstrated options rather than an enumeration of all possible inferences.

A near pair differs by one to four orthogonal region-boundary edges after the best rotation or reflection. An exact definition includes the original region labels and solution. Timing and spacing use global request indices. Trace similarity uses consecutive accepted boards of the same size and compares ordered technique IDs with a sequence-matching ratio from zero to one.

Region span is the width and height of the region's bounding box. A narrow connection is a cell whose removal disconnects its region. A branch cell has at least three same-region neighbors. The descriptive large-compact statistic counts area at least twice the board side and compactness of at least 0.55, using 4π × area / perimeter². These reporting thresholds have no role in puzzle acceptance.

## Fulfillment and reserve depletion

| Size | Requests | Fresh | Reserve | Unfulfilled | Fulfilled |
| --- | ---: | ---: | ---: | ---: | ---: |
| 8×8 | 1,667 | 72 | 48 | 1,547 | 120 |
| 9×9 | 1,667 | 84 | 41 | 1,542 | 125 |
| 10×10 | 1,666 | 174 | 43 | 1,449 | 217 |
| **All** | **5,000** | **330** | **132** | **4,538** | **462 (9.24%)** |

Fresh fulfillment was 6.60% of all requests. Of 4,670 fresh exhaustions, reserve lookup fulfilled 132 and returned 4,538 explicit exhaustion failures. All 360 original reserve layouts were used. Fresh edits had already produced 72, 79 and 77 of those layouts by size, so only 48, 41 and 43 were counted as reserve retrievals. Matching uses the same symmetry-independent layout identity as the exclusion set. The 545,875 already-used reserve entries skipped during scans are repeated checks, with zero repeated definitions served.

| Size | First unfulfilled | Last reserve | Last fresh | Fresh structure rejects | Fresh ambiguous rejects | Fresh gate rejects | Fresh used-layout skips |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 8×8 | 361 | 358 | 331 | 3,950 | 3,306 | 1,410 | 4,261 |
| 9×9 | 368 | 365 | 512 | 4,216 | 3,133 | 1,545 | 3,966 |
| 10×10 | 612 | 603 | 903 | 3,911 | 2,639 | 1,081 | 4,688 |
| **All** | **361** | **603** | **903** | **12,077** | **9,078** | **4,036** | **12,915** |

Gate rejections comprised 1,726 classic-solvable candidates, 1,216 triple-solvable candidates and 1,094 candidates stalled even with chains. Reserve validation rejected no eligible unused entry. The first 120 requests per size filled 360/360 with 262 fresh and 98 reserve, close to the earlier short runs. All 4,097 requests after request 903 went unfulfilled. The short prefix obscured this persistent depletion.

## Timing

| Size | Mean (ms) | Median (ms) | p95 (ms) | Worst (ms) | Total (s) | Fresh search phase (s) | Reserve phase (s) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 8×8 | 48.15 | 44.61 | 78.20 | 589.34 | 80.27 | 27.97 | 51.82 |
| 9×9 | 66.02 | 61.70 | 114.64 | 680.83 | 110.06 | 43.33 | 66.07 |
| 10×10 | 81.68 | 69.64 | 145.94 | 897.09 | 136.07 | 59.30 | 75.86 |
| **All** | **65.28** | **56.55** | **124.17** | **897.09** | **326.40** | **130.61** | **193.75** |

Repeated reserve scans dominated overall runtime. They spent about 183.27 s outside structural, uniqueness and proof validation, in inventory traversal and layout-key work. Within the fresh phase, proof gates cost 94.69 s, uniqueness 10.48 s and structure 4.34 s. Candidate proposal and key work accounted for most of the remaining 21.11 s. Reserve proof validation cost 10.33 s. The initial three root-validation calls totaled 1.81 s. Average request times were 103.73 ms for fresh successes, 102.97 ms for reserve successes and 61.39 ms for unfulfilled requests. The latter dominate the overall average. These instrumented runtime scans differ from the previous audit's in-memory prevalidated lookup and are not directly comparable.

## Logical proofs and openings

All 462 boards passed independent structural and uniqueness validation and the original NIGHTMARES gate. The analyzer regenerated their solutions solely from visible constraints, with zero invalid eliminations observed. No chain-free subset solved any board in its original orientation or in the reflected and region-reordered audit. All reflected proofs solved, and 373 changed their ordered technique sequence. That is evidence of alternative solving orders under this test, without a claim about every possible order.

Values below are minimum / median / maximum. Available moves at the initial scheduler tier are separate from all untouched-board move options found by the family probes.

| Size | Opening X cells | Opening steps | Initial tier moves | Untouched options | Untouched X cells | Total steps | Dependency depth | Implication links |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 8×8 | 5 / 6 / 46 | 1 / 1 / 19 | 1 / 2 / 4 | 4 / 13 / 18 | 16 / 31 / 35 | 16 / 19 / 28 | 11 / 14 / 18 | 5 / 5 / 9 |
| 9×9 | 6 / 7 / 57 | 1 / 1 / 21 | 1 / 2 / 3 | 5 / 14 / 23 | 22 / 41 / 54 | 17 / 23 / 30 | 11 / 17 / 19 | 5 / 9 / 13 |
| 10×10 | 7 / 16 / 44 | 1 / 2 / 12 | 1 / 3 / 4 | 7 / 20 / 32 | 39 / 54 / 69 | 22 / 23 / 43 | 11 / 15 / 20 | 5 / 7 / 9 |

| Production technique | Opening | Midgame | Endgame |
| --- | ---: | ---: | ---: |
| Region-to-line confinement | 826 | 610 | 49 |
| Line-to-region confinement | 50 | 317 | 0 |
| Candidate pairs | 27 | 627 | 0 |
| Shared conflicts | 247 | 2,011 | 17 |
| Three-group confinement | 43 | 178 | 0 |
| Adjacency triple | 60 | 607 | 0 |
| Implication chains | 104 | 818 | 0 |
| Forced placement in a row, column or region | 0 | 2,190 | 2,065 |

Shared conflicts include the immediate fatal-square case where assuming a bear removes every candidate in a required group. Untouched-board probes found shared conflicts on all 462 boards, adjacency triples on 367, pairs on 233, and implications on 411. Generalized Hall reservations were visible on 432. Adding only generalized Hall to a stalled chain-free proof produced zero further Hall moves or solved boards. These early reservations can be redundant by the time basic deductions are exhausted.

With bounded contradiction enabled in place of chains, all 462 puzzles solved without a blind guess. The alternative proofs used 528 recorded contradiction moves. These prove an assumed candidate impossible by emptying a required group after at most eight forced placements. They provide an alternative advanced explanation under the tested solver and do not establish an easier shortcut. The independent proof pass took 103.18 s in summed per-board audit time, separate from request timing.

## Terrain geometry

| Size | Area range / median | Largest region per board, range / median | Median width / height | Boards spanning opposite edges | Boards with narrow connections | Median branch cells per board | Median perimeter / area |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: |
| 8×8 | 2–31 / 7 | 15–31 / 16 | 3 / 3 | 62/120 | 120/120 | 21 | 2.20 |
| 9×9 | 2–30 / 7 | 15–30 / 23 | 4 / 3 | 44/125 | 125/125 | 32 | 2.20 |
| 10×10 | 2–43 / 7 | 23–43 / 28 | 3 / 3 | 90/217 | 217/217 | 40 | 2.00 |

| Size | Regions with 2 cells | 3–5 | 6–10 | 11 to below twice the side | At least twice the side | Large and compact |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 8×8 | 236 | 200 | 219 | 205 | 100 | 0 |
| 9×9 | 238 | 188 | 344 | 215 | 140 | 0 |
| 10×10 | 536 | 434 | 508 | 349 | 343 | 0 |

Every board's smallest region had two cells. Large regions were common but none met the compactness threshold used here. The 10×10 set has substantial area concentration, with a largest region of 28 cells on the median board. Branching and narrow passages are common even when a region occupies much of the board. The full per-area distributions and span statistics are in the machine-readable summary. These are geometry measurements without a claim about visual legibility or human enjoyment.

## Replayability and limits

| Size | Accepted layouts | Exact / symmetry-normalized answers | Most common answer | Near pairs / compared pairs | Near-pair request gap min / median / max | Technique signatures | Cell-level traces | Median adjacent trace similarity |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 8×8 | 120 | 6 / 6 | 34 | 171 / 7,140 | 3 / 72 / 291 | 29 | 46 | 0.629 |
| 9×9 | 125 | 6 / 6 | 24 | 137 / 7,750 | 6 / 105 / 414 | 38 | 56 | 0.565 |
| 10×10 | 217 | 7 / 7 | 34 | 214 / 23,436 | 3 / 198 / 771 | 54 | 76 | 0.522 |

There were zero exact definition repeats, material-label-only repeats, or rotation/reflection-only repeats. There are therefore no exact repeat gaps to report. Near pairs and shared traces still occur. An identical technique sequence may use different cells, and even the same cell-level deduction trace can occur on a different layout. Compared with the original 360-request benchmark, the full run added one exact answer at 8×8 and none at 9×9 or 10×10, despite serving 102 more puzzles. Fresh edits leave each root's bears intact. The limited root set therefore remains a practical cap on answer variety even when boundaries change.

Generation is suitable for bounded manual sampling with a finite stock. It did not sustain this uninterrupted 5,000-request sequence. Root diversification and a larger source of independently valid layouts remain open. Reserve scan overhead is a separate issue from stock exhaustion. No construction, acceptance or budget changes were made in this benchmark. Godot 4.7.2 passed the prototype, logical audit, advanced deduction, construction, uniqueness repair, schedule and calibration regressions in isolated user-data directories.

## Reproduction

```powershell
.\tests\run_isolated.ps1 -Godot $godot -Script res://tests/nightmares_stress.gd -UserArguments @('--legacy')
.\tests\run_isolated.ps1 -Godot $godot -Script res://tests/nightmares_stress_proofs.gd -UserArguments @('res://.godot/<first-run>/Godot/app_userdata/Cubdoku/nightmares-stress.jsonl')
python -B tests/nightmares_stress_report.py <request-jsonl> <proof-jsonl> .godot/nightmares-stress-summary.json
```

Both runners require a fresh isolated user-data directory. The benchmark and proof audit do not instantiate a game session or open a campaign save.
The historical policy flag preserves the original eligibility rules. Current builds cache reserve layout keys, so timings may differ from the archived run.
