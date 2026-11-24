# NIGHTMARES generation failure investigation

Request 903 was the last new layout found in the original run. The runtime samples one-cell edits from a fixed root catalog and excludes layouts already served in the same Free Play service. The reserve shares this exclusion set. The benchmark consumed the entire validated union reachable by those proposal rules and the shipped reserve. The result gives no mathematical upper bound on the wider NIGHTMARES puzzle space.

## Finite runtime inventory

The isolated inventory diagnostic enumerates each concrete one-cell proposal from the shipped roots and applies the unchanged connectivity, solution-count and difficulty validation with empty history. Counts below are proposal attempts before canonical deduplication. A valid proposal preserves the parent solution because it moves only a non-bear cell between regions. The uniqueness failures in this proposal family therefore have multiple solutions.

| Size | Proposed edits | Invalid terrain | Multiple solutions | Unique | Failed gate | Distinct accepted edit layouts | Edit layouts also in reserve | Combined eligible layouts | Served |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 8×8 | 279 | 86 | 71 | 122 | 29 | 93 | 93 | 120 | 120 |
| 9×9 | 408 | 137 | 98 | 173 | 48 | 125 | 120 | 125 | 125 |
| 10×10 | 569 | 177 | 123 | 269 | 52 | 217 | 120 | 217 | 217 |
| **Total** | **1,256** | **400** | **292** | **564** | **129** | **435** | **333** | **462** | **462** |

The reserve holds 120 layouts per size. Fresh requests had already served 228 when the reserve looked for those layouts, leaving 132 reserve-sourced results and zero reserve validation failures. The last reserve was served at request 603, after which fresh search still occasionally found an unseen edit. The eight-attempt budget can make a request fail while other eligible layouts remain. After the entire reachable union was used, changing seeds or increasing the number of attempts could only revisit proposals in that union.

## History and seed replay

The diagnostic reconstructed the exact per-size history immediately before each of 18 logged requests. All reproduced their logged result and puzzle ID. On requests 904, 905, 906, 1200, 4998, 4999 and 5000, empty history yielded seven fresh valid boards, also with the reserve disabled. The same seven requests succeeded when run in forward order, reverse order, or one at a time with history reset. Preloading the final history made the seven requests fail. A separate process test used request 4999 and the original seed 854998. Its fresh board ID was `4d2972694394443d`.

Resetting history before each diagnostic request disables between-request duplicate filtering without bypassing validity, uniqueness or the proof gate. Within a request the generator does not accumulate an exclusion list for unsuccessful proposals.

Adding 730,000 to each of the seven sampled late seeds gave seven fresh successes with empty history and seven failures with final history. With the original recorded history, disabling reserve made requests 358, 365 and 603 fail. Those requests had exhausted their fresh budgets and depended on the reserve. The later sample failed with or without the spent reserve.

| Logged request | Size | Result | Edits tried | Invalid | Multiple | Unique evaluated | Chain stall | Gate rejected | Used-layout skips | Fresh / reserve exhausted | Time (ms) |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| 358 | 8×8 | Reserve | 8 | 2 | 4 | 0 | 0 | 0 | 2 | Yes / no | 124.38 |
| 603 | 10×10 | Reserve | 8 | 3 | 2 | 1 | 0 | 1 | 2 | Yes / no | 192.47 |
| 903 | 10×10 | Fresh | 2 | 0 | 0 | 1 | 0 | 0 | 1 | No / not attempted | 77.88 |
| 904 | 8×8 | Unfulfilled | 8 | 2 | 3 | 2 | 1 | 2 | 1 | Yes / yes | 54.51 |
| 905 | 9×9 | Unfulfilled | 8 | 2 | 2 | 1 | 0 | 1 | 3 | Yes / yes | 60.54 |
| 906 | 10×10 | Unfulfilled | 8 | 4 | 2 | 1 | 0 | 1 | 1 | Yes / yes | 70.04 |
| 4999 | 8×8 | Unfulfilled | 8 | 2 | 4 | 1 | 1 | 1 | 1 | Yes / yes | 49.47 |
| 5000 | 9×9 | Unfulfilled | 8 | 5 | 1 | 0 | 0 | 0 | 2 | Yes / yes | 43.68 |

These counters describe fresh proposals only. History skips happen before validation, so the unique column counts only candidates that actually reached the solver and had one solution. Chain stalls are a subset of gate rejections. The request timing includes the applicable reserve path.

## Which reuse rules exist

- The exclusion dictionary belongs to one `FreePlay` service instance and is scoped by board size. A separate service or process starts with empty history. No global registry or disk record of consumed reserve entries was found.
- Playable Free Play retains the service as the board scene stays open, including when switching modes or difficulties. Reopening a saved NIGHTMARES definition records its layout in that running service. Saving the definition itself does not save the exclusion history.
- The canonical key ignores terrain labels, rotations and reflections. It compares exact partitions under those equivalences. There is no near-layout distance filter, no answer-arrangement exclusion and no ban on puzzles generated in prior tests or sessions.
- Seeds initialize the random proposal order for each request. Neither the generator nor the benchmark has a used-seed registry or a cutoff at request 903.
- The no-repeat rule is intentional within the running sequence. Its interaction with a small static edit neighborhood and shared finite reserve is the limiting behavior at long horizons. Previously served but still valid layouts become unavailable for the lifetime of that service.

## Construction and terrain

Playable Free Play starts from the shipped proof roots, edits one boundary cell and does not promote returned layouts to new parents. It does not call the broader region-growth sampler. The runtime edit neither moves a bear nor removes a cell from a two-cell donor. It also protects two-cell regions used as strong implication links from expansion. These restrictions protect the intended answer and a construction motif. They constrain reachable proposals without being general terrain eligibility rules.

The broader growth algorithm expands an orthogonal frontier. Swap-aware growth defers edges that permit known swaps. Chain-aware growth can freeze two-cell motifs, and required seed expansion gives every region a second cell. In a bounded control with the first root's anchors fixed in each size, ordinary, swap-guided and chain-guided growth each used 24 matching seeds per size. Across the 216 proposals, 214 were ambiguous, one failed terrain construction, and one admitted a classic proof. None passed NIGHTMARES. This isolates those growth choices at fixed anchors and does not measure the yield of all possible anchors. The earlier broad-anchor trial sampled 191 distinct starts with zero accepted directly, also predominantly due to ambiguity.

The validators check full orthogonal connectivity using traversal. There is no general shape, width, symmetry or compactness rule. Independent measurements from the stress log found a region with a single-cell articulation on every served board and opposite-edge spans on 196 boards. Branching was common, and the largest regions reached 31, 30 and 43 cells by size while the smallest regions held two cells. Neither locally adjacent edits nor a plausible shape replaces the full connectivity check.

## Difficulty gate

Of the 129 unique proposals rejected by difficulty, 54 admitted a classic proof, 37 admitted a triple proof and 38 stalled even with chains. An experimental Hall and bounded-contradiction solver completed all 25 sampled chain-stall cases without changing any gate. These are genuinely interesting candidates that the current profile cannot accept. The sample does not establish that they satisfy a proposed replacement definition of NIGHTMARES.

The diagnostic reflected and relabeled 101 sampled unique rejected layouts to change the scan order. No gate classification changed in that sample. The earlier proof audit of all 462 accepted boards also found no easier chain-free proof under its reflected ordering. These tests cover specific alternative scan orders. They cannot exclude every possible ordering. Revising the profile alone would still leave the current proposal library finite, and would not address the dominant terrain, ambiguity and repeat counts.

## Recommended next steps and limits

First, make the novelty policy explicit. A bounded recent-layout window or clearly marked optional reuse could keep previously validated boards eligible after a long session. That would improve availability, with increased repetition. Keep the current gate and independently validate any reused definition as appropriate. Track reserve depletion separately and avoid rescanning the entire spent inventory on every request.

For genuinely new boards, enlarge and diversify the proof roots and test validated multi-edit or new-anchor construction. Compare candidates by accepted layouts and answer diversity, because adding more shapes around one unchanged answer cannot fix answer concentration. Treat a broader advanced-proof profile as a separate calibration task. This investigation did not modify production code or rerun the 5,000 requests. The three requested specialist agents were contacted, but each hit a usage limit. The primary agent ran the isolated diagnostics directly.

## Reproduction

```powershell
$log = 'res://.godot/<stress-run>/Godot/app_userdata/Cubdoku/nightmares-stress.jsonl'
.\tests\run_isolated.ps1 -Godot $godot -Script res://tests/nightmares_history_diagnostic.gd -UserArguments @($log)
.\tests\run_isolated.ps1 -Godot $godot -Script res://tests/nightmares_history_diagnostic.gd -UserArguments @($log, '4999')
.\tests\run_isolated.ps1 -Godot $godot -Script res://tests/nightmares_candidate_inventory.gd -UserArguments @($log)
```
