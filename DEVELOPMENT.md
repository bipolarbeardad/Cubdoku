# Cubdoku development

## Milestone 1 — Playable 4×4 prototype

Run `project.godot` in Godot 4. The main scene is `scenes/puzzle_board.tscn`. Hold left click on a cell for 400 ms to place a bear cub head. An in-cell bar shows progress, and releasing early or leaving the cell cancels the hold. Right click attempts to place an X immediately.

Correct bears and X marks lock for the attempt. An incorrect bear leaves a locked X and costs one heart. An incorrect X costs one heart, briefly flashes red, plays a warning tone and leaves the cell empty. Three misses end the attempt. **Restart** clears player marks and resets hearts and time, with any preplaced tutorial bears still locked. Completing a row or column with all its correct marks plays one chime, including when the same move completes both. Placing all required bears still completes the puzzle.

Godot 4.7.2 passed the prototype suite headless and windowed using injected mouse events, including real-time holds, canceling on release and pointer exit, and chime playback-state checks. All five other headless regression suites passed. The isolated runs preserved the live campaign save hash.

### Marking rules

Bear cub heads and X marks are the only committed marks. Wrong marks cost a heart, so a player can test deductions over repeated attempts while each attempt tracks mistakes.

### Local puzzle modes

`scripts/campaign_catalog.gd` defines permanent level IDs and BASE difficulty tags for Campaign Path #1–#8. The old fixed puzzles remain in that catalog as legacy test fixtures. The live campaign generates a personal puzzle on first reaching a level and saves its distinct instance ID, level ID, difficulty, size, regions and verified solution before opening it. The loader verifies saved definitions with the exhaustive solver. **Next puzzle** advances after completion when another level exists.

**Free Play** opens a BASE board. The **Difficulty** selector and **Generate New Puzzle** request a validated board with an automatically selected eligible size. **Return to Campaign Path** restores the suspended campaign attempt, including marks, hearts and elapsed time. **Restart** keeps the current definition and starts a new attempt. Losing the last heart records a failure. Restarting an unfinished campaign attempt counts as a new attempt without recording a failure.

`scripts/puzzle_session.gd` records attempts started, failures, completion, best successful time and hearts remaining on the latest success. The save reserves a field for consumable usage. Local campaign statistics record unique completions overall and by difficulty, the fastest successful time and the highest level reached. Free Play contributes no campaign statistics.

`scripts/campaign_save.gd` stores version 1 at `user://campaign.save`. Sessions can use a different save path for isolated profiles and tests. The prototype opens the default local profile. Campaign actions save immediately. The running timer is checkpointed roughly once a second and on clean exit from the campaign. Entering and playing Free Play leaves the disk profile untouched and suspends the running campaign timer in memory. Unsupported save versions are left intact.

#### Read-only save audit

- The default Windows profile resolves to `%APPDATA%\Godot\app_userdata\Cubdoku\campaign.save`. This was the only campaign save found in the checked locations. The workspace's redirected Godot test directory contained no campaign save, and the live profile had no `.tmp` sibling. The game uses `.tmp` during writes and reads the finalized save path.
- The live file decoded fully as version 1. It contains a completed 4×4 BASE assignment at Campaign Path #1, one attempt, zero failures, three hearts at completion, and a best time of 104.139 seconds. There is no Path #2 assignment. Completion and advancement are separate actions, so this state continues to open at Path #1 until **Next puzzle** is selected.
- The current loader restored the stored puzzle definition and marks exactly, and the saved solution passed the uniqueness check. An independent check verified the level and instance IDs and restored the saved attempt. The save's SHA-256 and modification time were unchanged across the audit. No save data or loading behavior was changed.

#### Planned campaign navigation and retry economy

The path will show 10,000 stages as paw prints along a winding forest trail, arranged in 200 sections of 50. Players can drag vertically with a pointer or touch to move through the current section. Tapping a completed paw print immediately replays that stage. Returning from a puzzle restores the current stage and path scroll position. The Bear Guide will take players to distant unlocked stages or sections. Path interaction and the Bear Guide must enforce stage locks.

Completed stages are permanently free and replayable without a limit. Each replay uses the saved puzzle definition, can improve the best time, and preserves the original completion record and highest campaign progress. Replays also provide opportunities to practice and earn coins. BASE, EASY and MEDIUM use normal paw prints. HARD uses brown prints, EXTRA HARD uses purple prints with visible claws, and NIGHTMARES uses red flaming prints. Use distinguishable silhouettes or details as well as color.

The first attempt at a newly unlocked stage is free. Each attempt starts with three hearts and fails at zero. Retrying that unfinished stage after a failure costs 10, then 20, 40, 80, and at most 100 coins. The fee is tracked per unfinished stage and permanently removed at completion. Restart, navigation and relaunch must enforce any outstanding fee. Players must always have a route to continue when they lack coins.

Resolve before implementation how much completed-stage replay pays, whether repeat rewards have limits, and how a coinless player can recover before completing any stage. Define how abandoning an active attempt is treated, when a retry debit and new attempt commit together, and how interrupted attempts resume. The save design must settle migration of existing assignments, per-stage failure and fee state, original versus best completion records, and retention of path position. These requirements are planned and are separate from the simulation.

`scripts/puzzle_generator.gd` grows one connected terrain region per seed bear and tries up to 32 candidates by default. The seeded candidates and the size-specific fallbacks go through the same checks. `scripts/puzzle_validator.gd` checks the terrain partition, `scripts/puzzle_solver.gd` counts solutions up to two, `scripts/puzzle_game_state.gd` manages play, and `scripts/puzzle_board_ui.gd` binds the scene controls to game state.

The only column orders that satisfy the 4×4 row, column and non-touching rules are 2–4–1–3 and 3–1–4–2, using one-based columns from top to bottom. To deduce the answer, check the terrain colors in both orders. Uniqueness guarantees that exactly one order uses all four colors.

### BASE difficulty calibration

BASE supports 4×4 through 7×7 in Free Play. Pass the board side as the fourth argument to `PuzzleGenerator.generate(seed, max_attempts, difficulty, size)`. Every new BASE board requires exactly one singleton, at least one irregular region, one unique solution, and a complete proof from basic deductions. Generation starts from a seeded non-touching bear arrangement, reserves one singleton, and gives each other region a second cell that an earlier bear can rule out. Further growth preserves that deduction order. The validator, exhaustive solver, and logical analyzer still check every returned board, including fallbacks. Campaign still requests 4×4 and keeps previously saved assignments as they were.

`scripts/difficulty_analyzer.gd` takes only the region layout and records each forced placement, the technique used, and the cells it eliminates. A singleton region provides an opening move. Further moves come from the last remaining candidate in a region, row or column. Placed bears eliminate candidates in their own region, row, column and diagonal neighbors. The analyzer reports when it gets stuck or finds a contradiction. `scripts/puzzle_difficulty.gd` stores provisional singleton limits of 1 for BASE, 0–1 for EASY, and 0 for MEDIUM through NIGHTMARES. Only BASE has a logical classification and supports generation.

#### Four-size generation benchmark

Godot 4.7.2 verified 1,024 seeded requests per size (seeds 0–1023) under the exactly-one rule. Every returned board had exactly one singleton and a unique solution, and the logical analyzer solved every board. Separate zero-budget checks validated the four fallbacks. Candidate acceptance counts fresh accepts divided by all attempted candidates. Timings include validation and retries.

| Side | Acceptance | Rejected | Failures / fallbacks | Mean / worst | Distinct layouts¹ | Region-size patterns | Bear arrangements | Deductions per board |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4×4 | 83.87% | 197 | 0 / 0 | 0.350 / 1.076 ms | 541 | 12 | 2 | 4 |
| 5×5 | 67.77% | 487 | 0 / 0 | 0.702 / 3.592 ms | 1,017 | 63 | 14 | 5 |
| 6×6 | 37.21% | 1,728 | 0 / 0 | 1.255 / 21.452 ms | 1,024 | 284 | 90 | 6 |
| 7×7 | 24.16% | 3,211 | 0 / 1 | 2.676 / 77.129 ms | 1,023 | 737 | 481 | 7 |

¹ Layout counts ignore terrain labels. The test prints the full histogram of region areas and the totals by deduction technique.

The generated deduction traces used the singleton followed by last-candidate-in-region moves. Separate fixtures verified row and column deductions and rejected a uniquely solvable puzzle with two singleton regions. GDScript validation and the full headless suite passed, including Campaign and Free Play save regressions. The live campaign save hash was unchanged.

### Expanded logical analysis

`DifficultyAnalyzer.analyze(regions)` retains BASE-only reasoning. Passing `true` as the second argument enables four candidate restrictions (region-to-row, region-to-column, row-to-region, and column-to-region), pairs of groups that reserve the same two groups of another family, and eliminations for a candidate that conflicts with every remaining placement in a required group. The pattern module works on visible candidates. It uses neither stored answers nor search. The analyzer still tries forced placements first, then restrictions, pairs, and common conflicts.

Each round records the applied technique, involved cells and groups, confirmed bears, and eliminated candidates. Placements also record row, column, region and diagonal exclusions individually. The report counts eliminations once even when multiple rules apply. It records total steps, placements, complexity, the longest dependency chain through the affected source groups, and distinct choices in the first applicable technique tier at each round. These provisional measurements describe one deterministic proof and are not calibrated difficulty ratings.

`PuzzleAnalysis.assess(regions)` reports solved, stuck, invalid, or multiple solutions by presenting the logical trace alongside the independent exhaustive count, capped at two. The uniqueness check never supplies candidate placements to the analyzer. A fixture with one exhaustive solution remains logically stuck with all currently supported techniques enabled.

The existing live-game profile is configured in `scripts/puzzle_difficulty.gd`. It enables BASE only. The separate campaign simulation below applies the planned size ranges independently of logical difficulty.

Godot 4.7.2 passed check-only validation, the full headless and windowed suites, and the terrain pixel checks. Tests reproduced the expected eliminations for every new technique, verified repeatable traces and all four assessment outcomes, and checked every eligible size. All 4,096 seeded BASE requests returned valid boards whose traces matched in BASE and advanced modes. Generation acceptance and diversity counts matched the singleton benchmark. The live campaign save hash was unchanged.

### Advanced logical reasoning audit

| Candidate family | Relationship to the current analyzer |
| --- | --- |
| Region-to-row and region-to-column | Implemented restrictions. The inverse line-to-region directions are also implemented. |
| K regions confined to K rows or columns | Implemented for K=1, 2 and 3 through restrictions, pairs and group triples. The audit tests K=4 using the same exactly-one argument. Four required bears consume the four distinct lines, so other regions cannot use them. Larger K remains untested. |
| Shared neighbors of two candidates | A two-position case of shared conflicts. Conflict checks already include diagonals, along with rows, columns and regions. |
| Edge, corner and L shapes | Position alone cannot justify an elimination. Confinement and shared conflicts account for the associated line and neighbor effects. Adjacency triples also check whether a candidate participates in any compatible triple. A new shape-specific rule needs a case those techniques miss. |
| Fatal squares | A candidate directly conflicting with every position in one required group is already a shared conflict. Emptying a group after forced consequences can require a longer argument. |
| Contradiction and bounded bifurcation | Current implication chains propagate conflicts and two-candidate implications. The audit temporarily assumes one bear and applies at most eight forced placements in a copied candidate state. It excludes the assumed cell only when a named required group becomes empty. A two-sided split could also prove an exclusion common to both branches, or rule out the failed side. This experiment tested the positive assumption only, with no nesting. A surviving branch commits nothing. |
| Tight groups first | Changes probe order and explanation, with no new inference rule. Compare it against row-major order under the same bound. |

The row and column quartet fixtures demonstrate a confinement with no smaller region subset reserving the same number of lines. The 5×5 calibration fixture `stuck_5` has one independently verified solution. All current techniques stall, including chains, and adding quartets alone still stalls. A single bounded contradiction completes it. In zero-based cell indices, the row-major branch assumes 0 and forces 21 and 12, emptying region 0. Tight-group ordering assumes 1 and forces 8, emptying row 2. Both found the contradiction on the first probe. Tight-first shortened the hypothetical path on this fixture without reducing the probe count. No hypothetical bear is added to the committed trace.

The bounded generation diagnostic used 1,024 seeded starts per size from 5×5 to 10×10, each with singleton expansion and up to five boundary edits. It found 217, 72, 31, 12, 8 and 8 unique final boards respectively. The existing analyzer solved all 348, so neither experimental rule recovered a newly solvable generated candidate in this sample. The sampler is biased toward proof-grown starts and cannot estimate campaign acceptance. The controlled fixture establishes extra solving power for bounded contradiction, while the generation results establish no yield improvement. Difficulty gates and gameplay remain on the production rules.

Reproduce with `.\tests\run_isolated.ps1 -Godot $godot -Script res://tests/logical_reasoning_audit.gd`. The independent solver supplies only test assertions. The experimental analyzer receives the layout and live candidates.

Godot 4.7.2 passed the audit and all six headless regression suites. The 5,000-stage benchmark was not rerun.

### Difficulty calibration study

Run `godot --headless --path . --script res://tests/difficulty_calibration_study.gd`. Seven fixed, uniquely solvable boards were run under all eight combinations of the three advanced technique families. BASE deductions were always available. The study checks that the BASE-only and full traces match the production analyzer and that no trace eliminates an independently verified solution bear. Godot 4.7.2 passed script validation, all 56 controlled runs, and the existing targeted solver, analyzer, and size-profile regressions. The 1,500-puzzle replayability benchmark was not rerun. The live campaign save hash was unchanged.

| Implemented technique | Relative reasoning demand |
| --- | --- |
| Singleton-region placement | Direct observation of one cell. |
| Last candidate in a region, row, or column | Check all remaining candidates in one required group. May depend on earlier eliminations. |
| Row, column, region, and diagonal exclusion | Direct application of a rule from a confirmed bear. |
| Region-to-row, region-to-column, row-to-region, and column-to-region | Track one unresolved group and see that its candidates are confined to one group in another family. The four directions share the same logic. |
| Candidate pair | Track two required groups that together reserve two groups of another family. This can eliminate candidates outside the pair. |
| Shared conflict | Check each alternative in one unresolved group. An outside candidate can be eliminated when every alternative conflicts with it, including through different rules. |

R denotes the four restrictions, P denotes pairs, and C denotes shared conflicts. The highest technique and metrics below describe the full production trace. The successful subsets show which optional families suffice under the tested scheduler. A dash means the full analyzer stalled.

| Fixture | Smallest successful subsets beyond BASE | Highest technique in full trace | Steps | Eliminated | Chain depth | Forced placements |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| `base_5` | None required | Singleton | 5 | 20 | 4 | 5 |
| `restriction_5` | R or C | Region-to-row | 7 | 20 | 6 | 5 |
| `conflict_5` | C | Shared conflict | 11 | 20 | 7 | 5 |
| `pair_7` | P | Candidate pair | 11 | 42 | 9 | 7 |
| `conflict_7` | C | Shared conflict | 19 | 42 | 12 | 7 |
| `pair_and_conflict_7` | P+C | Shared conflict | 12 | 42 | 10 | 7 |
| `stuck_5` | — | Shared conflict | 3 | 3 | 1 | 0 |

Restrictions add solving power over BASE, but are a special case of shared conflicts. If all source candidates lie in one target group, any outside candidate in that target already conflicts with all of them. In `restriction_5`, C alone finished in six steps whereas R finished in seven. P and C each solved boards the other could not, and both were necessary on `pair_and_conflict_7`. That board took fewer steps than `conflict_7`, even with the extra required family. Group count and visibility matter alongside chain depth. On every solved size N, placements and eliminations end at N and N²−N, so those totals cannot separate difficulty at a fixed size. All metrics depend on the selected proof and have no player calibration yet.

#### Provisional profiles for a later milestone

Every gate below assumes a connected board with one independently verified solution. Apply board-size and provisional singleton limits separately from the logical gate. These profiles have not been implemented or validated as player difficulty bands.

| Profile | Proposed sizes | Proposed logical gate |
| --- | --- | --- |
| BASE | 5×5–7×7, with 4×4 for tutorial and testing | Existing BASE proof and exactly one singleton. |
| EASY | 5×5–7×7 | BASE stalls. BASE+R solves. |
| MEDIUM | 5×5–7×7 | BASE+R stalls. Exactly one of BASE+R+P and BASE+R+C solves in separate runs. If both solve, keep the board outside this initial calibration sample. |
| HARD | 6×6–8×8 | Full current techniques solve, and removing either P or C makes the analyzer stall. |
| EXTRA HARD | 7×7–9×9 | Full current techniques stall. An explicit deduction spanning at least three required groups completes the proof with the current techniques. Remove the new family to verify it is required. |
| NIGHTMARES | 8×8–10×10 | The EXTRA HARD technique set stalls. A proof with explicit linked implications across at least four links provides a candidate gate, pending technique implementation and playtest calibration. |

The study distinguishes restriction-only from pair- or conflict-dependent puzzles. It also shows a board requiring both advanced families, but that fixture has two singleton regions and fails the separate zero-singleton proposal for HARD. It demonstrates a logical capability, not HARD candidate eligibility. There is no calibrated ordering between the pair and shared-conflict families. EXTRA HARD and NIGHTMARES cannot be distinguished reliably today, and sizes 8×8–10×10 are outside current engine support.

The next generation milestone should start with a bounded EASY trial on 5×5–7×7, accepting only boards that pass the restriction gate and the independent uniqueness check. Report yield by size, retest necessity under different move orders, and use blinded player tests to check the proposed labels. Higher bands need verified zero-singleton fixtures, larger Hall sets or multi-group support checks that account for adjacency, and explainable implication chains. Keep any unique board that exhausts known deductions unclassified until a logical proof is available.

### Integrated campaign generation simulation

`scripts/campaign_schedule.gd` defines the isolated 10,000-stage schedule and an override for the first 20-stage difficulty block. The introductory sizes are 4, 4, 5, 6 and 7, with the first proved bear included as a locked given in the stage-one simulation definition. The project had no supplied ordering for stages 6–25, so the run used the default interleaved order shown in the schedule. Complete later blocks kept the 7:5:4:2:2 quotas without adjacent repeats in the default schedule, including block boundaries.

`scripts/campaign_generation.gd` uses connected growth and restricted logical proofs for experimental EASY, MEDIUM and HARD requests through 7×7. BASE uses the existing seeded generation path. EXTRA HARD and NIGHTMARES require additional logical techniques. The schedule requests the full intended size ranges, so stages above engine capacity are reported as unsupported. Navigation, economy, and live campaign assignment behavior are untouched.

The 5,000-stage run returned 1,731 validated puzzles. It recorded 1,941 exhausted requests and 1,328 unsupported requests, with no fallback or substituted board. No accepted board met a lower difficulty gate. There were five exact definition duplicates, 77 near-layout pairs and 1,372 reasoning signatures. The intended mix is impractical with current yield, especially for HARD, which fulfilled 18 of 999 requests. See [the simulation report](CAMPAIGN_SIMULATION.md) for the size and difficulty breakdown, overlap matrix, timings, stage separations and reproduction commands.

Godot 4.7.2 passed the schedule test across all 10,000 stages, all 56 controlled difficulty runs, and the full prototype suite, including the 4,096-request BASE regression batch. The live campaign save hash was unchanged.

### Unified generation follow-up

The campaign generator now alternates connected seed growth and proof-based starting layouts, expands singleton regions where the profile requires it, and repairs boundaries while preserving the intended bear placement. An alternate solution can guide a repair that makes two of its bears share a region. For EXTRA HARD and NIGHTMARES, the generator also uses the visible proof of a rejected easier board to select edits that break early restrictions. The analyzer receives the layout only. Every accepted board still passes the independent solution count and its original structural and logical gates. The higher-difficulty attempt budget remains 64.

The engine accepts 8×8 through 10×10 layouts. Three-group deductions include reservations across group families and local candidate support that accounts for adjacency. The implication analyzer records explicit paths made from conflicts and exactly-two-candidate group links. EXTRA HARD must stall with all classic techniques and solve with triples. NIGHTMARES must stall under every non-chain subset and solve with an explicit implication proof. The campaign schedule now uses the supplied stages 6–25 order. The seven existing terrain materials still render as before. IDs for Water, Sand and Moss are reserved for later artwork.

The rerun validated 3,014 of 5,000 requests, up from 1,731. Every category returned a verified board, including 66 EXTRA HARD and one 8×8 NIGHTMARES puzzle. There were 1,986 budget exhaustions, zero unsupported requests, zero fallbacks and zero lower-gate overlaps. No 9×9 or 10×10 NIGHTMARES request succeeded. The primary blocker is candidate ambiguity, which accounted for 155,260 rejections. The [simulation report](CAMPAIGN_SIMULATION.md) gives the strategy comparison, timing, stage-level reproduction and coverage by profile and size.

Godot 4.7.2 passed the advanced deduction tests, schedule tests, controlled difficulty study, and full prototype suite. An independent Python solver validated each returned board. The live campaign save hash matched before and after the run.

### Uniqueness-guided generation optimization

The generator retains up to eight alternate bear arrangements within a growth lineage. It scores boundary edits by the alternatives they would eliminate and penalizes edits that revive known defeated alternatives. Intended bears, required region connectivity, and singleton limits remain protected. Larger boards can retain a lineage for eight more attempts, within the same 64-candidate request budget. A disconnected or nonunique candidate still fails validation. Difficulty gates and the logical analyzer remain separate from generation-side solution witnesses.

The exhaustive solver still stops at two matches in production. It skips branches whose remaining rows cannot supply a required region and caches dead search states on 8×8–10×10 while preserving witness order. The simulation records construction, structural checks, uniqueness, edits, and difficulty time separately. The bounded ambiguity survey counts at most 12 solutions on the first ambiguous candidate of every fifth request, with its time tracked separately. The report treats a count of 12 as a lower bound.

The matched 5,000-stage rerun validated 3,160 requests, up from 3,014, and reduced ambiguity rejections by 8,800. Repairs directly created 8,566 unique candidates, of which 1,738 passed their assigned profile. There were 1,840 exhausted requests, zero fallbacks, and zero lower-difficulty acceptances. Summed request time fell from 229.804 to 187.588 seconds with the same attempt budgets. Nightmare yield remains impractical at every size, with 5/156 accepted at 8×8, 2/177 at 9×9 and 0/166 at 10×10. [The simulation report](CAMPAIGN_SIMULATION.md) includes the bounded counts, timing by phase, per-size and per-profile success, and exact and near repeats.

Godot 4.7.2 passed the new repair tests, advanced deduction, schedule and calibration tests, and the full prototype regression suite. The independent Python verifier checked all 3,160 returned boards. The 7:5:4:2:2 allocation, seeded introductory boards, and live campaign save hash matched the previous run or the pre-run state, as applicable.

### Difficulty-guided construction

HARD, EXTRA HARD and NIGHTMARES now use candidate plans in the isolated campaign generator. Growth still starts from legal bear anchors. It can defer a cell assignment that would complete a legal two-row column swap, and boundary repair can use surviving swaps as additional witnesses. When a simpler proof rejects a unique board, its restrictions and three-group steps can guide edits that introduce an additional candidate. The repair score still protects uniqueness progress against remembered alternatives.

Some NIGHTMARES starts reserve two connected, two-cell regions designed to support a five-link implication. The path alternates geometric conflicts and exactly-one group implications. Assuming the eliminated candidate contains a bear leads back to that candidate being empty. The generation plan is never given to the analyzer. Group preservation is a repair preference, and the existing independent uniqueness check and chain-free necessity gates still decide acceptance. No general hypothetical search was added.

The matched 5,000-stage run validated 3,645 requests, up from 3,160. HARD improved from 377 to 753, EXTRA HARD from 108 to 209, and NIGHTMARES from seven to 15. Six 10×10 NIGHTMARES requests passed, establishing feasibility with the current proof techniques. The profile remains unreliable at all three sizes. Ambiguity rejections fell by 24,896, while repair-gate survival fell from 20.3% to 17.0%. More repairs reached uniqueness and more passed their gate in absolute terms. Summed generation time rose from 187.588 to 283.828 seconds. The same 1,355 unfulfilled requests recorded in the rerun were budget exhaustions. The [simulation report](CAMPAIGN_SIMULATION.md) includes the matched construction diagnostic, gate-rejection breakdown, and per-size results.

Godot 4.7.2 passed the construction, uniqueness repair, advanced deduction, schedule, calibration, and full prototype regression tests. The independent Python verifier checked all 3,645 accepted boards. BASE, EASY and MEDIUM seeded outputs matched the prior benchmark. The campaign save hash was unchanged.

### Multi-row ambiguity and proof reuse

The isolated campaign generator records whether sampled alternatives come from one multi-row rotation or several disjoint swaps. HARD repairs can sample additional alternatives once per seed lineage and retain earlier proof feedback while traversing ambiguous candidates. The analyzer shares the conflict graph across rounds and can continue a stalled trace when adding lower-priority techniques. Exhaustive uniqueness checks remain independent, and all original controlled technique subsets still apply. See [CAMPAIGN_SIMULATION.md](CAMPAIGN_SIMULATION.md) for the matched benchmark.

The same 5,000 requests validated 3,671 puzzles (73.42%), up from 3,645 (72.90%). HARD rose from 753 to 779 and accounted for all 2,103 fewer multiple-solution rejections. The other five profiles reproduced the prior definitions and outcomes. The measured difficulty phase fell from 190.840 s to 147.652 s. NIGHTMARES still fulfilled just 15/499, and only nine of its 1,737 unique repairs passed the gate. The matched pilot reduced EXTRA HARD and NIGHTMARES yield when it applied the new repair policy to those profiles, so they retain the previous construction policy.

Godot 4.7.2 check-only validation, advanced deduction, construction, uniqueness repair, schedule, calibration and prototype regressions passed. The windowed terrain pixel fixture passed. The full run recorded no invalid acceptances, and the independent Python audit verified every accepted board. The benchmark stayed isolated from campaign session loading. The live save hash changed during the full-run interval for an unconfirmed reason. A subsequent isolated 100-request rerun confirmed the hash stayed unchanged in that interval.

### Save isolation and advanced-generation diagnostics

The campaign benchmark creates a schedule and generator directly. Its only explicit file write is the JSONL report. The earlier harness defaulted to a report in `user://` and accepted arbitrary output paths. The prototype test supplies a randomly named `test-profile-*.save` to its session before attaching the board scene. The terrain fixture writes a separate preview PNG. Running the ordinary main scene creates a session with the default `user://campaign.save` and can checkpoint an active campaign attempt roughly once a second or on exit.

The previously observed hash change cannot be attributed to a specific process. The live Godot logs record separate windowed engine launches around that run, so another instance running the main scene could have written the file. The audit used read-only checks on the live profile. Both headless and windowed startup smoke tests wrote their campaign profiles under separate workspace test directories. The prototype and windowed terrain suites also passed with isolation enabled. The live hash matched before and after those tests.

On Windows, launch Godot tests and benchmarks through `tests/run_isolated.ps1`. It creates a fresh workspace directory and redirects `APPDATA` for each child process, including windowed runs. The benchmark verifies Godot's resolved user directory before opening its output and accepts only a bare JSONL filename within it. Negative checks rejected both a missing isolation setting and `campaign.save` as the report name.

```powershell
.\tests\run_isolated.ps1 -Godot $godot -Script res://tests/campaign_simulation.gd -UserArguments @('1200','advanced-pilot.jsonl','advanced')
.\tests\run_isolated.ps1 -Godot $godot -Windowed -Scene res://tests/terrain_visual_test.tscn -UserArguments @('--capture')
```

The runner prints the isolated directory and full report path. For the prior generation policy, use `multi_row` as the third benchmark argument. Historical direct commands in the simulation report record earlier runs. Use the isolated launcher for new runs.

The advanced policy increases the share of NIGHTMARES starts eligible for the existing two-domino implication construction. Boundary repair preserves both two-cell regions, so those strong links cannot be lost by growing them. When a unique candidate has a simpler proof, repair can favor edits that add an alternative to an early shared conflict or group reservation. The planned path can still be bypassed by easier reasoning or fail to lead to a complete proof. Every accepted candidate goes through the original uniqueness and technique-subset gates. The two highest gates now also reuse the static layout conflict graph across their technique-subset checks, with fresh candidate state for every proof.

In the first 700-stage pilot, broader application of the new repair score reduced EXTRA HARD from 33 to 30 and held NIGHTMARES at two. In a 1,200-stage trial, increasing the share of general seeded starts for EXTRA HARD reduced it from 52 to 39. The retained policy uses the previous EXTRA HARD construction and applies the construction changes only to NIGHTMARES.

The matched 1,200-stage NIGHTMARES sample rose from 3/120 to 4/120, with 1/34 at 8×8, 1/41 at 9×9, and 2/45 at 10×10. All four accepted proofs needed implication chains. Ambiguous rejections rose from 6,187 to 6,204. Of 205 sampled NIGHTMARES alternatives, 195 changed at least three rows. Repairs reaching uniqueness rose from 424 to 468, but only three passed the gate in each run. In the new run another 420 unique repairs admitted a classic proof, 38 admitted a chain-free triple proof, and seven still stalled with chains. Structurally preserving the two strong links did little to prevent easier proofs. NIGHTMARES remains unreliable and the pilot is too small to establish a stable yield gain. A chain construction that also blocks the earlier classic shortcuts remains open.

The final pilot returned 880 boards, with 320 budget exhaustions, no invalid acceptances and a matching live save hash. BASE through EXTRA HARD reproduced their previous outcomes, boards, rejection counts and proof signatures. EXTRA HARD remained at 52/120. The independent Python audit verified all 880 boards, and the Godot proof audit found no lower-difficulty acceptances. All six headless regression suites passed, including equality of the complete proof reports for all 32 technique masks with or without conflict-graph reuse. A new 5,000-stage benchmark remains pending.

### NIGHTMARES-first development

NIGHTMARES is the only generation target in this milestone. The production gate still requires all 16 chain-free subsets to stall and a complete proof with explicit implications. A candidate replacement for a later calibration milestone would retain that easier-proof exclusion and admit a complete proof with at least one independently necessary advanced family, such as matching or bounded contradiction. Before adopting it, compare full and family-ablated runs from scratch, test alternate deduction orders, and inspect dependency depth and which constraints each advanced move connects. A long trace or a large board alone is insufficient. The proposed profile is experimental and is not used to accept puzzles in this milestone.

The opt-in Hall rule checks region subsets of size four or more against their combined possible rows or columns. If K regions reserve exactly K lines, other regions cannot use those lines. The original restrictions, pairs and triples already cover smaller K. Fixtures verify both orientations at K=4 and a five-region alternating cycle with no smaller reservation. In the projected region-to-line graph, alternating cycles support alternative matchings. A projected matching by itself says nothing about the other axis or diagonal contacts. The implementation emits an explicit Hall witness instead of giving matching cycles a second deduction name. Current shared conflicts already cover immediate fatal squares, while adjacency triples enforce compatibility across three required groups. Bounded contradiction from the preceding audit remains opt-in. Current implication search already finds paths beyond five links when needed, so there is no separate longer-chain rule.

The isolated construction service starts from 18 previously verified boards spanning the three sizes. It moves a non-bear boundary cell while protecting two-cell terrain groups used in the parent proof. It independently rechecks connectivity, minimum region sizes, uniqueness and all original proof gates after every candidate edit. It starts a fresh bounded search with at most eight edits per request. If those edits fail, it may consume a separate prevalidated reserve board. The reserve was prepared offline in the harness by expanding the accepted edit graph, subject to an 8,000-edit cap per size. Existing campaign assignments and player saves are outside this service. The request caller owns the exclusion set and would need to persist it before using this in a live session.

The isolated test used 120 new seeded requests per size. A layout identity ignores terrain relabeling, rotation and reflection. The 360 served boards were all unique by that measure and passed a separate Python flood-fill and solution enumeration. Fresh fulfillment accounted for 254 boards, and 106 came from the reserve. The fresh-only target therefore remains unmet. The reserves were built from closely related proof templates, so this result applies to the tested inventory and exclusion window and does not establish indefinite fulfillment.

| Size | Fresh | Reserve | Failed after reserve | Independent bear arrangements | Near pairs out of 7,140 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 8×8 | 67 | 53 | 0 | 5 | 213 |
| 9×9 | 82 | 38 | 0 | 6 | 124 |
| 10×10 | 105 | 15 | 0 | 7 | 72 |

Near pairs differ by one to four internal boundary edges after aligning through any rotation or reflection. The most frequent bear arrangements occurred 51, 24 and 21 times respectively. Local edits preserve the unique answer of their root, which explains the narrow answer space. The reserve offers measurable layout variety, with particularly concentrated answer reuse at 8×8.

| Size | Runtime terrain / uniqueness / gate rejections | Previously served candidates skipped | Mean / worst (ms) | Longest implication (links) | Dependency depth |
| --- | ---: | ---: | ---: | ---: | ---: |
| 8×8 | 240 / 161 / 69 | 149 | 47.1 / 159.7 | 9 | 11–18 |
| 9×9 | 203 / 142 / 73 | 93 | 81.2 / 263.7 | 13 | 11–19 |
| 10×10 | 149 / 101 / 35 | 46 | 113.8 / 239.0 | 9 | 11–19 |

Each reserve reached 120 boards after 349, 372 or 313 offline edits respectively. Runtime timing includes fresh search and reserve selection, excluding reserve preparation and independent auditing. On the first 24 seeds at each size, the previous 64-candidate construction served 1, 1 and 0 requests. It rejected 996, 1,303 and 1,394 ambiguous candidates. The new strategy reduces the search by staying near a valid proof and keeping the intended placement intact. Earlier ambiguity diagnostics still show multi-row alternatives, so each edited layout goes through a new exhaustive uniqueness check.

Among 23 representatives with different implication lengths and counts, enabling Hall confinement after the full chain-free analyzer stalled yielded zero alternative complete proofs. Horizontal reflection, which changes the scan order, produced zero easier proofs under the production subsets. This samples one alternative order. Across each representative's weak links, at least three of row, column, region and diagonal conflict appeared, and 13 of 23 used all four. The first implication excludes one cell. Six to nine bears were subsequently confirmed over the remaining proof, sometimes following additional implications. Every representative reproduced its proof from the layout and completed in gameplay state when the correct bears were placed in reverse row order.

The six board-only fixtures in `tests/nightmares_playtest_examples.json` provide two proof structures per size for blinded playtesting. Track clarity, enjoyment, frustration, perceived difficulty, and which deductions felt satisfying. These metrics describe automated proofs. The prototype renderer stops at 7×7, so the larger boards' visual readability and player experience still need evaluation.

Godot 4.7.2 passed the NIGHTMARES reliability and quality audits, the logical audit, and all six headless regression suites. The independent Python audit checked every returned board. The isolated run preserved the live save hash. No mixed 5,000-stage run was performed.

```powershell
.\tests\run_isolated.ps1 -Godot $godot -Script res://tests/nightmares_reliability.gd -UserArguments @('--control')
python tests/nightmares_report.py <printed-results-path>
```

### NIGHTMARES diversity and reserve audit

The original 5, 6 and 7 solution counts were exact bear placements in board coordinates. Recounting up to rotation and reflection leaves the same counts. The benchmark started with exactly 5, 6 and 7 fixed proof roots. Each edit protects the parent's bears, which remain a valid solution. The independent uniqueness gate rejects any edit that also admits another solution. Consequently, the 360 distinct layouts may provide different deductions while still repeating answers. The most common original 8×8 arrangement appeared on 51 of 120 boards.

A bounded search of 48 independent procedural seeds per size produced one additional validated root each at 8×8 and 9×9 and none at 10×10, using the existing 64-candidate budget. Adding those roots improved both answer variety and fresh fulfillment on the same 120-request sequences. All three hybrid batches still filled 120 requests under unchanged gates.

| Size | Exact and symmetry-normalized arrangements, control → trial | Fresh, control → trial | Reserve, control → trial |
| --- | ---: | ---: | ---: |
| 8×8 | 5 → 6 | 67 → 76 | 53 → 44 |
| 9×9 | 6 → 7 | 82 → 102 | 38 → 18 |
| 10×10 | 7 → 7 | 105 → 105 | 15 → 15 |

Across the augmented batches, 283 boards were fresh and 77 came from the reserve. Near-layout pairs fell from 213 to 171 at 8×8 and from 124 to 81 at 9×9, with 72 at 10×10 on both runs. Near pairs differ by one to four orthogonal boundary edges after alignment by a rotation or reflection. The most common 8×8 answer fell from 51 to 34 occurrences. The independent verifier found zero symmetry-equivalent layouts within each batch or reserve. The full reserves contained only 6, 6 and 4 distinct answers respectively, fewer than the hybrid stream at 9×9 and 10×10. The breadth-first build can fill capacity before visiting every root, and shape variety alone does not establish adequate long-term variety.

The reserve remains an isolated prototype, with no campaign assignment integration or automatic replenishment. The request API now counts fresh exhaustion and reserve exhaustion separately. A spent reserve returns an empty result and increments the exhaustion counter, with no silent reuse of an excluded layout. A future caller must persist the exclusion set and surface depletion to the player. A finite inventory can run out even after a successful benchmark.

For each size, a reserve-only drain served 120 distinct layouts before the next ten requests explicitly reported exhaustion. Mean in-memory reserve lookup was 0.130, 0.112 and 0.124 ms, with a worst observation of 0.506 ms across all sizes. This excludes preparation and validation. The complete hybrid request, including fresh search before reserve lookup, averaged 53.4, 90.4 and 114.1 ms, with a worst observation of 230.7 ms. These are isolated measurements, not live UI load-time results. The prototype persistence suite passed, including the existing assignment-preservation test. The live campaign save hash stayed unchanged during the matched trial.

The six existing fixtures are in [the blinded paper playtest packet](tests/NIGHTMARES_PLAYTEST.md), with a separate score row for each board. Record completion and elapsed time separately from perceived difficulty, fairness, clarity and reward. No human sessions have been conducted. This format omits the game's immediate feedback and heart penalties, so it can test the underlying deductions before the larger boards have a live UI.

Run the matched procedural-root trial and drain test with `.\tests\run_isolated.ps1 -Godot $godot -Script res://tests/nightmares_reliability.gd -UserArguments @('--diversity')`. The JSON report includes both controls and every reserve entry. Pass the report to `python tests/nightmares_report.py` for independent connectivity, uniqueness and diversity checks. The Godot script's `--verify-reserve` mode takes the same report path and reruns the proof and all 16 chain-free subsets directly.

Both audits passed. The Python verifier checked all 720 served boards across control and trial and all 360 trial reserve entries. Each reserve board solved with the full analyzer and stalled under all 16 chain-free subsets in the independent Godot pass. The 5,000-stage benchmark was not rerun.

### NIGHTMARES elimination-first and construction freedom

The production analyzer already starts with every cell as a candidate and tracks the exactly-one groups for rows, columns and regions. It propagates confinement, pairs, shared conflicts, three-group compatibility and implication chains before any bear is committed when no group has a single candidate. A placement is committed only when its group has one candidate. The audit runs from an untouched layout. The independent solution is used only to check deductions after they are produced.

The opt-in elimination analyzer reuses the generalized Hall rule and the bounded contradiction implementation from the logical audit. On a stall it can try a Hall witness, or copy the candidate state, assume a bear and propagate at most eight forced placements. If a required group empties, the trace names the group and records the hypothetical placements as evidence for excluding the assumed cell. Neither the assumption nor its consequences become committed placements. There are no nested guesses. The existing NIGHTMARES acceptance gate is unchanged.

The current proof-root builder starts from a small fixed library. Its boundary edits preserve the intended bear array and protect exactly-two-cell regions used in chains. Those are construction choices. The acceptance checks require exactly N distinct connected regions, the existing NIGHTMARES singleton limit, a unique legal solution and a complete qualifying proof. Connectivity is checked by flood fill and independently rechecked in Python. There are no area-equality, width, compactness, aspect-ratio or symmetry requirements.

The new sampler counts the legal completions for every remaining-column mask and previous column. It weights the next column by its completion count, so every complete legal arrangement has equal probability before terrain growth. The counts are 5,242 at 8×8, 47,622 at 9×9 and 479,306 at 10×10. This is the legal placement space before imposing a terrain partition, uniqueness or reasoning requirements.

The matched pilot used 32 requests per size and at most eight candidate attempts per request, with no reserve. The geometry-only arm stopped protecting two-cell proof regions during edits. The expanded arm used the first two attempts for newly sampled placements, alternating a planned implication motif and ordinary connected growth, then used up to six freer root edits.

| Size | Current / freer edits / expanded fulfilled | Accepted answer classes in each arm | Current / expanded mean (ms) | Current / expanded worst (ms) |
| --- | ---: | ---: | ---: | ---: |
| 8×8 | 29 / 29 / 24 | 5 | 67.4 / 62.9 | 128.5 / 130.3 |
| 9×9 | 32 / 32 / 26 | 6 | 95.0 / 80.2 | 131.1 / 162.4 |
| 10×10 | 32 / 32 / 30 | 7 | 115.1 / 125.6 | 182.8 / 226.6 |

Independent placements yielded 63, 64 and 64 distinct starts from 64 attempts per size. All 192 broad starts were rejected. There were 183 ambiguous layouts, eight layouts with easier proofs and one failed terrain construction. Every expanded-arm success came from a root edit. The extra sampling widened the attempted solution space and reduced fulfillment at the same budget, with no new accepted bear arrangements. Removing the proof-region protection alone returned exactly the same accepted boards as the control. The default policy remains in use. Future improvements need better terrain constraints or ambiguity repair around unfamiliar anchors rather than substituting raw starts for proven edits.

The current accepted boards already support irregular terrain. All 93 contain a region with a cell whose removal would disconnect it, and 35 contain a region spanning opposite edges. Maximum region areas were 30, 29 and 43 cells by size. The expanded arm produced opposite-edge spans in 36 of its 80 accepted boards. An area or corridor statistic describes a board and is not an acceptance criterion.

| Size | Deductions before first bear, current → expanded | Candidates eliminated before first bear, current → expanded | Opening dependency depth, current → expanded | First bear reachable with classic families, current → expanded |
| --- | --- | --- | --- | --- |
| 8×8 | 1–15 → 1–14 | 5–46 → 6–44 | 1–9 → 1–7 | 24/29 → 18/24 |
| 9×9 | 1–21 → 1–21 | 7–57 → 7–57 | 1–9 → 1–9 | 27/32 → 21/26 |
| 10×10 | 1–3 → 1–3 | 8–23 → 7–23 | 1 → 1–2 | 32/32 → 30/30 |

These are the recorded deterministic proof prefixes, not minimum move counts across all possible orders. No accepted board forced a bear before its first elimination. Restrictions and shared conflicts offered untouched-board eliminations in all arms. The current boards also offered an explicit chain immediately in 24/29, 28/32 and 27/32 cases. Detected untouched options across the inspected families covered an average of 31.1, 39.7 and 51.8 distinct cells by size. The Hall probe emits one witness at a time, and the triple probe uses its existing priority order, so these counts measure demonstrated options, not all logically implied X marks.

Classic reasoning could reach a first bear on most boards even though chain-free proofs could not complete them. In the current arm, all five 8×8 boards that stalled before the first bear without chains reached it with triples disabled and chains enabled. Five 9×9 boards stalled before the first bear in both single-family ablations, although the full analyzer reached it. This demonstrates different opening dependencies without requiring a specific opening or minimum X count. Construction produced six, seven and four distinct ordered opening technique signatures by size in the control, versus five, five and three in the expanded arm.

All 266 accepted results, including repeated boards across comparison arms, passed independent uniqueness verification and the existing full NIGHTMARES gate. Adding bounded contradiction to the chain-free analyzer completed all 266 proofs, and adding only Hall confinement completed none. This demonstrates an alternative advanced proof on this sample. It provides no evidence that the existing easier technique sets can finish those boards or that the broader construction policy increases yield. The test checked every experimental exclusion against the independent solution after the proof and detected no invalid exclusion.

Godot 4.7.2 passed the opening and logical audits and all six headless regression suites. The isolated opening run left the live save hash unchanged. No large campaign benchmark was rerun.

```powershell
.\tests\run_isolated.ps1 -Godot $godot -Script res://tests/nightmares_opening_audit.gd
python tests/nightmares_opening_report.py <printed-results-path>
```

### Seamless terrain rendering

`scripts/board_terrain.gd` uses a `TileMapLayer` and a square `TileSet` with a separate atlas source for each material. The puzzle's region ID selects the atlas. The cell's board coordinate selects the matching crop from that atlas, so textures continue across same-region cells. Terrain-autotile edge matching and random variants were evaluated. The renderer uses fixed board-space crops because those provide continuous texture detail and exact material placement across arbitrary puzzle layouts.

`scripts/terrain_surfaces.gd` creates procedural placeholder sheets for grass, wood, stone, dirt, mud, gravel, forest floor, water, sand and moss. To supply replacement art, assign continuous 840 × 840 sheets to the main scene's `terrain_sheets` array in that order. Empty slots retain the procedural version. The scene draws a one-pixel translucent grid and a separate four-pixel black outline on inter-region edges and the board perimeter. Transparent cell buttons keep their mark labels and input above both border systems.

Open `tests/terrain_visual_test.tscn` in Godot and run the current scene to inspect the seven-material fixture. `godot --path . res://tests/terrain_visual_test.tscn -- --capture` runs the windowed pixel checks and saves `user://terrain-preview.png`. The playable grid and terrain share one uniform transform to fit larger boards in the existing viewport. `godot --path . -- --puzzle-diagnostics` prints the logical deduction count and singleton region count on each puzzle load to the developer console.

#### Procedural material audit

`terrain_surfaces.gd` defines material IDs and base colors in `MATERIALS` and `BASE_COLORS`. `make_texture()` shades the full sheet with seeded noise and applies the material pattern below. `BoardTerrain.set_board()` selects the source by region ID and samples the sheet at the board's cell coordinate. `_ensure_atlas()` provides that source and its replacement-art slot. The renderer supports ten materials and a ten-cell atlas per side.

| Material | Base color | Current pattern and visual result |
| --- | --- | --- |
| Grass | `#416831` | Short `_stroke()` blades over mottled green. Recognizable as stylized turf. |
| Wood | `#96633a` | Horizontally warped sinusoidal grain in `make_texture()`. Reads as wood grain, with no knots or end grain. |
| Stone | `#536271` | Large shaded `_scatter()` / `_oval()` shapes. Reads as smooth cobbles. |
| Dirt | `#80503b` | Fine scattered grains on reddish-brown noise. Reads as dry granular soil. |
| Mud | `#47403d` | Dark, clouded pooling and faint bands in `make_texture()`. Wetness is only weakly conveyed. |
| Gravel | `#827a6b` | Many small shaded ovals. Reads as pebbles, sharing stone's rounded silhouette at a smaller scale. |
| Forest Floor | `#564b31` | Rotated brown ovals with `_stroke()` veins. Reads as simplified leaf litter. |
| Water | `#26749d` | Curved ripple highlights. |
| Sand | `#c9a255` | Fine stipple on warm gold. |
| Moss | `#3b8070` | Rounded teal-green clusters. |

The seven- and ten-material pixel fixtures check continuity and boundaries. Human contrast and glyph readability across display scales remain open.

### 1,500-puzzle BASE replayability test

Godot 4.7.2 generated seeds 0–1499 with one generator instance and its standard 32-candidate budget. Seed 0 was the 4×4 introduction. Subsequent sizes cycled 5×5, 6×6, 7×7, starting at seed 1. An independent check flood-filled terrain, enumerated legal non-touching column permutations, and compared the sole solution with the BASE trace. All 1,500 boards passed, each with one singleton. Earlier returned region arrays remained unchanged after all later generations.

| Size | Boards | Label-free layouts | Layouts up to rotation/reflection | Complete definitions | Bear arrangements | Candidate acceptance | Rejections | Failures / fallbacks | Mean / median / worst (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4×4 | 1 | 1 | 1 | 1 | 1 | 100.00% | 0 | 0 / 0 | 0.655 / 0.655 / 0.655 |
| 5×5 | 500 | 499 | 492 | 499 | 14 | 67.93% | 236 | 0 / 0 | 0.729 / 0.606 / 3.155 |
| 6×6 | 500 | 500 | 500 | 500 | 90 | 36.31% | 877 | 0 / 0 | 1.361 / 1.114 / 6.198 |
| 7×7 | 499 | 499 | 499 | 499 | 325 | 24.03% | 1,574 | 0 / 1 | 2.397 / 1.929 / 9.901 |
| **All** | **1,500** | **1,499** | **1,492** | **1,499** | **430** | **35.81%** | **2,687** | **0 / 1** | **1.494 / 1.131 / 9.901** |

A complete definition includes size, difficulty, original terrain IDs and solved bear cells. Seeds 532 and 1417 produced the same 5×5 definition. Near matches differ across one to four orthogonal internal boundary edges in their given orientation. There were 23 such pairs across 41 boards, all 5×5. No exact or near match occurred between successive boards of the same size. The only fallback was seed 651 at 7×7 after exhausting all 32 candidates. It passed validation and did not repeat. The slowest request was seed 543 at 7×7 (9.901 ms, 10 rejections). None reached the test's 10 ms outlier threshold, though this was one timing run on one machine.

| Sequence segment | Label-free layouts | Symmetry-normalized layouts | Bear arrangements | Distinct reasoning signatures | Mean chain depth | Mean / worst (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Seeds 0–499 | 500 | 498 | 223 | 90 | 5.150 | 1.485 / 6.198 |
| Seeds 500–999 | 500 | 499 | 224 | 93 | 5.182 | 1.637 / 9.901 |
| Seeds 1000–1499 | 500 | 498 | 230 | 95 | 5.148 | 1.361 / 8.121 |

All boards used a singleton placement followed by last-candidate-in-region placements and their normal exclusions. Complexity was 1 in every trace. Deduction counts (minimum / mean / median / maximum) were 4 / 5.998 / 6 / 7 overall and exactly the board side within each size. Chain depths were 3 / 5.160 / 5 / 7 overall. The 125 reasoning signatures use board size, ordered techniques, choices per round and chain depth. The most common signature occurred 97 times. For example, 5×5 seeds 1 and 16 have the same five steps but chain depths of 3 and 5. The 7×7 sample ranges from depth 4 at seed 90 to depth 7 at seed 6. These are differences in proof structure, without a calibrated player difficulty judgment.

Layout variety held across all thirds. Reasoning variety was narrower, and 5×5 reused just 14 bear arrangements across its 500 boards. A future progression system could avoid recent symmetry-normalized repeats and sample for diverse BASE proofs, including more row- and column-forced placements. The simulation used a fixed size rotation for reproducibility. The proposed campaign policy is one 4×4 introduction followed by 5×5 or larger boards. Campaign scheduling and assignments were untouched.

The existing headless suite passed with zero failures, and the windowed seven-material pixel fixture passed. The live campaign save hash was unchanged.

### Playable Free Play difficulty testing

Free Play offers BASE at 4×4–7×7, EASY and MEDIUM at 5×5–7×7, HARD at 6×6–8×8, EXTRA HARD at 7×7–9×9, and NIGHTMARES at 8×8–10×10. Normal play chooses a size automatically. Provisioning runs in a worker and uses the existing acceptance gates. An exhausted request reports failure and leaves the current board available. NIGHTMARES tries fresh construction first, then revalidates a reserve board outside the current repeat window for that size. The reserve holds 120 entries per size, and older layouts become available again as the window advances.

Launch with `--free-play-dev` to expose the collapsible **Developer** window. It offers exact eligible sizes, random or explicit seeds, validation and source metadata, restart, and one save/reopen slot at `user://cubdoku-playtest.json`. Reopening checks the stored layout, solution and difficulty again. Seed replay depends on the generator version and the current NIGHTMARES exclusion set. Save the full definition to reproduce a particular layout.

The optional proof viewer derives moves from the terrain and committed visible marks. It lists the first applicable set of moves, then a sequential proof. Switch to the Hall and contradiction mode to inspect chain-free alternatives. The viewer never reads the stored solution. It leaves marks, hearts and campaign progress unchanged.

The terrain, borders and mouse hit targets share one uniform scale at every size. The three additions use ripple patterns for Water, fine stippling for Sand and clusters for Moss. Automated tests establish correctness and rendering alignment. Human difficulty, material legibility across hardware and perceived sound quality still need playtesting.

Godot 4.7.2 passed the prototype suite headless and windowed and the six other headless suites. The prototype checks played all six difficulties with exact overrides, including completing NIGHTMARES at 8×8, 9×9 and 10×10 with injected mouse input. It checked tile and hit-target alignment, incorrect-mark penalties, locking, a red flash and warning playback on wrong X, restart identity, read-only diagnostics, definition reopen and explicit reserve exhaustion. The windowed seven- and ten-material pixel checks passed. Tests preserved the campaign attempt on return and compared its on-disk bytes through Free Play. The live save hash was unchanged.

```powershell
.\tests\run_isolated.ps1 -Godot $godot -Windowed -UserArguments @('--free-play-dev')
```

### NIGHTMARES 5,000-request stress test

The isolated Free Play service fulfilled 462 of 5,000 consecutive NIGHTMARES requests (9.24%), with 330 fresh results, 132 reserve results and 4,538 explicit exhaustions. The accepted totals were 120/1,667 at 8×8, 125/1,667 at 9×9 and 217/1,666 at 10×10. The first 120 requests per size still fulfilled 360/360, with 262 fresh and 98 reserve. The last successful request was 903. All 360 reserve layouts were eventually consumed or excluded because a fresh request had already served the same layout. No layout repeated under the current symmetry and label exclusions.

Every returned board passed independent connectivity, uniqueness and NIGHTMARES proof checks. The exact and symmetry-normalized answer counts were both 6, 6 and 7 by size. A reflected and relabeled proof audit found no chain-free shortcuts. Bounded contradictions completed all 462 proofs as an alternative advanced technique, while Hall confinement alone completed none. The generation gate and eight-attempt budget were unchanged.

Summed request time was 326.40 s, including 193.75 s in reserve lookup and validation. Repeated scans of spent inventory dominated that phase. The Godot 4.7.2 regressions and independent Python audit passed. The live campaign save was never opened. See [the detailed stress-test report](NIGHTMARES_STRESS_TEST.md) for proof, geometry, replayability, timing and reproduction details.

### NIGHTMARES failure investigation

Exhaustive enumeration of the runtime's fixed one-cell edit menu verified 435 eligible layouts across the three sizes. The union with the shipped reserve contained exactly the 462 canonical layouts served in the stress run. The remaining requests could only revisit served layouts or reject invalid, ambiguous or misclassified proposals. The cutoff at request 903 was specific to that seed order and history. All seven sampled later requests produced fresh boards with empty history and no reserve, while original or final history reproduced their failures. Changing seeds did not recover a new eligible board from the spent inventory.

The production exclusion is scoped to one Free Play service and compares exact layouts up to terrain relabeling, rotation and reflection. There is no persistent registry, answer-arrangement filter, near-layout filter or used-seed limit. Reuse limits, root-constrained edits and a shared finite reserve combine to cap long-session novelty. The unchanged gate rejected 129 of 564 unique edit proposals. Experimental Hall and bounded contradiction completed all 25 sampled chain-stall cases, which supports a separate calibration study.

The isolated Godot diagnostics did not modify production code, validation gates, budgets, or save data. No full benchmark was rerun. See [NIGHTMARES_FAILURE_INVESTIGATION.md](NIGHTMARES_FAILURE_INVESTIGATION.md) for stage counters, terrain controls, reproduction commands and recommended next steps.

### NIGHTMARES rolling availability and expanded construction

Free Play now remembers the last 32 served NIGHTMARES layouts per size. The identity still ignores terrain labels, rotations and reflections. It does not compare bear arrangements or consult past sessions. After a layout leaves the window, both generation and reserve lookup can serve it again. Reopening a definition refreshes its position in the window. The provisioner accepts a window override, with zero disabling it and minus one restoring unlimited exclusion for the historical control.

The expanded policy adds seven independently generated roots using a bounded offline search of 96 seed requests per size through the existing campaign-generation algorithm. It also keeps up to eight recent, fully validated fresh children per size as additional parents. A child can therefore accumulate multiple boundary changes over successive requests. Each request still attempts at most eight edits. Every proposed output goes through the existing structure, uniqueness and difficulty checks. The reserve caches layout keys and revalidates the selected board. The Free Play provisioner remains separate from campaign assignments and retries.

The 25 previously sampled chain-stall puzzles were rechecked. Every one solved with the opt-in analyzer, used at least one bounded contradiction, and retained every independently verified bear in its proof. All 16 existing chain-free subsets stalled and Hall alone did not finish any. The alternative proofs used 35 bounded contradictions in total. These are concrete cases of advanced reasoning beyond the current chain-only acceptance rule.

For a later gate calibration, require independent uniqueness and a complete reproducible proof. Check that all existing simpler masks stall, and ablate the extra reasoning families to demonstrate necessity. For contradiction-based proofs, collect the number of forced consequences, the empty group witness, which row, column, region and adjacency rules interact, and whether reflected or reordered scans find an easier proof. Compare those measurements with the chain-based reference set and blinded human playtests before choosing thresholds. The existing acceptance rule is unchanged.

The matched trial issued 144 requests per size and arm using seeds 67000 + 1000 × side + zero-based request index. All arms used the same reserve and candidate budgets. The legacy arm disabled expanded roots and used unlimited exclusion. The rolling-only arm changed only exclusion. The expanded arm is the new default. “Fresh” means generated and validated during the request, including any permitted repeat. “Novel” counts distinct layouts outside the entire 462-layout historical set.

| Policy | Size | Fresh / reserve / failed | Distinct / novel | Exact and symmetry-normalized answers | Repeats / request gap range | Mean / worst (ms) |
| --- | --- | --- | --- | ---: | --- | --- |
| Legacy | 8×8 | 69 / 51 / 24 | 120 / 0 | 6 | 0 | 68.8 / 418.2 |
| Legacy | 9×9 | 78 / 46 / 20 | 124 / 0 | 6 | 0 | 135.1 / 567.4 |
| Legacy | 10×10 | 130 / 14 / 0 | 144 / 0 | 7 | 0 | 382.8 / 1,589.4 |
| Rolling only | 8×8 | 126 / 18 / 0 | 86 / 0 | 6 | 58 / 33–134 | 254.1 / 1,290.5 |
| Rolling only | 9×9 | 132 / 12 / 0 | 96 / 0 | 6 | 48 / 34–118 | 358.2 / 1,967.5 |
| Rolling only | 10×10 | 140 / 4 / 0 | 116 / 0 | 7 | 28 / 34–129 | 304.2 / 2,577.8 |
| Expanded | 8×8 | 134 / 10 / 0 | 136 / 98 | 11 | 8 / 35–114 | 202.6 / 1,632.9 |
| Expanded | 9×9 | 139 / 5 / 0 | 131 / 80 | 7 | 13 / 35–112 | 256.1 / 2,518.2 |
| Expanded | 10×10 | 143 / 1 / 0 | 137 / 81 | 8 | 7 / 41–125 | 264.2 / 1,922.2 |

Rolling reuse alone served 432/432 with 134 repeats and 34 reserve results. Expansion served 432/432 with 28 repeats and 16 reserve results. The 259 novel distinct layouts were all freshly constructed. The old pool and these discoveries establish a lower bound of 721 distinct eligible layouts across both policies. The evolving parent graph was not enumerated exhaustively. The exact and symmetry-normalized repeat counts agreed in this sample. No repeat fell within the rolling window. Timings include cold root validation and reserve lookup, exclude testing audits, and reflect concurrent test activity on one machine.

All 259 novel layouts had a branching region and an orthogonal articulation cell. Seventy-nine included a region spanning opposite edges. Their largest observed regions by size occupied 30, 31 and 43 cells. Seed sampling and parent expansion improve answer diversity without enforcing compactness, uniform areas or minimum widths. The independent Python audit flood-filled each accepted board and verified its unique solution. The generation path used the unchanged logical gate on every result.

The Godot proof comparison reproduced all archived and novel-layout solutions with no mismatches. The novel layouts introduced 32, 7 and 15 technique-order signatures absent from the original run. The isolated Godot 4.7.2 prototype, logical audit, advanced deduction, construction, uniqueness repair, schedule and calibration suites passed. The prototype test covers the A–B–A progression of a one-board window and existing campaign assignment protection. No live campaign save was accessed, and no new 5,000-request run was performed. The short run supports availability with bounded reuse and increased novelty, without establishing indefinite novelty or human difficulty.

Reproduce the independent root search with `tests/nightmares_root_search.gd` via the isolated runner. The seven shipped search results are in `data/nightmares_expanded_roots.json`. Run `tests/nightmares_window_trial.gd` with the historical stress JSONL path and one of `legacy`, `rolling`, or `expanded`. Pass the three output logs to `python -B tests/nightmares_window_report.py`. The Godot comparison mode takes the historical log, expanded log and `proofs` as arguments.

### Verification

- Godot 4.7.2 passed GDScript check-only validation and headless and windowed startup smoke tests. Local startup emitted a Windows root certificate-store diagnostic. The windowed run also reported unavailable shader caching.
- `godot --headless --path . --script res://tests/prototype_test.gd` passed with zero failures. Tests cover invalid terrain, zero and multiple solutions, deterministic generation, fallback, mark handling, hearts, restart, elapsed time and completion.
- Godot 4.7.2 passed check-only validation, the updated headless suite and two consecutive startup checks. The suite verifies two profiles at the same level, persistence across reconstructed sessions, attempt and failure counts, best times, Free Play isolation, and preservation of unsupported saves. It also pins legacy fixture #8 and validates all eight legacy fixtures. Verification redirected Windows `APPDATA` to the workspace because the sandbox restricts writes to the default user directory.
- After BASE calibration, Godot 4.7.2 passed GDScript validation and the full headless suite. Across 1,000 seeded requests, 1,000 candidates were accepted and zero rejected, with zero failed requests or fallbacks. Mean generation was 0.408 ms and worst-case generation was 3.005 ms in that run. The batch verified 740 distinct layouts ignoring terrain labels, 18 region-size patterns and both possible bear arrangements. It also exercised every forced-placement technique. A separate test verified the fallback. Persistence tests confirmed that opening, restarting and returning from Free Play preserve a pre-calibration campaign assignment without a singleton.
- Independent review used a separate exhaustive enumeration and connectivity check on 1,000 generated boards, with zero mismatches. Review also found an out-of-range mark lookup, which was fixed and covered by the rerun suite.
- Godot 4.7.2 passed GDScript validation and the full headless and windowed suites after the terrain change. The windowed fixture passed material sampling on both sides of cell boundaries and checks for grid, region and perimeter lines. Visual inspection of the capture showed continuous grass, connected wood grain and stones crossing cell boundaries. Automated tests also checked exact tile-to-button alignment and region edge placement.
- Free Play size checks passed in Godot 4.7.2 headless and windowed, including the 4,000-puzzle generation batch and terrain pixel checks. The scene tests selected and completed all four sizes, checked the grid and borders against terrain IDs, exercised incorrect placements and X marks, and verified restart identity. The test campaign save remained byte-for-byte identical through Free Play, and returning restored the original puzzle and attempt. The live profile hash was unchanged during verification. A separate windowed check sent a pointer event to the bottom-right cell of the scaled 7×7 board and confirmed that it received an X mark. The diagnostic printed deduction and singleton counts for all four sizes.

Terrain artwork remains procedural and stylized. Physical keyboard and mouse interaction and visual checks across display scales remain open. Additional deduction techniques and higher difficulty calibration belong to later milestones.

## 5,000 NIGHTMARES requests and full campaign simulation

The production NIGHTMARES service fulfilled 5,000/5,000 isolated seeded requests, including 4,776 fresh builds and 224 validated reserve results. Independent flood-fill and solution enumeration verified every distinct definition and answer. All 16 chain-free technique subsets stalled on each served board, while the production logical proof solved it without consulting the answer. This run recorded 2,862 distinct partitions up to symmetry and labels, including 2,351 absent from both earlier journals. No partition returned inside the 32-board per-size window and the reserve did not exhaust. Mean request time was 156.13 ms, p95 was 341.38 ms, and the worst request took 2,142.57 ms. The most frequent 9×9 bear arrangement occurred 416 times. Full metrics and reproduction commands are in [NIGHTMARES_5000_REPORT.md](NIGHTMARES_5000_REPORT.md).

The second isolated process requested all 10,000 stages from the deterministic schedule. It preserved the five introductions, the 499 complete 7:5:4:2:2 blocks and the truncated 15-stage block of 5 EASY, 3 MEDIUM, 3 HARD, 2 EXTRA HARD and 2 NIGHTMARES. It fulfilled 8,301 stages with zero invalid acceptances. All 1,000 NIGHTMARES assignments succeeded, including 36 reserves. The other tiers exhausted 1,699 request budgets, led by 581 EXTRA HARD failures in 1,000 requests. The same first 5,000 requests improved from 3,671 to 4,155 fulfillments. All 4,501 lower-tier outcomes and definitions in that prefix matched the prior benchmark.

The mixed run recorded 8,101 canonical partitions and 219 exact definition pairs, of which 215 were NIGHTMARES. Fresh reconstruction contributed more repeat pairs than reserve reuse. The recorded technique masks satisfied the existing gates. Under alternative reasoning runs, 48 NIGHTMARES boards solved with a Hall extension and all 1,000 solved with bounded contradiction. The reflected production scans all solved, while chain-free reflected scans stalled on every NIGHTMARES board. These are reproducible alternative proof paths and provisional calibration evidence. The production gates, candidate budgets and no-repeat settings were preserved.

Both journals are recoverable in independent benchmark directories. The mixed journal pins each accepted stage's full definition. The planned full schedule remains a simulation, and the live campaign save/replay integration still covers the existing playable stages. All seven post-benchmark Godot 4.7.2 regression suites passed, including current campaign persistence and replay. No live campaign data was accessed. Full allocation, performance, repeat distances, technique overlap and artifact paths are in [CAMPAIGN_10000_REPORT.md](CAMPAIGN_10000_REPORT.md).

## EXTRA HARD reliability and remaining campaign gaps

The archived 10,000-stage journal recorded 1,699 budget exhaustions, of which EXTRA HARD accounted for 581. The table counts candidate rejections only within unfulfilled requests. Every such request used 64 attempts. “Too easy” combines the named easier-profile checks. “Stalled” combines the named logical stalls. The final column counts boards rejected by the unchanged single-family overlap rule.

| Difficulty | Size | Failed / requested | Multiple solutions | Too easy | Stalled | Family overlap |
|---|---:|---:|---:|---:|---:|---:|
| EASY | 5×5 | 2 / 1,237 | 58 | 39 | 31 | 0 |
| EASY | 6×6 | 113 / 1,154 | 5,023 | 514 | 1,695 | 0 |
| EASY | 7×7 | 376 / 1,107 | 20,635 | 651 | 2,778 | 0 |
| MEDIUM | 5×5 | 0 / 854 | 0 | 0 | 0 | 0 |
| MEDIUM | 6×6 | 12 / 837 | 685 | 50 | 27 | 6 |
| MEDIUM | 7×7 | 177 / 807 | 10,864 | 271 | 156 | 37 |
| HARD | 6×6 | 123 / 680 | 5,384 | 2,056 | 166 | 266 |
| HARD | 7×7 | 132 / 657 | 7,028 | 1,132 | 146 | 142 |
| HARD | 8×8 | 183 / 662 | 10,401 | 878 | 302 | 131 |
| EXTRA HARD | 7×7 | 165 / 339 | 7,846 | 2,666 | 48 | 0 |
| EXTRA HARD | 8×8 | 194 / 335 | 10,023 | 2,325 | 68 | 0 |
| EXTRA HARD | 9×9 | 222 / 326 | 12,647 | 1,482 | 79 | 0 |

EASY, MEDIUM and HARD account for 491, 189 and 438 exhaustions, respectively. Multiple solutions account for 60,078 of 71,552 rejected attempts across those 1,118 requests. For EXTRA HARD, ambiguity accounts for 30,516 of 37,184 attempts on failed requests. Of 4,108 EXTRA HARD ambiguity repairs that reached uniqueness across all requests, only 277 passed the gate (6.74%). Across all EXTRA HARD requests, the analyzer logged 9,321 classic-solvable rejections and 309 triple stalls. In the first ambiguous candidate on every fifth stage where one was recorded, 119/167 samples hit the 12-solution cap. The nearest alternate among the sampled witnesses changed at least three rows in 103 cases.

Ordinary EXTRA HARD starts with randomly chosen legal, row-indexed bear anchors and grows connected terrain from a proof-oriented or seeded frontier. Its planned seeded starts bias second-cell choices away from known two-row swap endpoints. Boundary edits preserve anchors and can remain in one lineage until a restart, at intervals of 16 attempts on 7×7 and 24 on larger boards. All 419 accepted boards contain a region articulation cell, and maximum region sizes reached 24, 28 and 32 cells by board size. Accepted boards had 143, 139 and 104 exact arrangements, or 69, 126 and 102 after symmetry normalization. The legal arrangement spaces before adding terrain constraints are 646, 5,242 and 47,622 respectively. The accepted sample shows broader starting diversity than the NIGHTMARES root system, although it does not measure anchor coverage across rejected lineages. The campaign service has no EXTRA HARD reserve or repeat history. Free Play can try up to three ordinary generation calls for the same chosen size.

EXTRA HARD must solve with triples plus the classic families, while every classic-only subset stalls. NIGHTMARES requires the chain-free profiles to stall. The useful transferable mechanism is editing or promoting separately validated roots while preserving anchors and rerunning the EXTRA HARD gate. Preserving NIGHTMARES two-cell implication links verbatim would protect a different proof structure. An EXTRA HARD edit scorer could instead protect the candidate sets needed by decisive triple deductions. This warrants a separate comparison against broader seed sampling and the existing repair scorer.

### Matched root-edit pilot

The test-only control used the current 64-attempt generator. The trial used the identical first 56 ordinary attempts and reserved up to eight attempts for independently checked, single-cell root edits. The roots were all 209 successful EXTRA HARD boards from stages 1–5,000. The held-out requests were the first 50 later EXTRA HARD stages of each eligible size, using their original seeds. The control reproduced all 150 archived outcomes and definitions. Both arms used the same 64-attempt cap. The experiment used neither reserve substitution nor repeat filtering.

| Size | Control fulfilled | Trial fulfilled | Accepted edits / novel partitions | Symmetry-normalized arrangements, control / trial | Mean ms, control / trial | p95 ms, control / trial |
|---|---:|---:|---:|---:|---:|---:|
| 7×7 | 25 / 50 | 49 / 50 | 29 / 29 | 19 / 34 | 177.6 / 197.5 | 382.7 / 433.4 |
| 8×8 | 18 / 50 | 49 / 50 | 35 / 35 | 18 / 41 | 169.9 / 168.9 | 376.0 / 340.2 |
| 9×9 | 16 / 50 | 50 / 50 | 36 / 36 | 16 / 42 | 214.4 / 219.6 | 464.2 / 428.5 |
| Total | 59 / 150 | 148 / 150 | 100 / 100 | 53 / 117 | 187.3 / 195.3 | 398.9 / 428.2 |

The trial recovered 89 formerly exhausted requests and fulfilled every request the control fulfilled. It accepted 48 ordinary results and 100 fresh edits. All 148 accepted partitions were distinct up to labels and symmetry. Novelty was measured against all successful EXTRA HARD boards in the 10,000-stage archive. Each edit remains within four orthogonal boundary-edge changes of its root and retains the root's bear arrangement, so novelty does not establish long-run variety. The 100 edit successes followed 79 structural rejections, 67 ambiguity rejections, 27 classic-solvable rejections and five triple stalls. Worst recorded generation time was 996.5 ms for the control and 763.9 ms for the trial. Timing excludes the audit and reflects local process contention during the run.

The Godot proof audit ran all 32 technique-family subsets without exposing the answer to the analyzer. No classic-only mask solved any accepted definition, and all solved with the classic-plus-triples mask. All also solved when chains were available, so the decisive distinction from NIGHTMARES is that the chain-free proof is sufficient. Python independently flood-filled and enumerated solutions for every accepted result. Both checks passed.

The next useful comparison is a larger holdout with further independent root sampling and root provenance tracked per size. Compare the fixed catalog with limited promotion of newly validated edits and measure near repeats and answer concentration. Keep unedited reserve retrieval as a separate experiment, with its usage explicitly recorded. This pilot observed zero duplicate partitions and provides no reason to impose additional repeat restrictions. The EASY 7×7, MEDIUM 7×7 and HARD 8×8 gaps are good targets for ambiguity-focused trials after EXTRA HARD validation. No production policy, saves or assigned definitions were changed, and no new full campaign benchmark was run.

Reproduce with the isolated runner, script `res://tests/extra_hard_trial.gd` and the archived campaign JSONL as its only user argument using a `res://` path. Pass the campaign journal and generated `extra-hard-trial.jsonl` to `python -B tests/extra_hard_trial_report.py`. The pilot output is in `.godot/isolated-f99cbda70b55491c92167687a7f5af2c/Godot/app_userdata/Cubdoku/extra-hard-trial.jsonl`.

Godot 4.7.2 regression results were zero failures for the prototype, logical reasoning audit, advanced deductions, construction plan, uniqueness repair, campaign schedule and difficulty calibration. `git diff --check` passed.

## EXTRA HARD root-edit holdout and production integration

Godot 4.7.2 ran 300 matched requests per size, using seed 4,300,000 + 1,000 × side + request index. None were used in the first pilot. Three isolated processes each ran the 64-attempt ordinary control, the 56 + 8 root-edit policy, and the same root-edit policy starting with an empty pool. The fixed catalog came from 240 ordinary requests per size with independent seeds 2,200,000 + 1,000 × side + index. The qualifying root counts were 89, 98 and 67, all distinct up to symmetry. Catalog generation and proof verification took 42–55 seconds by size in this concurrent run. The empty-start arm spent all 64 attempts on ordinary generation until its first success and then added ordinary successes as roots. Neither arm used a campaign archive, a player save, an unedited reserve board, or a repeat filter.

| Size | Ordinary | Fixed catalog | Empty start | Fixed-catalog edit successes | Ordinary / fixed p95 (ms) |
|---|---:|---:|---:|---:|---:|
| 7×7 | 138 / 300 | 293 / 300 | 294 / 300 | 175 | 162.3 / 150.4 |
| 8×8 | 116 / 300 | 292 / 300 | 295 / 300 | 192 | 180.0 / 189.0 |
| 9×9 | 102 / 300 | 297 / 300 | 292 / 300 | 209 | 235.2 / 251.3 |
| Total | 356 / 900 | 882 / 900 | 881 / 900 | 576 | Per-size values above |

The catalog arm recovered 526 control failures and retained every control success, with 18 remaining exhaustions. The final 50 requests at each size fulfilled 49, 47 and 50, respectively. Across 1,559 classified edits, 576 succeeded, 497 failed structure, 355 had multiple solutions, 115 admitted a classic-only proof and 16 stalled with triples. Per-size mean request times for ordinary / fixed catalog were 82.3 / 83.5 ms, 92.9 / 100.4 ms and 107.6 / 120.1 ms. Times exclude proof auditing and include concurrent runner load.

| Size | Fixed canonical layouts | Fixed exact / symmetry-only / near pairs | Fixed exact / near pairs in the prior 32 served | Empty exact / near pairs | Fixed exact / normalized bear arrangements | Fixed signatures |
|---|---:|---:|---:|---:|---:|---:|
| 7×7 | 275 | 20 / 0 / 22 | 6 / 1 | 39 / 235 | 156 / 73 | 238 |
| 8×8 | 276 | 19 / 0 / 15 | 8 / 3 | 14 / 252 | 177 / 153 | 239 |
| 9×9 | 287 | 11 / 0 / 42 | 4 / 8 | 17 / 255 | 153 / 153 | 223 |

Near pairs differ by one to four orthogonal terrain-boundary edges after best symmetry alignment. None of the three arms had relabel-only repeats. The ordinary control had zero exact, symmetry-only or near pairs in this sample. The fixed catalog yielded 838 canonical layouts in 882 successes, or 44 repeated results when each layout's first occurrence is counted once. Exact pairs total 50 because some layouts appeared more than twice. The empty-start arm was nearly as reliable but produced 742 near pairs compared with 79 for the fixed catalog. Its 7×7 answer concentration peaked at 29 uses of one symmetry-normalized answer, compared with 15 for the fixed catalog. Fixed-catalog successes used 70, 82 and 65 distinct parents by size, with the most-used parent returning six, six and seven children. Root and answer reuse are measured rather than filtered. The catalog is finite but its roots do not deplete because no request consumes them.

An independent Python enumerator and flood fill verified all accepted boards and catalog roots. The Godot audit checked all 32 family masks, always passing only the terrain layout to the analyzer. Every accepted board stalled under every classic-only subset and solved with triples enabled. In the fixed arm, 389 accepted boards also solved with triples alone, and 303 admitted an alternative chain-enabled proof without triples. Among the 576 edited results, 319 inherited the exact technique-order signature of their parent. Edited boards contributed 72, 79 and 76 distinct technique sequences absent from the catalog by size. The signed child-minus-parent dependency depth ranged from −4 to +5, with median zero at every size. These technique-level measures show both novel reasoning paths and substantial inherited structure. They do not measure human enjoyment.

The fixed catalog is enabled for production EXTRA HARD. The existing budget reserves the last eight attempts for a single-cell edit using a packaged catalog root when available. Each candidate must pass connectivity, singleton, independent uniqueness and the unchanged EXTRA HARD logical gate. The catalog is project data supplied to new installs. Missing or empty catalog data leaves the ordinary attempt budget available. The generator keeps the catalog in memory within its service instance and stores no consumed-root state. The campaign simulation's current arm uses the production path and its historical arms retain the ordinary control. Free Play uses the production path. No campaign save, assignment, difficulty gate or NIGHTMARES policy was changed. The results support enabling the fixed catalog. Near repeats and parent-like reasoning remain measurable constraints, and the finite sample does not establish indefinite diversity.

To reproduce, run `tests/run_isolated.ps1` with `res://tests/extra_hard_trial.gd` and user arguments `holdout`, then one of `7`, `8`, `9`. Pass the three `extra-hard-holdout.jsonl` files to `python -B tests/extra_hard_holdout_report.py <summary.json> <7-log> <8-log> <9-log>`. The verified summary is `.godot/extra-hard-holdout-summary.json`. The runner's `production` mode takes one holdout journal as a `res://` path and checks cold and reused-service parity. No new full campaign benchmark ran.

Production matched all 900 fixed-catalog outcomes and successful definitions using both a fresh service per request and a reused service. A 25-stage campaign smoke run finished with zero invalid acceptances. All seven Godot 4.7.2 regressions passed. The Free Play prototype test uses a known root-edit seed, exercises restart and completion, and verifies the isolated campaign save byte-for-byte alongside the restored assignment and attempt. No live player directory was accessed.

## Terrain construction bottleneck investigation

A matched EXTRA HARD diagnostic ran 12 requests each at 7×7, 8×8 and 9×9 with the existing 64-attempt budget. Bear-first grew 2,304 valid partitions around 36 legal starts, but 2,177 were ambiguous and only six qualified. Terrain-first qualified one proposal, and joint construction qualified three. Joint successfully reanchored one accepted 7×7 proposal. In the same-answer control, catalog edits qualified 806/2,304 proposals while fresh regrowth around the same parent bears qualified 1/2,304. The results isolate terrain construction as the measured bottleneck in these protocols. The production hybrid fulfilled all 36 matched requests. The 10×10 NIGHTMARES diagnostic yielded 13/48 edits versus 0/48 same-answer regrowth proposals.

No geometry cap beyond connectivity and the established difficulty profile was found. Frontier preferences, planned growth and one-cell anchor-preserving edits constrain what the current search proposes. The ten-material rendering permutation preserved borders, the logical proof and a repeated fixed-seed generation. Relabeling logical IDs can change trace order, even though the tested permutations preserved uniqueness and gate status. Root edits gave the best qualified proposal yield and inherit parent answers and substantial reasoning structure. Retain the current hybrid while evaluating controlled multi-witness boundary changes and more independent root answers.

Reproduce with the isolated Godot runner and res://tests/terrain_construction_trial.gd for each size. Feed the journals to tests/terrain_construction_report.py. Use res://tests/terrain_construction_supplement.gd for the opening, material and NIGHTMARES probes. All 853 EXTRA HARD and 13 NIGHTMARES accepted records independently passed Python connectivity and uniqueness checks. All seven isolated Godot 4.7.2 regression suites passed. No production behavior, save, assignment or artwork was changed. The complete methods, per-size results and recommendations are in [TERRAIN_CONSTRUCTION_REPORT.md](TERRAIN_CONSTRUCTION_REPORT.md).
