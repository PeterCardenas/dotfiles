import json, os, shutil, subprocess, tempfile, time, unittest, sys
from pathlib import Path

SCRIPT = Path(__file__).with_name("executable_tmux_automation.py")


def cli(root, *args, timeout=8):
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--runtime-root", root, *args],
        text=True,
        capture_output=True,
        timeout=timeout,
    )


@unittest.skipUnless(shutil.which("tmux"), "tmux unavailable")
class WrapperIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.parent = tempfile.mkdtemp()
        self.root = str(Path(self.parent) / "runtime")
        self.created = []

    def tearDown(self):
        failures = []
        for name in reversed(self.created):
            result = cli(self.root, "close", name, timeout=15)
            try:
                json.loads(result.stdout)
            except json.JSONDecodeError:
                failures.append(f"{name}: malformed stdout={result.stdout!r} stderr={result.stderr!r}")
                continue
            if result.returncode != 0 or Path(self.root, name).exists():
                failures.append(f"{name}: stdout={result.stdout!r} stderr={result.stderr!r}")
        result = self._outcome.result
        body_failed = any(test is self for test, _ in result.failures + result.errors)
        if failures:
            message = "close teardown failed (runtime evidence preserved at %s): %s" % (self.root, "\n".join(failures)[:2000])
            if body_failed:
                print(message, file=sys.stderr)
            else:
                self.fail(message)
        if not body_failed:
            shutil.rmtree(self.parent)

    def create(self, name="demo", *args):
        r = cli(self.root, "create", name, *args)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.created.append(name)
        return json.loads(r.stdout)

    def test_create_info_exec_private_socket_and_stable_ids(self):
        data = self.create("one", "-f", "/dev/null")
        info = cli(self.root, "info", "one")
        self.assertEqual(json.loads(info.stdout), data)
        self.assertTrue(data["socket"].startswith(self.root))
        self.assertEqual(
            cli(
                self.root, "exec", "one", "--", "display-message", "-p", "#{session_id}"
            ).stdout.strip(),
            data["session_id"],
        )

    def test_multiple_panes_and_literal_payload_and_selector_rejection(self):
        self.create(
            "odd_name", "-f", "/dev/null", "sh", "-c", 'printf -- "-f payload"; sleep 2'
        )
        self.assertIn(
            "-f payload",
            cli(self.root, "exec", "odd_name", "--", "capture-pane", "-p").stdout,
        )
        for selector in (["-S", "/x"], ["-S/x"], ["-L", "x"], ["-Lx"]):
            self.assertEqual(
                cli(
                    self.root, "exec", "odd_name", *selector, "list-sessions"
                ).returncode,
                2,
            )

    def test_missing_f_and_wait_diagnostics(self):
        self.assertEqual(cli(self.root, "create", "bad", "-f").returncode, 2)
        self.create("waiter", "-f", "/dev/null", "sh", "-c", "printf ready; sleep 2")
        result = cli(
            self.root,
            "wait",
            "--regex",
            "ready",
            "--duration",
            "0.1",
            "--wait-timeout",
            "2",
            "waiter",
            "--",
            "capture-pane",
            "-p",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        timeout = cli(
            self.root,
            "wait",
            "--regex",
            "never",
            "--duration",
            "0.1",
            "--wait-timeout",
            "0.1",
            "waiter",
            "--",
            "capture-pane",
            "-p",
        )
        self.assertEqual(timeout.returncode, 2)
        self.assertIn("wait timed out", timeout.stderr)
        self.assertIn("last observation", timeout.stderr)
        self.assertIn("returncode", timeout.stderr)

    def test_unknown_tmux_command_has_no_direct_executable_fallback(self):
        self.create("unknown", "-f", "/dev/null")
        result = cli(self.root, "exec", "unknown", "--", "definitely-not-a-command")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotEqual(result.stderr, "")

    def test_absent_operations_do_not_create_state(self):
        for action in ("info", "exec", "wait"):
            result = cli(self.root, action, "none", "--", "list-sessions")
            self.assertEqual(result.returncode, 2)
        self.assertFalse(Path(self.root, "none").exists())

    def test_absent_close_does_not_create_state_and_is_idempotent(self):
        self.assertEqual(
            json.loads(cli(self.root, "close", "none").stdout), {"fallback": False}
        )
        self.assertFalse(Path(self.root, "none").exists())
        self.create()
        self.assertEqual(cli(self.root, "close", "demo", timeout=15).returncode, 0)
        self.assertEqual(cli(self.root, "close", "demo", timeout=15).returncode, 0)
        self.assertFalse(Path(self.root, "demo").exists())

    def test_concurrent_first_use_creates_distinct_names(self):
        processes = [
            subprocess.Popen([sys.executable, str(SCRIPT), "--runtime-root", self.root, "create", name, "-f", "/dev/null"], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            for name in ("first", "second")
        ]
        results = [process.communicate(timeout=20) for process in processes]
        self.assertEqual([process.returncode for process in processes], [0, 0])
        for name, (stdout, stderr) in zip(("first", "second"), results):
            self.assertEqual(stderr, "")
            self.assertEqual(json.loads(stdout)["status"], "active")
            self.created.append(name)
        self.assertTrue(Path(self.root, ".tmux-automation-root").is_file())

    def test_duplicate_create_one_winner_and_independent_names(self):
        ps = [
            subprocess.Popen(
                [
                    "python3",
                    str(SCRIPT),
                    "--runtime-root",
                    self.root,
                    "create",
                    "same",
                    "-f",
                    "/dev/null",
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            for _ in range(2)
        ]
        results = []
        for p in ps:
            p.communicate()
            results.append(p.returncode)
            if p.returncode == 0:
                self.created.append("same")
        self.assertEqual(sorted(results), [0, 2])
        self.create("other", "-f", "/dev/null")
        self.assertNotEqual(
            json.loads(cli(self.root, "info", "same").stdout)["socket"],
            json.loads(cli(self.root, "info", "other").stdout)["socket"],
        )


if __name__ == "__main__":
    unittest.main()
