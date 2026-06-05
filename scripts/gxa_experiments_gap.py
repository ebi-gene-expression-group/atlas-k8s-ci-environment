#!/usr/bin/env python3
"""List experiment accessions on SOURCE but not on TARGET (species present on TARGET only)."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.request
from collections import defaultdict


def fetch_experiments(url: str) -> list[dict]:
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = json.load(resp)
    if isinstance(data, dict) and "experiments" in data:
        return data["experiments"]
    if isinstance(data, list):
        return data
    raise ValueError(f"Unexpected JSON shape from {url}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--count",
        type=int,
        default=0,
        help="Max accessions to print (0 = all)",
    )
    parser.add_argument(
        "--per-species",
        type=int,
        default=0,
        help="If set, show at most N accessions per species (sorted)",
    )
    parser.add_argument(
        "--comma-list",
        action="store_true",
        help="Print a single comma-separated list (for trigger-indexing)",
    )
    args = parser.parse_args()

    source_url = os.environ.get("GXA_SOURCE_JSON_URL", "").strip()
    target_url = os.environ.get("GXA_TARGET_JSON_URL", "").strip()
    if not source_url or not target_url:
        print(
            "Set GXA_SOURCE_JSON_URL and GXA_TARGET_JSON_URL in .env (see .env.example)",
            file=sys.stderr,
        )
        return 1

    target_env = os.environ.get("TARGET_ENVIRONMENT", "").strip()
    print(f"GXA_SOURCE_JSON_URL={source_url}")
    print(f"GXA_TARGET_JSON_URL={target_url}")
    if target_env:
        print(f"TARGET_ENVIRONMENT={target_env}")
    print()

    prod = fetch_experiments(source_url)
    master = fetch_experiments(target_url)

    master_accessions = {e["experimentAccession"] for e in master}
    master_species = {e.get("species") or "(unknown)" for e in master}

    missing_by_species: dict[str, list[str]] = defaultdict(list)
    for e in prod:
        acc = e["experimentAccession"]
        species = e.get("species") or "(unknown)"
        if species in master_species and acc not in master_accessions:
            missing_by_species[species].append(acc)

    flat_sorted = sorted(
        acc
        for accs in missing_by_species.values()
        for acc in accs
    )
    if args.count:
        flat_sorted = flat_sorted[: args.count]

    total_missing = sum(len(v) for v in missing_by_species.values())
    print(f"Missing on target (species on target only): {total_missing}")
    print(f"Species with gaps: {len(missing_by_species)}")
    print()

    if args.comma_list:
        print(",".join(flat_sorted))
        return 0

    shown = 0
    for species in sorted(missing_by_species):
        accs = sorted(missing_by_species[species])
        if args.per_species:
            accs = accs[: args.per_species]
        if args.count:
            accs = accs[: max(0, args.count - shown)]
            if not accs:
                break
        master_count = sum(
            1 for e in master if (e.get("species") or "(unknown)") == species
        )
        preview = ", ".join(accs[:3])
        extra = len(missing_by_species[species]) - min(3, len(accs))
        suffix = f" … (+{extra} more)" if extra > 0 else ""
        print(f"{species} ({len(missing_by_species[species])} missing, {master_count} on target): {preview}{suffix}")
        shown += len(accs)

    return 0


if __name__ == "__main__":
    sys.exit(main())
