#!/usr/bin/env python3
"""Merge all JSON files in ~/.claude/settings.d/ into a single settings object.

Objects are deep-merged alphabetically (later files win for scalars).
Arrays are concatenated.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def deep_merge(base: dict, overlay: dict) -> dict:
    result = dict(base)
    for key, value in overlay.items():
        if key in result:
            if isinstance(result[key], dict) and isinstance(value, dict):
                result[key] = deep_merge(result[key], value)
            elif isinstance(result[key], list) and isinstance(value, list):
                result[key] = result[key] + value
            else:
                result[key] = value
        else:
            result[key] = value
    return result


def main() -> None:
    settings_dir = Path.home() / ".claude" / "settings.d"
    merged: dict = {}
    for path in sorted(settings_dir.glob("*.json")):
        with open(path) as f:
            merged = deep_merge(merged, json.load(f))
    json.dump(merged, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
