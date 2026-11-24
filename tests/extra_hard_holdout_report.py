"""Independently audit the EXTRA HARD holdout journals and quantify repetition."""

import argparse
from collections import Counter
from difflib import SequenceMatcher
from itertools import combinations
import json
from pathlib import Path

from campaign_simulation_report import verify_board
from nightmares_report import canonical_solution, orientations
from nightmares_stress_report import describe


def audit(row):
    assert verify_board(row)
    assert min(Counter(row["regions"]).values()) >= 2
    assert 15 in row["solved_masks"] and min(row["solved_masks"]) > 7
    assert any(technique in (14, 15) for technique in row["trace"])


def compare_layouts(boards):
    oriented = [tuple(orientations(board)) for board in boards]
    pairs = Counter()
    recent = Counter()
    for i, j in combinations(range(len(boards)), 2):
        left, right = oriented[i], oriented[j]
        if boards[i]["regions"] == boards[j]["regions"]:
            kind = "exact"
        elif left[0] == right[0]:
            kind = "relabeled"
        else:
            delta = min((left[0] ^ mask).bit_count() for mask in right)
            if delta > 4:
                continue
            kind = "near" if delta else "symmetry"
        pairs[kind] += 1
        if j - i <= 32:
            recent[kind] += 1
    return {"all_pairs": pairs, "within_32_served": recent}


def summarize(rows):
    roots = {r["id"]: r for r in rows if r.get("kind") == "root"}
    catalog = [r for r in roots.values() if r["source"] == "catalog"]
    catalog_traces = {tuple(r["trace"]) for r in catalog}
    catalog_keys = {min(orientations(r)) for r in catalog}
    for root in roots.values():
        audit(root)
    stats = {"size": catalog[0]["size"], "catalog": len(catalog), "catalog_layouts": len(catalog_keys),
             "catalog_signatures": len(catalog_traces),
             "catalog_usec": next(r["usec"] for r in rows if r.get("kind") == "catalog_timing")}
    control = {}
    for arm in ("control", "root_edit", "empty_start"):
        requests = [r for r in rows if r.get("arm") == arm]
        assert [r["stage"] for r in requests] == list(range(300))
        side = stats["size"]
        assert all(r["seed"] == 4300000 + 1000 * side + r["stage"] and r["size"] == side for r in requests)
        accepted = [r for r in requests if r["status"] == "success"]
        for board in accepted:
            audit(board)
        edits = [r for r in accepted if r.get("parent")]
        for child in edits:
            parent = roots[child["parent"]]
            assert parent["solution"] == child["solution"]
            assert sum(a != b for a, b in zip(parent["regions"], child["regions"])) == 1
        parents = Counter(r["parent"] for r in edits)
        attempted = Counter(p for row in requests for p in row["parents"])
        reasons = Counter()
        for row in requests:
            reasons.update(row["rejections"])
        answers = Counter(tuple(r["solution"]) for r in accepted)
        normalized = Counter(canonical_solution(r["solution"], side) for r in accepted)
        traces = {tuple(r["trace"]) for r in accepted}
        layouts = {min(orientations(r)) for r in accepted}
        paired = {r["stage"]: r["status"] for r in requests}
        stats[arm] = {
            "success": len(accepted), "edits": len(edits), "rejections": reasons,
            "request_usec": describe([r["usec"] for r in requests]),
            "layout_pairs": compare_layouts(accepted),
            "canonical_layouts": len(layouts),
            "edit_layouts_outside_catalog": len({min(orientations(r)) for r in edits} - catalog_keys),
            "exact_arrangements": len(answers), "normalized_arrangements": len(normalized),
            "max_normalized_arrangement_uses": max(normalized.values()),
            "parents_attempted": len(attempted), "most_attempted_parent": max(attempted.values(), default=0),
            "parent_use_counts": parents, "parent_attempt_counts": attempted,
            "distinct_signatures": len(traces), "signatures_outside_catalog": len(traces - catalog_traces),
            "edit_signatures_outside_catalog": len({tuple(r["trace"]) for r in edits} - catalog_traces),
            "triples_without_classic_families": sum(8 in r["solved_masks"] for r in accepted),
            "alternate_chain_proofs_without_triples": sum(
                any(mask & 16 and not mask & 8 for mask in r["solved_masks"]) for r in accepted
            ),
            "unchanged_parent_signatures": sum(r["trace"] == roots[r["parent"]]["trace"] for r in edits),
            "parent_trace_similarity": describe([
                SequenceMatcher(None, r["trace"], roots[r["parent"]]["trace"], autojunk=False).ratio()
                for r in edits
            ]),
            "child_minus_parent_depth": describe([r["depth"] - roots[r["parent"]]["depth"] for r in edits]),
            "windows": [{"fulfilled": sum(r["status"] == "success" for r in requests[i:i+50]),
                         "edits": sum(bool(r.get("parent")) for r in requests[i:i+50]),
                         "starting_pool": requests[i]["pool_size"]} for i in range(0, 300, 50)],
            "rescued": sum(control.get(i) == "failed" and s == "success" for i, s in paired.items()),
            "lost": sum(control.get(i) == "success" and s == "failed" for i, s in paired.items()),
        }
        if arm == "control":
            control = paired
    return stats


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("journals", nargs=3, type=Path)
    parser.add_argument("--catalog", type=Path)
    args = parser.parse_args()
    results = []
    catalog = {}
    for path in args.journals:
        rows = [json.loads(line) for line in path.read_text(encoding="utf-8-sig").splitlines()]
        summary = summarize(rows)
        results.append(summary)
        catalog[str(summary["size"])] = [
            {"regions": row["regions"], "solution": row["solution"]}
            for row in rows if row.get("kind") == "root" and row["source"] == "catalog"
        ]
    assert {r["size"] for r in results} == {7, 8, 9}
    args.output.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    if args.catalog:
        groups = []
        for size, roots in sorted(catalog.items()):
            entries = ",\n".join("    " + json.dumps(root, separators=(",", ":")) for root in roots)
            groups.append(f'  "{size}": [\n{entries}\n  ]')
        args.catalog.write_text("{\n" + ",\n".join(groups) + "\n}\n", encoding="utf-8")


if __name__ == "__main__":
    main()
