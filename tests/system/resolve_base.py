#!/usr/bin/env python3
"""Print GXA_SYSTEM_BASE for a catalogue ENV (ci|test|staging|public|fallback)."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml

CATALOGUE = Path(__file__).resolve().parents[2] / "config" / "gxa-environments.yaml"


def base_url_for(env: str) -> str:
    data = yaml.safe_load(CATALOGUE.read_text())
    # Helm / gxa-deploy ENV=test is k8s_test; environments.test is legacy wwwdev.
    if env == "test":
        env = "k8s_test"
    block = (data.get("environments") or {}).get(env)
    if not isinstance(block, dict):
        raise SystemExit(f"Unknown environment {env!r} in {CATALOGUE}")
    url = (block.get("base_url") or "").rstrip("/")
    if not url:
        raise SystemExit(f"No base_url for environments.{env} in {CATALOGUE}")
    return url


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("env", help="Catalogue key, e.g. staging")
    args = parser.parse_args()
    print(base_url_for(args.env), end="")


if __name__ == "__main__":
    main()
    sys.exit(0)
