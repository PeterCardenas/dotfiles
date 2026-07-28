#!/usr/bin/env python3
"""PreToolUse hook that sanitizes git commit and PR commands."""

from __future__ import annotations

import json
import re
import shlex
import subprocess
import sys

from hook_context import allow_with_updated_input

_DECISION_REASON = "Removed agent attribution and formatted the git command."
COMMIT_CMD_RE = re.compile(r"(^|[;&|])\s*git\b(?:(?![;&|]).)*\bcommit(\s|$)")
PR_CREATE_CMD_RE = re.compile(r"(^|[;&|])\s*gh\s+pr\s+create(\s|$)")
HEREDOC_MESSAGE_RE = re.compile(
    r"(\s(?:-m|--message)\s+[\"']\$\(\s*cat\s+<<'EOF'\n)([\s\S]*?)(\nEOF\n\)\s*[\"'])"
)
MESSAGE_OPT_RE = re.compile(r"(?<=\s)(?:--message|-m)(?=[\s=])")
QUOTED_VALUE_RE = re.compile(r"[ \t]+([\"'])(.*?)\1", re.DOTALL)
TRAILER_PATTERNS = (
    r"Made-with:\s*Cursor",
    r"Co-authored-by:\s*Cursor <[^>]+>",
    r"Co-authored-by:\s*Claude <[^>]+>",
)
LITERAL_TRAILER_RES = tuple(
    re.compile(rf"(?i){pattern}(?=(?:\r?\n|$|['\"]))") for pattern in TRAILER_PATTERNS
)
ESCAPED_TRAILER_RES = tuple(
    re.compile(rf"(?i){pattern}(?=(?:\\n|$|['\"]))") for pattern in TRAILER_PATTERNS
)
PR_ATTRIBUTION_PATTERNS = (
    r"Made with \[Cursor\]\(https://cursor\.com\)",
    # Claude Code prefixes the line with a 🤖 emoji; strip it too when present.
    r"(?:🤖\s*)?Generated with \[Claude Code\]\(https://claude\.(?:com/claude-code|ai/code)\)",
)
LITERAL_PR_ATTRIBUTION_RES = tuple(
    re.compile(rf"(?i){pattern}(?=(?:\r?\n|$|['\"]))")
    for pattern in PR_ATTRIBUTION_PATTERNS
)
ESCAPED_PR_ATTRIBUTION_RES = tuple(
    re.compile(rf"(?i){pattern}(?=(?:\\n|$|['\"]))")
    for pattern in PR_ATTRIBUTION_PATTERNS
)
EMPTY_TRAILER_ARG_RE = re.compile(r"""\s+--trailer(?:\s+|=)(['"])\s*\1""")
LITERAL_EMPTY_LINES_BEFORE_CLOSER_RE = re.compile(r"\n{2,}(?=['\"])")
ESCAPED_EMPTY_LINES_BEFORE_CLOSER_RE = re.compile(r"(?:\\n){2,}(?=['\"])")


def _format_message(message: str) -> str:
    try:
        result = subprocess.run(
            ["commitmsgfmt"],
            input=message,
            text=True,
            capture_output=True,
            check=False,
        )
    except OSError:
        return message

    if result.returncode != 0:
        return message

    return result.stdout


def _replace_heredoc_message(command: str) -> str:
    def _replacement(match: re.Match[str]) -> str:
        prefix, message, suffix = match.groups()
        formatted = _format_message(message).rstrip("\n")
        return f"{prefix}{formatted}{suffix}"

    return HEREDOC_MESSAGE_RE.sub(_replacement, command, count=1)


def _decode_dquoted(text: str) -> str:
    """Decode the literal text bash hands to a program from a double-quoted arg.

    Single left-to-right pass (not chained str.replace, which would
    double-process already-decoded output). Inside bash double quotes a
    backslash is only special before `$`, backtick, `"`, `\\`, and a real
    newline (line continuation); every other backslash is passed through
    unchanged, backslash and all.
    """
    out: list[str] = []
    i = 0
    n = len(text)
    while i < n:
        char = text[i]
        if char == "\\" and i + 1 < n:
            nxt = text[i + 1]
            if nxt in ("$", "`", '"', "\\"):
                out.append(nxt)
                i += 2
                continue
            if nxt == "\n":
                # Backslash-newline is a line continuation inside bash double
                # quotes: it is consumed and contributes nothing to the value.
                i += 2
                continue
            if nxt == "n":
                # Not real bash semantics: this repairs the common agent
                # mistake of writing the two characters `\n` inside a
                # double-quoted -m instead of an actual newline. Kept
                # intentionally (this is why the old code had
                # `.replace("\\n", "\n")`).
                out.append("\n")
                i += 2
                continue
            out.append(char)
            out.append(nxt)
            i += 2
            continue
        out.append(char)
        i += 1
    return "".join(out)


def _find_message_args(command: str) -> list[tuple[int, int, str, str]] | None:
    """Locate every quoted -m/--message argument, left to right.

    Each span starts at the whitespace before the option and ends after the
    closing quote, so a caller can splice one out without leaving a double
    space. Scanning resumes past each value, so a `-m` occurring inside a
    message body is not mistaken for another option.

    Returns None if the command holds a -m/--message this parser cannot read
    whole (unquoted value, or the `--message=body` form). Rewriting only the
    messages it can read would silently reorder the commit body, so the caller
    leaves such a command untouched.
    """
    message_args: list[tuple[int, int, str, str]] = []
    pos = 0
    while True:
        option = MESSAGE_OPT_RE.search(command, pos)
        if option is None:
            return message_args

        value = QUOTED_VALUE_RE.match(command, option.end())
        if value is None:
            return None

        start = option.start()
        while start > 0 and command[start - 1] in " \t":
            start -= 1
        message_args.append((start, value.end(), value.group(1), value.group(2)))
        pos = value.end()


def _segment_spans(command: str) -> list[tuple[int, int]]:
    """Split a command line into top-level segments.

    Quote-aware, so a `;` or `|` inside a commit message is not read as a
    command boundary. Segments matter because -m arguments must only ever be
    joined within the one `git commit` they belong to: scanning the whole line
    would merge the messages of two commits into the first of them.
    """
    spans: list[tuple[int, int]] = []
    start = 0
    quote = ""
    index = 0
    while index < len(command):
        char = command[index]
        if quote:
            if char == "\\" and quote == '"' and index + 1 < len(command):
                index += 2
                continue
            if char == quote:
                quote = ""
            index += 1
            continue
        if char in "\"'":
            quote = char
            index += 1
            continue
        if char == "\\" and index + 1 < len(command):
            index += 2
            continue
        if char in ";&|\n":
            spans.append((start, index))
            start = index + 1
        index += 1
    spans.append((start, len(command)))
    return spans


def _replace_quoted_message(command: str) -> str:
    # Right to left so each rewrite leaves the earlier segment spans valid.
    for start, end in reversed(_segment_spans(command)):
        segment = command[start:end]
        if not (COMMIT_CMD_RE.search(segment) or PR_CREATE_CMD_RE.search(segment)):
            continue
        rewritten = _replace_segment_messages(segment)
        if rewritten != segment:
            command = command[:start] + rewritten + command[end:]
    return command


def _replace_segment_messages(command: str) -> str:
    message_args = _find_message_args(command)
    if not message_args:
        return command

    # git joins repeated -m bodies with a blank line between them, so decode
    # them into that one message and format it as a whole. Running
    # commitmsgfmt per -m instead would read every paragraph as its own
    # subject line, and formatting only the first (what this hook used to do)
    # left the rest as single 400-char lines.
    decoded = "\n\n".join(
        # A single-quoted body is already the literal bytes bash passes on.
        _decode_dquoted(body) if quote == '"' else body
        for _start, _end, quote, body in message_args
    )
    formatted = _format_message(decoded).rstrip("\n")

    # Splice from the right so the earlier spans stay valid: the trailing -m
    # args collapse into the first one, which becomes the whole message.
    rebuilt = command
    for start, end, _quote, _body in reversed(message_args[1:]):
        rebuilt = rebuilt[:start] + rebuilt[end:]

    first_start, first_end, _quote, _body = message_args[0]
    # shlex.quote (single-quoting) replaces hand-rolled double-quote escaping
    # so arbitrary bytes (including real newlines) round-trip correctly; the
    # original quote char is dropped since shlex.quote picks its own. Behavior
    # change: `$(...)`/`$VAR` in a double-quoted -m used to expand at exec
    # time -- now it's committed literally, since the message is re-encoded as
    # inert text.
    return rebuilt[:first_start] + f" -m {shlex.quote(formatted)}" + rebuilt[first_end:]


def _strip_agent_attribution(command: str) -> str:
    cleaned = command
    for trailer_re in LITERAL_TRAILER_RES:
        cleaned = trailer_re.sub("", cleaned)
    for trailer_re in ESCAPED_TRAILER_RES:
        cleaned = trailer_re.sub("", cleaned)
    cleaned = EMPTY_TRAILER_ARG_RE.sub("", cleaned)
    for attribution_re in LITERAL_PR_ATTRIBUTION_RES:
        cleaned = attribution_re.sub("", cleaned)
    for attribution_re in ESCAPED_PR_ATTRIBUTION_RES:
        cleaned = attribution_re.sub("", cleaned)
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)
    cleaned = re.sub(r"(?:\\n){3,}", lambda _: "\\n\\n", cleaned)
    cleaned = re.sub(r"[ \t]+\n", "\n", cleaned)
    cleaned = LITERAL_EMPTY_LINES_BEFORE_CLOSER_RE.sub("\n", cleaned)
    cleaned = ESCAPED_EMPTY_LINES_BEFORE_CLOSER_RE.sub("\\n", cleaned)
    return cleaned


def _sanitize_command(command: str) -> str:
    command = _strip_agent_attribution(command)
    if HEREDOC_MESSAGE_RE.search(command):
        return _replace_heredoc_message(command)

    return _replace_quoted_message(command)


def _main() -> None:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        payload = {}

    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        json.dump({}, sys.stdout)
        return

    command = tool_input.get("command")
    if not isinstance(command, str) or not (
        COMMIT_CMD_RE.search(command) or PR_CREATE_CMD_RE.search(command)
    ):
        json.dump({}, sys.stdout)
        return

    cleaned = _sanitize_command(command)
    if cleaned == command:
        json.dump({}, sys.stdout)
        return

    json.dump(
        allow_with_updated_input(tool_input, {"command": cleaned}, _DECISION_REASON),
        sys.stdout,
    )


if __name__ == "__main__":
    _main()
