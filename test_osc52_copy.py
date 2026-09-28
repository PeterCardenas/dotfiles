import base64
import errno
import os
import pty
import socket
import subprocess
import tempfile
import termios
import unittest
from pathlib import Path


ROOT = Path(__file__).parent
OSC52_COPY = ROOT / "dot_local/bin/executable_osc52_copy"


class Osc52CopyTest(unittest.TestCase):
    def test_herdr_uses_bare_osc52_when_tmux_is_inherited(self):
        master, slave = pty.openpty()
        tty_path = os.ttyname(slave)
        attributes = termios.tcgetattr(slave)
        attributes[1] &= ~termios.OPOST
        termios.tcsetattr(slave, termios.TCSANOW, attributes)

        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            tmux_socket = socket.socket(socket.AF_UNIX)
            tmux_socket.bind(str(temp_path / "tmux.sock"))
            env = os.environ | {
                "HERDR_ENV": "1",
                "TMUX": f"{temp_path / 'tmux.sock'},1,0",
                "OSC52_TEST_TTY": tty_path,
            }
            fake_tmux = temp_path / "tmux"
            fake_tmux.write_text("#!/bin/sh\nprintf '%s\\n' \"$OSC52_TEST_TTY\"\n")
            fake_tmux.chmod(0o755)
            env["PATH"] = f"{temp_path}:{env['PATH']}"

            try:
                process = subprocess.Popen(
                    ["fish", "--no-config", str(OSC52_COPY), "copied from lazygit"],
                    stdin=slave,
                    stdout=slave,
                    stderr=slave,
                    env=env,
                )
                os.close(slave)
                output = bytearray()
                while True:
                    try:
                        chunk = os.read(master, 4096)
                    except OSError as error:
                        if error.errno == errno.EIO:
                            break
                        raise
                    if not chunk:
                        break
                    output.extend(chunk)
                self.assertEqual(process.wait(), 0, bytes(output))
            finally:
                os.close(master)
                tmux_socket.close()

        encoded = base64.b64encode(b"copied from lazygit")
        self.assertEqual(bytes(output), b"\x1b]52;c;" + encoded + b"\x1b\\")


if __name__ == "__main__":
    unittest.main()
