#!/usr/bin/env python3
"""PreToolUse hook that rewrites file paths to their chezmoi source equivalents.

When Claude tries to Edit/Write/Read a chezmoi-managed file at its target path
(e.g. ~/.config/fish/config.fish), this hook rewrites the path to the chezmoi
source directory (e.g. ~/.local/share/chezmoi/dot_config/fish/config.fish).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys


def chezmoi_source_path(target: str) -> str | None:
    """Return the chezmoi source path for a target path, or None."""
    try:
        result = subprocess.run(
            ["chezmoi", "source-path", target],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None
    if result.returncode == 0:
        return result.stdout.strip()
    return None


def resolve_and_lookup(file_path: str) -> str | None:
    """Try to find the chezmoi source path, resolving symlinks if needed."""
    source = chezmoi_source_path(file_path)
    if source:
        return source

    # Resolve symlinks and try again (e.g. ~/.config/nvim -> ~/.config/nvim_conf/...)
    try:
        resolved = os.path.realpath(file_path)
    except (OSError, ValueError):
        return None

    if resolved != file_path:
        return chezmoi_source_path(resolved)
    return None


def _main() -> None:
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError:
        return

    tool_input = input_data.get("tool_input", {})

    # Edit/Write/Read use "file_path", Glob/Grep use "path"
    path_key = "file_path" if "file_path" in tool_input else "path"
    file_path = tool_input.get(path_key, "")

    if not file_path:
        return

    source_path = resolve_and_lookup(file_path)
    if not source_path:
        return

    # Build updatedInput with the rewritten path
    updated_input = dict(tool_input)
    updated_input[path_key] = source_path

    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "updatedInput": updated_input,
                "additionalContext": (
                    f"Path rewritten: {file_path} -> {source_path} (chezmoi source). "
                ),
            }
        },
        sys.stdout,
    )


if __name__ == "__main__":
    _main()
