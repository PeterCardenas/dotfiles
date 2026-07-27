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
import os
import stat
import subprocess
import tempfile
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


# A stub `git` that dumps whatever follows -m/--message to a file, so tests
# can assert on the literal bytes a real `git commit` would have received --
# the only way to prove the hook produces valid, correctly-quoted bash,
# rather than a string that merely looks right.
_STUB_GIT_SCRIPT = """#!/usr/bin/env bash
prev=""
for arg in "$@"; do
  if [ "$prev" = "-m" ] || [ "$prev" = "--message" ]; then
    printf '%s' "$arg" > "$GIT_STUB_OUT"
  fi
  prev="$arg"
done
"""


def _deliver_via_stub_git(command: str) -> str:
    """Execute `command` under bash with a stub `git` on PATH and return the
    exact text `git` received as its -m/--message argument."""
    with tempfile.TemporaryDirectory() as tmpdir:
        stub_dir = Path(tmpdir) / "bin"
        stub_dir.mkdir()
        stub_git = stub_dir / "git"
        stub_git.write_text(_STUB_GIT_SCRIPT)
        stub_git.chmod(stub_git.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)

        out_file = Path(tmpdir) / "captured_message.txt"
        env = dict(os.environ)
        env["PATH"] = f"{stub_dir}{os.pathsep}{env.get('PATH', '')}"
        env["GIT_STUB_OUT"] = str(out_file)

        result = subprocess.run(
            ["bash", "-c", command],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        assert result.returncode == 0, (
            f"sanitized command failed to execute: {result.stderr}"
        )
        assert out_file.exists(), "stub git never saw a -m/--message argument"
        return out_file.read_text()


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
        # Re-encoding now always goes through shlex.quote(), which emits a
        # single-quoted argument (never double quotes) whenever quoting is
        # needed -- the quote character changes even though the message
        # content is untouched.
        self.assertEqual(cleaned, "git commit -m 'feat: x'")

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
        # Message content is unchanged (no attribution to strip); only the
        # quote style changes, since re-encoding always goes through
        # shlex.quote() now (see comment on the sibling test above).
        self.assertEqual(cleaned, "git commit -m 'docs: mention Claude Code in the readme'")

    def test_still_strips_cursor_attribution(self) -> None:
        command = (
            'gh pr create --body "$(cat <<\'EOF\'\n'
            "Body.\n\n"
            "Made with [Cursor](https://cursor.com)\n"
            'EOF\n)"'
        )
        cleaned = self.module._sanitize_command(command)
        self.assertNotIn("Cursor", cleaned)


class DoubleQuotedMessageRoundTripTest(unittest.TestCase):
    """Regression tests for the decode -> format -> re-encode fix.

    The old code chained `.replace()` calls that (a) turned real newlines
    into literal `\\n` -- which bash double quotes do not interpret, so the
    message collapsed onto one line -- and (b) doubled the user's own `\\$`
    escapes, which bash then unescapes and expands as positional parameters
    (`$9`, `$1`) on re-parse, silently eating dollar amounts. These tests
    execute the sanitized command under a real bash to prove the fix, since
    a pure string comparison would not catch a quoting bug like this one.
    """

    def setUp(self) -> None:
        self.module = load_module()

    def test_end_to_end_bash_round_trip_preserves_dollar_amounts(self) -> None:
        # The real command that triggered this bug report.
        raw_message = (
            "feat(tmux.statusbar): slim down the narrow tier\\n\\n"
            "Under 115 columns things get tight (\\$9.9 / \\$123 / \\$1.2k)\\n"
            "via a shared helper"
        )
        command = f'git commit -m "{raw_message}"'

        cleaned = self.module._sanitize_command(command)
        delivered = _deliver_via_stub_git(cleaned)

        self.assertIn("$9.9", delivered)
        self.assertIn("$123", delivered)
        self.assertIn("$1.2k", delivered)
        self.assertNotIn("\\$", delivered)
        self.assertGreaterEqual(delivered.count("\n"), 2)
        self.assertIn(
            "feat(tmux.statusbar): slim down the narrow tier", delivered
        )

    def test_literal_backslash_n_is_deliberately_treated_as_newline(self) -> None:
        """Accepted trade-off, not a bug: a double-quoted -m body containing
        the literal two characters `\\n` is split onto a real newline. The
        losing case is a message that meant those two characters literally
        (e.g. "docs: explain printf \\n usage in scripts"), which now also
        gets split. We keep the repair anyway -- without it, an agent's
        common mistake of writing -m "a\\nb" would collapse back onto one
        line, which is the exact bug this fix exists to eliminate. Escape
        hatch for a literal `\\n`: single quotes pass it through untouched,
        see test_single_quoted_message_untouched below.
        """
        command = 'git commit -m "line one\\nline two"'

        cleaned = self.module._sanitize_command(command)
        delivered = _deliver_via_stub_git(cleaned)

        self.assertIn("\n", delivered)
        self.assertIn("line one", delivered)
        self.assertIn("line two", delivered)

    def test_decode_dquoted_handles_literal_quote_and_backslash(self) -> None:
        # QUOTED_MESSAGE_RE's lazy `.*?` stops at the first literal quote
        # character regardless of a preceding backslash, so a -m body
        # containing an escaped double quote can't be captured whole by the
        # top-level regex (a pre-existing, out-of-scope limitation). This
        # tests the actual fix -- the decode step -- directly instead.
        raw = 'say \\"hi\\" and use path C:\\\\foo'
        decoded = self.module._decode_dquoted(raw)
        self.assertEqual(decoded, 'say "hi" and use path C:\\foo')

    def test_real_embedded_newline_survives_reencode_through_bash(self) -> None:
        """The core bug: a -m body with an actual embedded newline (not the
        two characters `\\n`) used to come back out as literal `\\n` text,
        because the old encode step re-escaped real newlines into that form.
        Drives the full sanitize -> bash -> stub-git pipeline so a quoting
        regression is caught, not just a string comparison.
        """
        raw_message = "line one\nline two"
        command = f'git commit -m "{raw_message}"'

        cleaned = self.module._sanitize_command(command)
        delivered = _deliver_via_stub_git(cleaned)

        self.assertIn("\n", delivered)
        self.assertNotIn("\\n", delivered)
        self.assertIn("line one", delivered)
        self.assertIn("line two", delivered)

    def test_embedded_apostrophe_and_backslash_survive_shlex_reencode_through_bash(
        self,
    ) -> None:
        """Guards the re-encode step's handling of an embedded `'`: shlex.quote
        emits the `'"'"'` idiom to splice a literal single quote into a
        single-quoted argument. No other message body in this suite contains
        an apostrophe, so a future swap back to hand-rolled escaping could
        silently break apostrophe messages with a green suite otherwise.
        """
        raw_message = "fix(cli): don't crash on a \\d regex"
        command = f'git commit -m "{raw_message}"'

        cleaned = self.module._sanitize_command(command)
        delivered = _deliver_via_stub_git(cleaned)

        self.assertIn("don't crash", delivered)
        self.assertIn("\\d regex", delivered)

    def test_single_quoted_message_untouched(self) -> None:
        command = "git commit -m 'a message with $9.9 and \\$ signs'"
        cleaned = self.module._sanitize_command(command)
        self.assertEqual(cleaned, command)

    def test_attribution_stripped_end_to_end_round_trip(self) -> None:
        raw_message = (
            "feat: add cost tracker\\n\\n"
            "Saves about \\$4.50 per run.\\n\\n"
            "🤖 Generated with [Claude Code](https://claude.com/claude-code)\\n\\n"
            "Co-Authored-By: Claude <noreply@anthropic.com>"
        )
        command = f'git commit -m "{raw_message}"'

        cleaned = self.module._sanitize_command(command)
        delivered = _deliver_via_stub_git(cleaned)

        self.assertNotIn("Claude Code", delivered)
        self.assertNotIn("Co-Authored-By", delivered)
        self.assertIn("$4.50", delivered)
        self.assertNotIn("\\$", delivered)
        self.assertGreaterEqual(delivered.count("\n"), 1)
        self.assertIn("feat: add cost tracker", delivered)


if __name__ == "__main__":
    unittest.main()
