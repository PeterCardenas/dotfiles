"""Regression checks for LazyGit opening files in its parent Neovim."""

import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest


class LazygitNvimTest(unittest.TestCase):
    def test_remote_edit_opens_literal_filename_and_line(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            filename = "hash#name.txt"
            client_dir = root / "client"
            client_dir.mkdir()
            (client_dir / filename).write_text("first line\nsecond line\n")
            (client_dir / "quote'#%.txt").write_text("special name\n")
            socket = root / "nvim.sock"
            server = subprocess.Popen(
                [
                    "nvim",
                    "--headless",
                    "-u",
                    "NONE",
                    "-i",
                    "NONE",
                    "--listen",
                    str(socket),
                ],
                cwd=root,
                stdin=subprocess.PIPE,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
            )
            try:
                for _ in range(100):
                    if socket.exists():
                        break
                    time.sleep(0.05)
                self.assertTrue(socket.exists(), "Neovim server failed to start")

                def open_file(*arguments):
                    result = subprocess.run(
                        [
                            "fish",
                            "-c",
                            'source "$argv[1]"; lazygit_nvim $argv[2..]',
                            str(
                                Path(__file__).resolve().parent
                                / "dot_config/fish/functions/lazygit_nvim.fish"
                            ),
                            *arguments,
                        ],
                        cwd=client_dir,
                        env={**os.environ, "NVIM": str(socket)},
                        capture_output=True,
                        text=True,
                        timeout=10,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)

                def query(expression):
                    return subprocess.run(
                        ["nvim", "--server", str(socket), "--remote-expr", expression],
                        capture_output=True,
                        text=True,
                        check=True,
                        timeout=10,
                    ).stdout.strip()

                open_file(filename)
                self.assertEqual(query('expand("%:p")'), str(client_dir / filename))
                self.assertEqual(query("getline(1)"), "first line")
                open_file(filename, "2")
                self.assertEqual(query("line('.')"), "2")
                open_file("quote'#%.txt")
                self.assertEqual(
                    query('expand("%:p")'), str(client_dir / "quote'#%.txt")
                )
                self.assertEqual(query("getline(1)"), "special name")
                open_file(filename)
                bad_line = subprocess.run(
                    [
                        "fish",
                        "-c",
                        'source "$argv[1]"; lazygit_nvim $argv[2..]',
                        str(
                            Path(__file__).resolve().parent
                            / "dot_config/fish/functions/lazygit_nvim.fish"
                        ),
                        filename,
                        "2) | quit",
                    ],
                    cwd=client_dir,
                    env={**os.environ, "NVIM": str(socket)},
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
                self.assertNotEqual(bad_line.returncode, 0)
                self.assertEqual(query('expand("%:p")'), str(client_dir / filename))
            finally:
                server.terminate()
                server.wait(timeout=5)
                if server.stdin:
                    server.stdin.close()
                if server.stderr:
                    server.stderr.close()


if __name__ == "__main__":
    unittest.main()
