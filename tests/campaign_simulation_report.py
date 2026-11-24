"""Summarize a campaign JSONL run and attach prior layout matches to each row."""

import argparse
import itertools
import json
from collections import Counter, defaultdict
from pathlib import Path
from statistics import mean, median


DIFFICULTIES = ["BASE", "EASY", "MEDIUM", "HARD", "EXTRA HARD", "NIGHTMARES"]


def layout_key(row):
    ids = {}
    return tuple(ids.setdefault(region, len(ids)) for region in row["regions"])


def boundaries(row):
    size, regions = row["size"], row["regions"]
    edges = (
        (cell, neighbor)
        for cell in range(size * size)
        for neighbor in ([cell + 1] if cell % size < size - 1 else [])
        + ([cell + size] if cell // size < size - 1 else [])
    )
    return sum(1 << index for index, (a, b) in enumerate(edges) if regions[a] != regions[b])


def find_layout_matches(rows):
    previous = defaultdict(list)
    exact_pairs = []
    near_pairs = []
    for row in rows:
        if row["status"] != "success":
            continue
        row["prior_exact_layouts"] = []
        row["prior_near_layouts"] = []
        edges = boundaries(row)
        for earlier, prior_edges in previous[row["size"]]:
            difference = (edges ^ prior_edges).bit_count()
            if difference == 0:
                row["prior_exact_layouts"].append(earlier)
                exact_pairs.append((earlier, row["stage"]))
            elif difference <= 4:
                row["prior_near_layouts"].append({"stage": earlier, "different_edges": difference})
                near_pairs.append((earlier, row["stage"]))
        previous[row["size"]].append((row["stage"], edges))
    return exact_pairs, near_pairs


def verify_board(row):
    """Independently flood-fill regions and count solutions by minimum-candidate row."""
    size, regions = row["size"], row["regions"]
    if len(regions) != size * size or set(regions) != set(range(size)):
        return False
    for region in range(size):
        cells = {index for index, label in enumerate(regions) if label == region}
        pending = [cells.pop()]
        while pending:
            y, x = divmod(pending.pop(), size)
            for dy, dx in ((0, -1), (0, 1), (1, 0), (-1, 0)):
                ny, nx = y + dy, x + dx
                neighbor = ny * size + nx
                if 0 <= ny < size and 0 <= nx < size and neighbor in cells:
                    cells.remove(neighbor)
                    pending.append(neighbor)
        if cells:
            return False
    assignments = [-20] * size
    options = [[(x, 1 << x, 1 << regions[y * size + x]) for x in range(size)] for y in range(size)]
    found = []

    def search(remaining, columns, terrain):
        if not remaining:
            found.append([y * size + x for y, x in enumerate(assignments)])
            return
        best = None
        for y in remaining:
            above = assignments[y - 1] if y else -20
            below = assignments[y + 1] if y + 1 < size else -20
            feasible = [option for option in options[y]
                        if not (option[1] & columns or option[2] & terrain)
                        and abs(above - option[0]) > 1 and abs(below - option[0]) > 1]
            if not feasible:
                return
            if best is None or len(feasible) < len(best):
                best, chosen = feasible, y
        remaining = [y for y in remaining if y != chosen]
        for x, column_bit, terrain_bit in best:
            assignments[chosen] = x
            search(remaining, columns | column_bit, terrain | terrain_bit)
            if len(found) == 2:
                break
        assignments[chosen] = -20

    search(list(range(size)), 0, 0)
    return found == [row["solution"]]


def summarize(rows):
    states = Counter(row["status"] for row in rows)
    sizes = Counter((row["size"], row["status"]) for row in rows)
    reasons = Counter(row["reason"] for row in rows if row["reason"])
    rejections = Counter()
    for row in rows:
        rejections.update(row["rejections"])
    print(f"requests={len(rows)} status={dict(states)} size/status={dict(sorted(sizes.items()))}")
    print(f"unfulfilled={dict(reasons)} candidate rejections={dict(rejections)}")
    phases = Counter()
    repairs = Counter()
    repaired_rejections = Counter()
    plans = Counter()
    samples = []
    for row in rows:
        phases.update(row.get("phase_usec", {}))
        repairs.update(row.get("repairs", {}))
        repaired_rejections.update(row.get("repair_gate_rejections", {}))
        plans.update(row.get("plans", {}))
        if "ambiguity_sample" in row:
            samples.append(row["ambiguity_sample"])
    if phases:
        print(f"phase seconds={ {key: round(value / 1e6, 3) for key, value in phases.items()} }")
    if repairs:
        print(f"repair outcomes={dict(repairs)}")
    if repaired_rejections:
        print(f"unique repairs rejected by gate={dict(repaired_rejections)}")
    if plans:
        print(f"construction plans={dict(plans)}")
    if samples:
        counts = Counter(f"{s['cap']}+" if s["count"] == s["cap"] else str(s["count"]) for s in samples)
        distance = Counter(s["nearest_rows_changed"] for s in samples)
        print(f"bounded ambiguity n={len(samples)} counts={dict(counts)} nearest differing rows={dict(sorted(distance.items()))}")
        cycles = Counter()
        for sample in samples:
            cycles.update(sample.get("cycle_patterns", {}))
        if cycles:
            print(f"sampled alternative cycle partitions={dict(cycles.most_common())}")
        patterns = [sample for sample in samples if "boundary_changes" in sample]
        if patterns:
            switches = [sample for sample in patterns if sample["nearest_rows_changed"] == 2]
            terrain_changes = dict(Counter(sample["same_terrain_changes"] for sample in switches))
            boundary_changes = sum(sample["boundary_changes"] for sample in patterns)
            print(f"two-row swaps, unchanged region per changed row={terrain_changes}; "
                  f"changed positions on a region boundary={boundary_changes}/{sum(s['nearest_rows_changed'] for s in patterns)}")

    accepted = [row for row in rows if row["status"] == "success"]
    attempted = [row for row in rows if row["status"] != "unsupported"]
    signatures = {
        (row["size"], tuple(row["minimal_masks"]), tuple(row["techniques"]), tuple(row["choices"]), row["chain"])
        for row in accepted
    }
    masks = [sum(mask in row["solved_by"] for row in accepted) for mask in range(8)]
    minimum = Counter(tuple(row["minimal_masks"]) for row in accepted)
    layouts = {(row["size"], layout_key(row)) for row in accepted}
    definitions = {
        (row["difficulty"], row["size"], tuple(row["regions"]), tuple(row["solution"]), tuple(row["locked_bears"]))
        for row in accepted
    }
    bears = {(row["size"], tuple(row["solution"])) for row in accepted}
    if accepted:
        print(f"layout={len(layouts)} definitions={len(definitions)} bear={len(bears)} signatures={len(signatures)}")
        print(f"overlap masks 0..7={masks} minimal masks={dict(minimum)}")
        if accepted[0]["difficulty"] in ["EXTRA HARD", "NIGHTMARES"]:
            print(f"overlap masks 15,31={[sum(mask in row['solved_by'] for row in accepted) for mask in [15, 31]]}")
        for key in ("steps", "chain"):
            values = [row[key] for row in accepted]
            print(f"{key} min/mean/median/max: {min(values)}/{mean(values):.2f}/{median(values)}/{max(values)}")
    if attempted:
        fallbacks = sum(row["fallback"] for row in accepted)
        fresh = len(accepted) - fallbacks
        total_candidates = fresh + sum(rejections.values())
        acceptance = 100 * fresh / total_candidates if total_candidates else 0
        print(f"fallbacks={fallbacks} candidate acceptance={fresh}/{total_candidates} ({acceptance:.3f}%)")
    for size, data in itertools.groupby(sorted(rows, key=lambda row: row["size"]), key=lambda row: row["size"]):
        size_rows = list(data)
        group = [row for row in size_rows if row["status"] != "unsupported"]
        if group:
            timing = sorted(row["usec"] / 1000 for row in group)
            p95 = timing[(95 * len(timing) + 99) // 100 - 1]
            fulfilled = sum(row["status"] == "success" for row in group)
            print(f"{size}x{size} fulfilled={fulfilled}/{len(size_rows)} "
                  f"exhausted={len(group) - fulfilled} unsupported={len(size_rows) - len(group)} "
                  f"mean={mean(timing):.3f} p95={p95:.3f} worst={max(timing):.3f} ms")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--annotated", type=Path)
    args = parser.parse_args()
    rows = [json.loads(line) for line in args.input.read_text(encoding="utf-8").splitlines()]
    if any(row["stage"] != stage for stage, row in enumerate(rows, 1)):
        raise ValueError("Expected consecutive stage records starting at stage 1")
    for row in rows:
        if "repairs" in row:
            repair = row["repairs"]
            classified = sum(repair[key] for key in ("no_edit", "still_ambiguous", "resolved", "structural_failure"))
            if repair["ambiguity_attempts"] != classified or repair["profile_pass"] > repair["resolved"]:
                raise ValueError(f"Inconsistent repair measurements at stage {row['stage']}")
            if "repair_gate_rejections" in row and sum(row["repair_gate_rejections"].values()) + repair["profile_pass"] != repair["resolved"]:
                raise ValueError(f"Incomplete repair-gate measurements at stage {row['stage']}")
        if row["status"] == "success" and not all(row[key] for key in ("rules", "unique", "logical", "profile_verified")):
            raise ValueError(f"Invalid acceptance at stage {row['stage']}")
        if row["status"] == "success":
            if not verify_board(row):
                raise ValueError(f"Independent verification failed at stage {row['stage']}")
            singleton_count = sum(count == 1 for count in Counter(row["regions"]).values())
            allowed = {"BASE": [1], "EASY": [0, 1], "MEDIUM": [0], "HARD": [0], "EXTRA HARD": [0], "NIGHTMARES": [0]}
            if singleton_count not in allowed[row["difficulty"]]:
                raise ValueError(f"Invalid singleton count at stage {row['stage']}")
            given = row["locked_bears"]
            if len(given) != (row["stage"] == 1) or any(bear not in row["solution"] for bear in given):
                raise ValueError(f"Invalid locked bear at stage {row['stage']}")
    exact, near = find_layout_matches(rows)
    print(f"Independently verified {sum(row['status'] == 'success' for row in rows)} accepted boards")
    print("ALL")
    summarize(rows)
    for category in DIFFICULTIES:
        print(f"\n{category}")
        summarize([row for row in rows if row["difficulty"] == category])
    print(f"\nExact layout pairs and stage separations: {[(a, b, b - a) for a, b in exact]}")
    print(f"Near layout pairs (1–4 boundary edges): {len(near)}, across {len({stage for pair in near for stage in pair})} stages")
    if args.annotated:
        args.annotated.write_text("".join(json.dumps(row) + "\n" for row in rows), encoding="utf-8")


if __name__ == "__main__":
    main()
