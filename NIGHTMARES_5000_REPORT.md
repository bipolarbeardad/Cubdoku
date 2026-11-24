# NIGHTMARES 5,000-request production benchmark

## Protocol

Godot 4.7.2 ran the production Free Play provisioner in one isolated service instance. Sizes alternate 8×8, 9×9 and 10×10, using seeds 850000–854999. The run includes the expanded root catalog, up to eight promoted parents per size, the eight-edit request budget and a 32-successful-board exclusion window per size. The validated reserve is consulted only after fresh search exhausts. The production rules and difficulty gates are unchanged.

Fresh describes the generation source. A fresh build can reconstruct an older layout. Layout novelty uses terrain partitions up to label permutation, rotation and reflection. We measure both the first appearance within this sequence and novelty relative to the 462 layouts served by the historical stress test. Repeat distance is measured both by global request indices and by successful same-size boards, the unit used by the rolling window. Exact definitions retain original terrain IDs and the solution.

The Godot proof audit checks every distinct board and claimed answer with every existing chain-free technique subset and the full solver, then records the result for each served request. A separate Python search flood-fills the terrain and independently checks uniqueness, all bear rules and the no-singleton condition. Exact repeats with the same answer reuse the audit result. Audit time is excluded from generation time.

## Reproduction

```powershell
.\tests\run_isolated.ps1 -Godot $godot -Script res://tests/nightmares_stress.gd
.\tests\run_isolated.ps1 -Godot $godot -Script res://tests/nightmares_stress_proofs.gd -UserArguments @('<request-log-resource-path>', '--production')
python -B tests/nightmares_stress_report.py <request-jsonl> <proof-jsonl> <summary-json> --historical <old-request-jsonl> --window 32
```

The proof stage can also run in three independent size shards by appending 8, 9 or 10 after the production flag and combining the resulting proof JSONL files. Below, counts of repeated pairs include all pairs, while repeat events count only returns after a layout's first occurrence.

## Fulfillment, novelty and timing

| Size | Requests fulfilled | Fresh | Reserve | Distinct partitions | Repeat events | Novel vs. both earlier runs | Exact / symmetry-normalized bear arrangements |
|---|---:|---:|---:|---:|---:|---:|---:|
| 8×8 | 1,667 / 1,667 | 1,598 | 69 | 880 | 787 | 731 | 11 / 11 |
| 9×9 | 1,667 / 1,667 | 1,575 | 92 | 966 | 701 | 822 | 7 / 7 |
| 10×10 | 1,666 / 1,666 | 1,603 | 63 | 1,016 | 650 | 798 | 8 / 8 |
| **Total** | **5,000 / 5,000** | **4,776** | **224** | **2,862** | **2,138** | **2,351** | **26 / 26** |

Fresh construction supplied 95.52% of requests. Of those results, 2,805 were first appearances within this run and 1,971 reconstructed a partition already seen in the run. The reserve supplied 57 first appearances and 167 previous partitions. Compared with the original 462-board stress corpus alone, there were 2,425 novel partitions. The stricter novelty column excludes layouts seen in either that corpus or the later 432-request comparison.

| Size | Mean (ms) | Median (ms) | p95 (ms) | Worst (ms) | Total (s) |
|---|---:|---:|---:|---:|---:|
| 8×8 | 117.97 | 93.15 | 238.83 | 1,452.47 | 196.65 |
| 9×9 | 155.62 | 124.77 | 320.57 | 1,350.16 | 259.42 |
| 10×10 | 194.84 | 159.43 | 401.67 | 2,142.57 | 324.60 |
| **All** | **156.13** | **125.74** | **341.38** | **2,142.57** | **780.67** |

There were 224 fresh-budget exhaustions and zero reserve exhaustions. Fresh search recorded 4,474 structural rejections, 3,443 uniqueness rejections and 306 recent-layout rejections. Difficulty rejections comprised 626 classic shortcuts, 443 EXTRA HARD shortcuts and 405 chain stalls. Reserve selection recorded 24 recent-layout skips. Construction and selection were bounded by the production settings. Of 744.28 seconds spent in fresh processing, 710.14 seconds were spent in proof validation. Uniqueness took 16.07 seconds and structural validation took 4.42 seconds within fresh processing. Reserve processing took 32.16 seconds in total.

## Repetition and geometry

No partition returned within the 32-board window. The shortest return was 33 successful same-size boards, or 99 overall requests. Median same-size gaps were 214, 200 and 267.5 at 8×8, 9×9 and 10×10 respectively. There were 5,765 exact-definition pairs across the run and 60 reserve-sourced exact return events. The near metric counts pairs differing by one to four terrain-boundary edges after best symmetry alignment. It found 12,422, 12,037 and 8,207 near pairs respectively.

| Size | Boards with a region spanning opposite edges | Boards with at least one narrow region cell | Largest region | Large compact region occurrences |
|---|---:|---:|---:|---:|
| 8×8 | 593 | 1,667 | 32 | 19 |
| 9×9 | 405 | 1,667 | 32 | 1 |
| 10×10 | 698 | 1,666 | 44 | 0 |

A narrow connection is a cell whose removal disconnects its region. Large means at least twice the board width in cells. Compact means a circularity score of at least 0.55. Median region area was 7, 8 and 7 cells by size, and median perimeter divided by area was 2.18, 2.00 and 2.00. Full area, span, branch and perimeter distributions are in the machine-readable summary. Wide variation in partitions coexisted with limited bear arrangement diversity, especially at 9×9 and 10×10. The original stress run fulfilled 462/5,000 with 330 fresh and 132 reserve. The intervening 432-request comparison fulfilled 432/432 with 416 fresh and 16 reserve. This run extends the availability evidence under the rolling policy and also shows substantially more reconstructed layouts than were visible in the short run.

## Candidate acceptance

Fresh search accepted 4,776 of 14,473 classified edit attempts (33.00%). This denominator includes recent-layout rejections and counts each attempt once. It excludes request-level exhaustion flags and reserve lookups.

| Size | Accepted / classified edits | Structural rejections | Uniqueness rejections | Recent-layout rejections | Classic shortcut / EXTRA HARD shortcut / chain stall |
|---|---:|---:|---:|---:|---:|
| 8×8 | 1,598 / 4,708 (33.94%) | 1,346 | 1,156 | 118 | 212 / 178 / 100 |
| 9×9 | 1,575 / 5,098 (30.89%) | 1,576 | 1,282 | 99 | 217 / 182 / 167 |
| 10×10 | 1,603 / 4,667 (34.35%) | 1,552 | 1,005 | 89 | 197 / 83 / 138 |

## Independent validation and logical variety

All 5,000 served boards passed verification, with zero invalid acceptances. The Godot proof shards audited 2,862 distinct board/answer pairs and matched every deduction against the separately established answer after analysis. All 16 chain-free configurations stalled on each board, and the production proof solved every board. Python independently verified connectivity, the absence of singletons, all bear-placement rules and uniqueness.

| Size | Technique sequences | Cell-level traces | Opening eliminations min / median / max | Total steps min / median / max | Dependency depth min / median / max | Implication links min / median / max |
|---|---:|---:|---:|---:|---:|---:|
| 8×8 | 185 | 311 | 5 / 6 / 49 | 16 / 22 / 31 | 10 / 15 / 20 | 5 / 7 / 9 |
| 9×9 | 118 | 324 | 6 / 7 / 63 | 17 / 24 / 31 | 11 / 15 / 20 | 5 / 7 / 13 |
| 10×10 | 127 | 224 | 7 / 16 / 55 | 20 / 23 / 43 | 10 / 15 / 20 | 5 / 7 / 11 |

The untouched-board audit found at least one shared-conflict deduction on every board, a Hall-set move on 4,855 boards, and a possible implication-chain move on 3,602. These numbers measure availability at the opening. The production trace does not enable the optional Hall or bounded-contradiction extensions. The mixed campaign report tests alternate solving orders and those alternate technique families. The most common single answer appeared 241, 416 and 267 times by size respectively, showing where arrangement diversity remains limited. The machine-readable summary includes technique usage by phase and consecutive trace similarity.

Reserve retrieval measured 143.57 ms mean, 122.46 ms median, 305.68 ms p95 and 1,128.25 ms worst. This is additional time after fresh search is exhausted. The finite benchmark verifies the recorded request sequence with the current reserve and reuse policy. Diversity and latency remain measurable concerns even though all requests were served.

The first 360 requests comprised 339 fresh and 21 reserve results, compared with 254 fresh and 106 reserve in the initial 360-request experiment. The runs used different seeds and inventory, so this is a descriptive comparison.

## Recorded artifacts

The raw journal is `.godot/isolated-1662b7eb42e749598cb89d8eb8764025/Godot/app_userdata/Cubdoku/nightmares-stress.jsonl`. The merged proofs are in `.godot/nightmares-5000-proofs.jsonl` and the verified statistics in `.godot/nightmares-5000-summary.json`.
