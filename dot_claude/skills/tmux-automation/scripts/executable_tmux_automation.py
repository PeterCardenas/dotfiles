#!/usr/bin/env python3
"""Bounded disposable tmux wrapper; same-UID TOCTOU replacement is out of scope."""

import argparse, errno, fcntl, json, math, os, re, secrets, stat, subprocess, sys, tempfile, time
from pathlib import Path

NAME_RE = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}$")
RUNTIME_ROOT_MARKER = ".tmux-automation-root"
RUNTIME_ROOT_MARKER_TOKEN = "tmux-automation-root-v1\n"


class WaitTimeout(TimeoutError):
    pass


class WrapperError(ValueError):
    pass


def default_runtime_root():
    return (
        Path(os.environ.get("XDG_RUNTIME_DIR", f"/tmp/tmux-automation-{os.getuid()}"))
        / "tmux-automation"
        if os.environ.get("XDG_RUNTIME_DIR")
        else Path(f"/tmp/tmux-automation-{os.getuid()}")
    )


def lexists(path):
    try:
        os.lstat(path)
        return True
    except FileNotFoundError:
        return False


def validate_name(name):
    if not isinstance(name, str) or not NAME_RE.fullmatch(name):
        raise ValueError("invalid automation name")
    return name


def _write_all(fd, data):
    remaining = memoryview(data)
    while remaining:
        written = os.write(fd, remaining)
        if written == 0:
            raise OSError("zero-byte write")
        remaining = remaining[written:]


def wait_until(observe, predicate, timeout=10, interval=0.1):
    end = time.monotonic() + timeout
    last = None
    while True:
        try:
            last = observe()
        except subprocess.TimeoutExpired as error:
            last = {
                "timeout": str(error),
                "returncode": getattr(error, "returncode", None),
                "stdout": getattr(error, "stdout", None),
                "stderr": getattr(error, "stderr", None),
            }
        if predicate(last):
            return last
        if time.monotonic() >= end:
            raise WaitTimeout(f"condition timed out; last observation: {last!r}")
        delay = min(interval, end - time.monotonic())
        if delay > 0:
            time.sleep(delay)


class Wrapper:
    def __init__(self, runtime_root, name, timeout=10):
        validate_name(name)
        self.timeout = timeout
        self.root = Path(runtime_root).expanduser()
        self.name = name
        self.state_dir = self.root / name
        self.socket = self.state_dir / "tmux.sock"
        self.metadata_path = self.state_dir / "metadata.json"
        self.lock_path = self.root / ".locks" / f"{name}.lock"
        if lexists(self.root):
            self.ensure_owned_root(False)

    def validate_state(self):
        if (
            not self.state_dir.exists()
            or self.state_dir.is_symlink()
            or not self.state_dir.is_dir()
            or self.state_dir.stat().st_uid != os.getuid()
            or self.state_dir.stat().st_mode & 0o077
        ):
            raise ValueError("unsafe state directory")
        if self.socket.exists() or self.socket.is_symlink():
            if (
                self.socket.is_symlink()
                or not stat.S_ISSOCK(self.socket.stat().st_mode)
                or self.socket.stat().st_uid != os.getuid()
            ):
                raise ValueError("invalid tmux socket")
        return self.state_dir

    def load_active_state(self):
        self.validate_state()
        if not self.socket.exists():
            raise ValueError("stale automation: tmux socket is missing")
        metadata = self.read_metadata()
        if metadata.get("status") != "active":
            raise ValueError("automation is still starting")
        return metadata

    def create(self, rest, config=None):
        if lexists(self.state_dir):
            raise WrapperError("state directory already exists; refusing adoption")
        try:
            self.state_dir.mkdir(mode=0o700)
        except FileExistsError as error:
            raise WrapperError(
                "state directory already exists; refusing adoption"
            ) from error
        self.write_metadata(
            {
                "status": "starting",
                "session_id": None,
                "window_id": None,
                "pane_id": None,
            }
        )
        try:
            result = self.run(
                ["new-session", "-d", "-x", "200", "-y", "50", "-s", self.name, *rest],
                False,
                config,
            )
            if result.returncode:
                raise ValueError(result.stderr.strip() or "create failed")
            values = self.run(
                [
                    "display-message",
                    "-t",
                    self.name,
                    "-p",
                    "#{session_id} #{window_id} #{pane_id}",
                ]
            ).stdout.split()
            if len(values) != 3:
                raise ValueError("unable to discover tmux identifiers")
            self.write_metadata(
                {
                    "status": "active",
                    "session_id": values[0],
                    "window_id": values[1],
                    "pane_id": values[2],
                }
            )
            return self.read_metadata()
        except Exception as error:
            import shutil

            observed = self.socket.exists()
            if isinstance(error, subprocess.TimeoutExpired) and not observed:
                raise ValueError(
                    f"startup indeterminate; run close {self.name} to recover"
                ) from error
            if not observed:
                # Without published metadata, the directory is unrecognized evidence; safety beats cleanup.
                raise error
            try:
                self.run(["kill-server"], False, timeout=self.timeout)
                verification = self.run(["list-sessions"], False, timeout=0.2)
                if verification.returncode == 0:
                    raise ValueError("tmux server still running")
                shutil.rmtree(self.state_dir)
                raise ValueError(f"create failed; rollback complete: {error}")
            except (
                subprocess.CalledProcessError,
                subprocess.TimeoutExpired,
                FileNotFoundError,
            ) as rollback_error:
                raise ValueError(
                    f"create failed; rollback unverifiable; state preserved: {rollback_error}"
                ) from error

    def ensure_owned_root(self, create=False):
        if not lexists(self.root):
            if not create:
                return False
            try:
                self.root.mkdir(mode=0o700, parents=True)
                marker = self.root / RUNTIME_ROOT_MARKER
                temporary_marker = self.root / (
                    f"{RUNTIME_ROOT_MARKER}.tmp-{os.getpid()}-{secrets.token_hex(8)}"
                )
                fd = None
                try:
                    fd = os.open(
                        temporary_marker,
                        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                        0o600,
                    )
                    _write_all(fd, RUNTIME_ROOT_MARKER_TOKEN.encode())
                    os.fsync(fd)
                finally:
                    if fd is not None:
                        os.close(fd)
                os.replace(temporary_marker, marker)
                directory_fd = os.open(self.root, os.O_RDONLY | os.O_DIRECTORY)
                try:
                    os.fsync(directory_fd)
                finally:
                    os.close(directory_fd)
                return True
            except FileExistsError:
                pass
            except OSError as error:
                try:
                    temporary_marker.unlink()
                except (UnboundLocalError, FileNotFoundError, OSError):
                    pass
                raise WrapperError(f"unable to initialize runtime root: {error}") from error
        try:
            root_info = os.lstat(self.root)
            if (
                not stat.S_ISDIR(root_info.st_mode)
                or root_info.st_uid != os.getuid()
                or stat.S_IMODE(root_info.st_mode) != 0o700
            ):
                raise WrapperError("unsafe runtime root")
            deadline = time.monotonic() + max(0, self.timeout)
            while True:
                try:
                    marker_info = os.lstat(self.root / RUNTIME_ROOT_MARKER)
                    break
                except FileNotFoundError:
                    if time.monotonic() >= deadline:
                        raise WrapperError("unsafe runtime root")
                    delay = min(0.01, deadline - time.monotonic())
                    if delay > 0:
                        time.sleep(delay)
                    else:
                        continue
            if (
                not stat.S_ISDIR(root_info.st_mode)
                or root_info.st_uid != os.getuid()
                or stat.S_IMODE(root_info.st_mode) != 0o700
                or not stat.S_ISREG(marker_info.st_mode)
                or marker_info.st_uid != os.getuid()
                or stat.S_IMODE(marker_info.st_mode) != 0o600
                or marker_info.st_nlink != 1
                or (self.root / RUNTIME_ROOT_MARKER).read_bytes() != RUNTIME_ROOT_MARKER_TOKEN.encode()
            ):
                raise WrapperError("unsafe runtime root")
        except (FileNotFoundError, OSError) as error:
            if isinstance(error, WrapperError):
                raise
            raise WrapperError("unsafe runtime root") from error
        return True

    def lock(self, create=False):
        if not self.ensure_owned_root(create):
            raise WrapperError("automation not found")
        locks = self.root / ".locks"
        try:
            locks.mkdir(mode=0o700, exist_ok=True)
        except OSError as error:
            raise WrapperError(f"unsafe locks directory: {error}") from error
        locks_info = os.lstat(locks)
        if (
            not stat.S_ISDIR(locks_info.st_mode)
            or stat.S_ISLNK(locks_info.st_mode)
            or locks_info.st_uid != os.getuid()
            or stat.S_IMODE(locks_info.st_mode) != 0o700
        ):
            raise WrapperError("unsafe locks directory")
        flags = os.O_RDWR | os.O_CREAT
        for flag in ("O_CLOEXEC", "O_NOFOLLOW"):
            value = getattr(os, flag, None)
            if value is None:
                raise WrapperError(f"{flag} is unavailable; refusing insecure lock")
            flags |= value
        try:
            fd = os.open(self.lock_path, flags, 0o600)
        except OSError as error:
            raise WrapperError(f"unsafe lock file: {error}") from error
        try:
            info = os.fstat(fd)
            if (
                not stat.S_ISREG(info.st_mode)
                or info.st_uid != os.getuid()
                or stat.S_IMODE(info.st_mode) != 0o600
                or info.st_nlink != 1
            ):
                raise WrapperError("unsafe lock file")
            f = os.fdopen(fd, "r+")
            deadline = time.monotonic() + max(0, self.timeout)
            while True:
                try:
                    fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    return f
                except OSError as error:
                    if error.errno not in (errno.EACCES, errno.EAGAIN):
                        f.close()
                        raise WrapperError(
                            f"lock failed for {self.name}: {error}"
                        ) from error
                    if time.monotonic() >= deadline:
                        f.close()
                        raise WrapperError(f"lock timeout for {self.name}") from error
                    time.sleep(min(0.01, max(0, deadline - time.monotonic())))
        except BaseException:
            try:
                os.close(fd)
            except OSError:
                pass
            raise

    def client_argv(self, args, config=None):
        args = list(args)
        i = 0
        while i < len(args) and args[i].startswith("-"):
            x = args[i]
            if x == "--":
                break
            if x in ("-S", "-L") or x.startswith("-S") or x.startswith("-L"):
                raise ValueError("socket selectors are owned by the wrapper")
            i += 2 if x in ("-f", "-c", "-T") and i + 1 < len(args) else 1
        return ["tmux"] + ([] if config is None else ["-f", config]) + [
            "-S",
            str(self.socket),
        ] + args, self.clean_env()

    @staticmethod
    def clean_env():
        e = os.environ.copy()
        e.pop("TMUX", None)
        e.pop("TMUX_PANE", None)
        return e

    def run(self, args, check=True, config=None, timeout=None):
        a, e = self.client_argv(args, config)
        return subprocess.run(
            a,
            env=e,
            text=True,
            capture_output=True,
            check=check,
            timeout=self.timeout if timeout is None else timeout,
        )

    def write_metadata(self, data):
        self.state_dir.mkdir(mode=0o700, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=self.state_dir)
        try:
            os.fchmod(fd, 0o600)
            _write_all(
                fd, (json.dumps({"socket": str(self.socket), **data}) + "\n").encode()
            )
            os.fsync(fd)
            os.replace(tmp, self.metadata_path)
            directory_fd = os.open(self.state_dir, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
        finally:
            os.close(fd)
            try:
                os.unlink(tmp)
            except FileNotFoundError:
                pass

    def read_metadata(self):
        if (
            not self.metadata_path.is_file()
            or self.metadata_path.is_symlink()
            or self.metadata_path.stat().st_uid != os.getuid()
            or self.metadata_path.stat().st_mode & 0o077
        ):
            raise ValueError("invalid metadata")
        try:
            d = json.loads(self.metadata_path.read_text())
        except (OSError, json.JSONDecodeError):
            raise ValueError("invalid metadata")
        if d.get("socket") != str(self.socket) or d.get("status") not in (
            "starting",
            "active",
        ):
            raise ValueError("invalid metadata")
        if d["status"] == "active" and not all(
            isinstance(d.get(k), str) for k in ("session_id", "window_id", "pane_id")
        ):
            raise ValueError("invalid metadata")
        if d["status"] == "starting" and any(
            d.get(k) is not None for k in ("session_id", "window_id", "pane_id")
        ):
            raise ValueError("invalid metadata")
        self.validate_state()
        return d

    def close(self):
        if not self.ensure_owned_root(False):
            return {"fallback": False}
        with self.lock():
            if not lexists(self.state_dir):
                return {"fallback": False}
            if self.state_dir.is_symlink():
                raise WrapperError("unsafe state directory")
            self.validate_state()
            if not lexists(self.metadata_path):
                raise ValueError("metadata missing; preserving state")
            if self.metadata_path.is_symlink():
                raise WrapperError("invalid metadata; preserving state")
            metadata = self.read_metadata()
            deadline = time.monotonic() + self.timeout
            fallback = False
            socket_exists = self.socket.exists()
            if not socket_exists:
                import shutil

                shutil.rmtree(self.state_dir)
                return {"fallback": False}
            if metadata["status"] == "starting":
                try:
                    self.run(["kill-server"], False, timeout=self.timeout)
                except (subprocess.TimeoutExpired, FileNotFoundError):
                    raise ValueError("unable to verify tmux shutdown")
                try:
                    self.run(["list-sessions"], timeout=0.2)
                    raise ValueError("tmux server still running")
                except subprocess.CalledProcessError:
                    pass
                import shutil

                shutil.rmtree(self.state_dir)
                return {"fallback": True}
            while time.monotonic() < deadline:
                try:
                    self.run(["list-sessions"], timeout=0.2)
                    time.sleep(0.05)
                except (
                    subprocess.CalledProcessError,
                    subprocess.TimeoutExpired,
                    FileNotFoundError,
                ):
                    break
            else:
                fallback = True
            if fallback:
                try:
                    self.run(["kill-server"], False, timeout=self.timeout)
                except (subprocess.TimeoutExpired, FileNotFoundError):
                    raise ValueError("unable to verify tmux shutdown")
            try:
                self.run(["list-sessions"], timeout=0.2)
                raise ValueError("tmux server still running")
            except subprocess.CalledProcessError:
                pass
            except (subprocess.TimeoutExpired, FileNotFoundError):
                raise ValueError("unable to verify tmux shutdown")
            import shutil

            shutil.rmtree(self.state_dir)
            return {"fallback": fallback}


def build_parser():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-root", default=default_runtime_root())
    parser.add_argument("--timeout", type=float, default=10)
    actions = parser.add_subparsers(dest="action", required=True)
    for action in ("create", "info", "close"):
        command = actions.add_parser(action)
        command.add_argument("name")
        command.add_argument("rest", nargs=argparse.REMAINDER)
    command = actions.add_parser("exec")
    command.add_argument("name")
    command.add_argument("command", nargs=argparse.REMAINDER)
    command = actions.add_parser("wait")
    command.add_argument("--regex")
    command.add_argument("--returncode", type=int, default=0)
    command.add_argument("--duration", type=float, default=0)
    command.add_argument("--wait-timeout", type=float, default=10)
    command.add_argument("name")
    command.add_argument("command", nargs=argparse.REMAINDER)
    return parser


def parse_cli(argv=None):
    args = build_parser().parse_args(argv)
    for name in ("timeout", "duration", "wait_timeout"):
        value = getattr(args, name, None)
        if value is not None and (not math.isfinite(value) or value < 0):
            raise WrapperError(f"{name.replace('_', '-')} must be finite and >= 0")
    if args.action == "wait" and args.regex is not None:
        try:
            args.compiled_regex = re.compile(args.regex)
        except re.error as error:
            raise WrapperError(f"invalid regex: {error}") from error
    return args


def main(argv=None):
    a = parse_cli(argv)
    w = Wrapper(a.runtime_root, a.name, a.timeout)
    if a.action in ("exec", "wait") and not a.command:
        raise WrapperError(f"{a.action} requires a tmux command")
    if a.action == "close":
        print(json.dumps(w.close()))
        return 0
    with w.lock(a.action == "create"):
        if a.action == "info":
            if not w.state_dir.exists():
                raise ValueError("automation not found")
            w.load_active_state()
            print(json.dumps(w.read_metadata()))
            return 0
        if a.action == "create":
            rest = a.rest[1:] if a.rest[:1] == ["--"] else a.rest
            config = None
            if rest[:1] == ["-f"] or (
                rest and rest[0].startswith("-f") and rest[0] != "-f"
            ):
                if rest[0] == "-f" and len(rest) < 2:
                    raise ValueError("missing -f value")
                config = rest[1] if rest[0] == "-f" else rest[0][2:]
                rest = rest[2:] if rest[0] == "-f" else rest[1:]
            if not rest:
                rest = ["sh"]
            if w.metadata_path.exists():
                raise ValueError("automation already exists")
            print(json.dumps(w.create(rest, config)))
            return 0
        w.load_active_state()
        cmd = a.command[1:] if a.command[:1] == ["--"] else a.command
        if a.action == "exec":
            r = w.run(cmd, False)
            sys.stdout.write(r.stdout)
            sys.stderr.write(r.stderr)
            return r.returncode
        stable = None
        wait_deadline = time.monotonic() + a.wait_timeout

        def observe():
            remaining = max(wait_deadline - time.monotonic(), 0)
            r = w.run(cmd, False, timeout=min(w.timeout, remaining))
            return {
                "returncode": r.returncode,
                "stdout": r.stdout,
                "stderr": r.stderr,
            }

        def ready(r):
            nonlocal stable
            matches = r["returncode"] == a.returncode and (
                not a.regex or a.compiled_regex.search(r.get("stdout") or "")
            )
            if matches:
                stable = stable or time.monotonic()
                return time.monotonic() - stable >= a.duration
            stable = None
            return False

        try:
            wait_until(observe, ready, timeout=a.wait_timeout, interval=0.05)
        except WaitTimeout as error:
            raise WaitTimeout(f"wait timed out; {error}") from error
        return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError, WaitTimeout, subprocess.TimeoutExpired) as e:
        print(str(e), file=sys.stderr)
        raise SystemExit(2)
