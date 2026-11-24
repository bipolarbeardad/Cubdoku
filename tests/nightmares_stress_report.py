"""Verify and summarize a complete 5,000-request NIGHTMARES benchmark."""

import argparse
from collections import Counter, defaultdict
from difflib import SequenceMatcher
from itertools import combinations
import json
from math import ceil, pi
from pathlib import Path
from statistics import mean, median

from campaign_simulation_report import layout_key, verify_board
from nightmares_opening_report import has_narrow_connection
from nightmares_report import canonical_solution, orientations


def read_jsonl(path):
    with path.open(encoding="utf-8-sig") as source:
        return [json.loads(line) for line in source]


def describe(values):
    ordered = sorted(values)
    if not ordered:
        return None
    return {
        "count": len(ordered),
        "min": ordered[0],
        "mean": round(mean(ordered), 4),
        "median": median(ordered),
        "p95": ordered[ceil(0.95 * len(ordered)) - 1],
        "max": ordered[-1],
        "total": sum(ordered),
    }


def geometry(boards):
    areas, minima, maxima, widths, heights, ratios, branch_cells = ([] for _ in range(7))
    all_areas = Counter()
    spans, narrow, compact, large = 0, 0, 0, 0
    for row in boards:
        side, regions = row["size"], row["regions"]
        cells_by_region = defaultdict(list)
        for index, region in enumerate(regions):
            cells_by_region[region].append(divmod(index, side))
        sizes = [len(cells) for cells in cells_by_region.values()]
        areas.extend(sizes)
        all_areas.update(sizes)
        minima.append(min(sizes))
        maxima.append(max(sizes))
        full_span = False
        branches = 0
        narrow += has_narrow_connection(row)
        for cells in cells_by_region.values():
            ys, xs = zip(*cells)
            width, height = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
            widths.append(width)
            heights.append(height)
            full_span |= width == side or height == side
            owned = set(cells)
            perimeter = 0
            for y, x in cells:
                degree = sum((y + dy, x + dx) in owned for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                branches += degree >= 3
                perimeter += 4 - degree
            area = len(cells)
            ratios.append(perimeter / area)
            large += area >= 2 * side
            compact += area >= 2 * side and 4 * pi * area / perimeter**2 >= 0.55
        spans += full_span
        branch_cells.append(branches)
    return {"areas": describe(areas), "area_histogram": all_areas, "board_minima": describe(minima),
            "board_maxima": describe(maxima), "region_widths": describe(widths), "region_heights": describe(heights),
            "spanning_boards": spans, "narrow_boards": narrow, "branch_cells": describe(branch_cells),
            "perimeter_area": describe(ratios), "large_regions": large, "large_compact_regions": compact}


def replayability(boards, inventory, historical=(), window=0):
    patterns = [tuple(orientations(row)) for row in boards]
    keys = [min(pattern) for pattern in patterns]
    recent = {}
    repeat_gaps = []
    first_in_run = Counter()
    reconstructed = Counter()
    for index, key in enumerate(keys):
        source = boards[index]["source"]
        (reconstructed if key in recent else first_in_run)[source] += 1
        if key in recent:
            gap = index - recent[key]
            if gap <= window:
                raise ValueError(f"Repeat inside rolling window at request {boards[index]['index']}")
            repeat_gaps.append(gap)
        recent[key] = index
    repeats = defaultdict(list)
    for first, second in combinations(range(len(boards)), 2):
        a, b = boards[first], boards[second]
        gap = b["index"] - a["index"]
        a_keys, b_keys = patterns[first], patterns[second]
        if a["regions"] == b["regions"] and a["solution"] == b["solution"]:
            repeats["exact"].append(gap)
        elif a_keys[0] == b_keys[0]:
            repeats["relabeled"].append(gap)
        else:
            distance = min((a_keys[0] ^ key).bit_count() for key in b_keys)
            if distance == 0:
                repeats["dihedral_only"].append(gap)
            elif distance <= 4:
                repeats["near"].append(gap)
    sources = [row for row in boards if row["source"] == "Validated reserve"]
    side = boards[0]["size"]
    reserve_keys = {min(orientations({"size": side, "regions": regions})) for regions in inventory}
    fresh_reserve_overlaps = sum(
        row["source"] == "Fresh" and min(keys) in reserve_keys
        for row, keys in zip(boards, patterns)
    )
    solutions = Counter(tuple(row["solution"]) for row in boards)
    normalized = Counter()
    for solution, count in solutions.items():
        normalized[canonical_solution(solution, boards[0]["size"])] += count
    return {"exact_placements": len(solutions), "symmetry_placements": len(normalized),
            "distinct_layouts": len(recent), "repeat_events": len(repeat_gaps),
            "first_in_run_by_source": first_in_run, "reconstructed_by_source": reconstructed,
            "window_gaps": describe(repeat_gaps),
            "novel_vs_historical": len(set(keys) - set(historical)),
            "novel_fresh_vs_historical": len({
                key for row, key in zip(boards, keys) if row["source"] == "Fresh" and key not in historical
            }),
            "most_frequent_solution": solutions.most_common(1)[0][1],
            "reserve_layouts": len({layout_key(row) for row in sources}),
            "reserve_exact_repeats": len(sources) - len({tuple(row["regions"]) for row in sources}),
            "reserve_stock": len(reserve_keys), "reserve_layouts_served_as_fresh": fresh_reserve_overlaps,
            "same_orientation_without_labels": len({layout_key(row) for row in boards}),
            "gaps": {key: describe(repeats[key]) for key in ("exact", "relabeled", "dihedral_only", "near")}}


def reasoning(boards, proofs):
    phases = [Counter(), Counter(), Counter()]
    techniques = []
    traces = set()
    untouched = Counter()
    for row, proof in zip(boards, proofs):
        if proof["index"] != row["index"] or proof["lower_masks"] or not proof["chains"]:
            raise ValueError(f"Failed proof gate at request {row['index']}")
        for phase, counts in zip(phases, proof["phases"]):
            phase.update(counts)
        trace = proof["trace"]
        techniques.append(tuple(step[0] for step in trace))
        traces.add(json.dumps(trace, separators=(",", ":")))
        untouched.update(proof["untouched_families"].keys())
    similarity = [SequenceMatcher(None, a, b, autojunk=False).ratio()
                  for a, b in zip(techniques, techniques[1:])]
    return {"phases": phases, "untouched_family_boards": untouched,
            "opening_x": describe([p["opening_x"] for p in proofs]),
            "opening_steps": describe([sum(p["phases"][0].values()) for p in proofs]),
            "initial_moves": describe([p["initial_moves"] for p in proofs]),
            "untouched_moves": describe([p["untouched_moves"] for p in proofs]),
            "untouched_cells": describe([p["untouched_cells"] for p in proofs]),
            "steps": describe([len(p["trace"]) for p in proofs]),
            "depth": describe([p["max_depth"] for p in proofs]),
            "chain_links": describe([length for p in proofs for length in p["chains"]]),
            "hall_solves": sum(p["hall_solved"] for p in proofs) if "hall_solved" in proofs[0] else None,
            "hall_moves": sum(p["hall_moves"] for p in proofs) if "hall_moves" in proofs[0] else None,
            "contradiction_solves": sum(p["contradiction_solved"] for p in proofs) if "contradiction_solved" in proofs[0] else None,
            "contradiction_moves": sum(p["contradiction_moves"] for p in proofs) if "contradiction_moves" in proofs[0] else None,
            "contradiction_probes": describe([p["contradiction_probes"] for p in proofs if "contradiction_probes" in p]),
            "mirror_solves": sum(p["mirror_solved"] for p in proofs) if "mirror_solved" in proofs[0] else None,
            "mirror_shortcuts": sum(bool(p["mirror_shortcuts"]) for p in proofs) if "mirror_shortcuts" in proofs[0] else None,
            "mirror_changed_order": sum(p["mirror_signature"] != list(t) for p, t in zip(proofs, techniques))
            if "mirror_signature" in proofs[0] else None,
            "technique_signatures": len(set(techniques)), "cell_traces": len(traces),
            "consecutive_same_size_similarity": describe(similarity),
            "audit_usec": describe([p["usec"] for p in proofs])}


def timing(rows):
    breakdown = Counter()
    reasons = Counter()
    gates = Counter()
    for row in rows:
        t = row["timing"]
        for phase in ("root_usec", "fresh_usec", "reserve_usec"):
            breakdown[phase] += t.get(phase, 0)
        for source in ("fresh", "reserve"):
            phase = t.get(source, {})
            reasons.update({source + "_" + k: phase.get(k, 0)
                            for k in ("structure", "uniqueness", "repeated", "reserve_exhausted", "fresh_exhausted")
                            if not (source == "fresh" and k == "reserve_exhausted")})
            gates.update({source + "_" + k: v for k, v in phase.get("gates", {}).items()})
            breakdown.update({source + "_" + k: v for k, v in phase.get("timing", {}).items()})
    sources = Counter(row["source"] for row in rows)
    return {"request_usec": describe([row["usec"] for row in rows]), "phase_usec": breakdown,
            "timing_by_outcome": {key: describe([r["usec"] for r in rows if r["source"] == key]) for key in sources},
            "reserve_lookup_usec": describe([r["timing"]["reserve_usec"] for r in rows if "reserve_usec" in r["timing"]]),
            "outcomes": Counter(row["source"] for row in rows), "rejections": reasons, "gates": gates,
            "first_120_outcomes": Counter(r["source"] for r in rows[:120]),
            "first_144_outcomes": Counter(r["source"] for r in rows[:144]),
            "first_unfulfilled": next((r["index"] for r in rows if r["source"] == "unfulfilled"), None),
            "last_reserve": max((r["index"] for r in rows if r["source"] == "Validated reserve"), default=None),
            "last_fresh": max((r["index"] for r in rows if r["source"] == "Fresh"), default=None)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("requests", type=Path)
    parser.add_argument("proofs", type=Path)
    parser.add_argument("summary", type=Path)
    parser.add_argument("--historical", type=Path)
    parser.add_argument("--window", type=int, default=0)
    args = parser.parse_args()
    requests = read_jsonl(args.requests)
    proofs = read_jsonl(args.proofs)
    if len(requests) != 5000 or any(
        (r["index"], r["size"], r["seed"]) != (i + 1, 8 + i % 3, 850000 + i)
        for i, r in enumerate(requests)
    ):
        raise ValueError("Unexpected benchmark sequence")
    proved = {p["index"]: p for p in proofs}
    accepted = [r for r in requests if r["source"] != "unfulfilled"]
    if len(proved) != len(proofs) or set(proved) != {r["index"] for r in accepted}:
        raise ValueError("Proof log must cover each accepted puzzle exactly once")
    checked = set()
    for row in accepted:
        key = row["size"], tuple(row["regions"]), tuple(row["solution"])
        if key not in checked:
            if min(Counter(row["regions"]).values()) < 2 or not verify_board(row):
                raise ValueError(f"Independent terrain/uniqueness failure at request {row['index']}")
            checked.add(key)
    print(f"Independently verified {len(accepted)} accepted boards.")
    inventory_file = Path(__file__).resolve().parents[1] / "data" / "nightmares_reserve.json"
    inventory = json.loads(inventory_file.read_text(encoding="utf-8"))
    summary = {"total": timing(requests)}
    historical = defaultdict(set)
    if args.historical:
        for row in read_jsonl(args.historical):
            if row["source"] != "unfulfilled":
                historical[row["size"]].add(min(orientations(row)))
    for side in (8, 9, 10):
        rows = [r for r in requests if r["size"] == side]
        boards = [r for r in accepted if r["size"] == side]
        summary[str(side)] = {
            "timing": timing(rows), "geometry": geometry(boards),
            "replayability": replayability(boards, inventory[str(side)], historical[side], args.window),
            "reasoning": reasoning(boards, [proved[b["index"]] for b in boards]),
        }
        print(side, summary[str(side)]["timing"]["outcomes"])
    args.summary.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
