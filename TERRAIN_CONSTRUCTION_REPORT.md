# Cubdoku terrain construction investigation

## Conclusion

Constructing terrain that eliminates alternative answers was the measured bottleneck. Bear-first generated 2,304 valid terrain partitions around 36 sampled legal arrangements. Of those, 2,177 admitted multiple solutions and six met EXTRA HARD. Regrowing terrain around the exact same bears as qualified catalog roots produced one qualified board in 2,304 proposals. Editing those roots produced 806. Holding the answers fixed rules out starting-answer choice as the explanation for that difference. The comparison conditions on already qualified terrain and does not separately identify the effects of inherited uniqueness, geometry or logical dependencies.

## Protocol

Godot 4.7.2 ran 12 requests per size with seeds 6,180,000 + 1,000 × side + request index. Each experimental request evaluates all 64 proposals, even after its first success. Production uses its unchanged 64-attempt ceiling and stops at first success. Every uniqueness check stops after two witnesses. Timing includes proposal construction and repair but excludes the additional correctness audits and journal writes.

- Bear-first fixes one randomized legal bear arrangement per request, grows seeded terrain, and repairs ambiguous candidates using bounded witnesses.
- Terrain-first samples seeds without specifying bears, grows orthogonally, and tries random boundary edits when ambiguous. Occupied seed draws use cyclic probing.
- Joint begins with terrain-first growth and changes which legal witness it protects during scored boundary edits. It can change both the material partition and the target answer in one lineage.
- Catalog edit and same-answer regrowth use the same 12 distinct published parents per size. Each edit starts from the original parent's terrain; each regrowth starts from its bear cells alone.

## Results

| Arm | Fulfilled at 7 / 8 / 9, out of 12 each | Qualified proposals | Structural | No answer | Multiple | Classic-solvable | Triple stall |
|---|---|---:|---:|---:|---:|---:|---:|
| Bear-first | 1 / 4 / 1 | 6 (0.26%) | 0 | 0 | 2,177 | 120 | 1 |
| Terrain-first | 0 / 1 / 0 | 1 (0.04%) | 918 | 394 | 982 | 9 | 0 |
| Joint | 2 / 1 / 0 | 3 (0.13%) | 717 | 382 | 1,170 | 32 | 0 |
| Catalog edit | 12 / 12 / 12 | 806 (34.98%) | 662 | 0 | 623 | 178 | 35 |
| Same-answer regrowth | 1 / 0 / 0 | 1 (0.04%) | 0 | 0 | 2,242 | 61 | 0 |
| Production | 12 / 12 / 12 | Stops at first success | — | — | — | — | — |

Terrain-first had 775 singleton and 143 connectivity failures. All 717 joint structural failures were singletons. All 662 catalog edit structural failures were connectivity failures. Joint changed its current intended answer on 412 edits, including one that qualified on 7×7. Removing a known alternative still left many ambiguous proposals. Production used 22 catalog edits among its 36 fulfilled requests. Detailed per-size counters are in the machine-readable summary.

## Geometry and reasoning

Production starts from randomized depth-first legal bear seeding. Its proof-first route limits frontier reachability to preserve a planned forcing order, and seeded frontier growth favors some adjacencies to avoid two-row swaps. Optional second-cell seeding can fail even when the bear permutation is legal. These are construction biases. The rulebook imposes no compactness, equal-area, shape or span limit. Root edits preserve the parent bears, transfer only one adjacent boundary cell, and independently validate global connectivity. EXTRA HARD's two-cell minimum is a difficulty constraint.

All structurally valid drafts in these arms had at least one orthogonal articulation cell. Valid region-area medians were generally 6, 7 and 8 by size. A 9×9 region reached 39 cells in the joint arm, 35 with terrain-first, 31 with bear-first and 27 with catalog edits. Opposite-edge regions occurred in every arm at every size. In structurally valid 9×9 drafts they occurred on 54/768 bear-first, 71/455 terrain-first, 97/498 joint, 149/548 catalog-edit and 51/768 same-answer-regrowth boards. The summary contains per-size area distributions, narrow-connection and branch counts, spans and perimeter/area metrics. It counts a descriptive large compact region only when area is at least twice the board width and circularity is at least 0.55. This measurement plays no part in acceptance.

Bear-first and same-answer regrowth each made 64 different valid canonical partitions per fixed answer. The catalog-edit arm accepted 494 canonical partitions across 806 results. None matched a shipped root. All 806 retained the parent answer and were two to four orthogonal boundary changes from it. Exact repeat pairs were 167, 152 and 124 by size. Near pairs with one to four boundary differences under best symmetry alignment were 323, 396 and 408. The experiment repeatedly drew from a single parent per request. The production sample had 36 separate layouts without exact or near pairs. The earlier fixed-catalog holdout had exact and near repeats across its longer mixed sequence.

The untouched-grid audit gathered eliminations available from the analyzer's per-family opening queries, before any bear was committed. Median counts for catalog edits were 17, 27 and 28 by size, versus 20, 22 and 24 for production. The accepted A, B and C samples were too small to compare reasoning quality. All 853 accepted EXTRA HARD records solved with triples enabled and stalled under all classic-only family subsets. Some solved under smaller triple-enabled masks. The previous holdout found 319/576 accepted edits shared the parent's technique order, and median dependency-depth change was zero. Current catalog edits sample random edges without protecting particular triple witnesses.

## Rendering and the NIGHTMARES probe

The renderer currently uses numeric logical region IDs as default material indexes. The engine consumes only the region partition. A real headless TileSet test reversed ten distinct texture sheets on a fixed 10×10 partition. All ten sheets changed assignments, while boundaries, solution and logical proof stayed identical. Generating the same EXTRA HARD seed before and after swapping the sheets returned the same definition. Reversing numeric logical labels is a separate intervention. All 853 accepted EXTRA HARD records retained their unique answer and gate after reversal, while 571 changed technique sequence. The Difficulty Analyst's independent reversal and cyclic tests of 120 holdout boards saw zero gate or solved-mask changes across 240 variants, alongside 91 technique-order changes and 61 depth changes. Technique-order and depth measurements are sensitive to scan order.

A supplemental 10×10 NIGHTMARES diagnostic used six roots with eight proposals per arm. Edits yielded 13/48 validated results and regrowth around those same bears yielded 0/48, all ambiguous. Edited failures were 14 connectivity, 17 ambiguity, three easier proofs and one chain stall. This is a directional diagnostic, with neither reserve use nor rolling-window history.

## Recommendation

Keep the existing hybrid. Among A, B and C, bear-first had the highest validated yield. Joint searched more intermediate answer arrangements and produced the broadest draft geometry, but only three drafts passed. The production hybrid delivered 35 distinct answers in 36 successes. Catalog edits reached 36 exact answers across 806 acceptances. The production hybrid therefore provided substantially more answer variation per served puzzle and lower observed close repetition. Root edits had the highest proposal yield and concentrate their outputs near validated parent terrain.

For the next comparison, keep the budget fixed and test boundary-transfer strategies that precheck donor connectivity and jointly eliminate several witnessed alternatives. Compare edits to already qualifying roots with edits to unique but easier partitions, using matched anchors where feasible. That would separate the effect of conditioning on uniqueness from conditioning on the target reasoning. Sample more independent root answers, then evaluate occasional reanchoring or two-cell moves against the existing catalog. The trials do not establish that any particular legal arrangement is unable to support a qualifying partition.

## Per-size measurements

| Size | Arm | Anchors proposed / valid | Exact / normalized unique answers | Exact / normalized accepted answers | Proof signatures |
|---|---|---:|---:|---:|---:|
| 7?7 | Bear-first | 12 / 12 | 12 / 12 | 1 / 1 | 1 |
| 7?7 | Terrain-first | ? | 5 / 5 | 0 / 0 | 0 |
| 7?7 | Joint | 201 / 201 | 25 / 19 | 2 / 2 | 2 |
| 7?7 | Catalog edit | 12 / 12 | 12 / 12 | 12 / 12 | 69 |
| 7?7 | Same-answer regrowth | 12 / 12 | 11 / 11 | 1 / 1 | 1 |
| 7?7 | Production | ? | 11 / 11 | 11 / 11 | 12 |
| 8?8 | Bear-first | 12 / 12 | 12 / 12 | 4 / 4 | 4 |
| 8?8 | Terrain-first | ? | 3 / 3 | 1 / 1 | 1 |
| 8?8 | Joint | 246 / 246 | 6 / 6 | 1 / 1 | 1 |
| 8?8 | Catalog edit | 12 / 12 | 12 / 12 | 12 / 12 | 75 |
| 8?8 | Same-answer regrowth | 12 / 12 | 9 / 9 | 0 / 0 | 0 |
| 8?8 | Production | ? | 12 / 12 | 12 / 12 | 12 |
| 9?9 | Bear-first | 12 / 12 | 7 / 7 | 1 / 1 | 1 |
| 9?9 | Terrain-first | ? | 2 / 2 | 0 / 0 | 0 |
| 9?9 | Joint | 221 / 221 | 2 / 2 | 0 / 0 | 0 |
| 9?9 | Catalog edit | 12 / 12 | 12 / 12 | 12 / 12 | 77 |
| 9?9 | Same-answer regrowth | 12 / 12 | 3 / 3 | 0 / 0 | 0 |
| 9?9 | Production | ? | 12 / 12 | 12 / 12 | 12 |

Joint proposed 79, 212 and 216 symmetry-normalized anchors by size. Terrain-first recorded 138, 198 and 173 distinct first witnesses across its drafts with at least one solution. Joint recorded 191, 237 and 226. Witness counts include ambiguous boards and are lower bounds because only the first witness per board is recorded. The only 7?7 root-regrowth acceptance retained its parent answer and was 29 boundary edges from its parent after best alignment.

| Size | Arm | Mean / median / p95 / max request time (ms) | Total uniqueness (ms) | Total logical gate (ms) |
|---|---|---:|---:|---:|
| 7?7 | Bear-first | 49.2 / 45.8 / 64.7 / 64.7 | 104.3 | 283.1 |
| 7?7 | Terrain-first | 24.9 / 21.5 / 42.6 / 42.6 | 56.3 | 14.7 |
| 7?7 | Joint | 30.7 / 28.6 / 49.0 / 49.0 | 76.2 | 111.7 |
| 7?7 | Catalog edit | 23.2 / 22.1 / 37.4 / 37.4 | 114.1 | 5343.8 |
| 7?7 | Same-answer regrowth | 50.1 / 45.7 / 74.2 / 74.2 | 89.0 | 160.8 |
| 7?7 | Production | 65.7 / 61.3 / 126.5 / 126.5 | 74.1 | 568.4 |
| 8?8 | Bear-first | 60.1 / 58.1 / 95.4 / 95.4 | 167.4 | 309.7 |
| 8?8 | Terrain-first | 36.2 / 31.1 / 88.5 / 88.5 | 102.6 | 41.1 |
| 8?8 | Joint | 35.0 / 35.0 / 50.5 / 50.5 | 116.3 | 48.0 |
| 8?8 | Catalog edit | 33.9 / 29.5 / 65.4 / 65.4 | 225.3 | 8923.6 |
| 8?8 | Same-answer regrowth | 65.0 / 51.2 / 168.6 / 168.6 | 134.3 | 110.9 |
| 8?8 | Production | 144.7 / 109.3 / 428.0 / 428.0 | 196.6 | 1310.5 |
| 9?9 | Bear-first | 66.3 / 50.1 / 141.8 / 141.8 | 324.9 | 111.8 |
| 9?9 | Terrain-first | 53.9 / 45.6 / 83.6 / 83.6 | 235.5 | 21.9 |
| 9?9 | Joint | 48.7 / 45.1 / 71.2 / 71.2 | 232.8 | 11.4 |
| 9?9 | Catalog edit | 35.3 / 33.6 / 52.3 / 52.3 | 528.6 | 10957.5 |
| 9?9 | Same-answer regrowth | 67.7 / 62.8 / 99.9 / 99.9 | 230.6 | 18.2 |
| 9?9 | Production | 137.3 / 114.9 / 294.5 / 294.5 | 451.2 | 831.3 |

Request times sum work up to first acceptance or exhaustion. Phase totals cover all proposals, including experimental work after first acceptance. Edit-only trials started with qualified roots. Their timings exclude root selection or catalog preparation costs outside the measured proposal loop and cannot establish a production speedup. Logical gates dominate total catalog-edit time.

## Reproduction and verification

Run the isolated Godot runner with res://tests/terrain_construction_trial.gd and a size argument of 7, 8 or 9. Pass the three output journals to python -B tests/terrain_construction_report.py .godot/terrain-construction-summary.json <7-log> <8-log> <9-log>. Run res://tests/terrain_construction_supplement.gd via the same runner with those three journal paths as res:// arguments. The supplemental NIGHTMARES journal can be verified using verify_board from tests/campaign_simulation_report.py.

Python independently flood-filled and enumerated all 853 accepted EXTRA HARD records and 13 accepted NIGHTMARES records. Godot completed every trial with zero verification failures. All seven regression suites passed, including the prototype's save isolation checks. No live data was accessed. Production generator, budgets, difficulty gates, existing assignments and rendering were unchanged.
