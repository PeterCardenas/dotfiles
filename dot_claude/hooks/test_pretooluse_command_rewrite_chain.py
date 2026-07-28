#!/usr/bin/env python3
"""Tests for pretooluse_command_rewrite_chain.py.

The chain exists because Claude Code honors only one hook's `updatedInput`:
these tests pin that rewrites compose in order, that a block short-circuits the
rest, and that the response carries the fields the harness requires before it
will apply a rewrite at all.

Not given an `executable_` chezmoi prefix so it deploys as a plain,
non-executable file.
"""

from __future__ import annotations

import importlib.util
import io
import json
import stat
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path


SCRIPT_PATH = Path(__file__).with_name("executable_pretooluse_command_rewrite_chain.py")


def load_module():
    # hook_context is a sibling in the hooks directory, which is on sys.path
    # when Claude Code runs the deployed script but not when loading by path.
    if str(SCRIPT_PATH.parent) not in sys.path:
        sys.path.insert(0, str(SCRIPT_PATH.parent))
    spec = importlib.util.spec_from_file_location(
        "pretooluse_command_rewrite_chain", SCRIPT_PATH
    )
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _write_stub(directory: Path, name: str, body: str) -> tuple[None, list[str]]:
    """Write a stub hook that prints `body` (a Python expression) as its
    response, and return the unfiltered chain entry that runs it."""
    script = directory / name
    script.write_text(
        "#!/usr/bin/env python3\n"
        "import json, sys\n"
        "payload = json.load(sys.stdin)\n"
        "command = payload['tool_input']['command']\n"
        f"print(json.dumps({body}))\n"
    )
    script.chmod(script.stat().st_mode | stat.S_IEXEC)
    return (None, [sys.executable, str(script)])


def _allow(command_expr: str, context: str) -> str:
    return (
        "{'hookSpecificOutput': {'hookEventName': 'PreToolUse',"
        " 'permissionDecision': 'allow',"
        " 'permissionDecisionReason': %r,"
        " 'updatedInput': {**payload['tool_input'], 'command': %s},"
        " 'additionalContext': %r}}" % (context, command_expr, context)
    )


def _run(module, payload: dict) -> dict:
    buffer = io.StringIO()
    with redirect_stdout(buffer):
        module._main(payload)
    return json.loads(buffer.getvalue())


class CommandRewriteChainTest(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_module()
        self._tmpdir = tempfile.TemporaryDirectory()
        self.tmpdir = Path(self._tmpdir.name)
        self.addCleanup(self._tmpdir.cleanup)

    def _payload(self, command: str) -> dict:
        return {
            "hook_event_name": "PreToolUse",
            "tool_name": "Bash",
            "tool_input": {"command": command, "description": "test"},
        }

    def test_rewrites_compose_in_order(self) -> None:
        """The whole point: the second link must see the first link's command,
        and the response must carry both rewrites."""
        first = _write_stub(
            self.tmpdir, "first.py", _allow('"PREFIX " + command', "prefixed")
        )
        second = _write_stub(
            self.tmpdir, "second.py", _allow('command + " SUFFIX"', "suffixed")
        )
        self.module.CHAIN = (first, second)

        output = _run(self.module, self._payload("git commit"))["hookSpecificOutput"]

        self.assertEqual(output["updatedInput"]["command"], "PREFIX git commit SUFFIX")
        self.assertEqual(output["permissionDecision"], "allow")
        self.assertTrue(output["permissionDecisionReason"])
        self.assertIn("prefixed", output["additionalContext"])
        self.assertIn("suffixed", output["additionalContext"])
        self.assertEqual(output["updatedInput"]["description"], "test")

    def test_deny_short_circuits_the_rest_of_the_chain(self) -> None:
        denier = _write_stub(
            self.tmpdir,
            "deny.py",
            "{'hookSpecificOutput': {'hookEventName': 'PreToolUse',"
            " 'permissionDecision': 'deny',"
            " 'permissionDecisionReason': 'use git rebase'}}",
        )
        marker = self.tmpdir / "ran"
        later = self.tmpdir / "later.py"
        later.write_text(
            "#!/usr/bin/env python3\n"
            "import json, sys\n"
            "sys.stdin.read()\n"
            f"open({str(marker)!r}, 'w').write('ran')\n"
            "print('{}')\n"
        )
        self.module.CHAIN = (denier, (None, [sys.executable, str(later)]))

        output = _run(self.module, self._payload("git merge main"))[
            "hookSpecificOutput"
        ]

        self.assertEqual(output["permissionDecision"], "deny")
        self.assertNotIn("updatedInput", output)
        self.assertFalse(marker.exists(), "chain kept running after a deny")

    def test_context_without_a_rewrite_is_passed_through(self) -> None:
        hinter = _write_stub(
            self.tmpdir,
            "hint.py",
            "{'hookSpecificOutput': {'hookEventName': 'PreToolUse',"
            " 'additionalContext': 'heads up'}}",
        )
        self.module.CHAIN = (hinter,)

        output = _run(self.module, self._payload("gh pr view 1"))["hookSpecificOutput"]

        self.assertEqual(output["additionalContext"], "heads up")
        self.assertNotIn("updatedInput", output)
        self.assertNotIn("permissionDecision", output)

    def test_silent_chain_returns_empty_response(self) -> None:
        quiet = _write_stub(self.tmpdir, "quiet.py", "{}")
        self.module.CHAIN = (quiet,)
        self.assertEqual(_run(self.module, self._payload("ls")), {})

    def test_broken_link_is_skipped_rather_than_blocking(self) -> None:
        """A missing binary or garbage output must not wedge shell commands."""
        garbage = self.tmpdir / "garbage.py"
        garbage.write_text(
            "#!/usr/bin/env python3\nimport sys\nsys.stdin.read()\nprint('not json')\n"
        )
        rewriter = _write_stub(
            self.tmpdir, "rewriter.py", _allow('"rtk " + command', "rtk rewrite")
        )
        self.module.CHAIN = (
            (None, ["definitely-not-a-real-binary"]),
            (None, [sys.executable, str(garbage)]),
            rewriter,
        )

        output = _run(self.module, self._payload("git status"))["hookSpecificOutput"]

        self.assertEqual(output["updatedInput"]["command"], "rtk git status")

    def test_non_command_tool_input_is_ignored(self) -> None:
        self.module.CHAIN = ()
        payload = {"tool_name": "Read", "tool_input": {"file_path": "/tmp/x"}}
        self.assertEqual(_run(self.module, payload), {})


class RealChainTest(unittest.TestCase):
    """Sanity check on the chain as actually shipped."""

    def setUp(self) -> None:
        self.module = load_module()

    def test_ships_the_git_sanitizer_and_rtk_last(self) -> None:
        argvs = [" ".join(argv) for _prefilter, argv in self.module.CHAIN]
        self.assertTrue(any("pretooluse_git_sanitize.py" in a for a in argvs))
        self.assertTrue(any("pretooluse_gh_user.py" in a for a in argvs))
        self.assertEqual(argvs[-1], "rtk hook claude")

    def test_prefilters_admit_every_command_their_link_handles(self) -> None:
        """A prefilter narrower than its link's own matcher would silently
        disable that link -- the exact failure mode this hook exists to fix."""
        handled = (
            'git commit -m "x"',
            "git commit --amend",
            'gh pr create --body "x"',
            "gh pr view 1",
            "GH_TOKEN=x gh api /user",
            'cd /repo && git add -A; git commit -m "x"',
        )
        for prefilter, argv in self.module.CHAIN:
            if prefilter is None:
                continue
            for command in handled:
                with self.subTest(link=argv[-1], command=command):
                    self.assertIsNotNone(prefilter.search(command))

    def test_prefilter_skips_links_for_unrelated_commands(self) -> None:
        skipped = [
            argv
            for prefilter, argv in self.module.CHAIN
            if prefilter is not None and not prefilter.search("ls -la")
        ]
        self.assertEqual(len(skipped), 2)


if __name__ == "__main__":
    unittest.main()
