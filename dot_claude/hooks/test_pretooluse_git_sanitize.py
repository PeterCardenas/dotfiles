#!/usr/bin/env python3
"""Tests for pretooluse_git_sanitize.py.

Covers stripping agent attribution (Cursor and Claude Code) from both git
commit and `gh pr create` commands, in heredoc, quoted-escaped, and trailer
forms.

Not given an `executable_` chezmoi prefix so it deploys as a plain,
non-executable file.
"""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


# Load from the chezmoi source script (not the `~/.claude/hooks` deployed copy)
# so the test always exercises the change under review, even before a
# `chezmoi apply` has synced it to the deployed path.
SCRIPT_PATH = Path(__file__).with_name("executable_pretooluse_git_sanitize.py")


def load_module():
    spec = importlib.util.spec_from_file_location(
        "pretooluse_git_sanitize", SCRIPT_PATH
    )
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class StripAgentAttributionTest(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_module()

    def test_removes_claude_pr_attribution_heredoc(self) -> None:
        command = (
            'gh pr create --title "feat: x" --body "$(cat <<\'EOF\'\n'
            "Does a thing.\n\n"
            "🤖 Generated with [Claude Code](https://claude.com/claude-code)\n"
            'EOF\n)"'
        )
        cleaned = self.module._sanitize_command(command)
        self.assertNotIn("Claude Code", cleaned)
        self.assertNotIn("🤖", cleaned)
        self.assertIn("Does a thing.", cleaned)

    def test_removes_claude_attribution_and_trailer_escaped(self) -> None:
        command = (
            'git commit -m "feat: x\\n\\n'
            "🤖 Generated with [Claude Code](https://claude.com/claude-code)\\n\\n"
            'Co-Authored-By: Claude <noreply@anthropic.com>"'
        )
        cleaned = self.module._sanitize_command(command)
        self.assertEqual(cleaned, 'git commit -m "feat: x"')

    def test_removes_claude_attribution_without_emoji(self) -> None:
        command = (
            'gh pr create --body "$(cat <<\'EOF\'\n'
            "Body.\n\n"
            "Generated with [Claude Code](https://claude.com/claude-code)\n"
            'EOF\n)"'
        )
        cleaned = self.module._sanitize_command(command)
        self.assertNotIn("Claude Code", cleaned)
        self.assertIn("Body.", cleaned)

    def test_preserves_unrelated_claude_mentions(self) -> None:
        command = 'git commit -m "docs: mention Claude Code in the readme"'
        cleaned = self.module._sanitize_command(command)
        self.assertEqual(cleaned, command)

    def test_still_strips_cursor_attribution(self) -> None:
        command = (
            'gh pr create --body "$(cat <<\'EOF\'\n'
            "Body.\n\n"
            "Made with [Cursor](https://cursor.com)\n"
            'EOF\n)"'
        )
        cleaned = self.module._sanitize_command(command)
        self.assertNotIn("Cursor", cleaned)


if __name__ == "__main__":
    unittest.main()
