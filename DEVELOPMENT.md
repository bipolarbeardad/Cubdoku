# Cubdoku development

## Milestone 1 — Playable 4×4 prototype

Run `project.godot` in Godot 4. The main scene is `scenes/puzzle_board.tscn`. Choose **Place bear** or **Mark X**, then select a cell. Selecting the same mark again clears it. An incorrect bear costs a heart and leaves the cell as it was. Three misses end the attempt. **Restart** resets marks, hearts and elapsed time on the active puzzle.

### Local puzzle modes

`scripts/campaign_catalog.gd` defines permanent level IDs and BASE difficulty tags for Campaign Path #1–#8. The old fixed puzzles remain in that catalog as legacy test fixtures. The live campaign generates a personal puzzle on first reaching a level and saves its distinct instance ID, level ID, difficulty, size, regions and verified solution before opening it. The loader verifies saved definitions with the exhaustive solver. **Next puzzle** advances after completion when another level exists.

**Generate test puzzle** enters Free Play or generates a fresh Free Play board. **Return to Campaign Path** resumes the saved campaign attempt, including its marks, hearts and elapsed time. Reopening the game resumes the current level and attempt. **Restart** keeps the assigned puzzle and starts a new attempt. Losing the last heart records a failure. Restarting an unfinished attempt counts as a new attempt without recording a failure.

`scripts/puzzle_session.gd` records attempts started, failures, completion, best successful time and hearts remaining on the latest success. The save reserves a field for consumable usage. Local campaign statistics record unique completions overall and by difficulty, the fastest successful time and the highest level reached. Free Play contributes no campaign statistics.

`scripts/campaign_save.gd` stores version 1 at `user://campaign.save`. Sessions can use a different save path for isolated profiles and tests. The prototype opens the default local profile. Campaign actions save immediately. The running timer is checkpointed roughly once a second, when leaving for Free Play and on clean exit. Unsupported save versions are left intact.

`scripts/puzzle_generator.gd` grows four connected terrain regions from a seeded arrangement and tries up to 32 candidates by default. It validates its fallback through the same solver. `scripts/puzzle_validator.gd` checks the terrain partition, `scripts/puzzle_solver.gd` counts solutions up to two, `scripts/puzzle_game_state.gd` manages play, and `scripts/puzzle_board_ui.gd` binds the scene controls to game state.

The only column orders that satisfy the 4×4 row, column and non-touching rules are 2–4–1–3 and 3–1–4–2, using one-based columns from top to bottom. To deduce the answer, check the terrain colors in both orders. Uniqueness guarantees that exactly one order uses all four colors.

### Seamless terrain rendering

`scripts/board_terrain.gd` uses a `TileMapLayer` and a square `TileSet` with a separate atlas source for each material. The puzzle's region ID selects the atlas. The cell's board coordinate selects the matching crop from that atlas, so textures continue across same-region cells. Terrain-autotile edge matching and random variants were evaluated. The renderer uses fixed board-space crops because those provide continuous texture detail and exact material placement across arbitrary puzzle layouts.

`scripts/terrain_surfaces.gd` creates procedural placeholder sheets for grass, wood, stone, dirt, mud, gravel and forest floor. To supply replacement art, assign continuous 588 × 588 sheets to the main scene's `terrain_sheets` array in that order. Empty slots retain the procedural version. The scene draws a one-pixel translucent grid and a separate four-pixel black outline on inter-region edges and the board perimeter. Transparent cell buttons keep their mark labels and input above both border systems.

Open `tests/terrain_visual_test.tscn` in Godot and run the current scene to inspect the seven-material fixture. `godot --path . res://tests/terrain_visual_test.tscn -- --capture` runs the windowed pixel checks and saves `user://terrain-preview.png`. The fixture is a rendering test. Playable campaign and Free Play boards are still 4×4.

### Verification

- Godot 4.7.2 passed GDScript check-only validation and headless and windowed startup smoke tests. Local startup emitted a Windows root certificate-store diagnostic. The windowed run also reported unavailable shader caching.
- `godot --headless --path . --script res://tests/prototype_test.gd` passed with zero failures. Tests cover invalid terrain, zero and multiple solutions, deterministic generation, fallback, mark handling, hearts, restart, elapsed time and completion.
- Godot 4.7.2 passed check-only validation, the updated headless suite and two consecutive startup checks. The suite verifies two profiles at the same level, persistence across reconstructed sessions, attempt and failure counts, best times, Free Play isolation, and preservation of unsupported saves. It also pins legacy fixture #8 and validates all eight legacy fixtures. Verification redirected Windows `APPDATA` to the workspace because the sandbox restricts writes to the default user directory.
- The seeded 4×4 BASE batch accepted 1,000 candidates, rejected 212, and had zero failed requests or fallbacks. It produced 844 distinct layouts with terrain IDs included, took 357.9 ms overall, and recorded a slowest generation of 1.850 ms on the local machine.
- Independent review used a separate exhaustive enumeration and connectivity check on 1,000 generated boards, with zero mismatches. Review also found an out-of-range mark lookup, which was fixed and covered by the rerun suite.
- Godot 4.7.2 passed GDScript validation and the full headless and windowed suites after the terrain change. The windowed fixture passed material sampling on both sides of cell boundaries and checks for grid, region and perimeter lines. Visual inspection of the capture showed continuous grass, connected wood grain and stones crossing cell boundaries. Automated tests also checked exact tile-to-button alignment and region edge placement.

Terrain artwork remains procedural and stylized. Physical mouse and keyboard interaction and visual checks across display scales remain open. Larger playable boards, the logical difficulty analyzer, six-level calibration and cross-size and cross-difficulty batch testing belong to later milestones.
