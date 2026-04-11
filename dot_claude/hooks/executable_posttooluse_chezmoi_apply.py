#!/usr/bin/env python3
"""Async PostToolUse hook that runs chezmoi apply after file edits.

When Claude edits or writes a file inside the chezmoi source directory,
this hook applies the change to the target path so the live config stays
in sync — the same workflow Neovim's BufWritePost autocmd provides.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys


def _apply_in_source_dir(source_dir: str, file_path: str) -> None:
    """Apply a file edit within a single chezmoi source dir."""
    source_dir = os.path.expanduser(source_dir)

    if not file_path.startswith(source_dir):
        return

    relative = os.path.relpath(file_path, source_dir)

    # Skip files that should never be applied
    if relative.startswith(".git") or relative.startswith(".chezmoi"):
        return

    # Template files — find and apply their dependents
    if relative.startswith(".chezmoitemplates/"):
        template_name = relative.removeprefix(".chezmoitemplates/")
        try:
            rg = subprocess.run(
                ["rg", "-l", f'(include|template) "{template_name}"', source_dir],
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )
        except (subprocess.TimeoutExpired, FileNotFoundError):
            return
        if rg.returncode == 0:
            for dep in rg.stdout.strip().splitlines():
                subprocess.run(
                    ["chezmoi", "--source", source_dir, "apply", "--source-path", dep],
                    capture_output=True,
                    timeout=30,
                    check=False,
                )
        return

    # Check if the file is ignored by chezmoi
    try:
        ignored = subprocess.run(
            ["chezmoi", "--source", source_dir, "ignored"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        if ignored.returncode == 0 and relative in ignored.stdout.splitlines():
            return
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass

    subprocess.run(
        ["chezmoi", "--source", source_dir, "apply", "--source-path", file_path],
        capture_output=True,
        timeout=30,
        check=False,
    )


def _main() -> None:
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError:
        return

    tool_input = input_data.get("tool_input", {})
    file_path = tool_input.get("file_path", "")

    if not file_path:
        return

    chezmoi_dirs = os.environ.get("CHEZMOI_SOURCE_DIR", "")
    if not chezmoi_dirs:
        return

    for source_dir in chezmoi_dirs.split(":"):
        if source_dir:
            _apply_in_source_dir(source_dir, file_path)


if __name__ == "__main__":
    _main()
