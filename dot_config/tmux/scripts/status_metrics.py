#!/usr/bin/env python3
"""Collect status metrics once, then render the shared colored-run protocol."""

import argparse
import json
import os
import re
import stat
import subprocess
from pathlib import Path

STYLE = re.compile(r"#\[([^]]*)\]")
COLORS = {
    "text": "#c0caf5",
    "separator": "#565f89",
    "cpu": "#ff9e64",
    "disk": "#bb9af7",
    "ram": "#7dcfff",
}


def command_output(argv: list[str]) -> str:
    try:
        result = subprocess.run(argv, text=True, capture_output=True, timeout=25)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return result.stdout.rstrip("\n") if result.returncode == 0 else ""


def colored_runs(text: str, initial_color: str = COLORS["text"]) -> list[dict[str, str]]:
    runs: list[dict[str, str]] = []
    color = initial_color
    offset = 0
    for match in STYLE.finditer(text):
        if match.start() > offset:
            runs.append({"fg": color, "text": text[offset : match.start()]})
        for attribute in match.group(1).split(","):
            if attribute.startswith("fg="):
                color = attribute.removeprefix("fg=")
        offset = match.end()
    if offset < len(text):
        runs.append({"fg": color, "text": text[offset:]})
    return [run for run in runs if run["text"]]


def collect(short: bool) -> list[dict[str, str]]:
    scripts = Path(os.environ.get("TMUX_SCRIPTS_DIR", Path.home() / ".config/tmux/scripts"))
    custom_dir = Path(os.environ.get("TMUX_CUSTOM_SCRIPTS_DIR", Path.home() / ".config/tmux/custom_scripts"))
    arguments = ["--short"] if short else []
    segments: list[list[dict[str, str]]] = []

    if custom_dir.is_dir():
        for script in sorted(custom_dir.iterdir()):
            if script.is_file() and script.stat().st_mode & stat.S_IXUSR:
                output = command_output([str(script), *arguments])
                if output:
                    segments.append(colored_runs(output))

    cursor = command_output([str(scripts / "cursor_spend.sh"), *arguments])
    if cursor:
        segments.append(colored_runs(cursor))

    for script_name, icon, color in (
        ("cpu.sh", "󰍛 ", COLORS["cpu"]),
        ("disk.sh", "󰋊 ", COLORS["disk"]),
        ("ram.sh", "󰘚 ", COLORS["ram"]),
    ):
        output = command_output([str(scripts / script_name), *arguments])
        if output:
            segments.append([{"fg": color, "text": icon}, *colored_runs(output)])

    separator = " " if short else " · "
    runs: list[dict[str, str]] = []
    for segment in segments:
        if runs:
            runs.append({"fg": COLORS["separator"], "text": separator})
        runs.extend(segment)
    return runs


def ansi_color(color: str) -> str:
    red, green, blue = (int(color[index : index + 2], 16) for index in (1, 3, 5))
    return f"\x1b[38;2;{red};{green};{blue}m"


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--short", action="store_true")
    parser.add_argument("--format", default="tmux")
    try:
        args = parser.parse_args()
    except SystemExit:
        return 2
    if args.format not in {"tmux", "herdr", "gnome", "protocol"}:
        print(f"invalid format: {args.format} (expected tmux, herdr, gnome, or protocol)", file=__import__("sys").stderr)
        return 2

    runs = collect(args.short)
    if args.format == "protocol":
        print(json.dumps({"version": 1, "runs": runs}, ensure_ascii=False), end="")
    elif args.format == "herdr":
        print("".join(run["text"] for run in runs), end="")
    elif args.format == "gnome":
        print("".join(ansi_color(run["fg"]) + run["text"] for run in runs) + ("\x1b[0m" if runs else ""), end="")
    else:
        print("".join(f"#[fg={run['fg']}]{run['text']}" for run in runs), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
