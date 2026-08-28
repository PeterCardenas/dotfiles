import importlib.util
import json
import os
import socket
import tempfile
import unittest
from unittest.mock import Mock
import stat
import subprocess
import sys
import time
import unittest.mock
from pathlib import Path

SCRIPT = Path(__file__).with_name("executable_tmux_automation.py")

def owned_root(parent):
    root = Path(parent) / "runtime"
    root.mkdir()
    marker = root / module.RUNTIME_ROOT_MARKER
    marker.write_text(module.RUNTIME_ROOT_MARKER_TOKEN)
    marker.chmod(0o600)
    root.chmod(0o700)
    return root
spec = importlib.util.spec_from_file_location("tmux_automation", SCRIPT)
module = importlib.util.module_from_spec(spec)


class WrapperContractTests(unittest.TestCase):
    def test_absent_root_create_initializes_owned_marker(self):
        with tempfile.TemporaryDirectory() as parent:
            root = Path(parent) / "root"
            module.Wrapper(root, "demo").lock(create=True).close()
            marker = root / module.RUNTIME_ROOT_MARKER
            self.assertEqual(stat.S_IMODE(root.stat().st_mode), 0o700)
            self.assertTrue(stat.S_ISREG(marker.stat().st_mode))
            self.assertEqual(marker.read_text(), module.RUNTIME_ROOT_MARKER_TOKEN)
            self.assertEqual(stat.S_IMODE(marker.stat().st_mode), 0o600)
            self.assertEqual(marker.stat().st_uid, os.getuid())

    def test_missing_exec_payload_fails_without_running_tmux(self):
        with tempfile.TemporaryDirectory() as parent:
            root = owned_root(parent)
            wrapper = module.Wrapper(root, "demo")
            wrapper.state_dir.mkdir(mode=0o700)
            wrapper.write_metadata({"status": "active", "session_id": "$1", "window_id": "@1", "pane_id": "%1"})
            sock = socket.socket(socket.AF_UNIX)
            sock.bind(str(wrapper.socket))
            with unittest.mock.patch.object(module.Wrapper, "run") as run:
                with self.assertRaises(module.WrapperError):
                    module.main(["--runtime-root", str(root), "exec", "demo", "--"])
                run.assert_not_called()
            sock.close()

    def test_existing_root_waits_for_marker_after_losing_mkdir_race(self):
        with tempfile.TemporaryDirectory() as parent:
            root = Path(parent) / "root"
            root.mkdir(mode=0o700)
            wrapper = module.Wrapper.__new__(module.Wrapper)
            wrapper.root, wrapper.timeout = root, 0.2
            marker = root / module.RUNTIME_ROOT_MARKER
            import threading
            observed_missing_marker = threading.Event()
            original_lstat = module.os.lstat

            def synchronized_lstat(path):
                try:
                    return original_lstat(path)
                except FileNotFoundError:
                    if Path(path) == marker:
                        observed_missing_marker.set()
                    raise

            thread_errors = []
            def publish():
                try:
                    self.assertTrue(observed_missing_marker.wait(1))
                    temporary_marker = root / f"{module.RUNTIME_ROOT_MARKER}.tmp"
                    fd = os.open(temporary_marker, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                except BaseException as error:
                    thread_errors.append(error)
                    return
                try:
                    try:
                        os.write(fd, module.RUNTIME_ROOT_MARKER_TOKEN.encode())
                        os.fsync(fd)
                    finally:
                        os.close(fd)
                    os.replace(temporary_marker, marker)
                except BaseException as error:
                    thread_errors.append(error)

            thread = threading.Thread(target=publish)
            thread.start()
            with unittest.mock.patch.object(module.os, "lstat", synchronized_lstat):
                self.assertTrue(wrapper.ensure_owned_root(create=True))
            thread.join()
            self.assertEqual(thread_errors, [])

    def test_marker_publication_handles_short_writes(self):
        with tempfile.TemporaryDirectory() as parent:
            root = Path(parent) / "root"
            wrapper = module.Wrapper.__new__(module.Wrapper)
            wrapper.root, wrapper.timeout = root, 1
            real_write = module.os.write
            writes = []

            def short_write(fd, data):
                chunk = data[:1]
                writes.append(chunk)
                return real_write(fd, chunk)

            with unittest.mock.patch.object(module.os, "write", short_write):
                self.assertTrue(wrapper.ensure_owned_root(create=True))
            self.assertEqual(b"".join(writes), module.RUNTIME_ROOT_MARKER_TOKEN.encode())
            self.assertEqual((root / module.RUNTIME_ROOT_MARKER).read_bytes(), module.RUNTIME_ROOT_MARKER_TOKEN.encode())

    def test_marker_publication_is_atomic_for_concurrent_wrappers(self):
        import threading
        with tempfile.TemporaryDirectory() as parent:
            root = Path(parent) / "root"
            publication_started = threading.Event()
            release_publication = threading.Event()
            second_started = threading.Event()
            second_finished = threading.Event()
            original_replace = module.os.replace

            def paused_replace(source, destination):
                if Path(destination) == root / module.RUNTIME_ROOT_MARKER:
                    publication_started.set()
                    self.assertFalse(Path(destination).exists())
                    self.assertTrue(release_publication.wait(1))
                return original_replace(source, destination)

            first = module.Wrapper.__new__(module.Wrapper)
            first.root, first.timeout = root, 1
            second = module.Wrapper.__new__(module.Wrapper)
            second.root, second.timeout = root, 1

            with unittest.mock.patch.object(module.os, "replace", paused_replace):
                first_result = []
                thread_errors = []
                def publish_first():
                    try:
                        first_result.append(first.ensure_owned_root(True))
                    except BaseException as error:
                        thread_errors.append(error)
                first_thread = threading.Thread(target=publish_first)
                first_thread.start()
                self.assertTrue(publication_started.wait(1))
                def publish_second():
                    try:
                        second_started.set()
                        second.ensure_owned_root(True)
                        second_finished.set()
                    except BaseException as error:
                        thread_errors.append(error)
                second_thread = threading.Thread(target=publish_second)
                second_thread.start()
                self.assertTrue(second_started.wait(1))
                self.assertFalse(second_finished.wait(0.05))
                self.assertFalse((root / module.RUNTIME_ROOT_MARKER).exists())
                release_publication.set()
                first_thread.join(1)
                second_thread.join(1)

            self.assertEqual(thread_errors, [])
            self.assertEqual(first_result, [True])
            self.assertTrue(second_finished.is_set())
            marker = root / module.RUNTIME_ROOT_MARKER
            self.assertEqual(marker.read_bytes(), module.RUNTIME_ROOT_MARKER_TOKEN.encode())
            self.assertEqual(stat.S_IMODE(marker.stat().st_mode), 0o600)
            self.assertEqual(list(root.glob(f"{module.RUNTIME_ROOT_MARKER}.*")), [])

    def test_existing_unmarked_root_is_rejected_before_locks(self):
        with tempfile.TemporaryDirectory() as parent:
            root = Path(parent) / "root"
            root.mkdir(mode=0o700)
            wrapper = module.Wrapper.__new__(module.Wrapper)
            wrapper.root = root
            wrapper.timeout = 0.01
            wrapper.name = "demo"
            wrapper.state_dir = root / "demo"
            wrapper.socket = wrapper.state_dir / "tmux.sock"
            wrapper.metadata_path = wrapper.state_dir / "metadata.json"
            wrapper.lock_path = root / ".locks" / "demo.lock"
            with self.assertRaises(module.WrapperError):
                wrapper.lock(create=True)
            self.assertFalse((root / ".locks").exists())

    @classmethod
    def setUpClass(cls):
        spec.loader.exec_module(module)

    def test_client_argv_is_explicitly_socketed_and_environment_is_clean(self):
        with tempfile.TemporaryDirectory() as parent:
            root = owned_root(parent)
            wrapper = module.Wrapper(Path(root), "demo")
            argv, env = wrapper.client_argv(["capture-pane", "-p"])
            self.assertEqual(argv[:3], ["tmux", "-S", str(wrapper.socket)])
            self.assertNotIn("TMUX", env)
            self.assertNotIn("TMUX_PANE", env)

    def test_names_reject_paths_dot_and_socket_overrides(self):
        for name in ["", ".", "..", "a/b", "-bad", "a\n"]:
            with self.assertRaises(ValueError):
                module.validate_name(name)
        with tempfile.TemporaryDirectory() as parent:
            root = owned_root(parent)
            wrapper = module.Wrapper(Path(root), "demo")
            with self.assertRaises(ValueError):
                wrapper.client_argv(["-S", "/other", "list-sessions"])
            with self.assertRaises(ValueError):
                wrapper.client_argv(["-L", "other", "list-sessions"])
            self.assertEqual(
                wrapper.client_argv(["display-message", "-p", "literal -S x"])[0][-1],
                "literal -S x",
            )

    def test_metadata_short_writes_publish_complete_json(self):
        with tempfile.TemporaryDirectory() as parent:
            root = owned_root(parent)
            wrapper = module.Wrapper(root, "demo")
            metadata = {"status": "active", "session_id": "$1", "window_id": "@1", "pane_id": "%1"}
            real_write = module.os.write
            with unittest.mock.patch.object(module.os, "write", side_effect=lambda fd, data: real_write(fd, data[:1])):
                wrapper.write_metadata(metadata)
            self.assertEqual(wrapper.read_metadata(), {**metadata, "socket": str(wrapper.socket)})
            self.assertEqual(list(wrapper.state_dir.glob("tmp*")), [])

    def test_metadata_zero_byte_write_preserves_prior_metadata_and_cleans_temp(self):
        with tempfile.TemporaryDirectory() as parent:
            root = owned_root(parent)
            wrapper = module.Wrapper(root, "demo")
            metadata = {"status": "active", "session_id": "$1", "window_id": "@1", "pane_id": "%1"}
            wrapper.write_metadata(metadata)
            with unittest.mock.patch.object(module.os, "write", return_value=0):
                with self.assertRaisesRegex(OSError, "zero-byte write"):
                    wrapper.write_metadata({**metadata, "status": "active"})
            self.assertEqual(wrapper.read_metadata()["status"], "active")
            self.assertEqual(list(wrapper.state_dir.glob("tmp*")), [])

    def test_metadata_publication_keeps_old_json_until_atomic_replace(self):
        import threading
        with tempfile.TemporaryDirectory() as parent:
            root = owned_root(parent)
            wrapper = module.Wrapper(root, "demo")
            wrapper.write_metadata({"status": "active", "session_id": "$1", "window_id": "@1", "pane_id": "%1"})
            paused = threading.Event()
            release = threading.Event()
            errors = []
            real_replace = module.os.replace
            def pause_replace(source, destination):
                paused.set()
                self.assertEqual(wrapper.read_metadata()["status"], "active")
                self.assertTrue(release.wait(1))
                return real_replace(source, destination)
            def publish():
                try:
                    wrapper.write_metadata({"status": "active", "session_id": "$2", "window_id": "@2", "pane_id": "%2"})
                except BaseException as error:
                    errors.append(error)
            with unittest.mock.patch.object(module.os, "replace", pause_replace):
                thread = threading.Thread(target=publish)
                thread.start()
                self.assertTrue(paused.wait(1))
                self.assertEqual(wrapper.read_metadata()["status"], "active")
                release.set()
                thread.join(1)
            self.assertEqual(errors, [])
            self.assertEqual(wrapper.read_metadata()["session_id"], "$2")

    def test_write_metadata_fsyncs_state_directory_after_replace(self):
        with tempfile.TemporaryDirectory() as parent:
            root = owned_root(parent)
            wrapper = module.Wrapper(root, "demo")
            real_fsync = module.os.fsync
            fsync_modes = []
            def record_fsync(fd):
                fsync_modes.append(stat.S_IFMT(os.fstat(fd).st_mode))
                return real_fsync(fd)
            with unittest.mock.patch.object(module.os, "fsync", side_effect=record_fsync):
                wrapper.write_metadata({"status": "active"})
            self.assertIn(stat.S_IFDIR, fsync_modes)

    def test_state_paths_are_private_and_metadata_has_stable_ids(self):
        with tempfile.TemporaryDirectory() as parent:
            root = owned_root(parent)
            wrapper = module.Wrapper(Path(root), "demo")
            self.assertTrue(str(wrapper.socket).startswith(str(Path(root).resolve())))
            self.assertFalse(wrapper.state_dir.exists())
            self.assertFalse((Path(root) / ".locks").exists())
            wrapper.state_dir.mkdir(mode=0o700)
            metadata = {
                "status": "active",
                "session_id": "$1",
                "window_id": "@1",
                "pane_id": "%1",
            }
            wrapper.write_metadata(metadata)
            self.assertEqual(
                wrapper.read_metadata(), {**metadata, "socket": str(wrapper.socket)}
            )

    def test_lock_contention_is_bounded_and_recovers_after_other_process_releases(self):
        with tempfile.TemporaryDirectory() as parent:
            root = owned_root(parent)
            wrapper = module.Wrapper(root, "demo", timeout=0.15)
            marker = Path(root) / "held"
            code = 'import time,sys; sys.path.insert(0, sys.argv[1]); from executable_tmux_automation import Wrapper; w=Wrapper(sys.argv[2], "demo", .15); f=w.lock(create=True); open(sys.argv[3], "w").close(); time.sleep(.4); f.close()'
            child = subprocess.Popen(
                [sys.executable, "-c", code, str(SCRIPT.parent), root, str(marker)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            for _ in range(50):
                if marker.exists():
                    break
                time.sleep(0.01)
            started = time.monotonic()
            with self.assertRaisesRegex(module.WrapperError, "lock timeout for demo"):
                module.Wrapper(root, "demo", 0.15).lock()
            self.assertLess(time.monotonic() - started, 0.35)
            stdout, stderr = child.communicate(timeout=2)
            self.assertEqual(child.returncode, 0, stderr.decode())
            recovered = module.Wrapper(root, "demo", 0.15).lock()
            recovered.close()

    def test_dangling_root_close_fails_closed_without_cleanup(self):
        with tempfile.TemporaryDirectory() as parent:
            root = Path(parent) / "root"
            root.symlink_to(Path(parent) / "missing", target_is_directory=True)
            with self.assertRaisesRegex(ValueError, "unsafe runtime root"):
                module.Wrapper(root, "demo")

    def test_marker_content_mode_and_symlink_are_rejected(self):
        for mutate in ("content", "mode", "symlink"):
            with tempfile.TemporaryDirectory() as parent:
                root = owned_root(parent)
                marker = root / module.RUNTIME_ROOT_MARKER
                if mutate == "content":
                    marker.write_text("wrong\\n")
                elif mutate == "mode":
                    marker.chmod(0o644)
                else:
                    marker.unlink()
                    marker.symlink_to(Path(parent) / "outside")
                with self.assertRaises(module.WrapperError):
                    module.Wrapper(root, "demo")

    def test_unmarked_root_rejects_all_actions_without_locks_mutation(self):
        with tempfile.TemporaryDirectory() as parent:
            root = Path(parent) / "root"
            root.mkdir(mode=0o700)
            for action in ("create", "info", "exec", "wait", "close"):
                with self.assertRaises((module.WrapperError, ValueError)):
                    wrapper = module.Wrapper(root, "demo", timeout=0.01)
                    if action == "close":
                        wrapper.close()
                    else:
                        module.main(["--runtime-root", str(root), "--timeout", "0.01", action, "demo", "--", "true"])
            self.assertFalse((root / ".locks").exists())

    def test_default_root_uses_xdg_runtime_directory_and_uid_fallback(self):
        with unittest.mock.patch.dict(
            os.environ, {"XDG_RUNTIME_DIR": "/run/user/test"}, clear=False
        ):
            self.assertEqual(
                module.default_runtime_root(), Path("/run/user/test/tmux-automation")
            )
        with unittest.mock.patch.dict(os.environ, {}, clear=True):
            self.assertEqual(
                module.default_runtime_root(),
                Path(f"/tmp/tmux-automation-{os.getuid()}"),
            )

    def test_lock_rejects_symlink_and_unsafe_lock_file(self):
        with (
            tempfile.TemporaryDirectory() as parent,
            tempfile.TemporaryDirectory() as outside,
        ):
            root = owned_root(parent)
            locks = Path(root) / ".locks"
            locks.mkdir(mode=0o700)
            (locks / "demo.lock").symlink_to(Path(outside) / "target")
            wrapper = module.Wrapper(root, "demo")
            with self.assertRaises(module.WrapperError):
                wrapper.lock()
            (locks / "demo.lock").unlink()
            unsafe = locks / "demo.lock"
            unsafe.touch(mode=0o600)
            unsafe.chmod(0o644)
            with self.assertRaises(module.WrapperError):
                wrapper.lock()

    def test_lock_rejects_unsafe_locks_directory(self):
        with tempfile.TemporaryDirectory() as parent:
            root = owned_root(parent)
            locks = Path(root) / ".locks"
            locks.mkdir(mode=0o700)
            locks.chmod(0o755)
            with self.assertRaises(module.WrapperError):
                module.Wrapper(root, "demo").lock()

    def test_constructor_rejects_unsafe_preexisting_root(self):
        with tempfile.TemporaryDirectory() as parent:
            root = Path(parent) / "root"
            root.mkdir(mode=0o755)
            with self.assertRaises(ValueError):
                module.Wrapper(root, "demo")

    def test_close_socket_shutdown_timeout_preserves_evidence(self):
        with tempfile.TemporaryDirectory() as parent:
            root = owned_root(parent)
            wrapper = module.Wrapper(root, "demo", timeout=0.01)
            wrapper.state_dir.mkdir(mode=0o700)
            sock = socket.socket(socket.AF_UNIX)
            sock.bind(str(wrapper.socket))
            wrapper.write_metadata(
                {
                    "status": "active",
                    "session_id": "$1",
                    "window_id": "@1",
                    "pane_id": "%1",
                }
            )
            wrapper.run = Mock(side_effect=subprocess.TimeoutExpired("tmux", 1))
            with self.assertRaisesRegex(ValueError, "unable to verify"):
                wrapper.close()
            self.assertTrue(wrapper.state_dir.exists())
            sock.close()

    def test_existing_state_symlink_is_rejected_without_following(self):
        with (
            tempfile.TemporaryDirectory() as parent,
            tempfile.TemporaryDirectory() as outside,
        ):
            root = owned_root(parent)
            target = Path(outside) / "keep"
            target.mkdir()
            (Path(root) / "demo").symlink_to(target, target_is_directory=True)
            wrapper = module.Wrapper(root, "demo")
            with self.assertRaises(ValueError):
                wrapper.load_active_state()
            self.assertTrue(target.exists())

    def test_create_refuses_preexisting_state_without_modifying_or_starting_tmux(self):
        with tempfile.TemporaryDirectory() as parent:
            root = owned_root(parent)
            wrapper = module.Wrapper(root, "demo")
            wrapper.state_dir.mkdir(mode=0o700)
            marker = wrapper.state_dir / "evidence"
            marker.write_text("keep")
            wrapper.run = Mock()
            with self.assertRaisesRegex(module.WrapperError, "state directory"):
                wrapper.create([])
            self.assertEqual(marker.read_text(), "keep")
            wrapper.run.assert_not_called()

    def test_info_requires_owned_socket(self):
        with tempfile.TemporaryDirectory() as parent:
            root = owned_root(parent)
            wrapper = module.Wrapper(root, "demo")
            wrapper.state_dir.mkdir(mode=0o700)
            wrapper.write_metadata(
                {
                    "status": "active",
                    "session_id": "$1",
                    "window_id": "@1",
                    "pane_id": "%1",
                }
            )
            with self.assertRaisesRegex(ValueError, "socket"):
                wrapper.load_active_state()

    def test_create_timeout_without_socket_preserves_private_state_until_close(self):
        with tempfile.TemporaryDirectory() as parent:
            root = owned_root(parent)
            wrapper = module.Wrapper(root, "demo")
            wrapper.run = Mock(side_effect=subprocess.TimeoutExpired(["tmux"], 1))
            with self.assertRaisesRegex(ValueError, "run close demo"):
                wrapper.create([])
            self.assertTrue(wrapper.metadata_path.exists())
            self.assertEqual(stat.S_IMODE(wrapper.metadata_path.stat().st_mode), 0o600)
            wrapper.close()
            self.assertFalse(wrapper.state_dir.exists())

    def test_create_file_not_found_before_server_preserves_no_state(self):
        with tempfile.TemporaryDirectory() as parent:
            root = owned_root(parent)
            wrapper = module.Wrapper(root, "demo")
            wrapper.run = Mock(side_effect=FileNotFoundError("tmux"))
            with self.assertRaises(FileNotFoundError):
                wrapper.create([])
            self.assertTrue(wrapper.state_dir.exists())

    def test_wait_timeout_passes_remaining_timeout_to_poll(self):
        with tempfile.TemporaryDirectory() as parent:
            root = owned_root(parent)
            wrapper = module.Wrapper(root, "demo", timeout=9)
            wrapper.state_dir.mkdir(mode=0o700)
            sock = socket.socket(socket.AF_UNIX)
            sock.bind(str(wrapper.socket))
            wrapper.write_metadata({"status": "active", "session_id": "$1", "window_id": "@1", "pane_id": "%1"})
            observed_timeouts = []

            def hung_observation(command, check=True, timeout=None):
                observed_timeouts.append(timeout)
                raise subprocess.TimeoutExpired(command, timeout, output="partial")

            started = time.monotonic()
            with unittest.mock.patch.object(module.Wrapper, "run", side_effect=hung_observation):
                with self.assertRaisesRegex(module.WaitTimeout, "last observation"):
                    module.main(["--runtime-root", str(root), "--timeout", "9", "wait", "--wait-timeout", "0.05", "demo", "--", "capture-pane"])
            elapsed = time.monotonic() - started
            self.assertGreater(observed_timeouts, [])
            self.assertTrue(all(timeout <= 0.05 + 0.01 for timeout in observed_timeouts))
            self.assertLess(elapsed, 0.5)
            sock.close()

    def test_close_missing_metadata_without_socket_preserves_unrecognized_state(self):
        with tempfile.TemporaryDirectory() as parent:
            root = owned_root(parent)
            wrapper = module.Wrapper(root, "demo")
            wrapper.state_dir.mkdir(mode=0o700)
            marker = wrapper.state_dir / "evidence"
            marker.write_text("keep")
            with self.assertRaisesRegex(ValueError, "metadata"):
                wrapper.close()
            self.assertEqual(marker.read_text(), "keep")

    def test_close_missing_metadata_with_socket_preserves_evidence(self):
        with tempfile.TemporaryDirectory() as parent:
            root = owned_root(parent)
            wrapper = module.Wrapper(root, "demo")
            wrapper.state_dir.mkdir(mode=0o700)
            sock = socket.socket(socket.AF_UNIX)
            sock.bind(str(wrapper.socket))
            wrapper.run = Mock()
            with self.assertRaisesRegex(ValueError, "metadata"):
                wrapper.close()
            self.assertTrue(wrapper.state_dir.exists())
            wrapper.run.assert_not_called()
            sock.close()

    def test_close_starting_with_live_socket_kills_exact_socket_and_removes_state(self):
        with tempfile.TemporaryDirectory() as parent:
            root = owned_root(parent)
            wrapper = module.Wrapper(root, "demo")
            wrapper.state_dir.mkdir(mode=0o700)
            sock = socket.socket(socket.AF_UNIX)
            sock.bind(str(wrapper.socket))
            wrapper.write_metadata(
                {
                    "status": "starting",
                    "session_id": None,
                    "window_id": None,
                    "pane_id": None,
                }
            )
            def run(argv, check=True, **kwargs):
                if argv == ["kill-server"]:
                    return Mock(returncode=0)
                if argv == ["list-sessions"]:
                    raise subprocess.CalledProcessError(1, argv)
                raise AssertionError(f"unexpected rollback command: {argv!r}")

            wrapper.run = Mock(side_effect=run)
            wrapper.close()
            self.assertEqual(wrapper.run.call_args_list[0].args[0], ["kill-server"])
            self.assertFalse(wrapper.state_dir.exists())
            sock.close()

    def test_info_exec_wait_reject_starting_state(self):
        with tempfile.TemporaryDirectory() as parent:
            root = owned_root(parent)
            wrapper = module.Wrapper(root, "demo")
            wrapper.state_dir.mkdir(mode=0o700)
            sock = socket.socket(socket.AF_UNIX)
            sock.bind(str(wrapper.socket))
            wrapper.write_metadata(
                {
                    "status": "starting",
                    "session_id": None,
                    "window_id": None,
                    "pane_id": None,
                }
            )
            with self.assertRaisesRegex(ValueError, "starting"):
                wrapper.load_active_state()
            for action in ("exec", "wait"):
                with self.assertRaisesRegex(ValueError, "starting"):
                    module.main(["--runtime-root", str(root), action, "demo", "--", "true"])
            sock.close()

    def test_close_starting_without_socket_removes_state(self):
        with tempfile.TemporaryDirectory() as parent:
            root = owned_root(parent)
            wrapper = module.Wrapper(root, "demo")
            wrapper.state_dir.mkdir(mode=0o700)
            wrapper.write_metadata(
                {
                    "status": "starting",
                    "session_id": None,
                    "window_id": None,
                    "pane_id": None,
                }
            )
            wrapper.close()
            self.assertFalse(wrapper.state_dir.exists())

    def test_wait_observations_are_bounded_and_diagnostic(self):
        observations = iter(["old", "still old"])
        last = ["old"]

        def observe():
            try:
                last[0] = next(observations)
            except StopIteration:
                pass
            return last[0]

        with self.assertRaises(module.WaitTimeout) as error:
            module.wait_until(
                observe, lambda text: text == "new", timeout=0.01, interval=0
            )
        self.assertIn("still old", str(error.exception))

    def test_wait_until_monotonic_rollover_never_sleeps_negative(self):
        monotonic = iter([100.0, 99.0, 101.0, 101.0])
        sleeps = []
        with unittest.mock.patch.object(module.time, "monotonic", side_effect=lambda: next(monotonic)):
            with unittest.mock.patch.object(module.time, "sleep", side_effect=sleeps.append):
                with self.assertRaises(module.WaitTimeout):
                    module.wait_until(lambda: "old", lambda value: False, timeout=1, interval=0.1)
        self.assertTrue(all(delay >= 0 for delay in sleeps))

    def test_absent_root_marker_monotonic_rollover_is_unsafe_runtime_root(self):
        with tempfile.TemporaryDirectory() as parent:
            root = Path(parent) / "root"
            root.mkdir(mode=0o700)
            wrapper = module.Wrapper.__new__(module.Wrapper)
            wrapper.root, wrapper.timeout = root, 1
            monotonic = iter([100.0, 99.0, 101.0, 101.0])
            sleeps = []
            with unittest.mock.patch.object(module.time, "monotonic", side_effect=lambda: next(monotonic)):
                with unittest.mock.patch.object(module.time, "sleep", side_effect=sleeps.append):
                    with self.assertRaisesRegex(module.WrapperError, "unsafe runtime root"):
                        wrapper.ensure_owned_root(create=False)
            self.assertTrue(all(delay >= 0 for delay in sleeps))

    def test_parser_preserves_payload_after_double_dash(self):
        parsed = module.parse_cli(["wait", "--regex", "x", "demo", "--", "-L", "value"])
        self.assertEqual(parsed.command, ["-L", "value"])
        self.assertEqual(parsed.name, "demo")

    def test_cli_accepts_documented_forms_and_payload_options(self):
        cases = [
            [
                "--runtime-root",
                "/tmp/x",
                "--timeout",
                "1",
                "create",
                "demo",
                "--",
                "-f",
                "payload",
            ],
            ["--runtime-root", "/tmp/x", "info", "demo"],
            ["--runtime-root", "/tmp/x", "close", "demo"],
            ["--runtime-root", "/tmp/x", "exec", "demo", "--", "-L", "payload"],
            [
                "--runtime-root",
                "/tmp/x",
                "wait",
                "--regex",
                "x",
                "demo",
                "--",
                "-S",
                "payload",
            ],
        ]
        for arguments in cases:
            result = subprocess.run(
                [sys.executable, str(SCRIPT), *arguments],
                text=True,
                capture_output=True,
            )
            self.assertNotIn("unrecognized arguments", result.stderr)

    def test_cli_rejects_wrapper_unknown_missing_and_tmux_selector_options(self):
        cases = [
            ["wait", "--unknown", "demo", "--", "true"],
            ["wait", "--regex"],
            ["wait", "--wait-timeout"],
            ["exec", "demo", "--", "-S", "/other", "list-sessions"],
            ["exec", "demo", "--", "-L/other", "list-sessions"],
        ]
        for arguments in cases:
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--runtime-root", "/tmp/x", *arguments],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 2, arguments)
            self.assertNotIn("Traceback", result.stderr)

    def test_cli_rejects_nonfinite_and_negative_wait_values(self):
        cases = [
            (["--timeout", "-1", "wait", "demo", "--", "true"], "finite"),
            (["--timeout", "nan", "wait", "demo", "--", "true"], "finite"),
            (["wait", "--duration", "-1", "demo", "--", "true"], "finite"),
            (["wait", "--wait-timeout", "inf", "demo", "--", "true"], "finite"),
        ]
        for arguments, message in cases:
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--runtime-root", "/tmp/x", *arguments],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 2, arguments)
            self.assertNotIn("Traceback", result.stderr)
            self.assertIn(message, result.stderr)

    def test_cli_reports_invalid_regex_concisely(self):
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--runtime-root",
                "/tmp/x",
                "wait",
                "--regex",
                "[",
                "demo",
                "--",
                "true",
            ],
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("Traceback", result.stderr)
        self.assertEqual(len(result.stderr.splitlines()), 1)

    def test_cli_preserves_starting_evidence_when_tmux_is_missing(self):
        with tempfile.TemporaryDirectory() as parent:
            root = Path(parent) / "absent-root"
            env = os.environ.copy()
            env["PATH"] = "/nonexistent"
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--runtime-root", str(root), "create", "demo"],
                env=env, text=True, capture_output=True,
            )
            self.assertEqual(result.returncode, 2)
            self.assertNotIn("Traceback", result.stderr)
            self.assertEqual(len(result.stderr.splitlines()), 1)
            self.assertEqual((root / module.RUNTIME_ROOT_MARKER).read_text(), module.RUNTIME_ROOT_MARKER_TOKEN)
            metadata = json.loads((root / "demo" / "metadata.json").read_text())
            self.assertEqual(metadata["status"], "starting")


if __name__ == "__main__":
    unittest.main()
