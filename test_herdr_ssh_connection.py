import os
import pty
import subprocess
import tempfile
import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path


ROOT = Path(__file__).parent
FUNCTION = ROOT / "dot_config/fish/functions/sync_herdr_ssh_connection.fish"
DETECTOR = SourceFileLoader(
    "herdr_client_connection",
    str(ROOT / "dot_local/bin/executable_herdr-client-connection"),
).load_module()

SSH_CLIENT_CONNECTION = "::1 53778 ::1 22"


class FakeProc:
    """A /proc tree holding synthetic Herdr processes."""

    def __init__(self, root: Path):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)

    def add(
        self,
        pid: int,
        args: list[str],
        environment: dict[str, str],
        tty: str,
    ) -> None:
        entry = self.root / str(pid)
        (entry / "fd").mkdir(parents=True)
        (entry / "cmdline").write_bytes(b"".join(f"{a}\0".encode() for a in args))
        (entry / "environ").write_bytes(
            b"".join(
                f"{name}={value}\0".encode() for name, value in environment.items()
            )
        )
        os.symlink(tty, entry / "fd" / "0")


class HerdrClientConnectionTest(unittest.TestCase):
    def setUp(self):
        self._temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp_dir.cleanup)
        self.proc = FakeProc(Path(self._temp_dir.name) / "proc")

    def make_tty(self, last_input: float) -> str:
        """Allocate a real pty whose atime stands in for its last keystroke."""
        master, slave = pty.openpty()
        self.addCleanup(os.close, master)
        self.addCleanup(os.close, slave)
        tty = os.ttyname(slave)
        os.utime(tty, (last_input, last_input))
        return tty

    def make_pipe(self, last_input: float) -> str:
        """Stand in for the stdin pipe of a remote-client-bridge."""
        reader, writer = os.pipe()
        self.addCleanup(os.close, reader)
        self.addCleanup(os.close, writer)
        pipe = f"/proc/self/fd/{reader}"
        os.utime(pipe, (last_input, last_input))
        return pipe

    def active_connection(self, session: str = "default") -> str | None:
        client = DETECTOR.active_client(
            DETECTOR.attached_clients(self.proc.root), session
        )
        return client.ssh_connection if client else None

    def add_local_client(self, pid: int, last_input: float) -> None:
        self.proc.add(
            pid,
            ["herdr"],
            {"WAYLAND_DISPLAY": "wayland-0"},
            self.make_tty(last_input),
        )

    def add_ssh_client(self, pid: int, last_input: float) -> None:
        self.proc.add(
            pid,
            ["herdr"],
            {"SSH_CONNECTION": SSH_CLIENT_CONNECTION},
            self.make_tty(last_input),
        )

    def test_local_client_in_use_wins_over_an_idle_ssh_client(self):
        self.add_ssh_client(101, last_input=1000.0)
        self.add_local_client(102, last_input=2000.0)

        self.assertIsNone(self.active_connection())

    def test_ssh_client_in_use_wins_over_an_idle_local_client(self):
        self.add_ssh_client(101, last_input=2000.0)
        self.add_local_client(102, last_input=1000.0)

        self.assertEqual(self.active_connection(), SSH_CLIENT_CONNECTION)

    def test_clients_of_other_sessions_are_ignored(self):
        self.proc.add(
            101,
            ["herdr", "--session", "herdr-persist-1"],
            {"SSH_CONNECTION": SSH_CLIENT_CONNECTION},
            self.make_tty(2000.0),
        )
        self.add_local_client(102, last_input=1000.0)

        self.assertIsNone(self.active_connection())
        self.assertEqual(
            self.active_connection("herdr-persist-1"), SSH_CLIENT_CONNECTION
        )

    def test_server_and_in_pane_cli_calls_are_not_clients(self):
        self.proc.add(
            101,
            ["herdr", "server"],
            {"SSH_CONNECTION": SSH_CLIENT_CONNECTION},
            self.make_tty(3000.0),
        )
        self.proc.add(
            102,
            ["herdr", "api", "snapshot"],
            {"SSH_CONNECTION": SSH_CLIENT_CONNECTION},
            self.make_tty(3000.0),
        )
        self.proc.add(
            103,
            ["herdr"],
            {"SSH_CONNECTION": SSH_CLIENT_CONNECTION, "HERDR_ENV": "1"},
            self.make_tty(3000.0),
        )
        self.add_local_client(104, last_input=1000.0)

        self.assertEqual(DETECTOR.attached_clients(self.proc.root)[0].pid, 104)
        self.assertIsNone(self.active_connection())

    def test_remote_bridge_in_use_wins_over_an_idle_local_client(self):
        self.add_local_client(101, last_input=1000.0)
        self.proc.add(
            102,
            ["herdr", "remote-client-bridge"],
            {"SSH_CONNECTION": SSH_CLIENT_CONNECTION},
            self.make_pipe(2000.0),
        )

        self.assertEqual(self.active_connection(), SSH_CLIENT_CONNECTION)

    def test_named_remote_bridge_is_only_a_client_of_its_session(self):
        self.proc.add(
            101,
            ["herdr", "--session", "work", "remote-client-bridge"],
            {"SSH_CONNECTION": SSH_CLIENT_CONNECTION},
            self.make_pipe(2000.0),
        )

        self.assertIsNone(self.active_connection())
        self.assertEqual(self.active_connection("work"), SSH_CLIENT_CONNECTION)

    def test_named_remote_bridge_with_idle_timeout_is_a_client(self):
        self.proc.add(
            101,
            ["herdr", "--session", "work", "remote-client-bridge", "--idle-timeout-v1"],
            {"SSH_CONNECTION": SSH_CLIENT_CONNECTION},
            self.make_pipe(2000.0),
        )

        self.assertEqual(self.active_connection("work"), SSH_CLIENT_CONNECTION)

    def test_local_client_in_use_wins_over_an_idle_remote_bridge(self):
        self.proc.add(
            101,
            ["herdr", "remote-client-bridge"],
            {"SSH_CONNECTION": SSH_CLIENT_CONNECTION},
            self.make_pipe(1000.0),
        )
        self.add_local_client(102, last_input=2000.0)

        self.assertIsNone(self.active_connection())

    def test_remote_attach_is_not_a_client_of_this_server(self):
        self.proc.add(
            101,
            ["herdr", "--remote", "otherhost"],
            {"SSH_CONNECTION": SSH_CLIENT_CONNECTION},
            self.make_tty(3000.0),
        )

        self.assertEqual(DETECTOR.attached_clients(self.proc.root), [])

    def test_explicit_attach_spelling_is_a_client(self):
        self.proc.add(
            101,
            ["herdr", "session", "attach", "work"],
            {"SSH_CONNECTION": SSH_CLIENT_CONNECTION},
            self.make_tty(2000.0),
        )

        self.assertIsNone(self.active_connection())
        self.assertEqual(self.active_connection("work"), SSH_CLIENT_CONNECTION)

    def test_session_is_derived_from_the_pane_socket_path(self):
        self.assertEqual(DETECTOR.current_session(None), "default")
        self.assertEqual(
            DETECTOR.current_session("/home/user/.config/herdr/herdr.sock"), "default"
        )
        # A named session is `<config>/sessions/<name>/herdr.sock`.
        self.assertEqual(
            DETECTOR.current_session(
                "/home/user/.config/herdr/sessions/work/herdr.sock"
            ),
            "work",
        )


class SyncHerdrSshConnectionTest(unittest.TestCase):
    def run_fish(self, script: str, detector_output: str) -> str:
        with tempfile.TemporaryDirectory() as temp_dir:
            bin_dir = Path(temp_dir)
            detector = bin_dir / "herdr-client-connection"
            detector.write_text(f"#!/bin/sh\nprintf '%s' '{detector_output}'\n")
            detector.chmod(0o755)
            env = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}"}
            result = subprocess.run(
                ["fish", "--no-config", "-c", f"source {FUNCTION}; {script}"],
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout

    def test_local_client_clears_an_inherited_connection(self):
        output = self.run_fish(
            "set -gx HERDR_ENV 1; "
            "set -gx SSH_CONNECTION stale; "
            "sync_herdr_ssh_connection; "
            'set -q SSH_CONNECTION; and echo "set:$SSH_CONNECTION"; or echo unset',
            detector_output="",
        )

        self.assertEqual(output.strip(), "unset")

    def test_ssh_client_replaces_an_inherited_connection(self):
        output = self.run_fish(
            "set -gx HERDR_ENV 1; "
            "set -gx SSH_CONNECTION stale; "
            "sync_herdr_ssh_connection; "
            "echo $SSH_CONNECTION",
            detector_output=SSH_CLIENT_CONNECTION,
        )

        self.assertEqual(output.strip(), SSH_CLIENT_CONNECTION)

    def test_outside_herdr_the_shell_keeps_its_own_connection(self):
        output = self.run_fish(
            "set -e HERDR_ENV; "
            "set -gx SSH_CONNECTION 'client 1 server 2'; "
            "sync_herdr_ssh_connection; "
            "echo $SSH_CONNECTION",
            detector_output="",
        )

        self.assertEqual(output.strip(), "client 1 server 2")


if __name__ == "__main__":
    unittest.main()
