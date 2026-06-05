#!/usr/bin/env python3
"""List production species absent on GXA target, ranked by experiment count."""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from collections import defaultdict


def fetch_experiments(url: str) -> list[dict]:
    with urllib.request.urlopen(url, timeout=120) as resp:
        data = json.load(resp)
    if isinstance(data, dict):
        return data["experiments"]
    return data


def to_slug(species: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", species.lower())
    return re.sub(r"_+", "_", slug).strip("_")


def jenkins_species_choices(jenkins_url: str, job: str, user: str, password: str) -> set[str]:
    url = f"{jenkins_url.rstrip('/')}/job/{job}/config.xml"
    req = urllib.request.Request(url)
    token = base64.b64encode(f"{user}:{password}".encode()).decode()
    req.add_header("Authorization", f"Basic {token}")
    with urllib.request.urlopen(req, timeout=60) as resp:
        root = ET.fromstring(resp.read())
    choices: set[str] = set()
    for param in root.findall(".//parameterDefinitions/*"):
        if param.findtext("name") != "SPECIES":
            continue
        for choice in param.findall(".//choices/a/string"):
            if choice.text:
                choices.add(choice.text)
    if not choices:
        raise ValueError(f"No SPECIES choices found in Jenkins job {job}")
    return choices


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--count", type=int, default=10, help="Max species to print")
    parser.add_argument(
        "--comma-slugs",
        action="store_true",
        help="Print comma-separated Jenkins SPECIES slugs only (for trigger-bioentities-top)",
    )
    parser.add_argument(
        "--require-jenkins-slug",
        action="store_true",
        default=True,
        help="Only include species with a matching Jenkins SPECIES choice (default: true)",
    )
    args = parser.parse_args()

    source_url = os.environ.get(
        "GXA_SOURCE_JSON_URL", "https://www.ebi.ac.uk/gxa/json/experiments"
    )
    target_url = os.environ.get("GXA_TARGET_JSON_URL", "").strip()
    if not target_url:
        print("Set GXA_TARGET_JSON_URL in .env (see .env.example)", file=sys.stderr)
        return 1

    prod = fetch_experiments(source_url)
    master = fetch_experiments(target_url)
    master_species = {e.get("species") or "(unknown)" for e in master}

    by_species: dict[str, int] = defaultdict(int)
    for e in prod:
        by_species[e.get("species") or "(unknown)"] += 1

    prod_only = [(sp, count, to_slug(sp)) for sp, count in by_species.items() if sp not in master_species]
    prod_only.sort(key=lambda x: -x[1])

    jenkins_choices: set[str] | None = None
    if args.require_jenkins_slug:
        jenkins_url = os.environ.get("JENKINS_URL", "http://45.88.80.151:30004/jenkins")
        job = os.environ.get(
            "JENKINS_BIOENTITIES_JOB", "H_bioentities_loading_pipeline_bulk_and_sc"
        )
        user = os.environ.get("JENKINS_USER", "")
        token = os.environ.get("JENKINS_TOKEN", "")
        if not user or not token:
            print("Set JENKINS_USER and JENKINS_TOKEN in .env", file=sys.stderr)
            return 1
        jenkins_choices = jenkins_species_choices(jenkins_url, job, user, token)

    picks: list[tuple[str, int, str]] = []
    for sp, count, slug in prod_only:
        if jenkins_choices is not None and slug not in jenkins_choices:
            continue
        picks.append((sp, count, slug))
        if len(picks) >= args.count:
            break

    if args.comma_slugs:
        print(",".join(slug for _, _, slug in picks))
        return 0

    print(f"GXA_SOURCE_JSON_URL={source_url}")
    print(f"GXA_TARGET_JSON_URL={target_url}")
    print(f"Prod-only species with Jenkins slug: showing top {len(picks)}\n")
    for sp, count, slug in picks:
        in_jenkins = "" if jenkins_choices is None else " ✓"
        print(f"  {slug}: {count} experiments ({sp}){in_jenkins}")

    skipped = [
        (sp, count, slug)
        for sp, count, slug in prod_only[: args.count + 5]
        if jenkins_choices and slug not in jenkins_choices
    ]
    if skipped and jenkins_choices:
        print("\nSkipped (no Jenkins SPECIES choice):")
        for sp, count, slug in skipped[:3]:
            print(f"  {slug}: {count} ({sp})")

    return 0


if __name__ == "__main__":
    sys.exit(main())
