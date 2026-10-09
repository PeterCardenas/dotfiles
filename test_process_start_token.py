"""Cross-platform process identity used by Neovim and tmux status markers."""
import os
import shlex
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).parent
TOKEN = ROOT / "dot_local/bin/executable_process-start-token"
PENDING = ROOT / "dot_config/tmux/scripts/executable_agentic_pending.sh"


class ProcessStartTokenTest(unittest.TestCase):
    def test_live_process_has_stable_token(self):
        results = [
            subprocess.run(["sh", str(TOKEN), str(os.getpid())], capture_output=True, text=True)
            for _ in range(2)
        ]
        self.assertTrue(all(result.returncode == 0 for result in results))
        self.assertEqual(results[0].stdout, results[1].stdout)
        self.assertRegex(results[0].stdout.strip(), r"^[A-Za-z0-9]+$")

    @unittest.skipUnless(sys.platform.startswith('linux'), 'Linux /proc start ticks')
    def test_linux_token_preserves_existing_marker_format(self):
        stat = Path(f'/proc/{os.getpid()}/stat').read_text().split(') ', 1)[1].split()[19]
        token = subprocess.check_output(['sh', str(TOKEN), str(os.getpid())], text=True).strip()
        self.assertEqual(token, stat)

    def test_missing_process_is_rejected(self):
        result = subprocess.run(["sh", str(TOKEN), "99999999"], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_tmux_marker_from_live_process_is_accepted_and_stale_marker_rejected(self):
        token = subprocess.check_output(["sh", str(TOKEN), str(os.getpid())], text=True).strip()
        with tempfile.TemporaryDirectory() as directory:
            shim = Path(directory) / "tmux"
            shim.write_text(
                '#!/bin/sh\ncase "$*" in *list-panes*) echo %1 ;; *show-options*) echo "$TEST_MARKER" ;; esac\n'
            )
            shim.chmod(0o755)
            token_command = Path(directory) / "process-start-token"
            token_command.write_text(f'#!/bin/sh\nexec sh {shlex.quote(str(TOKEN))} "$@"\n')
            token_command.chmod(0o755)
            for marker, expected in ((f"v1:{os.getpid()}:{token}:1:0", "working"),
                                     (f"v1:{os.getpid()}:{token}wrong:1:0", "none")):
                result = subprocess.run(
                    ["sh", str(PENDING), "--state", "test-socket", "test-window"],
                    env={**os.environ, "PATH": f"{directory}:{os.environ['PATH']}", "TEST_MARKER": marker},
                    capture_output=True, text=True, check=True,
                )
                self.assertEqual(result.stdout.strip(), expected)

    def test_invalid_pid_is_rejected(self):
        result = subprocess.run(["sh", str(TOKEN), "1;echo bad"], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
