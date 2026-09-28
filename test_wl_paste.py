import base64
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parent
WL_PASTE = ROOT / "dot_local/bin/executable_wl-paste"

PNG_BYTES = b"\x89PNG\r\n\x1a\nfake-image"


class WlPasteTest(unittest.TestCase):
    def run_wl_paste(
        self, args: list[str], fake_ssh: str
    ) -> subprocess.CompletedProcess[bytes]:
        with tempfile.TemporaryDirectory() as temp_dir:
            bin_dir = Path(temp_dir)
            ssh = bin_dir / "ssh"
            ssh.write_text(fake_ssh)
            ssh.chmod(0o755)
            env = {
                **os.environ,
                "PATH": f"{bin_dir}:{os.environ['PATH']}",
                "SSH_CONNECTION": "::1 53778 ::1 22",
            }
            return subprocess.run(
                ["python3", str(WL_PASTE), *args],
                env=env,
                capture_output=True,
                timeout=30,
                check=False,
            )

    def test_image_paste_reads_png_from_mac_clipboard(self):
        encoded = base64.b64encode(PNG_BYTES).decode("ascii")
        result = self.run_wl_paste(
            ["--type", "image/png"],
            f"#!/bin/sh\ncat > /dev/null\nprintf '%s\\n' '{encoded}'\n",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, PNG_BYTES)

    def test_unreachable_mac_fails_fast_instead_of_emitting_empty_image(self):
        result = self.run_wl_paste(
            ["--type", "image/png"],
            "#!/bin/sh\ncat > /dev/null\n"
            "echo 'ssh: connect to host macbook port 22: Connection timed out' >&2\n"
            "exit 255\n",
        )

        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, b"")
        self.assertIn(b"Cannot read the macOS clipboard", result.stderr)

    def test_unreachable_mac_fails_list_types(self):
        result = self.run_wl_paste(
            ["--list-types"],
            "#!/bin/sh\ncat > /dev/null\nexit 255\n",
        )

        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, b"")

    def test_ssh_is_invoked_with_a_connect_timeout(self):
        result = self.run_wl_paste(
            ["--list-types"],
            "#!/bin/sh\ncat > /dev/null\nprintf '%s\\n' \"$@\"\n",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(b"ConnectTimeout=", result.stdout)
        self.assertIn(b"BatchMode=yes", result.stdout)

    def test_text_paste_appends_newline(self):
        result = self.run_wl_paste(
            [],
            "#!/bin/sh\ncat > /dev/null\n"
            'for arg in "$@"; do\n'
            '  if [ "$arg" = pbpaste ]; then printf hello; fi\n'
            "done\n",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, b"hello\n")


if __name__ == "__main__":
    unittest.main()
