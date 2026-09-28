#!/usr/bin/env python3
"""Own a disposable Herdr session and its private tmux transport."""

import argparse
import fcntl
import json
import math
import os
import re
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
    def __init__(self, runtime_root, name, timeout=10, config=None):
        self.root = Path(runtime_root).expanduser()
        self.name = validate_name(name)
        self.timeout = timeout
        self.source_config = Path(config).expanduser() if config else None
        self.state_dir = self.root / name
        self.home = self.state_dir / "h"
        self.config_home = self.state_dir / "c"
        self.data_home = self.state_dir / "d"
        self.cache_home = self.state_dir / "k"
        self.config_path = self.config_home / "herdr" / "config.toml"
        self.metadata_path = self.state_dir / "metadata.json"
        self.lock_path = self.root / ".locks" / f"{name}.lock"
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
        if self.state_dir.exists() or self.state_dir.is_symlink():
            raise AutomationError("state directory already exists; refusing adoption")
        self.config_path.parent.mkdir(mode=0o700, parents=True)
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
        self.write_metadata({"kind": "herdr-automation", "status": "starting", "session_name": self.session_name, "transport_name": self.transport_name})

    def active_metadata(self, pane_id):
        return {
            "kind": "herdr-automation",
            "status": "active",
            "session_name": self.session_name,
            "transport_name": self.transport_name,
            "pane_id": pane_id,
            "home": str(self.home),
            "tmux_runtime": str(self.tmux_runtime),
        }

    def write_metadata(self, value):
        write_json_atomic(self.metadata_path, value)

    def read_metadata(self):
        if not self.metadata_path.is_file() or self.metadata_path.is_symlink():
            raise AutomationError("invalid Herdr automation metadata")
        value = json.loads(self.metadata_path.read_text())
        if value.get("kind") != "herdr-automation" or value.get("session_name") != self.session_name or value.get("transport_name") != self.transport_name:
            raise AutomationError("invalid Herdr automation metadata")
        return value

    def create(self):
        self.initialize_state()
        environment = self.isolated_env()
        launch = self.transport_argv("create")
        launch.extend(
            [
                "--",
                "env",
                *[f"{key}={value}" for key, value in environment.items() if key in {"HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME", "HERDR_CONFIG_PATH"}],
                "herdr",
                "--session",
                self.session_name,
            ]
        )
        result = self.run(launch, env=environment)
        if result.returncode:
            raise AutomationError(result.stderr.strip() or "unable to start Herdr transport")
        try:
            transport = json.loads(result.stdout)
        except json.JSONDecodeError as error:
            raise AutomationError("invalid tmux transport response") from error
        deadline = time.monotonic() + self.timeout
        health = None
        while time.monotonic() < deadline:
            health = self.run_herdr(["workspace", "list"], timeout=min(1, max(0.05, deadline - time.monotonic())))
            if health.returncode == 0:
                break
            time.sleep(0.05)
        if health is None or health.returncode:
            raise AutomationError((health.stderr if health else "").strip() or f"Herdr session {self.session_name} did not become ready")
        metadata = self.active_metadata(transport.get("pane_id"))
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

    def close(self):
        if not self.ensure_root(False) or not self.state_dir.exists():
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
        transport = self.run(self.transport_argv("close"))
        if transport.returncode:
            raise AutomationError(transport.stderr.strip() or "unable to close tmux transport")
        try:
            fallback = bool(json.loads(transport.stdout).get("fallback"))
        except json.JSONDecodeError as error:
            raise AutomationError("invalid tmux transport close response") from error
        shutil.rmtree(self.state_dir)
        return {"deleted": True, "fallback": fallback}


def build_parser():
    parser = argparse.ArgumentParser(description="Manage isolated disposable Herdr sessions")
    parser.add_argument("--runtime-root", default=default_runtime_root())
    parser.add_argument("--timeout", type=float, default=10)
    actions = parser.add_subparsers(dest="action", required=True)
    create = actions.add_parser("create")
    create.add_argument("name")
    create.add_argument("--config")
    for action in ("info", "close"):
        command = actions.add_parser(action)
        command.add_argument("name")
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
    wrapper = Wrapper(args.runtime_root, args.name, args.timeout, getattr(args, "config", None))
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
        wrapper.load_active()
        if args.action == "herdr":
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
