
# CUBDOKU — PERMANENT PROJECT RULES

## Technology
- Godot 4
- GDScript
- Desktop game targeting Steam

## Current Goal
Build and validate the puzzle engine.

Do NOT implement the lottery, coins, mascots,
animations, cosmetics, or Steam integration yet.

## Mandatory Puzzle Rules
1. Exactly one bear per row.
2. Exactly one bear per column.
3. Exactly one bear per terrain region.
4. Bears cannot touch, including diagonally.
5. Every terrain region must be orthogonally connected.
6. The same terrain cannot exist in separate regions.
7. Regions can have unequal sizes and irregular shapes.
8. Every cell belongs to exactly one region.
9. Every puzzle must have exactly one valid solution.
10. Difficulty must be assessed through logical solving,
    not board size alone.
11. Never knowingly require blind guessing.

## Difficulty
BASE, EASY, MEDIUM, HARD, EXTRA HARD, NIGHTMARES.

Progression should trend upward with controlled variation.

## Development Requirements
- Read DEVELOPMENT.md at the start of each task.
- Make focused, incremental changes.
- Never discard working functionality without approval.
- Do not invent new gameplay rules.
- Do not add features outside the active milestone.
- Run available tests after code changes.
- Report any untested functionality truthfully.
- Record completed work and blockers in DEVELOPMENT.md.
- Keep logic independent of user interface code.
- Preserve reproducible random seeds for puzzle generation.

## Definition of Done
A task is complete only when:
- Code is implemented.
- Applicable tests have run.
- No known rule violations remain.
- Changes and limitations are documented.

The human developer approves milestone advancement.
