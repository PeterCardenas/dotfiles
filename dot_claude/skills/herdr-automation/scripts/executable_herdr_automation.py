#!/usr/bin/env python3
"""Own a disposable Herdr session; use private tmux only for Herdr UI tests."""

import argparse
import fcntl
import json
import math
import os
import pwd
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path

NAME_RE = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.-]{0,15}$")
ROOT_MARKER = ".herdr-automation-root"
ROOT_MARKER_TOKEN = "herdr-automation-root-v1\n"
AMBIENT_MULTIPLEXER_VARIABLES = (
    "HERDR_ENV",
    "HERDR_WORKSPACE_ID",
    "HERDR_TAB_ID",
    "HERDR_PANE_ID",
    "HERDR_TERMINAL_ID",
    "HERDR_BIN_PATH",
    "HERDR_SOCKET_PATH",
    "HERDR_CLIENT_SOCKET_PATH",
    "HERDR_CONFIG_PATH",
    "TMUX",
    "TMUX_PANE",
)


class AutomationError(ValueError):
    pass


def default_runtime_root():
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    return Path(runtime) / "herdr-automation" if runtime else Path(f"/tmp/herdr-automation-{os.getuid()}")


def validate_name(name):
    if not isinstance(name, str) or not NAME_RE.fullmatch(name):
        raise AutomationError("invalid automation name")
    return name


def write_json_atomic(path, value):
    fd, temporary = tempfile.mkstemp(dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        data = (json.dumps(value, sort_keys=True) + "\n").encode()
        while data:
            written = os.write(fd, data)
            if not written:
                raise OSError("zero-byte write")
            data = data[written:]
        os.fsync(fd)
        os.replace(temporary, path)
    finally:
        os.close(fd)
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


class Wrapper:
    def __init__(self, runtime_root, name, timeout=10, config=None, visual=False):
        self.root = Path(runtime_root).expanduser()
        self.name = validate_name(name)
        self.timeout = timeout
        self.source_config = Path(config).expanduser() if config else None
        self.visual = visual
        self.state_dir = self.root / name
        self.home = self.state_dir / "h"
        account = pwd.getpwuid(os.getuid())
        self.pane_home = Path(account.pw_dir)
        self.pane_shell = account.pw_shell or "/bin/sh"
        self.pane_shell_path = self.state_dir / "pane-shell"
        self.config_home = self.state_dir / "c"
        self.data_home = self.state_dir / "d"
        self.cache_home = self.state_dir / "k"
        self.config_path = self.config_home / "herdr" / "config.toml"
        self.metadata_path = self.state_dir / "metadata.json"
        self.lock_path = self.root / ".locks" / f"{name}.lock"
        self.cleanup_path = self.root / ".locks" / f"{name}.cleanup.json"
        self.tmux_runtime = self.state_dir / "tmux-runtime"
        self.transport_name = f"herdr-{name}"
        self.session_name = f"ha-{name}"

    @property
    def transport_script(self):
        installed = Path(__file__).resolve().parents[2] / "tmux-automation" / "scripts" / "tmux_automation.py"
        source = Path(__file__).resolve().parents[2] / "tmux-automation" / "scripts" / "executable_tmux_automation.py"
        if installed.is_file():
            return installed
        if source.is_file():
            return source
        raise AutomationError("tmux automation transport is not installed")

    def ensure_root(self, create=False):
        if not self.root.exists():
            if not create:
                return False
            self.root.mkdir(mode=0o700, parents=True)
            marker = self.root / ROOT_MARKER
            marker.write_text(ROOT_MARKER_TOKEN)
            marker.chmod(0o600)
        info = self.root.lstat()
        marker = self.root / ROOT_MARKER
        if (
            not stat.S_ISDIR(info.st_mode)
            or info.st_uid != os.getuid()
            or stat.S_IMODE(info.st_mode) != 0o700
            or not marker.is_file()
            or marker.is_symlink()
            or marker.read_text() != ROOT_MARKER_TOKEN
            or stat.S_IMODE(marker.stat().st_mode) != 0o600
        ):
            raise AutomationError("unsafe Herdr automation root")
        return True

    def lock(self, create=False):
        if not self.ensure_root(create):
            raise AutomationError("automation not found")
        locks = self.root / ".locks"
        locks.mkdir(mode=0o700, exist_ok=True)
        fd = os.open(self.lock_path, os.O_RDWR | os.O_CREAT | os.O_CLOEXEC | os.O_NOFOLLOW, 0o600)
        file = os.fdopen(fd, "r+")
        deadline = time.monotonic() + self.timeout
        while True:
            try:
                fcntl.flock(file, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return file
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    file.close()
                    raise AutomationError(f"lock timeout for {self.name}")
                time.sleep(0.01)

    def validate_socket_capacity(self):
        longest_socket = self.config_home / "herdr" / "sessions" / self.session_name / "herdr-client.sock"
        if len(os.fsencode(longest_socket)) > 107:
            raise AutomationError(f"Herdr socket path is too long: {longest_socket}")

    def isolated_env(self):
        environment = os.environ.copy()
        for variable in AMBIENT_MULTIPLEXER_VARIABLES:
            environment.pop(variable, None)
        environment.update(
            HOME=str(self.home),
            SHELL=str(self.pane_shell_path),
            XDG_CONFIG_HOME=str(self.config_home),
            XDG_DATA_HOME=str(self.data_home),
            XDG_CACHE_HOME=str(self.cache_home),
            HERDR_CONFIG_PATH=str(self.config_path),
        )
        return environment

    def run(self, argv, *, env=None, timeout=None):
        return subprocess.run(
            argv,
            env=env,
            text=True,
            capture_output=True,
            timeout=self.timeout if timeout is None else timeout,
        )

    def transport_argv(self, action, *arguments):
        return [
            sys.executable,
            str(self.transport_script),
            "--runtime-root",
            str(self.tmux_runtime),
            "--timeout",
            str(self.timeout),
            action,
            *arguments,
            self.transport_name,
        ]

    def run_transport(self, action, arguments=(), timeout=None):
        argv = self.transport_argv(action)
        if arguments:
            argv.extend(["--", *arguments])
        return self.run(argv, timeout=timeout)

    def wait_transport_argv(self, regex, duration, wait_timeout):
        return [
            sys.executable,
            str(self.transport_script),
            "--runtime-root",
            str(self.tmux_runtime),
            "--timeout",
            str(self.timeout),
            "wait",
            "--regex",
            regex,
            "--duration",
            str(duration),
            "--wait-timeout",
            str(wait_timeout),
            self.transport_name,
            "--",
            "capture-pane",
            "-p",
        ]

    def run_herdr(self, arguments, timeout=None):
        return self.run(
            ["herdr", "--session", self.session_name, *arguments],
            env=self.isolated_env(),
            timeout=timeout,
        )

    def initialize_state(self):
        self.validate_socket_capacity()
        self.ensure_root(True)
        if self.state_dir.exists() or self.state_dir.is_symlink() or self.cleanup_path.exists() or self.cleanup_path.is_symlink():
            raise AutomationError("state or pending cleanup already exists; close it before creating")
        self.home.mkdir(mode=0o700, parents=True)
        self.home.chmod(0o700)
        self.config_path.parent.mkdir(mode=0o700, parents=True)
        (self.home / ".config").symlink_to(self.config_home)
        # Herdr stays private; only interactive pane shells regain the user's
        # normal HOME/XDG paths (and therefore normal app config and auth).
        self.pane_shell_path.write_text(
            "#!/bin/sh\n"
            + "\n".join(f"export {name}={shlex.quote(value)}" for name, value in {
                "HOME": str(self.pane_home),
                "XDG_CONFIG_HOME": str(self.pane_home / ".config"),
                "XDG_DATA_HOME": str(self.pane_home / ".local/share"),
                "XDG_CACHE_HOME": str(self.pane_home / ".cache"),
                "SHELL": self.pane_shell,
            }.items())
            + f"\nexec {shlex.quote(self.pane_shell)} \"$@\"\n"
        )
        self.pane_shell_path.chmod(0o700)
        self.data_home.mkdir(mode=0o700, parents=True)
        self.cache_home.mkdir(mode=0o700, parents=True)
        self.state_dir.chmod(0o700)
        source = self.source_config
        if source is None:
            configured = os.environ.get("HERDR_CONFIG_PATH")
            source = Path(configured).expanduser() if configured else Path.home() / ".config" / "herdr" / "config.toml"
        if source.is_file():
            shutil.copyfile(source, self.config_path)
        else:
            self.config_path.write_text("")
        self.config_path.chmod(0o600)
        self.write_metadata({**self.active_metadata(None), "status": "starting"})

    def active_metadata(self, pane_id):
        return {
            "kind": "herdr-automation",
            "status": "active",
            "session_name": self.session_name,
            "mode": "visual" if self.visual else "app",
            "transport_name": self.transport_name if self.visual else None,
            "pane_id": pane_id,
            "home": str(self.home),
            "pane_home": str(self.pane_home),
            "tmux_runtime": str(self.tmux_runtime) if self.visual else None,
        }

    def write_metadata(self, value):
        write_json_atomic(self.metadata_path, value)

    def read_metadata(self):
        if not self.metadata_path.is_file() or self.metadata_path.is_symlink():
            raise AutomationError("invalid Herdr automation metadata")
        value = json.loads(self.metadata_path.read_text())
        # Older controllers always created a visual transport; preserve cleanup.
        mode = value.get("mode", "visual")
        expected_transport = self.transport_name if mode == "visual" else None
        if mode not in ("app", "visual") or value.get("kind") != "herdr-automation" or value.get("session_name") != self.session_name or value.get("transport_name") != expected_transport:
            raise AutomationError("invalid Herdr automation metadata")
        return value

    def create(self):
        self.initialize_state()
        environment = self.isolated_env()
        pane_id = None
        server = None
        if self.visual:
            launch = self.transport_argv("create")
            # The transport is not under test; ignore user tmux configuration.
            launch.extend(["--", "-f", "/dev/null", "herdr", "--session", self.session_name])
            result = self.run(launch, env=environment)
            if result.returncode:
                raise AutomationError(result.stderr.strip() or "unable to start Herdr transport")
            try:
                pane_id = json.loads(result.stdout)["pane_id"]
            except (json.JSONDecodeError, KeyError) as error:
                raise AutomationError("invalid tmux transport response") from error
        else:
            with (self.state_dir / "server.log").open("w") as log:
                server = subprocess.Popen(
                    ["herdr", "--session", self.session_name, "server"],
                    env=environment,
                    stdin=subprocess.DEVNULL,
                    stdout=log,
                    stderr=log,
                    start_new_session=True,
                )
        deadline = time.monotonic() + self.timeout
        health = None
        while time.monotonic() < deadline:
            if server is not None and server.poll() is not None:
                raise AutomationError(f"Herdr server exited; inspect {self.state_dir / 'server.log'}")
            health = self.run_herdr(["workspace", "list"], timeout=min(1, max(0.05, deadline - time.monotonic())))
            if health.returncode == 0:
                break
            time.sleep(0.05)
        if health is None or health.returncode:
            raise AutomationError((health.stderr if health else "").strip() or f"Herdr session {self.session_name} did not become ready")
        metadata = self.active_metadata(pane_id)
        self.write_metadata(metadata)
        return metadata

    def load_active(self):
        metadata = self.read_metadata()
        if metadata.get("status") != "active":
            raise AutomationError("Herdr automation is still starting")
        health = self.run_herdr(["workspace", "list"])
        if health.returncode:
            raise AutomationError("Herdr automation is stale")
        return metadata

    def read_cleanup(self):
        if self.cleanup_path.is_symlink() or not self.cleanup_path.is_file():
            raise AutomationError("invalid Herdr cleanup marker")
        info = self.cleanup_path.stat()
        value = json.loads(self.cleanup_path.read_text())
        if not isinstance(value, dict):
            raise AutomationError("invalid Herdr cleanup marker")
        if (
            info.st_uid != os.getuid()
            or stat.S_IMODE(info.st_mode) != 0o600
            or value.get("kind") != "herdr-automation-cleanup"
            or value.get("session_name") != self.session_name
            or value.get("state_dir") != str(self.state_dir)
            or type(value.get("fallback")) is not bool
        ):
            raise AutomationError("invalid Herdr cleanup marker")
        return value

    def remove_private_state(self):
        if self.state_dir.is_symlink() or not self.state_dir.is_dir():
            raise AutomationError("invalid Herdr state directory")
        info = self.state_dir.stat()
        if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
            raise AutomationError("unsafe Herdr state directory")

        def reject_walk_error(error):
            raise error

        # Go modules and similar caches can contain read-only directories. Only
        # restore write access on owned directories inside the private tree.
        for directory, _, _ in os.walk(self.state_dir, followlinks=False, onerror=reject_walk_error):
            info = os.lstat(directory)
            if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
                raise AutomationError("unsafe directory in Herdr state")
            if not info.st_mode & stat.S_IWUSR:
                os.chmod(directory, stat.S_IMODE(info.st_mode) | stat.S_IWUSR | stat.S_IXUSR)
        shutil.rmtree(self.state_dir)

    def close(self):
        if not self.ensure_root(False):
            return {"deleted": False, "fallback": False}
        if self.cleanup_path.exists() or self.cleanup_path.is_symlink():
            fallback = self.read_cleanup()["fallback"]
            if self.state_dir.exists() or self.state_dir.is_symlink():
                self.remove_private_state()
            self.cleanup_path.unlink()
            return {"deleted": True, "fallback": fallback}
        if not self.state_dir.exists() and not self.state_dir.is_symlink():
            return {"deleted": False, "fallback": False}
        metadata = self.read_metadata()
        if metadata.get("status") not in ("starting", "active"):
            raise AutomationError("invalid Herdr automation state")
        environment = self.isolated_env()
        stopped = self.run(["herdr", "session", "stop", self.session_name, "--json"], env=environment)
        if stopped.returncode and "not found" not in stopped.stderr.lower() and "not running" not in stopped.stderr.lower():
            raise AutomationError(stopped.stderr.strip() or "unable to stop Herdr session")
        deleted = self.run(["herdr", "session", "delete", self.session_name, "--json"], env=environment)
        if deleted.returncode and "not found" not in deleted.stderr.lower():
            raise AutomationError(deleted.stderr.strip() or "unable to delete Herdr session")
        fallback = False
        if metadata.get("mode", "visual") == "visual":
            # The transport waits for natural exit before verified private-server cleanup.
            transport = self.run(self.transport_argv("close"), timeout=self.timeout * 2 + 1)
            if transport.returncode:
                raise AutomationError(transport.stderr.strip() or "unable to close tmux transport")
            try:
                fallback = bool(json.loads(transport.stdout).get("fallback"))
            except json.JSONDecodeError as error:
                raise AutomationError("invalid tmux transport close response") from error
        self.cleanup_path.parent.mkdir(mode=0o700, exist_ok=True)
        write_json_atomic(self.cleanup_path, {
            "kind": "herdr-automation-cleanup",
            "session_name": self.session_name,
            "state_dir": str(self.state_dir),
            "fallback": fallback,
        })
        self.remove_private_state()
        self.cleanup_path.unlink()
        return {"deleted": True, "fallback": fallback}


def build_parser():
    parser = argparse.ArgumentParser(description="Manage isolated disposable Herdr sessions")
    parser.add_argument("--runtime-root", default=default_runtime_root())
    parser.add_argument("--timeout", type=float, default=10)
    actions = parser.add_subparsers(dest="action", required=True)
    create = actions.add_parser("create")
    create.add_argument("name")
    create.add_argument("--config")
    create.add_argument("--visual", action="store_true", help="Use private tmux to test Herdr's rendered UI")
    for action in ("info", "close"):
        command = actions.add_parser(action)
        command.add_argument("name")
    capture = actions.add_parser("capture", help="Read agent-consumable text from an app pane")
    capture.add_argument("name")
    capture.add_argument("pane")
    capture.add_argument("--source", choices=("visible", "recent", "recent-unwrapped", "detection"), default="recent-unwrapped")
    capture.add_argument("--lines", type=int, default=200)
    capture.add_argument("--format", choices=("text", "ansi"), default="text")
    for action in ("herdr", "terminal"):
        command = actions.add_parser(action)
        command.add_argument("name")
        command.add_argument("command", nargs=argparse.REMAINDER)
    wait = actions.add_parser("wait-screen")
    wait.add_argument("--regex", required=True)
    wait.add_argument("--duration", type=float, default=0.2)
    wait.add_argument("--wait-timeout", type=float, default=10)
    wait.add_argument("name")
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    for key in ("timeout", "duration", "wait_timeout"):
        value = getattr(args, key, None)
        if value is not None and (not math.isfinite(value) or value < 0):
            raise AutomationError(f"{key.replace('_', '-')} must be finite and >= 0")
    if args.action == "capture" and args.lines <= 0:
        raise AutomationError("lines must be > 0")
    wrapper = Wrapper(args.runtime_root, args.name, args.timeout, getattr(args, "config", None), getattr(args, "visual", False))
    if args.action == "close":
        if not wrapper.ensure_root(False):
            print(json.dumps({"deleted": False, "fallback": False}))
            return 0
        with wrapper.lock():
            print(json.dumps(wrapper.close()))
        return 0
    with wrapper.lock(args.action == "create"):
        if args.action == "create":
            print(json.dumps(wrapper.create()))
            return 0
        if args.action == "info":
            print(json.dumps(wrapper.load_active()))
            return 0
        metadata = wrapper.load_active()
        if args.action == "capture":
            result = wrapper.run_herdr([
                "pane", "read", args.pane, "--source", args.source,
                "--lines", str(args.lines), "--format", args.format,
            ])
        elif args.action in ("terminal", "wait-screen") and metadata.get("mode", "visual") != "visual":
            raise AutomationError("Herdr UI commands require create --visual; use native pane APIs for app tests")
        elif args.action == "herdr":
            command = args.command[1:] if args.command[:1] == ["--"] else args.command
            if not command:
                raise AutomationError("herdr requires a command")
            result = wrapper.run_herdr(command)
        elif args.action == "terminal":
            command = args.command[1:] if args.command[:1] == ["--"] else args.command
            if not command:
                raise AutomationError("terminal requires a tmux command")
            result = wrapper.run_transport("exec", command)
        else:
            result = wrapper.run(
                wrapper.wait_transport_argv(args.regex, args.duration, args.wait_timeout),
                timeout=args.wait_timeout + args.timeout,
            )
        sys.stdout.write(result.stdout)
        sys.stderr.write(result.stderr)
        return result.returncode


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AutomationError, OSError, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(2)
