"""Summarize the matched Free Play policy trial and independently check accepted boards."""

import argparse
from collections import Counter
import json
from pathlib import Path
from statistics import mean

from campaign_simulation_report import verify_board
from nightmares_report import canonical_solution, orientations
from nightmares_opening_report import has_narrow_connection


def summarize(path, rolling):
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]
    for side in (8, 9, 10):
        group = [row for row in rows if row["size"] == side]
        assert [row["index"] for row in group] == list(range(1, 145))
        seen, exact, fresh_new, new = {}, {}, set(), set()
        last, gaps, exact_gaps = {}, [], []
        arrangements, normalized = set(), set()
        outcomes = Counter()
        exhaustion = Counter()
        geometry = Counter()
        for row in group:
            source = row["source"]
            outcomes[source] += 1
            if source == "unfulfilled":
                exhaustion["reserve"] += 1
                exhaustion["fresh"] += 1
                continue
            assert min(Counter(row["regions"]).values()) >= 2 and verify_board(row)
            if source == "Validated reserve":
                exhaustion["fresh"] += 1
            key = min(orientations(row))
            index = row["index"]
            if key in last:
                gaps.append(index - last[key])
                assert rolling and gaps[-1] > 32
            last[key] = index
            definition = tuple(row["regions"]), tuple(row["solution"])
            if definition in exact:
                exact_gaps.append(index - exact[definition])
            exact[definition] = index
            seen.setdefault(key, source)
            arrangements.add(tuple(row["solution"]))
            normalized.add(canonical_solution(row["solution"], side))
            if row["new_layout"]:
                if key not in new:
                    positions = {}
                    for cell, region in enumerate(row["regions"]):
                        positions.setdefault(region, []).append(divmod(cell, side))
                    spans = any(
                        max(ys) - min(ys) + 1 == side or max(xs) - min(xs) + 1 == side
                        for ys, xs in (zip(*cells) for cells in positions.values())
                    )
                    geometry["spans"] += spans
                    geometry["narrow"] += has_narrow_connection(row)
                    geometry["branching"] += any(
                        sum((y + dy, x + dx) in occupied for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1))) >= 3
                        for occupied in map(set, positions.values()) for y, x in occupied
                    )
                    geometry["largest_region"] = max(geometry["largest_region"], max(map(len, positions.values())))
                new.add(key)
                if source == "Fresh":
                    fresh_new.add(key)
        print(side, dict(outcomes), "distinct", len(seen), "novel/fresh novel", len(new), len(fresh_new),
              "arrangements exact/D4", len(arrangements), len(normalized), "canonical repeat count/min/max",
              (len(gaps), min(gaps, default=None), max(gaps, default=None)), "exact repeat count/min/max",
              (len(exact_gaps), min(exact_gaps, default=None), max(exact_gaps, default=None)),
              "exhaustion", dict(exhaustion), "novel geometry", dict(geometry), "mean/worst ms",
              round(mean(row["usec"] for row in group) / 1000, 2),
              round(max(row["usec"] for row in group) / 1000, 2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", type=Path, nargs="+")
    args = parser.parse_args()
    for log in args.logs:
        print(log.name)
        summarize(log, "legacy" not in log.name)


if __name__ == "__main__":
    main()
