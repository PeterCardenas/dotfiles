#!/usr/bin/env python3
"""Apply successful Edit/Write changes made inside the chezmoi source tree."""

from __future__ import annotations

import base64
import binascii
import json
import os
import subprocess
import sys
from pathlib import Path

from hook_context import deny_hook_response


SHARED_TEMPLATE_DIR = ".chezmoitemplates"
UNSCANNED_DIRS = frozenset({".git", "node_modules"})


def _shared_template_dependents(source_root: Path, edited: Path) -> list[str]:
    """Source entries that include a shared template.

    `.chezmoitemplates` files are not targets, so `apply --source-path` rejects them.
    Applying the entries that `{{ template "<name>" }}` them is what refreshes the targets.
    """
    reference = f'template "{edited.relative_to(source_root / SHARED_TEMPLATE_DIR).as_posix()}"'
    dependents: list[str] = []
    for directory, subdirectories, files in os.walk(source_root):
        subdirectories[:] = sorted(
            name for name in subdirectories if name not in UNSCANNED_DIRS
        )
        if Path(directory) == source_root and SHARED_TEMPLATE_DIR in subdirectories:
            subdirectories.remove(SHARED_TEMPLATE_DIR)
        for name in sorted(files):
            candidate = Path(directory) / name
            try:
                contents = candidate.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue
            if reference in contents:
                dependents.append(str(candidate))
    return dependents


def _main() -> None:
    if len(sys.argv) != 3 or sys.argv[1] != "--source-base64":
        return
    try:
        source_root = Path(base64.b64decode(sys.argv[2], validate=True).decode("utf-8")).resolve()
    except (binascii.Error, UnicodeDecodeError, ValueError):
        return
    if not source_root.is_dir():
        return
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        return

    if not isinstance(payload, dict):
        return
    tool_result = payload.get("tool_result", {})
    if not isinstance(tool_result, dict) or tool_result.get("is_error"):
        return

    tool_input = payload.get("tool_input", {})
    if not isinstance(tool_input, dict):
        return
    file_path = tool_input.get("file_path") or tool_input.get("path")
    if not isinstance(file_path, str) or not file_path:
        return

    cwd = payload.get("cwd") or payload.get("working_directory")
    if not isinstance(cwd, str) or not cwd:
        cwd = os.getcwd()
    try:
        absolute_path = os.path.realpath(
            file_path if os.path.isabs(file_path) else os.path.join(cwd, file_path)
        )
    except ValueError:
        return

    source_path = os.path.realpath(source_root)
    try:
        inside_source = os.path.commonpath([source_path, absolute_path]) == source_path
    except ValueError:
        return
    if not inside_source:
        return

    source_root = Path(source_path)
    edited = Path(absolute_path)
    if edited.is_relative_to(source_root / SHARED_TEMPLATE_DIR):
        apply_paths = _shared_template_dependents(source_root, edited)
        if not apply_paths:
            json.dump(
                deny_hook_response(
                    f"No source entry includes {absolute_path}; nothing to apply.",
                    "PostToolUse",
                ),
                sys.stdout,
            )
            return
    else:
        apply_paths = [absolute_path]

    for apply_path in apply_paths:
        try:
            apply_result = subprocess.run(
                ["chezmoi", "--source", source_path, "apply", "--source-path", apply_path],
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
        except (FileNotFoundError, subprocess.TimeoutExpired) as error:
            json.dump(
                deny_hook_response(f"chezmoi apply failed for {apply_path}: {error}", "PostToolUse"),
                sys.stdout,
            )
            return

        if apply_result.returncode != 0:
            details = (apply_result.stderr or apply_result.stdout).strip()
            json.dump(
                deny_hook_response(
                    f"chezmoi apply failed for {apply_path}: {details or 'unknown error'}",
                    "PostToolUse",
                ),
                sys.stdout,
            )
            return

    json.dump(
        deny_hook_response(
            f"Synced {', '.join(apply_paths)} with chezmoi; do not run a manual apply.",
            "PostToolUse",
        ),
        sys.stdout,
    )


if __name__ == "__main__":
    _main()
