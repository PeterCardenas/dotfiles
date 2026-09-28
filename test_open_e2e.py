import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parent
NVIM_ROOT = ROOT / "dot_config/nvim_conf/kickstart.nvim"
SCRIPT = NVIM_ROOT / "tests/open_e2e.lua"


class NvimOpenE2ETest(unittest.TestCase):
    def test_configured_gx_reaches_real_xdg_open_and_gio(self):
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            bin_dir = temp / "bin"
            bin_dir.mkdir()
            output = temp / "gio-output"
            (bin_dir / "systemctl").write_text(
                "#!/bin/sh\n"
                "test \"$1 $2\" = \"--user show-environment\" || exit 1\n"
                "printf 'DISPLAY=:1\\nWAYLAND_DISPLAY=wayland-0\\n'\n"
            )
            (bin_dir / "gio").write_text(
                "#!/bin/sh\n"
                "printf 'display=%s wayland=%s arg=%s\\n' \"$DISPLAY\" \"$WAYLAND_DISPLAY\" \"$2\" > \"$GX_E2E_OUTPUT\"\n"
            )
            for executable in bin_dir.iterdir():
                executable.chmod(0o755)
            environment = {
                **os.environ,
                "PATH": f"{bin_dir}:{os.environ['PATH']}",
                "DISPLAY": "",
                "WAYLAND_DISPLAY": "",
                "SSH_CONNECTION": "",
                "GX_E2E_OUTPUT": str(output),
            }
            result = subprocess.run(
                ["nvim", "--headless", "-u", str(NVIM_ROOT / "init.lua"), "-i", "NONE", "-S", str(SCRIPT)],
                cwd=NVIM_ROOT,
                env=environment,
                capture_output=True,
                text=True,
                check=False,
                timeout=30,
            )

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn("open e2e: ok", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
