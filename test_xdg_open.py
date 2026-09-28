import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parent
WRAPPER = ROOT / "dot_local/bin/executable_xdg-open"


class XdgOpenTest(unittest.TestCase):
    def test_preserves_explicit_graphical_environment(self):
        with tempfile.TemporaryDirectory() as directory:
            bin_dir = Path(directory)
            (bin_dir / "systemctl").write_text("#!/bin/sh\nexit 1\n")
            (bin_dir / "gio").write_text(
                "#!/bin/sh\n"
                "printf 'display=%s wayland=%s arg=%s\\n' \"$DISPLAY\" \"$WAYLAND_DISPLAY\" \"$2\"\n"
            )
            for executable in bin_dir.iterdir():
                executable.chmod(0o755)
            result = subprocess.run(
                ["bash", str(WRAPPER), "http://localhost:9/gx-diagnostic"],
                env={**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}", "DISPLAY": ":9", "WAYLAND_DISPLAY": "wayland-9", "SSH_CONNECTION": ""},
                capture_output=True,
                text=True,
                check=False,
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "display=:9 wayland=wayland-9 arg=http://localhost:9/gx-diagnostic\n")

    def test_systemctl_failure_does_not_hide_gio_error(self):
        with tempfile.TemporaryDirectory() as directory:
            bin_dir = Path(directory)
            (bin_dir / "systemctl").write_text("#!/bin/sh\nprintf 'systemctl failed\\n' >&2\nexit 1\n")
            (bin_dir / "gio").write_text("#!/bin/sh\nprintf 'gio failed\\n' >&2\nexit 7\n")
            for executable in bin_dir.iterdir():
                executable.chmod(0o755)
            result = subprocess.run(
                ["bash", str(WRAPPER), "http://localhost:9/gx-diagnostic"],
                env={**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}", "DISPLAY": "", "WAYLAND_DISPLAY": "", "SSH_CONNECTION": ""},
                capture_output=True,
                text=True,
                check=False,
            )

        self.assertEqual(result.returncode, 7)
        self.assertIn("gio failed", result.stderr)
        self.assertNotIn("systemctl failed", result.stderr)

    def test_ssh_branch_passes_arguments_to_ssh(self):
        with tempfile.TemporaryDirectory() as directory:
            bin_dir = Path(directory)
            (bin_dir / "ssh").write_text(
                "#!/bin/sh\nprintf '%s\\n' \"$@\"\n"
            )
            (bin_dir / "gio").write_text("#!/bin/sh\nexit 99\n")
            for executable in bin_dir.iterdir():
                executable.chmod(0o755)
            result = subprocess.run(
                ["bash", str(WRAPPER), "https://example.test/a b", "$(touch SHOULD_NOT_EXIST)"],
                env={**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}", "SSH_CONNECTION": "host"},
                capture_output=True,
                text=True,
                check=False,
            )

        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "macbook\nopen\nhttps://example.test/a b\n$(touch SHOULD_NOT_EXIST)\n")

    def test_recovers_graphical_environment_from_user_manager(self):
        with tempfile.TemporaryDirectory() as directory:
            bin_dir = Path(directory)
            (bin_dir / "systemctl").write_text(
                "#!/bin/sh\n"
                "test \"$1 $2\" = \"--user show-environment\" || exit 1\n"
                "printf 'DISPLAY=:1\\nWAYLAND_DISPLAY=wayland-0\\n'\n"
            )
            (bin_dir / "gio").write_text(
                "#!/bin/sh\n"
                "printf 'display=%s wayland=%s arg=%s\\n' \"$DISPLAY\" \"$WAYLAND_DISPLAY\" \"$2\"\n"
            )
            for executable in bin_dir.iterdir():
                executable.chmod(0o755)
            environment = {
                **os.environ,
                "PATH": f"{bin_dir}:{os.environ['PATH']}",
                "DISPLAY": "",
                "WAYLAND_DISPLAY": "",
                "SSH_CONNECTION": "",
            }
            result = subprocess.run(
                ["bash", str(WRAPPER), "http://localhost:9/gx-diagnostic"],
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "display=:1 wayland=wayland-0 arg=http://localhost:9/gx-diagnostic\n",
        )


if __name__ == "__main__":
    unittest.main()
