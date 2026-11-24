"""Verify a NIGHTMARES opening audit and report the measured tradeoffs."""

import argparse
from collections import Counter
import json
from pathlib import Path
from statistics import mean

from campaign_simulation_report import verify_board
from nightmares_report import canonical_solution


def has_narrow_connection(row):
    side, board = row["size"], row["regions"]
    neighbors = {cell: set() for cell in range(len(board))}
    for cell, region in enumerate(board):
        if cell % side < side - 1 and board[cell + 1] == region:
            neighbors[cell].add(cell + 1)
            neighbors[cell + 1].add(cell)
        if cell + side < len(board) and board[cell + side] == region:
            neighbors[cell].add(cell + side)
            neighbors[cell + side].add(cell)
    for removed, adjacent in neighbors.items():
        if len(adjacent) < 2:
            continue
        start = next(iter(adjacent))
        visited = {start, removed}
        pending = [start]
        while pending:
            for other in neighbors[pending.pop()] - visited:
                visited.add(other)
                pending.append(other)
        if not adjacent.issubset(visited):
            return True
    return False


def report(size, policy, data):
    boards = data["boards"]
    if len(boards) != data["fulfilled"]:
        raise ValueError("Missing accepted boards")
    for row in boards:
        if row["size"] != size or min(Counter(row["regions"]).values()) < 2 or not verify_board(row):
            raise ValueError(f"Invalid {size}x{size} {policy} board")
    arrangements = {canonical_solution(row["solution"], size) for row in boards}
    states = [row["production"] for row in boards]
    ranges = {
        key: (min(state[key] for state in states), max(state[key] for state in states))
        for key in ("steps", "eliminations", "dependency")
    } if boards else {}
    print(f"{size} {policy}: {len(boards)}/{data['requests']}, {len(arrangements)} arrangement classes, "
          f"mean/worst {data['mean_usec']/1000:.2f}/{data['worst_usec']/1000:.2f} ms")
    print(f"  broad {data['distinct_sampled_columns']}/{data['broad_attempts']} placements: "
          f"{data['broad_rejections']}; accepted sources {dict(Counter(row['source'] for row in boards))}")
    print(f"  opening ranges {ranges}; first bear reached by classic / chain-free / without triples "
          f"{sum(row['classic']['first_bear'] for row in boards)}/"
          f"{sum(row['chain_free_opening']['first_bear'] for row in boards)}/"
          f"{sum(row['without_triples_opening']['first_bear'] for row in boards)}; "
          f"ordered technique signatures {len({tuple(state['techniques']) for state in states})}")
    if boards:
        print(f"  direct untouched counts by family "
              f"{ {key: sum(bool(row['untouched'][key]) for row in boards) for key in boards[0]['untouched']} }; "
              f"mean distinct cells from observed untouched options "
              f"{mean(len(set().union(*row['untouched'].values())) for row in boards):.1f}")
        print(f"  boards with opposite-edge spans {sum(row['geometry']['spanning'] > 0 for row in boards)}; "
              f"boards with single-cell connections {sum(map(has_narrow_connection, boards))}; "
              f"maximum region size {max(row['geometry']['max_area'] for row in boards)}")
    for key in ("experimental_solved", "hall_only_solved", "contradiction_only_solved"):
        print(f"  {key}: {sum(row[key] for row in boards)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("results", type=Path)
    data = json.loads(parser.parse_args().results.read_text(encoding="utf-8"))
    for side in (8, 9, 10):
        for policy in ("current", "geometry_only", "expanded"):
            report(side, policy, data[str(side)][policy])


if __name__ == "__main__":
    main()
