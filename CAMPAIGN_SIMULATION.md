# 5,000-stage campaign simulation

## Multi-row ambiguity and proof reuse

The bounded ambiguity diagnostic samples the first ambiguous candidate on every fifth stage that encounters one. It compares each enumerated arrangement with the intended bear placement and decomposes the column permutation into disjoint cycles. A partition of `2+2` means two independent swaps. A partition of `4` means a four-row rotation. Both differ from the intended placement in four rows. The solver returns at most 12 arrangements per diagnostic, so the reported frequencies describe the sample rather than the full solution space.

In HARD generation, when the usual solver witness changes at least three rows, the repair can take one extra sample per seed lineage, requesting at most eight arrangements. The boundary scorer uses these multi-row witnesses alongside the existing swap witnesses. It can favor an edit that breaks more than one live witness without reviving a previously broken witness. It also keeps the last easier proof as a boundary-scoring hint across ambiguous intermediate layouts. The intended bear cells stay fixed, and every candidate still goes through the independent structure, bounded uniqueness and unchanged technique-subset gates. The repair sample cannot establish uniqueness.

The analyzer lazily builds the cell conflict graph once per run and filters it as candidates are eliminated. Campaign gates also continue a stalled trace when adding a lower-priority family. The existing technique order and available-choice metrics make that trace a valid prefix. Where the added family could change an earlier step, the gate still starts a separate proof. The regression fixture compares resumed reports with fresh reports, including deductions, choices and chain depth, and checks that the original prefix is stable.

### Bounded policy comparison

Stages 1–500 compared the previous planned policy with the combined sampling and proof-feedback change. The all-advanced pilot enabled it on HARD, EXTRA HARD and NIGHTMARES by removing the HARD-only guard in an isolated copy of the generator. All three runs used the same requests and budgets.

| Difficulty | Requests | Prior policy | Pilot with all advanced profiles | Selected policy |
| --- | ---: | ---: | ---: | ---: |
| HARD | 99 | 64 | 83 | 83 |
| EXTRA HARD | 50 | 24 | 19 | 24 |
| NIGHTMARES | 49 | 2 | 1 | 2 |

The HARD pilot made fewer ambiguous boards unique (328 versus 377), but more of those repairs passed the gate (53 versus 45). EXTRA HARD repair passes declined from 21 to 14, and NIGHTMARES repair passes declined from two to zero. Sampling and proof retention are enabled only for HARD. This comparison measures the two changes together and does not resolve their individual effects.

### Matched 5,000-stage results

The run used Godot 4.7.2, the same stages, schedule, seeds and candidate budgets as the prior planned run, with 32 BASE candidates and 64 for other profiles. It validated **3,671 of 5,000 (73.42%)**, up from 3,645 (72.90%). All 1,329 unfulfilled requests exhausted their budgets. There were zero unsupported requests, fallbacks and invalid acceptances. All accepted definitions passed the independent Python connectivity and uniqueness audit and the Godot technique-subset audit.

| Difficulty | Requested | Prior validated | Validated | Exhausted | Candidate acceptance | Prior / current summed request time (s) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| BASE | 5 | 5 | 5 | 0 | 38.462% | 0.010 / 0.009 |
| EASY | 1,747 | 1,501 | 1,501 | 246 | 3.721% | 24.232 / 26.443 |
| MEDIUM | 1,250 | 1,162 | 1,162 | 88 | 5.159% | 22.133 / 19.430 |
| HARD | 999 | 753 | 779 | 220 | 2.321% | 83.583 / 65.959 |
| EXTRA HARD | 500 | 209 | 209 | 291 | 0.814% | 63.651 / 54.644 |
| NIGHTMARES | 499 | 15 | 15 | 484 | 0.048% | 90.220 / 85.961 |
| **Total** | **5,000** | **3,645** | **3,671** | **1,329** | **2.389%** | **283.828 / 252.446** |

HARD validated 272/333 at 6×6, 266/337 at 7×7 and 241/329 at 8×8. It fulfilled 179 requests that previously exhausted their budgets, while exhausting 153 requests that had previously succeeded. The other five profiles reproduced the previous definitions, rejection counts and proof signatures. NIGHTMARES remains unreliable at **4/156 (2.56%)** on 8×8, **5/177 (2.82%)** on 9×9 and **6/166 (3.61%)** on 10×10.

| Profile | Multiple-solution rejections | Repairs reaching uniqueness | Passed assigned gate | Survival |
| --- | ---: | ---: | ---: | ---: |
| EASY | 27,553 | 3,138 | 674 | 21.5% |
| MEDIUM | 18,965 | 1,358 | 718 | 52.9% |
| HARD | 26,121 | 3,520 | 486 | 13.8% |
| EXTRA HARD | 20,866 | 2,031 | 140 | 6.9% |
| NIGHTMARES | 25,956 | 1,737 | 9 | 0.5% |
| **Total** | **119,461** | **11,784** | **2,027** | **17.2%** |

Multiple-solution rejections fell by 2,103, all in HARD. Of 110,649 ambiguity repair attempts, 98,865 remained ambiguous and 11,784 reached uniqueness. There were no missing edits or structural failures after repair. HARD repair survival rose from 479/3,590 (13.3%) to 486/3,520 (13.8%). Its largest post-repair rejection was a MEDIUM proof (2,066), followed by an EASY proof (461), a stall with all classic techniques (341), and competing single-family proofs (166). For NIGHTMARES, 1,558 unique repairs admitted a classic proof, 141 admitted a triple proof, and 29 still stalled with chains. These are properties of the resulting boards. An ambiguous parent does not establish a minimum proof against which to attribute a missing deduction. There were 30,517 difficulty-gate rejections overall, five failed constructions and eight candidates rejected by the prior BASE checks.

The ambiguity diagnostic surveyed 902 candidates, with 369 reaching the 12-solution cap. Of 6,034 sampled alternatives to the intended placements, 5,283 differed in at least three rows. Of those, 4,325 contained an individual cycle of length three or more. Frequent partitions included `2+2` (787), `2+3` (672), and single cycles of length four (662), five (601) and three (496). For the nearest sampled alternative on each surveyed board, 1,861 of 2,592 changed bear cells adjoined a region boundary. The alternatives can coexist with very different sets of region assignments. Breaking one swap does not address a separate rotation or establish uniqueness.

Measured difficulty validation decreased from **190.840 s to 147.652 s (22.6%)**, and summed request time decreased by **11.1%**. Other current phase totals were 8.674 s for construction, 25.282 s for structure, 46.319 s for uniqueness and 21.581 s for repair. The 0.317 s diagnostic and post-generation audit are excluded from request time. These are elapsed-time observations. The HARD result combines changes to candidate selection and proof cost. EXTRA HARD and NIGHTMARES had identical candidate outcomes, with lower measured difficulty-check times. EASY was slower in this run.

No accepted puzzle met a lower difficulty gate. All 779 HARD puzzles required the pair and shared-conflict families in the classic audit. All 209 EXTRA HARD puzzles required triples, and all 15 NIGHTMARES puzzles stalled under every chain-free subset. There were 3,669 distinct label-independent layouts, 928 bear arrangements and 3,480 proof signatures. The two exact pairs were stages 1,377/3,959 (separation 2,582) and 3,930/4,397 (separation 467). The 23 near pairs span 45 stages, using the existing one-to-four changed orthogonal boundary-edge metric in the given orientation.

The simulation wrote to the workspace and did not instantiate a campaign session. The live save hash changed during the first full-run interval, and the live Godot logs show separate windowed launches. The cause of the save write was not established. A subsequent isolated 100-stage rerun left the live file hash unchanged. No save recovery or edit was attempted.

To reproduce the selected policy and report:

```powershell
godot --headless --path . --script res://tests/campaign_simulation.gd -- 5000 res://.godot/multi-5000.jsonl multi_row
python tests/campaign_simulation_report.py .godot/multi-5000.jsonl --annotated .godot/multi-5000-annotated.jsonl
```

## Difficulty-guided construction

### Matched diagnostics

The previous full run logged 8,566 ambiguity repairs that reached uniqueness and 1,738 that passed their difficulty gate. It did not record the gate reason per repair. Rerunning the previous policy on the same first 300 requests reproduced its 193 accepted boards and recorded 464 repairs that reached uniqueness. Ninety passed the requested gate. In the 374 rejected repairs, the reasons differed by profile:

| Profile | What happened after the old repair made the board unique |
| --- | --- |
| EASY | 110 still needed more than restrictions, while 11 were already solvable with BASE. |
| MEDIUM | 20 could use restrictions alone, 11 still stalled with either single added family, and three fit both single-family proofs. |
| HARD | 66 could substitute a MEDIUM proof, 34 needed only restrictions, five fit both single-family proofs, and nine stalled with the classic families. |
| EXTRA HARD | 61 already had a classic proof and four stalled with triples. |
| NIGHTMARES | All 40 rejected unique repairs in this prefix had a classic proof, so the intended chain requirement was bypassed. |

An ambiguous parent has no established minimum proof. These counts identify what a repaired layout allowed or lacked, without attributing the loss of a specific deduction to an individual edit. The new policy targets these reasons at construction and repair time. HARD, EXTRA HARD and NIGHTMARES starts can defer growth edges that complete known two-row swaps, and surviving swaps become repair witnesses. The two highest profiles still use earlier proof feedback. Edits can now also add alternatives to region groups involved in a simpler triple, and HARD can use earlier restriction or single-family proofs as feedback. Some NIGHTMARES starts reserve two connected domino regions that support a five-link implication. The repair score discourages expansion into those regions. The analyzer derives any actual contradiction from the final terrain alone.

The construction fixture paired 40 starts at each size with the same RNG seed and identical intended bear placements. The planned variant used swap-aware growth alone in this diagnostic. The diagnostic solution cap was 12.

| Size | Connected starts, ordinary / swap-aware | Surviving two-row swaps, ordinary / swap-aware | Layouts hitting the solution cap, ordinary / swap-aware |
| --- | ---: | ---: | ---: |
| 6×6 | 40 / 40 | 86 / 25 | 23 / 4 |
| 8×8 | 40 / 40 | 209 / 32 | 40 / 29 |
| 10×10 | 40 / 40 | 345 / 58 | 40 / 38 |

The 38 planned 10×10 layouts that hit the cap contain at least 418 alternatives to their seed arrangements in aggregate. At most 58 can be two-row swaps, so at least 360 involve three or more rows. Preventing simple swaps helps but leaves substantial multi-row ambiguity on 10×10.

At the same 64-candidate budget, the planned 300-request pilot returned 218 boards versus 193 before. HARD rose from 24 to 39, EXTRA HARD from six to 14, and NIGHTMARES from zero to two. The planned pilot repaired 669 ambiguous layouts to uniqueness versus 464 in the control, and 111 went on to pass their gate versus 90. The fraction of unique repairs surviving the gate fell from 19.4% to 16.6%. The improvement came from more repairs reaching uniqueness and more absolute successes. Summed request time was 16.671 seconds versus 10.417 seconds for the prior benchmark's matched prefix.

### Full matched benchmark

Godot 4.7.2 fulfilled **3,645 of 5,000 (72.90%)**, up from 3,160 (63.20%). Each stage used the same seed, profile, size, and candidate budget as the prior optimization run. The BASE, EASY and MEDIUM definitions and outcomes were identical to that run. All 3,645 returned boards passed independent Python flood-fill and uniqueness verification and the Godot proof-subset audit. There were 1,355 exhausted requests, no unsupported requests, no fallbacks and no lower-difficulty acceptances. The live campaign save hash was unchanged.

| Difficulty | Requested | Prior fulfilled | Fulfilled | Exhausted | Candidate acceptance | Mean / p95 / worst (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| BASE | 5 | 5 | 5 | 0 | 38.462% | 2.009 / 4.830 / 4.830 |
| EASY | 1,747 | 1,501 | 1,501 | 246 | 3.721% | 13.871 / 41.219 / 117.293 |
| MEDIUM | 1,250 | 1,162 | 1,162 | 88 | 5.159% | 17.706 / 51.671 / 584.227 |
| HARD | 999 | 377 | 753 | 246 | 2.106% | 83.666 / 212.289 / 442.789 |
| EXTRA HARD | 500 | 108 | 209 | 291 | 0.814% | 127.302 / 287.171 / 862.606 |
| NIGHTMARES | 499 | 7 | 15 | 484 | 0.048% | 180.801 / 500.200 / 1,952.671 |
| **Total** | **5,000** | **3,160** | **3,645** | **1,355** | **2.339%** | **56.766 mean** |

| Difficulty | 4×4 | 5×5 | 6×6 | 7×7 | 8×8 | 9×9 | 10×10 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| BASE | 2 / 2 | 1 / 1 | 1 / 1 | 1 / 1 | — | — | — |
| EASY | — | 635 / 636 | 513 / 573 | 353 / 538 | — | — | — |
| MEDIUM | — | 423 / 423 | 419 / 424 | 320 / 403 | — | — | — |
| HARD | — | — | 267 / 333 | 263 / 336 | 223 / 330 | — | — |
| EXTRA HARD | — | — | — | 82 / 161 | 78 / 173 | 49 / 166 | — |
| NIGHTMARES | — | — | — | — | 4 / 156 | 5 / 177 | 6 / 166 |

Size cells show fulfilled / requested. NIGHTMARES remains unreliable at **8×8 (2.6%)**, **9×9 (2.8%)** and **10×10 (3.6%)**. This run demonstrates that a genuine chain-dependent 10×10 solution is achievable with the current techniques. The 8×8 yield slipped from five to four. The 10×10 mean rose from 114.591 to 210.702 ms and p95 rose from 327.539 to 559.163 ms.

### Candidate outcomes, repair survival and cost

Ambiguity rejected 121,564 candidates, down 24,896 from 146,460. Difficulty gates rejected 30,619 candidates, up from 24,829. Five initial constructions failed to fill the board and eight candidates failed the existing BASE checks. No evaluated higher candidate failed connectivity, singleton limits or legal-solution existence. Among the advanced profiles, HARD ambiguity fell from 44,175 to 28,224, EXTRA HARD from 25,824 to 20,866, and NIGHTMARES from 29,943 to 25,956. The bounded ambiguity median fell from 10 to eight, with 369 of 902 sampled candidates hitting the cap versus 435 of 905 previously. This survey still shows 527 nearest observed alternatives differing in two rows. It measures a deterministic capped sample rather than the full solution population.

| Profile | Became unique after repair | Still ambiguous | Unique and passed profile | Main rejection after uniqueness |
| --- | ---: | ---: | ---: | --- |
| EASY | 3,138 | 21,686 | 674 | 2,151 stalled with restrictions |
| MEDIUM | 1,358 | 15,681 | 718 | 366 already solved with restrictions |
| HARD | 3,590 | 22,326 | 479 | 2,087 could use a MEDIUM proof |
| EXTRA HARD | 2,031 | 17,953 | 140 | 1,835 already had a classic proof |
| NIGHTMARES | 1,737 | 23,117 | 9 | 1,558 already had a classic proof |
| **Total** | **11,854** | **100,763** | **2,020** | **9,834 unique repairs rejected at a gate** |

There were 112,617 ambiguity-repair opportunities, with no no-edit or structural failures. More repairs reached uniqueness, but gate survival fell from **20.3% to 17.0%**. The important gain was more absolute valid outputs, particularly at HARD and EXTRA HARD. Among the NIGHTMARES repairs that reached uniqueness, the gate also rejected 141 boards solved by triples and 29 that still stalled with chains. This distinguishes easier proofs bypassing the intended chain from the analyzer failing to finish a proof.

Summed request time rose from **187.588 s to 283.828 s (+51.3%)**. The measured phase totals were 7.830 s construction, 22.926 s structural checks, 41.266 s uniqueness, 18.433 s repair and 190.840 s difficulty validation. These exclude the separate 0.240 s ambiguity survey and post-generation audit. Difficulty checks were the largest measured cost as more candidates reached uniqueness. Timings are machine observations, not time limits.

### Minimum proof requirements and variety

The lower-profile proof results matched the previous run. Every HARD board required pairs and shared conflicts in the classic technique audit. EXTRA HARD had 209 chain-free proofs with triples and zero classic proofs. Its accepted traces used 138 three-group reservations and 93 adjacency-aware triple families at least once, with 22 boards using both. All 15 NIGHTMARES boards failed all 16 chain-free subsets. Six had shared conflicts + triples + chains as their only minimal subset. Stage 3,174 at 10×10 needed shared conflicts and chains, while stage 161 at 10×10 needed shared conflicts, triples and chains. These are minimum families among the tested subsets. The construction motif supplies no solution information to the analyzer. The proof is an explicit contradiction from a candidate to its negation, with no unrestricted search.

The run returned 3,643 distinct label-free layouts and complete definitions, 904 bear arrangements, and 3,453 reasoning signatures. Two exact repeats and 23 near pairs remained, all 5×5, with the same stage pairs and edge metric as the previous run. None came from the newly planned advanced boards. Proof traces ranged from 4 to 29 steps and dependency depths from 3 to 20.

Godot 4.7.2 passed construction and the reproducible 10×10 proof test, uniqueness repair, advanced deduction, schedule, calibration and full prototype regressions. The result remains short of 5,000. Multi-row ambiguity and preventing simpler proofs after a repair are the largest remaining obstacles for the hardest profile. Reproduce with:

```powershell
godot --headless --path . --script res://tests/construction_plan_test.gd
godot --headless --path . --script res://tests/campaign_simulation.gd -- 300 res://.godot/planned-control-300.jsonl optimized
godot --headless --path . --script res://tests/campaign_simulation.gd -- 5000 res://.godot/planned-5000.jsonl planned
python tests/campaign_simulation_report.py .godot/planned-5000.jsonl --annotated .godot/planned-5000-annotated.jsonl
```

## Uniqueness-guided optimization rerun

Godot 4.7.2 fulfilled **3,160 of 5,000 requests (63.20%)**, up from 3,014 (60.28%). The stage, board size, difficulty and seed matched the previous run for all 5,000 requests. The five introductory definitions also matched. Budgets stayed at 32 for BASE and 64 for all other categories. There were **1,840 budget exhaustions, zero unsupported requests and zero fallbacks**. Every returned board passed the independent Python connectivity and uniqueness checks and the Godot technique-subset audit. The live campaign save hash was unchanged.

### Ambiguity diagnosis

The optimized run rejected 146,460 candidates for multiple solutions, down 8,800 from 155,260. Difficulty gates rejected 24,829 candidates, up from 22,244 as more boards reached the uniqueness gate. The existing BASE checks rejected eight candidates. No higher candidate was rejected for broken connectivity, singleton limits or zero solutions.

The survey counted up to 12 solutions on the first ambiguous candidate of every fifth request. Of 905 samples, 181 had exactly two and 435 hit 12 or more. The bounded median was 10. The nearest sampled alternative differed from the intended placement in two rows in 528 cases. In that pattern, the two bears exchange columns while still covering each region once. The search is capped and returns solutions in deterministic row order, so the measured distance is to the nearest **observed** alternative.

| Side | Candidates with multiple solutions / evaluated | Ambiguity rate | Survey samples at cap / sampled |
| --- | ---: | ---: | ---: |
| 4×4 | 0 / 2 | 0.0% | — |
| 5×5 | 3,550 / 9,870 | 36.0% | 0 / 160 |
| 6×6 | 25,260 / 34,714 | 72.8% | 59 / 261 |
| 7×7 | 53,094 / 60,933 | 87.1% | 192 / 283 |
| 8×8 | 33,886 / 37,116 | 91.3% | 104 / 118 |
| 9×9 | 20,363 / 21,198 | 96.1% | 57 / 60 |
| 10×10 | 10,307 / 10,624 | 97.0% | 23 / 23 |

NIGHTMARES hit the cap in 82 of 87 samples and rejected 29,943 ambiguous candidates out of 31,715 evaluated. Profile and board size overlap in this schedule, so the figures do not isolate the effect of either. In the matched 500-request legacy control, 27 of 50 two-row swaps retained each displaced bear's original region and 23 exchanged regions. Across its 86 sampled alternatives, 201 of 269 displaced bear positions touched a different region along an orthogonal edge. This explains why a layout grown around one legal placement can leave many alternatives and why boundary edits often provide a direct way to remove them. Connectivity, anchor protection and singleton limits still constrain which edits can be used.

### Repair and timing

The generator scores connected boundary edits against up to eight remembered alternate arrangements, rewarding eliminations and penalizing the revival of a defeated alternative. It retains the same intended bears and rechecks structure and uniqueness after each applied edit. Large boards can retain one lineage for eight more attempts before regrowth. Ordinary uniqueness searches stop after two matches. The exhaustive solver skips branches missing a required region in the remaining rows and caches dead search states on 8×8–10×10. The analyzer never receives the witnesses.

| Profile | Repair attempts on ambiguous boards | Became unique | Still ambiguous | Unique and passed profile |
| --- | ---: | ---: | ---: | ---: |
| EASY | 24,824 | 3,138 | 21,686 | 674 |
| MEDIUM | 17,039 | 1,358 | 15,681 | 718 |
| HARD | 40,277 | 2,351 | 37,926 | 277 |
| EXTRA HARD | 24,639 | 1,047 | 23,592 | 64 |
| NIGHTMARES | 28,617 | 672 | 27,945 | 5 |
| **Total** | **135,396** | **8,566** | **126,830** | **1,738** |

No measured ambiguity repair failed to find an edit or failed a structural check. Of the repairs that made a board unique, 6,828 still failed the assigned difficulty gate. In the same first 500 requests, the legacy control validated 304 boards and the optimized path validated 326. Repairs yielded 762 unique boards in the control and 796 in the optimized run. Direct profile passes after those repairs rose from 151 to 164. Both paths used the same candidate budgets.

| Timed phase | Legacy first 500 (s) | Optimized first 500 (s) | Optimized 5,000 (s) |
| --- | ---: | ---: | ---: |
| Construction | 1.018 | 0.627 | 6.193 |
| Structural validation | 3.297 | 2.425 | 23.390 |
| Uniqueness | 7.397 | 3.697 | 34.294 |
| Boundary repair | 1.516 | 1.686 | 16.284 |
| Difficulty validation | 12.186 | 10.330 | 105.584 |

Phase times cover higher profiles. Totals exclude the separate bounded survey, which took 0.162 s in the full run. Summed request time, including overhead, fell from 229.804 to 187.588 s (18.4%). The all-request average fell from 45.961 to 37.518 ms. Difficulty validation is now the largest measured phase, while ambiguity remains the largest candidate rejection reason. Timings are single-machine observations.

### Coverage and proof results

| Difficulty | Requested | Prior validated | Validated | Exhausted | Candidate acceptance | Prior → current mean (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| BASE | 5 | 5 | 5 | 0 | 38.462% | 1.830 → 2.109 |
| EASY | 1,747 | 1,495 | 1,501 | 246 | 3.721% | 13.385 → 12.513 |
| MEDIUM | 1,250 | 1,141 | 1,162 | 88 | 5.159% | 15.045 → 15.465 |
| HARD | 999 | 306 | 377 | 622 | 0.734% | 59.898 → 61.645 |
| EXTRA HARD | 500 | 66 | 108 | 392 | 0.379% | 87.162 → 73.908 |
| NIGHTMARES | 499 | 1 | 7 | 492 | 0.022% | 168.710 → 95.887 |
| **Total** | **5,000** | **3,014** | **3,160** | **1,840** | **1.811%** | **45.961 → 37.518** |

| Difficulty | 4×4 | 5×5 | 6×6 | 7×7 | 8×8 | 9×9 | 10×10 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| BASE | 2 / 2 | 1 / 1 | 1 / 1 | 1 / 1 | — | — | — |
| EASY | — | 635 / 636 | 513 / 573 | 353 / 538 | — | — | — |
| MEDIUM | — | 423 / 423 | 419 / 424 | 320 / 403 | — | — | — |
| HARD | — | — | 170 / 333 | 103 / 336 | 104 / 330 | — | — |
| EXTRA HARD | — | — | — | 41 / 161 | 44 / 173 | 23 / 166 | — |
| NIGHTMARES | — | — | — | — | 5 / 156 | 2 / 177 | 0 / 166 |

The size cells show validated / requested. NIGHTMARES remains impractical at **8×8 (3.2%)**, **9×9 (1.1%)** and **10×10 (0%)**. Mean 10×10 request time fell from 292.027 to 114.591 ms, with an observed worst of 862.942 ms. Faster rejection alone did not yield a qualifying 10×10 board.

There were no lower-difficulty acceptances. All 377 HARD boards needed pairs and shared conflicts under the classic subsets. Every EXTRA HARD board needed triples in a chain-free proof. Seventy-four traces used three-group reservations and 47 used adjacency-aware triples, with 13 using both. All seven NIGHTMARES boards stalled under every chain-free subset and needed implication chains. Their successful stages were 303, 313, 1,907, 2,520, 2,560, 3,398 and 3,410. Across the run there were 2,969 distinct reasoning signatures, up from 2,808. Accepted traces ranged from 4 to 30 steps and chain depths from 3 to 21.

There were 3,158 distinct layouts and definitions, two exact repeats, and 23 near pairs across 45 stages. All close or exact repeats were 5×5 under the same comparison metric as the previous run. The exact pairs were stages 1,377 and 3,959 (2,582 apart), and 3,930 and 4,397 (467 apart). The previous run had zero exact repeats and 30 near pairs. The new run also produced 685 bear arrangements, up from 564.

Godot 4.7.2 passed the repair, advanced deduction, schedule, calibration and full prototype regression tests, including the existing BASE batch. To reproduce:

```powershell
godot --headless --path . --script res://tests/campaign_simulation.gd -- 5000 res://.godot/unique-5000.jsonl optimized
python tests/campaign_simulation_report.py .godot/unique-5000.jsonl --annotated .godot/unique-5000-annotated.jsonl
godot --headless --path . --script res://tests/campaign_simulation.gd -- 500 res://.godot/unique-legacy-pilot.jsonl legacy
```

## Prior unified generation benchmark

Godot 4.7.2 fulfilled **3,014 of 5,000 requests (60.28%)**, up from 1,731 (34.62%). All six profiles produced at least one validated board. There were **1,986 budget exhaustions, zero unsupported requests, and zero fallbacks**. Every accepted board passed a separate Python flood-fill and exhaustive minimum-candidate-row solver, as well as the Godot technique-subset audit. The schedule used the supplied stages 6–25 order, the existing five introductions, schedule seed `2601`, and puzzle seed `50000 + stage`. The budget stayed at 64 candidates for higher difficulties and 32 for BASE. The live campaign save hash was unchanged.

### Changes and prior failure diagnosis

The earlier 1,328 unsupported requests split into 329 missing board-size support, 159 missing techniques, and 840 missing both. Of the earlier rejected higher candidates, 125,683 lacked uniqueness and 25,769 exceeded singleton limits. Connected seed growth guaranteed at least one solution, so the old combined solution-count rejection was an ambiguity problem, not a no-solution problem. The lower-gate and incomplete-proof counters explained additional rejections. The 1,941 exhausted requests hit a candidate limit, not a wall-clock timeout. HARD previously both lacked an 8×8 path and rarely produced boards that passed exclusivity on 6×6 and 7×7.

The rerun uses the same seeded BASE path. Higher generation alternates proof-based starting layouts and connected growth, extends each required non-singleton region, and tries connected boundary edits. A known alternate solution guides edits that give it two bears in one region. The intended bear is protected. At the two highest tiers, edits can also target restrictions in a rejected easier proof. All outputs still pass the exhaustive solver and the same gate for their category. In a paired run of the first 240 requests, unguided growth returned 88 boards, guided growth and boundary repair returned 147, and the final version with proof-targeted edits returned 151. The latter added four EXTRA HARD boards. The seeds, sizes and budgets were the same in that comparison.

The final run rejected 155,260 candidates for multiple solutions, 22,244 for proof/profile gates, and 8 under the existing BASE constraints. No higher candidate failed due to terrain connectivity, singleton limits, or zero solutions in this run. EASY and MEDIUM yield improved substantially. HARD still rejected 47,828 ambiguous candidates, 3,795 candidates that met MEDIUM, 1,818 restriction-solvable candidates, 464 overlapping single-family proofs, and 174 that stalled at the required proof gate. NIGHTMARES rejected 30,891 ambiguous candidates. Of the other rejected NIGHTMARES candidates, 861 were solvable with classic techniques, 123 with triples, and eight stalled even with chains. This separates the construction bottleneck from the limits of the proof techniques.

### Outcomes and performance

| Profile | Requested | Validated | Exhausted | Unsupported | Candidate acceptance | Mean / p95 / worst (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| BASE | 5 | 5 | 0 | 0 | 38.462% | 1.830 / 4.550 / 4.550 |
| EASY | 1,747 | 1,495 | 252 | 0 | 3.668% | 13.385 / 39.222 / 106.330 |
| MEDIUM | 1,250 | 1,141 | 109 | 0 | 4.836% | 15.045 / 43.596 / 123.861 |
| HARD | 999 | 306 | 693 | 0 | 0.563% | 59.898 / 125.651 / 330.396 |
| EXTRA HARD | 500 | 66 | 434 | 0 | 0.221% | 87.162 / 180.626 / 388.386 |
| NIGHTMARES | 499 | 1 | 498 | 0 | 0.003% | 168.710 / 465.250 / 1,018.595 |
| **Total** | **5,000** | **3,014** | **1,986** | **0** | **1.670%** | **45.961 mean** |

Candidate acceptance divides fresh boards by all evaluated candidates. Timings include all searches and accept/reject checks, including exhausted requests, and exclude the separate post-generation audit. These are measurements from one machine. Previously, EASY averaged 14.769 ms, MEDIUM 17.287 ms and attempted HARD 24.931 ms. EASY and MEDIUM means improved, while the new HARD search did more work to find qualifying boards. HARD now also attempts the 8×8 requests omitted from the old timing. On the shared 6×6 and 7×7 HARD sizes, means rose from 22.121 and 27.707 ms to 55.707 and 56.368 ms. Summed stage-request generation time rose from 64.148 to 229.804 seconds, partly because every planned size and profile now runs a search.

| Profile | Size | Validated / requested | Mean / worst (ms) |
| --- | ---: | ---: | ---: |
| BASE | 4 | 2 / 2 | 1.061 / 1.418 |
| BASE | 5 | 1 / 1 | 0.947 / 0.947 |
| BASE | 6 | 1 / 1 | 1.531 / 1.531 |
| BASE | 7 | 1 / 1 | 4.550 / 4.550 |
| EASY | 5 | 633 / 636 | 5.930 / 38.587 |
| EASY | 6 | 518 / 573 | 12.126 / 77.504 |
| EASY | 7 | 344 / 538 | 23.540 / 106.330 |
| MEDIUM | 5 | 423 / 423 | 6.035 / 33.079 |
| MEDIUM | 6 | 412 / 424 | 13.122 / 74.450 |
| MEDIUM | 7 | 306 / 403 | 26.525 / 123.861 |
| HARD | 6 | 162 / 333 | 55.707 / 287.665 |
| HARD | 7 | 101 / 336 | 56.368 / 180.494 |
| HARD | 8 | 43 / 330 | 67.722 / 330.396 |
| EXTRA HARD | 7 | 35 / 161 | 63.491 / 219.446 |
| EXTRA HARD | 8 | 28 / 173 | 77.968 / 388.386 |
| EXTRA HARD | 9 | 3 / 166 | 119.702 / 311.063 |
| NIGHTMARES | 8 | 1 / 156 | 92.546 / 624.736 |
| NIGHTMARES | 9 | 0 / 177 | 120.184 / 420.690 |
| NIGHTMARES | 10 | 0 / 166 | 292.027 / 1,018.595 |

### Logical overlap and layout variety

Every column includes BASE deductions. R, P and C mean restrictions, candidate pairs and shared conflicts. T means three-group reservations or adjacency-aware triples. I means implication chains. Dashes indicate supersets not needed for the lower profiles' audit.

| Assigned | BASE | +R | +P | +R+P | +C | +R+C | +P+C | Classic R+P+C | Classic+T | Classic+T+I |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| BASE | 5 | 5 | 5 | 5 | 5 | 5 | 5 | 5 | — | — |
| EASY | 0 | 1,495 | 660 | 1,495 | 1,495 | 1,495 | 1,495 | 1,495 | — | — |
| MEDIUM | 0 | 0 | 39 | 63 | 1,078 | 1,078 | 1,141 | 1,141 | — | — |
| HARD | 0 | 0 | 0 | 0 | 0 | 0 | 306 | 306 | — | — |
| EXTRA HARD | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 66 | 66 |
| NIGHTMARES | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 |

No board met a strictly lower gate. Every HARD board needed pairs and shared conflicts under the tested classic subsets. EXTRA HARD needed triples in a chain-free proof. Of its 66 accepted traces, 40 used three-group reservations and 36 used adjacency-aware triples, with ten using both. The NIGHTMARES board at stage 2,560 stalled under all 16 chain-free masks. Its two minimal successful masks were P+C+I and R+P+T+I. The explicit chains use candidate conflicts and groups with exactly two remaining candidates. No exhaustive-search result is fed into logical analysis.

| Profile | Distinct reasoning signatures | Steps min / median / max | Chain depth min / median / max |
| --- | ---: | ---: | ---: |
| BASE | 4 | 4 / 5 / 7 | 4 / 4 / 7 |
| EASY | 1,293 | 6 / 8 / 13 | 3 / 7 / 11 |
| MEDIUM | 1,138 | 6 / 11 / 21 | 4 / 8 / 14 |
| HARD | 306 | 9 / 14 / 21 | 5 / 10 / 15 |
| EXTRA HARD | 66 | 10 / 18 / 24 | 7 / 12 / 20 |
| NIGHTMARES | 1 | 21 / 21 / 21 | 15 / 15 / 15 |
| **Total** | **2,808** | **4 / 10 / 24** | **3 / 7 / 20** |

The rerun had **3,014 distinct label-free layouts and complete definitions**, **564 distinct bear arrangements**, **zero exact repeats**, and **30 near pairs across 58 stages**. The same orientation and boundary-edge metric from the original run was used. All near pairs were 5×5. Four differed by two edges, nine by three, and 17 by four. Exact counts improved from five to zero and near-pair counts fell from 77 to 30 even with more returned boards. These are observations of the seeded sample.

The target mix still fails the 5,000 validated-board requirement. The most direct next bottleneck is construction of unique, zero-singleton candidates that stall just below the required technique set. Larger candidates need especially strong uniqueness guidance. The 9×9–10×10 NIGHTMARES sample returned zero accepted boards, despite engine validation at those dimensions. A separate 10×10 fixture passed structural, uniqueness and logical checks, without claiming it met NIGHTMARES. The terrain renderer still uses seven drawn materials, with three stable IDs reserved for future artwork.

Tests passed on Godot 4.7.2 for advanced pattern witnesses, larger engine sizes, the 10,000-stage schedule, controlled difficulty regressions, and the full prototype suite including the 4,096-request BASE batch. To rerun the new data:

```powershell
godot --headless --path . --script res://tests/campaign_simulation.gd -- 5000 res://.godot/unified-5000.jsonl legacy
python tests/campaign_simulation_report.py .godot/unified-5000.jsonl --annotated .godot/unified-5000-annotated.jsonl
```

## Original benchmark for comparison

The planned schedule allocated every stage deterministically. The generation service fulfilled **1,731 of 5,000 requests (34.62%)**. Another 1,941 exhausted the budget and 1,328 were unsupported. The **7:5:4:2:2 distribution is not practical for a playable campaign yet**. All returned boards passed connectivity, bear-placement, unique-solution, logical-proof, and profile checks. No request used a fallback or substituted another size or difficulty.

## Method

Godot 4.7.2 simulated stages 1–5,000 using schedule seed `2601`, puzzle seed `50000 + stage`, and at most 64 candidates for each higher-difficulty request. The existing BASE budget was 32. The schedule requests sizes across the full intended ranges, including sizes the current engine cannot generate. The first five requests produced 4×4, 4×4, 5×5, 6×6 and 7×7 BASE boards. Stage 1 includes its first confirmed bear as a locked given in the simulation definition. The gameplay session and save system are separate from this harness.

The first 20-stage block uses a provisional interleaved order because the preferred order was unavailable in the supplied specification and project files. The schedule accepts a replacement order with the correct quotas. Later complete blocks preserve the quotas and vary the order. Stage 5,000 ends five stages short of the final full block in this run, which explains the slightly unequal HARD and NIGHTMARES counts.

## Request outcomes

| Assigned difficulty | Requested | Generated | Budget exhausted | Unsupported | Fulfilled |
| --- | ---: | ---: | ---: | ---: | ---: |
| BASE | 5 | 5 | 0 | 0 | 100.00% |
| EASY | 1,747 | 1,101 | 646 | 0 | 63.02% |
| MEDIUM | 1,250 | 607 | 643 | 0 | 48.56% |
| HARD | 999 | 18 | 652 | 329 | 1.80% |
| EXTRA HARD | 500 | 0 | 0 | 500 | 0.00% |
| NIGHTMARES | 499 | 0 | 0 | 499 | 0.00% |
| **Total** | **5,000** | **1,731** | **1,941** | **1,328** | **34.62%** |

### Board sizes and performance

Timing includes generation and its acceptance checks on this machine. It excludes the post-generation eight-mask audit and layout comparisons. Failed requests are included in timing. Unsupported requests perform no generation and have no timing summary.

| Difficulty | Side | Requested | Generated | Failed | Unsupported | Mean / p95 / worst (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| BASE | 4 | 2 | 2 | 0 | 0 | 0.666 / 0.744 / 0.744 |
| BASE | 5 | 1 | 1 | 0 | 0 | 0.840 / 0.840 / 0.840 |
| BASE | 6 | 1 | 1 | 0 | 0 | 1.898 / 1.898 / 1.898 |
| BASE | 7 | 1 | 1 | 0 | 0 | 10.177 / 10.177 / 10.177 |
| EASY | 5 | 634 | 634 | 0 | 0 | 3.805 / 10.729 / 20.451 |
| EASY | 6 | 576 | 394 | 182 | 0 | 14.125 / 26.952 / 88.950 |
| EASY | 7 | 537 | 73 | 464 | 0 | 28.404 / 39.467 / 106.219 |
| MEDIUM | 5 | 427 | 416 | 11 | 0 | 7.992 / 17.021 / 34.204 |
| MEDIUM | 6 | 420 | 162 | 258 | 0 | 17.431 / 26.527 / 49.104 |
| MEDIUM | 7 | 403 | 29 | 374 | 0 | 26.986 / 35.378 / 86.583 |
| HARD | 6 | 333 | 14 | 319 | 0 | 22.121 / 33.007 / 143.127 |
| HARD | 7 | 337 | 4 | 333 | 0 | 27.707 / 35.932 / 96.716 |
| HARD | 8 | 329 | 0 | 0 | 329 | — |
| EXTRA HARD | 7 | 159 | 0 | 0 | 159 | — |
| EXTRA HARD | 8 | 173 | 0 | 0 | 173 | — |
| EXTRA HARD | 9 | 168 | 0 | 0 | 168 | — |
| NIGHTMARES | 8 | 156 | 0 | 0 | 156 | — |
| NIGHTMARES | 9 | 177 | 0 | 0 | 177 | — |
| NIGHTMARES | 10 | 166 | 0 | 0 | 166 | — |

Of the 1,328 unsupported requests, 329 lacked board-size support alone, 159 lacked the deduction techniques alone, and 840 lacked both. Lack of a unique solution accounted for 125,683 rejected higher-difficulty candidates. Singleton limits accounted for 25,769. Lower gates rejected 816 BASE-solvable candidates, 323 restriction-solvable candidates assigned to MEDIUM or HARD, and 159 candidates assigned to HARD that met the MEDIUM gate. Another 104 candidates had both competing single-family proofs after restrictions stalled and were excluded from the provisional MEDIUM and HARD profiles.

## Logical proof and overlap

Each column counts accepted boards solved by that technique subset. BASE techniques are present in every run. R means region/line restrictions, P means candidate pairs, and C means shared conflicts. A board may count in several columns. For example, a shared conflict can express a region/line restriction.

| Assigned | BASE | +R | +P | +R+P | +C | +R+C | +P+C | All |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| BASE | 5 | 5 | 5 | 5 | 5 | 5 | 5 | 5 |
| EASY | 0 | 1,101 | 674 | 1,101 | 1,101 | 1,101 | 1,101 | 1,101 |
| MEDIUM | 0 | 0 | 12 | 14 | 593 | 593 | 607 | 607 |
| HARD | 0 | 0 | 0 | 0 | 0 | 0 | 18 | 18 |

No accepted board met a strictly lower gate. There were alternative proofs within assignments. For example, EASY had 674 boards individually solvable by R, P or C and 427 individually solvable by R or C. MEDIUM had 593 C-only minima and 12 P-only minima. Stages 1,684 and 2,876 each had two minimal proofs, R+P and P+C. All 18 HARD boards required P+C. These results support differences in the tested reasoning gates. Player difficulty still needs calibration.

| Difficulty | Distinct reasoning signatures | Steps min / median / max | Chain depth min / median / max |
| --- | ---: | ---: | ---: |
| BASE | 4 | 4 / 5 / 7 | 4 / 4 / 7 |
| EASY | 759 | 6 / 7 / 12 | 4 / 6 / 11 |
| MEDIUM | 591 | 7 / 10 / 19 | 4 / 7 / 13 |
| HARD | 18 | 10 / 12 / 16 | 6 / 9 / 10 |
| **Total** | **1,372** | **4 / 8 / 19** | **4 / 6 / 13** |

The signature combines board size, minimal proof masks, ordered techniques, choices per step and dependency depth. The ranges overlap, especially between MEDIUM and HARD. Step counts and chain depths alone would misclassify some boards.

## Layout uniqueness

| Difficulty | Returned | Distinct layouts | Distinct complete definitions | Bear arrangements within category |
| --- | ---: | ---: | ---: | ---: |
| BASE | 5 | 5 | 5 | 4 |
| EASY | 1,101 | 1,097 | 1,097 | 160 |
| MEDIUM | 607 | 606 | 606 | 78 |
| HARD | 18 | 18 | 18 | 13 |
| **Total** | **1,731** | **1,726** | **1,726** | **179** |

Exact layout matches ignore terrain labels. Rotations and reflections are treated as different orientations. A near match is a same-size pair whose internal orthogonal boundary masks differ by one to four edges. All five exact matches were also duplicates of the complete definition (difficulty, size, original IDs, solution and givens). All were 5×5.

| Stages | Separation | Difficulty |
| --- | ---: | --- |
| 1,030 → 1,297 | 267 | EASY |
| 1,034 → 3,223 | 2,189 | MEDIUM |
| 1,265 → 3,349 | 2,084 | EASY |
| 3,153 → 3,433 | 280 | EASY |
| 333 → 3,693 | 3,360 | EASY |

The 77 near-match pairs involved 137 stages and were all 5×5. There were 45 EASY–EASY pairs, 20 MEDIUM–MEDIUM pairs and 12 EASY–MEDIUM pairs. Larger sizes had fewer accepted samples and should be compared again when yield improves.

## Remaining work

Improve exact-uniqueness construction and HARD yield at 6×6 and 7×7 before inspecting broader distribution or imposing a duplicate rejection window. EXTRA HARD needs a verified multi-group deduction family. NIGHTMARES needs verified implication-chain reasoning. Sizes 8×8–10×10 need engine and terrain support. Keep disallowed sizes and unfinished profiles explicit until each gate and its generation yield pass validation.

## Reproduction

```powershell
godot --headless --path . --script res://tests/campaign_simulation.gd -- 5000 res://.godot/campaign-5000.jsonl
python tests/campaign_simulation_report.py .godot/campaign-5000.jsonl --annotated .godot/campaign-5000-annotated.jsonl
```

The annotated output records each request, its proof checks and measurements when a board exists, and earlier exact or near layout matches. Unsupported or exhausted requests have no generated definition or proof.
