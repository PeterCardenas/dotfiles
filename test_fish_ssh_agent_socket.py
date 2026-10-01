"""Regression checks for the stable SSH agent socket in interactive fish."""

import os
import socket
import subprocess
import tempfile
import unittest
from pathlib import Path


CONFIG = Path(__file__).parent / "dot_config/fish/interactive_config.fish"


class FishSshAgentSocketTest(unittest.TestCase):
    def test_competing_shell_creating_stable_path_does_not_fail_or_lose_new_agent(self):
        config = CONFIG.read_text()
        socket_setup = config.split("set -l stable_ssh_auth_sock ", 1)[1]
        socket_setup = (
            "set -l stable_ssh_auth_sock "
            + socket_setup.split("set -gx SSH_AUTH_SOCK $stable_ssh_auth_sock", 1)[0]
            + "set -gx SSH_AUTH_SOCK $stable_ssh_auth_sock"
        )

        with tempfile.TemporaryDirectory() as home:
            ssh_dir = Path(home) / ".ssh"
            ssh_dir.mkdir()
            previous_socket = ssh_dir / "previous.sock"
            inherited_socket = ssh_dir / "inherited.sock"
            with socket.socket(socket.AF_UNIX) as previous_agent, socket.socket(
                socket.AF_UNIX
            ) as inherited_agent:
                previous_agent.bind(str(previous_socket))
                inherited_agent.bind(str(inherited_socket))
                env = {
                    **os.environ,
                    "HOME": home,
                    "SSH_AUTH_SOCK": str(inherited_socket),
                    "OLD_SOCKET": str(previous_socket),
                }
                env.pop("HERDR_ENV", None)
                # Create a competing link just as this shell tries to publish its own.
                script = (
                    """function ln
    set -l stable $HOME/.ssh/ssh-agent.$hostname.sock
    if not test -e $stable
        command ln -s "$OLD_SOCKET" "$stable"
    end
    command ln $argv
end
"""
                    + socket_setup
                )
                result = subprocess.run(
                    ["fish", "--no-config", "-c", script],
                    env=env,
                    text=True,
                    capture_output=True,
                )
                hostname = subprocess.check_output(["hostname"], text=True).strip()
                stable = ssh_dir / f"ssh-agent.{hostname}.sock"
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, "")
                self.assertEqual(stable.readlink(), inherited_socket)
                self.assertEqual(
                    set(ssh_dir.iterdir()), {previous_socket, inherited_socket, stable}
                )


if __name__ == "__main__":
    unittest.main()
