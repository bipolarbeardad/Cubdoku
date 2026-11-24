"""Independently audit the 10,000-stage campaign simulation journal."""

import argparse
from collections import Counter, defaultdict
from itertools import combinations
import json
from pathlib import Path

from campaign_simulation_report import DIFFICULTIES, verify_board
from nightmares_report import canonical_solution, orientations
from nightmares_stress_report import describe

QUOTAS = {"EASY": 7, "MEDIUM": 5, "HARD": 4, "EXTRA HARD": 2, "NIGHTMARES": 2}
OPENING = (
    "EASY EASY MEDIUM HARD EASY MEDIUM EXTRA-HARD EASY MEDIUM HARD "
    "NIGHTMARES EASY MEDIUM HARD EASY EXTRA-HARD MEDIUM HARD EASY NIGHTMARES"
).split()
LIMITS = dict(zip(DIFFICULTIES, [(4, 7), (5, 7), (5, 7), (6, 8), (7, 9), (8, 10)]))


def signature(row):
    return tuple(row["techniques"]), tuple(row["minimal_masks"])


def audit_schedule(rows):
    if len(rows) != 10000 or [row["stage"] for row in rows] != list(range(1, 10001)):
        raise ValueError("Expected all 10,000 consecutive assignments")
    for index, row in enumerate(rows):
        difficulty, side = row["difficulty"], row["size"]
        lo, hi = LIMITS[difficulty]
        if not lo <= side <= hi or row["seed"] != row["stage"] + 50000 or bool(row["locked_bear"]) != (index == 0):
            raise ValueError(f"Invalid assignment at stage {index + 1}")
    if [(row["difficulty"], row["size"]) for row in rows[:5]] != [("BASE", n) for n in [4, 4, 5, 6, 7]]:
        raise ValueError("Introductory assignments differ")
    if [row["difficulty"].replace(" ", "-") for row in rows[5:25]] != OPENING:
        raise ValueError("Opening block order differs")
    for index in range(5, 9985, 20):
        if Counter(row["difficulty"] for row in rows[index:index + 20]) != QUOTAS:
            raise ValueError(f"Quota mismatch at stage {index + 1}")


def audit_boards(rows):
    checked = set()
    recent = defaultdict(list)
    for row in rows:
        if row["status"] != "success":
            continue
        if not all(row[key] for key in ("rules", "unique", "logical", "profile_verified")):
            raise ValueError(f"Invalid proof at stage {row['stage']}")
        singletons = sum(count == 1 for count in Counter(row["regions"]).values())
        lower = 1 if row["difficulty"] == "BASE" else 0
        upper = 1 if row["difficulty"] in ("BASE", "EASY") else 0
        if not lower <= singletons <= upper:
            raise ValueError(f"Invalid region size at stage {row['stage']}")
        locked = row["locked_bears"]
        if len(locked) != (row["stage"] == 1) or any(bear not in row["solution"] for bear in locked):
            raise ValueError(f"Invalid given at stage {row['stage']}")
        definition = row["size"], tuple(row["regions"]), tuple(row["solution"])
        if definition not in checked:
            if not verify_board(row):
                raise ValueError(f"Invalid independent solution at stage {row['stage']}")
            checked.add(definition)
        row["boundaries"] = tuple(orientations(row))
        if row["difficulty"] == "NIGHTMARES":
            seen = recent[row["size"]]
            key = min(row["boundaries"])
            if key in seen[-32:]:
                raise ValueError(f"NIGHTMARES repeat inside window at stage {row['stage']}")
            seen.append(key)
    return len(checked)


def metrics(rows):
    accepted = [row for row in rows if row["status"] == "success"]
    phase_usec = Counter()
    rejection_reasons = Counter()
    for row in rows:
        phase_usec.update(row.get("phase_usec", {}))
        rejection_reasons.update(row.get("rejections", {}))
        timing = row.get("timing", {})
        phase_usec.update({k: v for k, v in timing.items() if k.endswith("_usec")})
        for source in ("fresh", "reserve"):
            details = timing.get(source, {})
            rejection_reasons.update({
                f"{source}_{k}": v for k, v in details.items()
                if isinstance(v, int) and (source, k) != ("fresh", "reserve_exhausted")
            })
            rejection_reasons.update(details.get("gates", {}))
    return {
        "allocated": len(rows), "success": len(accepted),
        "sources": Counter(row["source"] for row in rows),
        "failure_reasons": Counter(row["reason"] for row in rows if row["status"] != "success"),
        "size_allocated": Counter(row["size"] for row in rows),
        "size_success": Counter(row["size"] for row in accepted),
        "rejections": rejection_reasons, "phase_usec": phase_usec,
        "time_usec": describe([row["usec"] for row in rows]),
        "time_by_size_usec": {side: describe([row["usec"] for row in rows if row["size"] == side])
                              for side in sorted({row["size"] for row in rows})},
        "steps": describe([row["steps"] for row in accepted]),
        "depth": describe([row["chain"] for row in accepted]),
        "eliminations": describe([row["eliminations"] for row in accepted]),
        "placements": describe([row["placements"] for row in accepted]),
        "opening_steps": describe([len(row["opening_eliminations"]) for row in accepted]),
        "opening_eliminations": describe([sum(row["opening_eliminations"]) for row in accepted]),
        "chain_lengths": describe([n for row in accepted for n in row["chain_lengths"]]),
        "families_used": dict(sum_counters(row["technique_counts"] for row in accepted)),
        "minimal_masks": Counter(",".join(map(str, row["minimal_masks"])) for row in accepted),
        "solved_masks": Counter(mask for row in accepted for mask in row["solved_by"]),
        "reflected_solved": sum(row["reflected_solved"] for row in accepted),
        "reflected_changed_order": sum(row["reflected_order"] != row["techniques"] for row in accepted),
        "reflected_chain_free": sum(row["reflected_chain_free"] for row in accepted),
        "hall_solved": sum(row.get("hall_solved", False) for row in accepted),
        "contradiction_solved": sum(row.get("contradiction_solved", False) for row in accepted),
        "hall_moves": sum(row.get("hall_moves", 0) for row in accepted),
        "contradiction_moves": sum(row.get("contradiction_moves", 0) for row in accepted),
    }


def sum_counters(items):
    result = Counter()
    for item in items:
        result.update(item)
    return result


def replayability(rows):
    accepted = [row for row in rows if row["status"] == "success"]
    sizes = defaultdict(list)
    for row in accepted:
        sizes[row["size"]].append(row)
    names = ("exact", "relabeled", "same_labels_different_givens_or_tags", "symmetry", "near")
    gaps = defaultdict(list)
    pairs_by_segment = defaultdict(Counter)
    exact_pairs = []
    exact_pairs_by_source = Counter()
    for group in sizes.values():
        for a, b in combinations(group, 2):
            left, right = a["boundaries"][0], b["boundaries"]
            if left == right[0]:
                exact = all(a[k] == b[k] for k in ("difficulty", "regions", "solution", "locked_bears"))
                kind = ("exact" if exact else "relabeled" if a["regions"] != b["regions"]
                        else "same_labels_different_givens_or_tags")
            else:
                delta = min((left ^ mask).bit_count() for mask in right)
                if delta > 4:
                    continue
                kind = "near" if delta else "symmetry"
            gap = b["stage"] - a["stage"]
            gaps[kind].append(gap)
            segment = (b["stage"] - 1) // 2500
            pairs_by_segment[segment][kind] += 1
            if kind == "exact":
                exact_pairs.append([a["stage"], b["stage"], gap])
                exact_pairs_by_source[f"{a['source']} → {b['source']}"] += 1
    segments = {}
    known = set()
    for s in range(4):
        boards = [row for row in accepted if (row["stage"] - 1) // 2500 == s]
        layouts = {(row["size"], min(row["boundaries"])) for row in boards}
        segments[s] = {"success": len(boards), "layouts": len(layouts), "new_layouts": len(layouts - known),
                       "arrangements": len({(row["size"], tuple(row["solution"])) for row in boards}),
                       "signatures": len({(row["size"], signature(row)) for row in boards}),
                       "sources": Counter(row["source"] for row in boards),
                       "later_stage_pairs": pairs_by_segment[s]}
        known.update(layouts)
    answers = Counter((r["size"], tuple(r["solution"])) for r in accepted)
    signatures = Counter((r["size"], signature(r)) for r in accepted)
    sym_answers = {(r["size"], canonical_solution(r["solution"], r["size"])) for r in accepted}
    return {"canonical_layouts": len(known), "exact_pairs": sorted(exact_pairs),
            "exact_pairs_by_source": exact_pairs_by_source,
            "gaps": {name: describe(gaps[name]) for name in names}, "segments": segments,
            "exact_arrangements": len(answers), "symmetry_arrangements": len(sym_answers),
            "max_answer_occurrences": max(answers.values(), default=0),
            "reasoning_signatures": len(signatures),
            "max_signature_occurrences": max(signatures.values(), default=0)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("summary", type=Path)
    parser.add_argument("--historical", type=Path)
    args = parser.parse_args()
    rows = [json.loads(line) for line in args.log.read_text(encoding="utf-8").splitlines()]
    audit_schedule(rows)
    checked = audit_boards(rows)
    stats = {"final_partial": Counter(row["difficulty"] for row in rows[9985:]),
             "total": metrics(rows), "verified_exact_boards": checked,
             "difficulties": {d: metrics([row for row in rows if row["difficulty"] == d]) for d in DIFFICULTIES},
             "replayability": replayability(rows)}
    if args.historical:
        prior = [json.loads(line) for line in args.historical.read_text(encoding="utf-8-sig").splitlines()]
        matched = Counter()
        for old, new in zip(prior, rows):
            if old["stage"] != new["stage"] or old["difficulty"] != new["difficulty"] or old["size"] != new["size"]:
                raise ValueError("Historical scheduling differed")
            if old["difficulty"] != "NIGHTMARES":
                matched["compared"] += 1
                matched["same_status_and_board"] += all(old.get(key) == new.get(key)
                                                         for key in ("status", "regions", "solution", "locked_bears"))
        stats["historical_lower_match"] = matched
    args.summary.write_text(json.dumps(stats, indent=2) + "\n", encoding="utf-8")
    print("Campaign accepted", stats["total"]["success"], "independently verified distinct board/solution pairs", checked)


if __name__ == "__main__":
    main()
