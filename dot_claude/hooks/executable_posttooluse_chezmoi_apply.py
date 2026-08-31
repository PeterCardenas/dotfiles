#!/usr/bin/env python3
"""Apply successful Edit/Write changes made inside the chezmoi source tree."""

from __future__ import annotations

import json
import os
import subprocess
import sys

from hook_context import deny_hook_response


def _main() -> None:
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
    absolute_path = os.path.realpath(
        file_path if os.path.isabs(file_path) else os.path.join(cwd, file_path)
    )

    try:
        source_result = subprocess.run(
            ["chezmoi", "source-path"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return
    if source_result.returncode != 0:
        return

    source_path = os.path.realpath(source_result.stdout.strip())
    try:
        inside_source = os.path.commonpath([source_path, absolute_path]) == source_path
    except ValueError:
        return
    if not inside_source:
        return

    try:
        apply_result = subprocess.run(
            ["chezmoi", "apply", "--source-path", absolute_path],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired) as error:
        json.dump(
            deny_hook_response(f"chezmoi apply failed for {absolute_path}: {error}", "PostToolUse"),
            sys.stdout,
        )
        return

    if apply_result.returncode != 0:
        details = (apply_result.stderr or apply_result.stdout).strip()
        json.dump(
            deny_hook_response(
                f"chezmoi apply failed for {absolute_path}: {details or 'unknown error'}",
                "PostToolUse",
            ),
            sys.stdout,
        )
        return

    json.dump(
        deny_hook_response(
            f"Applied {absolute_path} with chezmoi; do not run a manual apply.",
            "PostToolUse",
        ),
        sys.stdout,
    )


if __name__ == "__main__":
    _main()
