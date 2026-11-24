"""Audit and summarize the terrain construction experiment journals."""

import argparse
from collections import Counter, defaultdict
from itertools import combinations
import json
from pathlib import Path

from campaign_simulation_report import verify_board
from nightmares_report import canonical_solution, orientations
from nightmares_stress_report import describe, geometry, read_jsonl

SIZES = (7, 8, 9)
ARMS = ("bear_first", "terrain_first", "joint", "root_edit", "root_regrow", "production")


def board_for(row):
    return {"size": row["side"], "regions": row["regions"], "solution": row["witnessed"]}


def layout_key(row):
    return min(orientations(board_for(row)))


def anchor_coverage(rows, field, side):
    anchor_counts = Counter(tuple(row[field]) for row in rows if row[field])
    normalized = Counter()
    for anchor, count in anchor_counts.items():
        normalized[canonical_solution(anchor, side)] += count
    return {"observations": sum(anchor_counts.values()), "exact": len(anchor_counts),
            "normalized": len(normalized), "max_exact_uses": max(anchor_counts.values(), default=0),
            "max_normalized_uses": max(normalized.values(), default=0)}


def repetitions(rows):
    oriented = [tuple(orientations(board_for(row))) for row in rows]
    keys = [min(variants) for variants in oriented]
    last = {}
    gaps = []
    for row, key in zip(rows, keys):
        if key in last:
            gaps.append(row["request"] - last[key])
        last[key] = row["request"]
    counts = Counter(keys)
    exact = Counter((tuple(row["regions"]), tuple(row["witnessed"])) for row in rows)
    in_place = Counter(variants[0] for variants in oriented)
    exact_pairs = sum(count * (count - 1) // 2 for count in exact.values())
    in_place_pairs = sum(count * (count - 1) // 2 for count in in_place.values())
    all_pairs = sum(count * (count - 1) // 2 for count in counts.values())
    near_pairs = sum(
        0 < min((left[0] ^ variant).bit_count() for variant in right) <= 4
        for left, right in combinations(oriented, 2)
    )
    return {"partitions": len(counts), "exact_definitions": len(exact),
            "exact_repeat_pairs": exact_pairs, "relabel_only_pairs": in_place_pairs - exact_pairs,
            "symmetry_only_pairs": all_pairs - in_place_pairs, "near_pairs": near_pairs,
            "repeat_events": len(gaps), "repeat_request_gaps": describe(gaps)}


def summarize_arm(rows, side, arm):
    requests = defaultdict(list)
    for row in rows:
        requests[row["request"]].append(row)
    if set(requests) != set(range(12)):
        raise ValueError(f"Missing request records for {side}/{arm}")
    successes = [row for row in rows if row["status"] == "accepted"]
    first_successes = []
    fixed_usec = []
    first_or_exhaustion_usec = []
    first_or_exhaustion_attempts = []
    for request in requests.values():
        ordered = sorted(request, key=lambda row: row["attempt"])
        expected_attempts = [-1] if arm == "production" else list(range(64))
        if [row["attempt"] for row in ordered] != expected_attempts:
            raise ValueError(f"Missing or duplicate attempts for {side}/{arm}/{ordered[0]['request']}")
        elapsed = 0
        for index, row in enumerate(ordered, start=1):
            elapsed += row["usec"]
            if row["status"] == "accepted":
                first_successes.append(row)
                break
        fixed_usec.append(sum(row["usec"] for row in ordered))
        first_or_exhaustion_usec.append(elapsed)
        first_or_exhaustion_attempts.append(index)

    accepted_partitions_by_answer = defaultdict(set)
    accepted_partitions_by_normalized_answer = defaultdict(set)
    constructed_partitions_by_anchor = defaultdict(set)
    structural_failures = {"structure", "construction", "singleton", "exhausted"}
    structurally_valid = [row for row in rows if row["status"] not in structural_failures]
    for row in structurally_valid:
        if row["anchor"]:
            constructed_partitions_by_anchor[tuple(row["anchor"])].add(layout_key(row))
    for row in successes:
        key = layout_key(row)
        accepted_partitions_by_answer[tuple(row["witnessed"])].add(key)
        accepted_partitions_by_normalized_answer[canonical_solution(row["witnessed"], side)].add(key)
    signatures = Counter(tuple(row["trace"]) for row in successes)
    masks = Counter(mask for row in successes for mask in row["masks"])
    outcomes = Counter(row["status"] for row in rows)
    rejections = Counter()
    for row in rows:
        rejections.update(row.get("rejections", {}))
    return {
        "requests": len(requests), "records": len(rows), "outcomes": outcomes,
        "production_rejections": rejections,
        "fulfilled": len(first_successes), "edited": sum(row["edited"] for row in rows),
        "reanchored": sum(row["reanchored"] for row in rows),
        "accepted_edits": sum(row["edited"] for row in successes),
        "accepted_reanchors": sum(row["reanchored"] for row in successes),
        "attempt_usec": describe([row["usec"] for row in rows]),
        "uniqueness_usec": describe([row["unique_usec"] for row in rows]),
        "proof_usec": describe([row["proof_usec"] for row in rows]),
        "full_diagnostic_request_usec": describe(fixed_usec),
        "first_success_or_exhaustion_usec": describe(first_or_exhaustion_usec),
        "first_success_or_exhaustion_attempts": None if arm == "production" else describe(first_or_exhaustion_attempts),
        "intent_anchors_proposed": anchor_coverage(rows, "anchor", side),
        "intent_anchors_structurally_valid": anchor_coverage(structurally_valid, "anchor", side),
        "answers_witnessed": anchor_coverage(rows, "witnessed", side),
        "answers_unique": anchor_coverage(
            [row for row in structurally_valid if row["status"] not in ("no_solution", "multiple")],
            "witnessed", side
        ),
        "accepted_answers": anchor_coverage(successes, "witnessed", side),
        "first_accepted_answers": anchor_coverage(first_successes, "witnessed", side),
        "constructed_partitions_per_anchor": describe([len(x) for x in constructed_partitions_by_anchor.values()]),
        "accepted_partitions_per_answer": describe([len(x) for x in accepted_partitions_by_answer.values()]),
        "accepted_partitions_per_normalized_answer": describe(
            [len(partitions) for partitions in accepted_partitions_by_normalized_answer.values()]
        ),
        "layout_repetition": repetitions(successes),
        "first_acceptance_repetition": repetitions(first_successes),
        "proof_signatures": len(signatures),
        "proof_most_common_signature_uses": max(signatures.values(), default=0),
        "proof_steps": describe([len(row["trace"]) for row in successes]),
        "proof_opening_x": describe([row["opening"] for row in successes]),
        "proof_solved_masks": masks,
        "relabeled_gate": Counter(row["relabel_gate"] for row in successes if "relabel_gate" in row),
        "relabeled_trace_changes": sum(row.get("relabel_trace_changed", False) for row in successes),
        "geometry": geometry([board_for(row) for row in successes]),
        "structurally_valid_geometry": geometry([board_for(row) for row in structurally_valid]),
        "accepted_parent_counts": Counter(row["parent"] for row in successes if row["parent"] >= 0),
    }


def compare_to_roots(rows, roots, side):
    accepted = [row for row in rows if row["status"] == "accepted"]
    parents_attempted = Counter(row["parent"] for row in rows)
    pairs = [(row, roots[row["parent"]]) for row in accepted]
    parent_partition_keys = {
        min(orientations({"size": side, "regions": root["regions"]})) for root in roots
    }
    return {
        "distinct_attempted_parents": len(parents_attempted),
        "distinct_accepted_parents": len({row["parent"] for row in accepted}),
        "accepted_with_unchanged_answer": sum(row["witnessed"] == parent["solution"] for row, parent in pairs),
        "accepted_matching_any_catalog_partition": sum(layout_key(row) in parent_partition_keys for row in accepted),
        "parent_minimum_boundary_delta": describe([
            min((next(orientations(board_for(row))) ^ variant).bit_count()
                for variant in orientations({"size": side, "regions": parent["regions"]}))
            for row, parent in pairs
        ]),
    }


def summarize(rows, catalog):
    groups = defaultdict(list)
    validated = 0
    for row in sorted(rows, key=lambda entry: (entry["side"], entry["arm"], entry["request"], entry["attempt"])):
        side = row["side"]
        arm = row["arm"]
        groups[(side, arm)].append(row)
        if row["status"] != "accepted":
            continue
        if not verify_board(board_for(row)):
            raise ValueError(f"Invalid accepted board: {side}/{arm}/{row['request']}/{row['attempt']}")
        if min(Counter(row["regions"]).values()) < 2:
            raise ValueError(f"Accepted singleton: {side}/{arm}/{row['request']}/{row['attempt']}")
        if not row["trace"] or 15 not in row["masks"] or any(mask < 8 for mask in row["masks"]):
            raise ValueError(f"Invalid recorded EXTRA HARD proof: {side}/{arm}/{row['request']}/{row['attempt']}")
        validated += 1
    if set(groups) != {(side, arm) for side in SIZES for arm in ARMS}:
        raise ValueError("Supply complete journals for sizes 7, 8 and 9")
    output = {"accepted_verified": validated, "sizes": defaultdict(dict)}
    for (side, arm), group in groups.items():
        output["sizes"][side][arm] = summarize_arm(group, side, arm)
        if arm in ("root_edit", "root_regrow"):
            output["sizes"][side][arm]["parent_comparison"] = compare_to_roots(group, catalog[str(side)], side)
    for side, arms in output["sizes"].items():
        production = {r["request"] for r in groups[(side, "production")] if r["status"] == "accepted"}
        for arm, stats in arms.items():
            fulfilled = {r["request"] for r in groups[(side, arm)] if r["status"] == "accepted"}
            stats["paired_vs_production"] = {
                "both": len(fulfilled & production), "gained": len(fulfilled - production),
                "lost": len(production - fulfilled),
            }
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("journals", type=Path, nargs="+")
    parser.add_argument("--catalog", type=Path, default=Path(__file__).resolve().parents[1] / "data/extra_hard_roots.json")
    args = parser.parse_args()
    catalog = json.loads(args.catalog.read_text(encoding="utf-8-sig"))
    output = summarize((row for journal in args.journals for row in read_jsonl(journal)), catalog)
    args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Independent topology and uniqueness checks passed on {output['accepted_verified']} boards")
    for side, arms in output["sizes"].items():
        for arm, stats in arms.items():
            print(f"{side} {arm}: {stats['fulfilled']}/{stats['requests']} fulfilled, {stats['outcomes']}")


if __name__ == "__main__":
    main()
