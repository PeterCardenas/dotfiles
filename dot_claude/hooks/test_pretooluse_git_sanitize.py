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
import json
import os
import shlex
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


# Load from the chezmoi source script (not the `~/.claude/hooks` deployed copy)
# so the test always exercises the change under review, even before a
# `chezmoi apply` has synced it to the deployed path.
SCRIPT_PATH = Path(__file__).with_name("executable_pretooluse_git_sanitize.py")


def load_module():
    # The hook imports hook_context, a sibling in the same hooks directory
    # (which is on sys.path when Claude Code runs the deployed script, but not
    # when this test loads it by path).
    if str(SCRIPT_PATH.parent) not in sys.path:
        sys.path.insert(0, str(SCRIPT_PATH.parent))
    spec = importlib.util.spec_from_file_location(
        "pretooluse_git_sanitize", SCRIPT_PATH
    )
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _run_hook(command: str) -> dict:
    """Run the hook as Claude Code does -- payload on stdin -- and return its
    parsed response."""
    payload = {
        "session_id": "test",
        "hook_event_name": "PreToolUse",
        "tool_name": "Bash",
        "tool_input": {"command": command, "description": "test"},
    }
    result = subprocess.run(
        [sys.executable, str(SCRIPT_PATH)],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, f"hook failed: {result.stderr}"
    return json.loads(result.stdout)


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


def _count_message_options(command: str) -> int:
    return sum(token in ("-m", "--message") for token in shlex.split(command))


def _deliver_via_stub_git(command: str) -> str:
    """Execute `command` under bash with a stub `git` on PATH and return the
    exact text `git` received as its -m/--message argument."""
    with tempfile.TemporaryDirectory() as tmpdir:
        stub_dir = Path(tmpdir) / "bin"
        stub_dir.mkdir()
        stub_git = stub_dir / "git"
        stub_git.write_text(_STUB_GIT_SCRIPT)
        stub_git.chmod(
            stub_git.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH
        )

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
            "gh pr create --body \"$(cat <<'EOF'\n"
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
        self.assertEqual(
            cleaned, "git commit -m 'docs: mention Claude Code in the readme'"
        )

    def test_still_strips_cursor_attribution(self) -> None:
        command = (
            "gh pr create --body \"$(cat <<'EOF'\n"
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
        self.assertIn("feat(tmux.statusbar): slim down the narrow tier", delivered)

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

    def test_repeated_m_args_join_into_one_wrapped_message(self) -> None:
        """The multiple-`-m` path: formatting only the first -m left every
        later paragraph as one 400-char line. That is a valid commit body, but
        an unreadable one -- and it is what made `rtk git log` (which
        truncates output lines at 120 chars and appends `...`) look like the
        stored message had been mangled.
        """
        paragraphs = (
            "fix(nvim.shell): stop leaking libuv check handles",
            "Shell.async_cmd used plenary.job, which allocates a uv_check_t per Job "
            "to poll for pipe drain, allocates a SECOND one when Job:start() "
            "re-enters _reset(), and on completion only stops the handle before "
            "dropping the reference.",
            "Migrate to native vim.system(), which closes its own check handle on "
            "exit. The public Async.wrap signature is unchanged, so no caller is "
            "affected.",
        )
        command = "git commit" + "".join(f' -m "{p}"' for p in paragraphs)

        cleaned = self.module._sanitize_command(command)
        delivered = _deliver_via_stub_git(cleaned)

        # The collapsed args must leave exactly one message argument, or the
        # stub (which records the last -m it sees) would prove nothing.
        self.assertEqual(_count_message_options(cleaned), 1)
        for paragraph in paragraphs:
            self.assertIn(paragraph, " ".join(delivered.split()))
        self.assertNotIn("...", delivered)
        self.assertLessEqual(max(len(line) for line in delivered.splitlines()), 120)

    def test_two_commits_on_one_line_keep_their_own_messages(self) -> None:
        """Joining -m args must stay inside one `git commit`. Scanning the whole
        line merged both commits' messages into the first one, which left the
        second commit with no -m at all.
        """
        command = (
            'git commit --amend -q -m "chore: first" ; '
            'git commit -m "feat: second" -m "Second body."'
        )
        cleaned = self.module._sanitize_command(command)

        first, second = cleaned.split(";")
        self.assertEqual(_count_message_options(first), 1)
        self.assertEqual(_count_message_options(second), 1)
        self.assertIn("chore: first", first)
        self.assertNotIn("chore: first", second)
        self.assertIn("feat: second", second)
        self.assertIn("Second body.", second)
        self.assertNotIn("feat: second", first)

    def test_semicolon_inside_a_message_is_not_a_command_boundary(self) -> None:
        command = 'git commit -m "fix: guard a; b in the parser" -m "Body text."'
        cleaned = self.module._sanitize_command(command)
        delivered = _deliver_via_stub_git(cleaned)

        self.assertEqual(_count_message_options(cleaned), 1)
        self.assertIn("guard a; b in the parser", delivered)
        self.assertIn("Body text.", delivered)

    def test_unparseable_message_arg_leaves_command_untouched(self) -> None:
        # An unquoted -m body means the parser cannot tell where the message
        # ends, so joining would drop or reorder paragraphs. Bail instead.
        command = 'git commit -m wip -m "second paragraph here"'
        self.assertEqual(self.module._sanitize_command(command), command)

    def test_dash_m_inside_a_message_body_is_not_read_as_an_option(self) -> None:
        command = 'git commit -m "docs: explain when to pass -m twice"'
        cleaned = self.module._sanitize_command(command)
        delivered = _deliver_via_stub_git(cleaned)
        # Counted after bash-style tokenizing: the body's own " -m " text is
        # not an option, and a substring count would say otherwise.
        self.assertEqual(_count_message_options(cleaned), 1)
        self.assertIn("pass -m twice", delivered)

    def test_single_quoted_body_joins_literally(self) -> None:
        # Mixed quoting: the double-quoted body gets bash's double-quote
        # decoding, the single-quoted one must stay byte-literal (its `\n` is
        # two characters, not a newline).
        command = "git commit -m \"feat: add thing\" -m 'prints a \\n between rows'"

        cleaned = self.module._sanitize_command(command)
        delivered = _deliver_via_stub_git(cleaned)

        self.assertIn("feat: add thing", delivered)
        self.assertIn("\\n between rows", delivered)

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


class HookResponseContractTest(unittest.TestCase):
    """The response shape the harness actually honors.

    A rewrite is only applied when permissionDecision comes with a
    permissionDecisionReason. Without the reason the harness still surfaces
    additionalContext, so the hook reports success while the original command
    runs -- the failure that made every rewrite here a silent no-op.
    """

    def test_rewrite_response_carries_a_permission_decision_reason(self) -> None:
        response = _run_hook(
            'git commit -m "feat: x\\n\\n'
            '🤖 Generated with [Claude Code](https://claude.com/claude-code)"'
        )
        output = response["hookSpecificOutput"]

        self.assertIn("updatedInput", output)
        self.assertEqual(output["permissionDecision"], "allow")
        self.assertTrue(output["permissionDecisionReason"])
        self.assertEqual(output["hookEventName"], "PreToolUse")
        self.assertNotIn("Claude Code", output["updatedInput"]["command"])
        # Unrelated tool_input keys must survive the swap.
        self.assertEqual(output["updatedInput"]["description"], "test")

    def test_untouched_command_gets_an_empty_response(self) -> None:
        self.assertEqual(_run_hook("git status"), {})


if __name__ == "__main__":
    unittest.main()
