# Cubdoku 10,000-stage campaign simulation

## Protocol and limits

The isolated runner uses the deterministic campaign scheduler, including the existing five introductory assignments and the established stages 6–25 block. BASE through EXTRA HARD use the campaign generation service and its existing budgets. NIGHTMARES uses the current production provisioner at the scheduler's exact assigned size, with a separate recent-layout history, promoted roots and reserve view. This makes the current NIGHTMARES generator available to the simulation without changing live campaign generation. The scheduler stops at stage 10,000, truncating the last ordinary block after 15 entries.

Each successful stage writes its complete puzzle definition to the journal. An exhausted stage remains explicitly unfulfilled, and processing continues so later stages can be evaluated. No easier difficulty or alternate size substitutes for a failed assignment. The journal pins the recorded definition independently of subsequent generation. The live campaign does not yet use this 10,000-stage scheduler and provisioner, so the simulation does not establish live restart, reopening and replay at all 10,000 stages. Existing persistence regressions cover the current playable campaign.

The runner checks the original orientation against independent technique masks and confirms that every accepted proof matches the stored solution after analysis. It also reflects the board and reverses the region IDs to change the scan order using the same production technique family. NIGHTMARES additionally tests the collective chain-free suite in the reflected orientation, plus chain-free Hall and bounded-contradiction alternatives on the original board. These alternate proofs do not change acceptance. Python separately checks schedule quotas, sizes, locked givens, orthogonal connectivity, uniqueness and the NIGHTMARES rolling window.

Repetition compares only equal-sized boards. Exact definitions include difficulty, terrain IDs, solution and locked givens. Same-orientation partition matches with different labels, givens or tags are counted separately. The symmetry category excludes both same-orientation categories. Near pairs differ by one to four orthogonal terrain-boundary edges after best symmetry alignment. Segment pair counts assign cross-segment pairs to the later stage.

## Reproduction

```powershell
.\tests\run_isolated.ps1 -Godot $godot -Script res://tests/campaign_simulation.gd -UserArguments @('10000','campaign-10000.jsonl','current')
python -B tests/campaign_10000_report.py <campaign-jsonl> <summary-json>
```

The NIGHTMARES runner and campaign runner write separate user-data directories and never open a live save. Per-request logs are append-only, with flushes every 100 requests. The proof audit flushes each 50 verified boards. These journals preserve completed records after interruption. Resuming generation from a partial journal would also require reconstructing the provisioner's promoted roots and recent-layout history.

## Allocation and fulfillment

All 10,000 stage requests were recorded. **8,301 stages received a validated puzzle (83.01%), and 1,699 went unfulfilled.** The independent flood-fill and bounded solution enumeration verified 8,123 distinct board-and-answer pairs. The intro sequence was 1 (4×4, 1 locked), 2 (4×4, 0 locked), 3 (5×5, 0 locked), 4 (6×6, 0 locked), 5 (7×7, 0 locked).

| Difficulty | Requested | Validated | Fresh | NIGHTMARES reserve | BASE fallback | Unfulfilled | Validated / requested by size |
|---|---:|---:|---:|---:|---:|---:|---|
| BASE | 5 | 5 (100.00%) | 5 | 0 | 0 | 0 | 4×4 2/2, 5×5 1/1, 6×6 1/1, 7×7 1/1 |
| EASY | 3,498 | 3,007 (85.96%) | 3,007 | 0 | 0 | 491 | 5×5 1,235/1,237, 6×6 1,041/1,154, 7×7 731/1,107 |
| MEDIUM | 2,498 | 2,309 (92.43%) | 2,309 | 0 | 0 | 189 | 5×5 854/854, 6×6 825/837, 7×7 630/807 |
| HARD | 1,999 | 1,561 (78.09%) | 1,561 | 0 | 0 | 438 | 6×6 557/680, 7×7 525/657, 8×8 479/662 |
| EXTRA HARD | 1,000 | 419 (41.90%) | 419 | 0 | 0 | 581 | 7×7 174/339, 8×8 141/335, 9×9 104/326 |
| NIGHTMARES | 1,000 | 1,000 (100.00%) | 964 | 36 | 0 | 0 | 10×10 340/340, 8×8 319/319, 9×9 341/341 |
| **Total** | 10,000 | 8,301 (83.01%) | 8,265 | 36 | 0 | 1,699 | See difficulty rows |

The 499 complete blocks follow the 7:5:4:2:2 allocation, including the fixed first block. The final 15 stages allocate 3 MEDIUM, 5 EASY, 2 NIGHTMARES, 3 HARD, 2 EXTRA HARD. The scheduler provides this final prefix using the same block algorithm.

Request failures by recorded cause: 1,699 budget exhausted. Across the same first 5,000 scheduled requests, the prior benchmark fulfilled 3,671, compared with 4,155 in this run. All 4,501 of 4,501 lower-tier requests preserved their prior outcomes and definitions. This is a matched schedule comparison. NIGHTMARES uses the newer production provisioner.

The NIGHTMARES fresh/reserve counts were 312/7 at 8×8, 319/22 at 9×9 and 333/7 at 10×10. The reserve served every fresh-budget exhaustion and never exhausted. Among the other difficulty tiers, candidate logs recorded 188,472 multiple-solution rejections. EXTRA HARD alone recorded 40,881 multiple-solution rejections, 9,321 classic-solvable rejections and 309 triple stalls. These are candidate counts, while unfulfilled stages are request counts. EXTRA HARD had the lowest fulfillment at 41.90%, dropping to 31.90% at 9×9. Full campaign availability remains unverified because 1,699 stages lacked a validated assignment under the configured budgets.

## Generation performance

| Difficulty | Mean (ms) | Median (ms) | p95 (ms) | Worst (ms) | Total (s) |
|---|---:|---:|---:|---:|---:|
| BASE | 1.33 | 0.82 | 3.02 | 3.02 | 0.01 |
| EASY | 10.32 | 6.61 | 29.35 | 57.23 | 36.11 |
| MEDIUM | 10.36 | 6.64 | 29.14 | 96.24 | 25.87 |
| HARD | 44.58 | 37.20 | 104.97 | 213.24 | 89.12 |
| EXTRA HARD | 71.79 | 60.67 | 151.09 | 264.43 | 71.79 |
| NIGHTMARES | 81.30 | 76.72 | 121.25 | 788.76 | 81.30 |
| **Total** | 30.42 | 16.55 | 101.65 | 788.76 | 304.20 |

Timing includes all requests, including failures and reserve retrieval. Independent proof and repetition audits are outside generation timings. Per-size timing and rejection counters are in the summary JSON.

## Repetition across the campaign

| Pair category | Pairs | Min / median / max stage gap |
|---|---:|---:|
| Identical definition | 219 | 48 / 3,440 / 9,179 |
| Identical partition, different labels | 0 | — |
| Same labels, different givens or tags | 0 | — |
| Rotation or reflection only | 23 | 509 / 2,342 / 7,720 |
| Near partition | 2,791 | 2 / 2,076 / 9,844 |

| Stages | Validated | Distinct partitions in segment | First campaign appearance | Exact pairs | Near pairs | Distinct bear arrangements | Distinct reasoning signatures |
|---|---:|---:|---:|---:|---:|---:|---:|
| 1–2,500 | 2,075 | 2,069 | 2,069 | 6 | 249 | 606 | 1,584 |
| 2,501–5,000 | 2,080 | 2,071 | 2,037 | 40 | 515 | 636 | 1,629 |
| 5,001–7,500 | 2,077 | 2,065 | 2,017 | 64 | 846 | 618 | 1,594 |
| 7,501–10,000 | 2,069 | 2,060 | 1,978 | 109 | 1,181 | 618 | 1,590 |

The accepted sequence included 8,101 canonical partitions, 1,361 exact bear arrangements, 591 arrangements modulo symmetry, and 5,442 size-specific signatures. The most frequent answer appeared 238 times and the most frequent signature appeared 76 times. Signatures use the sequence of techniques and the smallest sufficient tested masks.

The closest exact pair was at stages 7,580 and 7,628, 48 stages apart. Exact pair provenance: Fresh → Fresh 188, Fresh → Validated reserve 17, Validated reserve → Fresh 9, Validated reserve → Validated reserve 5. The summary records both stage numbers and separation for every exact pair.

NIGHTMARES supplied 215 exact pairs, EASY supplied three, and MEDIUM supplied one. The closest overall pair was MEDIUM. The closest NIGHTMARES pair was at stages 1,742 and 2,490, 748 stages apart. The 32-board per-size policy applied to all NIGHTMARES results and had zero violations. Fresh-to-fresh pairs account for most repeats, consistent with construction revisiting partitions outside the window. Reserve reuse explains only five pairs with reserve results at both ends.

## Logical difficulty calibration

Each cell in the overlap table counts boards solved by that tested family mask. Restrictions, pairs, shared conflicts, triples and implication chains have mask values 1, 2, 4, 8 and 16. Basic reasoning is always active. Minimal masks remove every tested unnecessary family and are recorded individually in the summary.

| Assigned difficulty | Basic | + Restrictions | Restrictions + pairs | Restrictions + conflicts | All classic | Classic + triples | Extended with chains |
|---|---:|---:|---:|---:|---:|---:|---:|
| BASE | 5 | 5 | 5 | 5 | 5 | — | — |
| EASY | 0 | 3,007 | 3,007 | 3,007 | 3,007 | — | — |
| MEDIUM | 0 | 0 | 126 | 2,183 | 2,309 | — | — |
| HARD | 0 | 0 | 0 | 0 | 1,561 | — | — |
| EXTRA HARD | 0 | 0 | 0 | 0 | 0 | 419 | 419 |
| NIGHTMARES | 0 | 0 | 0 | 0 | 0 | 0 | 1,000 |

| Difficulty | Deduction steps | Candidate eliminations | Forced placements | Dependency depth | Pre-bear eliminations |
|---|---:|---:|---:|---:|---:|
| BASE | 4 / 5 / 7 | 12 / 20 / 42 | 4 / 5 / 7 | 4 / 4 / 7 | 0 / 0 / 0 |
| EASY | 6 / 8 / 14 | 20 / 30 / 42 | 5 / 6 / 7 | 3 / 7 / 12 | 0 / 0 / 29 |
| MEDIUM | 6 / 11 / 20 | 20 / 30 / 42 | 5 / 6 / 7 | 4 / 8 / 15 | 1 / 12 / 34 |
| HARD | 8 / 14 / 26 | 30 / 42 / 56 | 6 / 7 / 8 | 5 / 10 / 17 | 3 / 19 / 47 |
| EXTRA HARD | 10 / 18 / 27 | 42 / 56 / 72 | 7 / 8 / 9 | 6 / 12 / 21 | 4 / 26 / 53 |
| NIGHTMARES | 17 / 23.0 / 43 | 56 / 72.0 / 90 | 8 / 9.0 / 10 | 10 / 15.0 / 19 | 5 / 12.0 / 59 |

Ranges above show minimum, median and maximum. The machine-readable audit includes each family's usage and minimum masks, opening step counts, and implication-chain lengths. Forced placements measure the analyzer's deduction trace. The locked tutorial bear was added to the definition after validating the underlying puzzle.

| Difficulty | Reflected scan solved | Technique order changed |
|---|---:|---:|
| BASE | 5/5 | 0 |
| EASY | 3,007/3,007 | 470 |
| MEDIUM | 2,309/2,309 | 1,600 |
| HARD | 1,561/1,561 | 1,148 |
| EXTRA HARD | 419/419 | 256 |
| NIGHTMARES | 1,000/1,000 | 781 |

The chain-free reflected scan solved 0 NIGHTMARES boards. The alternate Hall extension solved 48, and bounded contradiction solved 1,000, of 1,000. Production implication paths ran from 5 to 13 links with median 7. These alternate proofs are evidence about available reasoning paths. Their use as classification criteria would require a separate calibration study.

The tested standard profile masks had zero lower-tier overlap where the assigned gate requires a simpler mask to stall. Individual reasoning families nevertheless transfer across categories. All EASY boards also solved with shared conflicts alone, 2,183 MEDIUM boards did the same, and every HARD board solved with pairs and shared conflicts without enabling explicit restrictions. The deduction-step and dependency-depth ranges overlap across adjacent tiers. These measurements support comparing alternative proof families during calibration. They leave human difficulty and enjoyment to playtesting.

## Regression and isolation

After both benchmark runs, all seven Godot 4.7.2 suites passed with zero failures: prototype, logical reasoning audit, advanced deductions, construction plan, uniqueness repair, campaign schedule and difficulty calibration. The prototype suite exercised save/load and replay behavior using its isolated profile. The two benchmark processes used different user directories and service instances. No live campaign saves or existing assignments were accessed or changed.

## Artifacts

The recoverable per-stage journal is `.godot/isolated-91a92a21da3c4056829870d57e3fc550/Godot/app_userdata/Cubdoku/campaign-10000.jsonl`. The verified statistics and exact repeat stage pairs are in `.godot/campaign-10000-summary.json`.
