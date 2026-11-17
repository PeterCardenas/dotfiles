"""wait_for_pr_checks.py maps PR check states to deterministic exit codes, using a fake gh."""
import json
import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parent / "dot_claude/skills/github-ci-wait/scripts/executable_wait_for_pr_checks.py"
SHA = "a" * 40

FAKE_GH = textwrap.dedent(
    """\
    #!/usr/bin/env python3
    import json, os, sys
    args = " ".join(sys.argv[1:])
    fixture = json.loads(os.environ["FAKE_GH_FIXTURE"])
    if args.startswith("pr view"):
        print(json.dumps({"number": 7, "url": "https://github.com/o/r/pull/7", "headRefOid": fixture["sha"]}))
    elif "/pulls/7" in args:
        print(fixture.get("current_sha", fixture["sha"]))
    elif "/check-runs" in args:
        for run in fixture["runs"]:
            print(json.dumps(run))
    elif "/status" in args:
        print(json.dumps(fixture.get("statuses", [])))
    elif args.startswith("api graphql"):
        print(json.dumps(fixture.get("threads", [])))
    else:
        sys.exit(f"unexpected gh call: {args}")
    """
)


def run(id_, name, status="completed", conclusion="success"):
    return {"id": id_, "name": name, "status": status, "conclusion": conclusion, "html_url": f"u/{id_}"}


class WaitForPrChecksTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        bin_dir = Path(temp.name)
        fake = bin_dir / "gh"
        fake.write_text(FAKE_GH)
        fake.chmod(0o755)
        self.path = f"{bin_dir}:{os.environ['PATH']}"

    def wait(self, fixture, *flags):
        env = {**os.environ, "PATH": self.path, "FAKE_GH_FIXTURE": json.dumps({"sha": SHA, **fixture})}
        args = ["python3", str(SCRIPT), "7", "--interval", "0", "--settle", "0", "--budget", "0", *flags]
        return subprocess.run(args, capture_output=True, text=True, env=env)

    def test_all_passing_reports_unresolved_threads(self):
        thread = {"isResolved": False, "isOutdated": False,
                  "comments": {"nodes": [{"author": {"login": "cursor"}, "url": "t/1", "body": "Bug: x\\nmore"}]}}
        result = self.wait({"runs": [run(1, "test")], "statuses": [{"context": "buildkite", "state": "success"}],
                            "threads": [thread]})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("RESULT: PASS 2 checks", result.stdout)
        self.assertIn("UNRESOLVED_THREADS: 1", result.stdout)

    def test_failure_exits_before_pending_checks_finish(self):
        result = self.wait({"runs": [run(1, "lint", conclusion="failure"), run(2, "e2e", status="in_progress")]})
        self.assertEqual(result.returncode, 1)
        self.assertIn("FAIL     lint (failure) u/1", result.stdout)

    def test_rerun_supersedes_older_failure(self):
        result = self.wait({"runs": [run(1, "lint", conclusion="failure"), run(2, "lint")]})
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_pending_buildkite_status_exits_8_at_budget(self):
        result = self.wait({"runs": [run(1, "test")], "statuses": [{"context": "buildkite", "state": "pending"}]})
        self.assertEqual(result.returncode, 8)
        self.assertIn("PENDING  buildkite", result.stdout)

    def test_head_moved_exits_3(self):
        result = self.wait({"runs": [run(1, "test")], "current_sha": "b" * 40})
        self.assertEqual(result.returncode, 3)

    def test_no_checks_after_settle_exits_4(self):
        result = self.wait({"runs": []})
        self.assertEqual(result.returncode, 4)


if __name__ == "__main__":
    unittest.main()
