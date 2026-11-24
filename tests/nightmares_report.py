"""Independently verify NIGHTMARES benchmark boards and audit layout variation."""

import argparse
from collections import Counter
from itertools import combinations
import json
from pathlib import Path

from campaign_simulation_report import boundaries, verify_board


def orientations(row):
    side = row["size"]
    board = row["regions"]
    for variant in range(8):
        cells = []
        for y in range(side):
            for x in range(side):
                a = side - 1 - x if variant & 1 else x
                b = side - 1 - y if variant & 2 else y
                cells.append(board[a * side + b if variant & 4 else b * side + a])
        yield boundaries({"size": side, "regions": cells})


def canonical_solution(solution, side):
    variants = []
    for variant in range(8):
        cells = []
        for cell in solution:
            y, x = divmod(cell, side)
            a = side - 1 - x if variant & 1 else x
            b = side - 1 - y if variant & 2 else y
            cells.append(a * side + b if variant & 4 else b * side + a)
        variants.append(tuple(sorted(cells)))
    return min(variants)


def audit_boards(label, side, boards):
    if not boards:
        raise ValueError(f"Empty {label}")
    for row in boards:
        if row["size"] != side or min(Counter(row["regions"]).values()) < 2 or not verify_board(row):
            raise ValueError(f"Invalid {label} sample")
    masks = [tuple(orientations(row)) for row in boards]
    distances = Counter(min((a[0] ^ edge).bit_count() for edge in b) for a, b in combinations(masks, 2))
    if distances[0]:
        raise ValueError(f"Equivalent layouts repeated in {label}")
    arrangements = Counter(tuple(row["solution"]) for row in boards)
    normalized = Counter()
    for solution, count in arrangements.items():
        normalized[canonical_solution(solution, side)] += count
    print(f"{label}: {len(boards)} verified, {len(arrangements)} exact / {len(normalized)} symmetry classes, "
          f"most common exact / class {max(arrangements.values())}/{max(normalized.values())}, "
          f"near pairs {sum(distances[k] for k in range(1, 5))}/{sum(distances.values())}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("results", type=Path)
    data = json.loads(parser.parse_args().results.read_text(encoding="utf-8"))
    for key, metrics in sorted(data.items()):
        side = int(key.rsplit("_", 1)[-1])
        if metrics["outcomes"]["failed"]:
            raise ValueError(f"Incomplete {key} run")
        audit_boards(key, side, metrics["boards"])
        if "reserve_audit" in metrics:
            audit_boards(key + " full reserve", side, metrics["reserve_audit"]["boards"])


if __name__ == "__main__":
    main()
