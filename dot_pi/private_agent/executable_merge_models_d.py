#!/usr/bin/env python3
"""Merge all JSON files in ~/.pi/agent/models.d/ into one models object."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def deep_merge(base: dict, overlay: dict) -> dict:
    result = dict(base)
    for key, value in overlay.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def main() -> None:
    models_dir = Path.home() / ".pi" / "agent" / "models.d"
    merged: dict = {}
    for path in sorted(models_dir.glob("*.json")):
        with path.open() as fragment:
            merged = deep_merge(merged, json.load(fragment))
    json.dump(merged, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
