"""Summarize the archived campaign and independently audit the matched EXTRA HARD trial."""

import argparse
from collections import Counter
import json
from pathlib import Path

from campaign_simulation_report import verify_board
from nightmares_report import canonical_solution, orientations
from nightmares_stress_report import describe


def read_journal(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8-sig").splitlines()]


def layout(row):
    return min(orientations(row))


def aggregate(rows):
    reasons = Counter()
    for row in rows:
        reasons.update(row["rejections"])
    return reasons


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("campaign", type=Path)
    parser.add_argument("trial", type=Path)
    args = parser.parse_args()
    campaign = read_journal(args.campaign)
    trial = read_journal(args.trial)
    assert len(campaign) == 10000 and len(trial) == 300
    archive = {row["stage"]: row for row in campaign}
    for difficulty in ("EASY", "MEDIUM", "HARD", "EXTRA HARD"):
        for side in sorted({row["size"] for row in campaign if row["difficulty"] == difficulty}):
            rows = [row for row in campaign if (row["difficulty"], row["size"]) == (difficulty, side)]
            failures = [row for row in rows if row["status"] != "success"]
            print(difficulty, side, len(failures), "/", len(rows), dict(aggregate(failures)))
    for side in (7, 8, 9):
        known = {layout(row) for row in campaign
                 if row["difficulty"] == "EXTRA HARD" and row["size"] == side and row["status"] == "success"}
        roots = [row for row in campaign if row["stage"] <= 5000 and row["difficulty"] == "EXTRA HARD"
                 and row["size"] == side and row["status"] == "success"]
        print(side, "root arrangements", len({canonical_solution(r["solution"], side) for r in roots}), "/", len(roots))
        matched = {}
        for arm in ("control", "root_edit"):
            rows = [row for row in trial if row["size"] == side and row["arm"] == arm]
            assert len(rows) == 50 and len({r["stage"] for r in rows}) == 50
            accepted = [r for r in rows if r["status"] == "success"]
            for row in accepted:
                assert verify_board(row) and min(Counter(row["regions"]).values()) >= 2
                assert 15 in row["solved_masks"] and min(row["solved_masks"]) > 7
            for row in rows:
                old = archive[row["stage"]]
                assert old["difficulty"] == "EXTRA HARD" and old["seed"] == row["seed"]
                if arm == "control":
                    assert all(old.get(k) == row.get(k) for k in ("status", "regions", "solution"))
            layouts = {layout(row) for row in accepted}
            edits = [r for r in accepted if r["source"] == "root_edit"]
            print(side, arm, "accepted", len(accepted), "from edits", len(edits),
                  "layouts", len(layouts), "novel vs archive", len(layouts - known),
                  "novel edits", len({layout(r) for r in edits} - known),
                  "arrangements", len({canonical_solution(r["solution"], side) for r in accepted}),
                  "time usec", describe([r["usec"] for r in rows]),
                  "edit rejections", {k: v for k, v in aggregate(rows).items() if k.startswith("edit_")})
            matched[arm] = {row["stage"]: row["status"] for row in rows}
        assert matched["control"].keys() == matched["root_edit"].keys()
        print(side, "paired outcomes", Counter((status, matched["root_edit"][stage])
                                                for stage, status in matched["control"].items()))


if __name__ == "__main__":
    main()
