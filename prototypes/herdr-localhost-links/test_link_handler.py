import contextlib
import importlib.util
import io
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import tomllib
import unittest
from unittest.mock import patch

MODULE = Path(__file__).with_name("link_handler.py")
spec = importlib.util.spec_from_file_location("link_handler", MODULE)
link_handler = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = link_handler
spec.loader.exec_module(link_handler)


class LinkHandlerTests(unittest.TestCase):
    def test_rewrites_loopback_and_preserves_url_components(self):
        env = {"SSH_CONNECTION": "192.0.2.8 5555 10.0.0.4 22"}
        result = link_handler.rewrite_url("https://localhost:8443/a%2Fb?q=x#frag", env, platform="linux")
        self.assertEqual(result, "https://10.0.0.4:8443/a%2Fb?q=x#frag")

    def test_preserves_empty_query_fragment_case_and_port_spelling(self):
        env = {"HERDR_LOCALHOST_LINK_HOST": "Node.Example"}
        cases = {
            "HTTP://LOCALHOST:00080/path?": "HTTP://Node.Example:00080/path?",
            "http://localhost:00080/path#": "http://Node.Example:00080/path#",
            "https://localhost?#": "https://Node.Example?#",
        }
        for original, expected in cases.items():
            with self.subTest(original=original):
                self.assertEqual(link_handler.rewrite_url(original, env), expected)

    def test_accepts_valid_ipv6_override_and_brackets_authority(self):
        env = {"HERDR_LOCALHOST_LINK_HOST": "2001:db8::7"}
        self.assertEqual(link_handler.rewrite_url("http://localhost:80/x", env), "http://[2001:db8::7]:80/x")

    def test_rejects_loopback_unspecified_and_multicast_targets(self):
        for target in ("127.0.0.1", "::1", "0.0.0.0", "::", "224.0.0.1", "ff02::1", "localhost", "node.localhost"):
            with self.subTest(target=target), self.assertRaises(ValueError):
                link_handler.target_host({"HERDR_LOCALHOST_LINK_HOST": target})
            connection = f"192.0.2.8 55 {target} 22"
            with self.subTest(inferred_target=target), self.assertRaisesRegex(ValueError, "cannot infer"):
                link_handler.target_host({"SSH_CONNECTION": connection}, platform="linux")

    def test_macos_without_active_helper_rejects_ambiguous_inherited_ssh(self):
        with self.assertRaisesRegex(ValueError, "ambiguous"):
            link_handler.target_host({"SSH_CONNECTION": "192.0.2.8 55 10.0.0.7 22"}, platform="darwin")

    def test_rewrites_ipv4_and_ipv6_loopback_forms(self):
        env = {"HERDR_LOCALHOST_LINK_HOST": "herdr.example.test"}
        for source in ("http://127.0.0.1:3000/x", "http://[::1]:3000/x", "http://localhost.:3000/x"):
            with self.subTest(source=source):
                self.assertTrue(link_handler.rewrite_url(source, env).startswith("http://herdr.example.test:3000/"))

    def test_explicit_target_precedes_connection_address(self):
        env = {"HERDR_LOCALHOST_LINK_HOST": "machine.example.test", "SSH_CONNECTION": "192.0.2.9 4 10.0.0.2 22"}
        self.assertEqual(link_handler.rewrite_url("http://localhost/x", env), "http://machine.example.test/x")

    def test_ssh_client_and_hostname_are_fallback_evidence(self):
        self.assertEqual(link_handler.rewrite_url("http://localhost/x", {"SSH_CLIENT": "192.0.2.8 555 22", "HOSTNAME": "node.example.test"}, platform="linux"), "http://node.example.test/x")
        self.assertEqual(link_handler.rewrite_url("http://localhost/x", {"SSH_TTY": "/dev/pts/1", "HERDR_LOCALHOST_LINK_FQDN": "node.example.test"}, platform="linux"), "http://node.example.test/x")

    def test_local_and_unsubstantiated_context_are_unchanged(self):
        original = "http://localhost:99/x"
        self.assertEqual(link_handler.rewrite_url(original, {"HOSTNAME": "mac.local"}), original)
        self.assertEqual(link_handler.rewrite_url(original, {}), original)

    def test_invalid_urls_and_ambiguous_remote_evidence_fail_clearly(self):
        for url in ("javascript:alert(1)", "http://localhost:bad/x", "http://user:pass@localhost/x"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                link_handler.rewrite_url(url, {"SSH_CONNECTION": "a 1 b 2"}, platform="linux")
        with self.assertRaisesRegex(ValueError, "cannot infer"):
            link_handler.rewrite_url("http://localhost/x", {"SSH_CONNECTION": "192.0.2.8 55 127.0.0.1 22"}, platform="linux")

    def test_manifest_link_pattern_matches_case_insensitive_http_loopback(self):
        manifest = tomllib.loads(MODULE.with_name("herdr-plugin.toml").read_text())
        pattern = manifest["link_handlers"][0]["pattern"]
        self.assertIsNotNone(re.search(pattern, "HTTP://LOCALHOST:080/path"))
        self.assertIsNotNone(re.search(pattern, "HTTPS://localhost:080/path"))
        self.assertIsNone(re.search(pattern, "https://localhost.example/path"))

    def test_non_loopback_url_is_not_changed(self):
        url = "https://localhost.example.test:4/x"
        self.assertEqual(link_handler.rewrite_url(url, {"SSH_CONNECTION": "192.0.2.8 1 10.0.0.4 22"}), url)

    def test_active_client_helper_overrides_stale_ssh_environment(self):
        with tempfile.TemporaryDirectory() as directory:
            helper = Path(directory) / "herdr-client-connection"
            helper.write_text("#!/bin/sh\nprintf '%s' '192.0.2.8 55 10.0.0.7 22'\n")
            helper.chmod(0o755)
            env = {"PATH": directory, "SSH_CONNECTION": "192.0.2.8 1 10.0.0.3 22"}
            self.assertEqual(link_handler.rewrite_url("http://localhost/x", env), "http://10.0.0.7/x")

    def test_successful_empty_active_client_helper_means_local(self):
        with tempfile.TemporaryDirectory() as directory:
            helper = Path(directory) / "herdr-client-connection"
            helper.write_text("#!/bin/sh\nexit 0\n")
            helper.chmod(0o755)
            env = {"PATH": directory, "SSH_CONNECTION": "192.0.2.8 1 10.0.0.3 22"}
            self.assertEqual(link_handler.rewrite_url("http://localhost/x", env), "http://localhost/x")

    def test_failed_active_client_helper_does_not_fall_back_to_stale_ssh(self):
        with tempfile.TemporaryDirectory() as directory:
            helper = Path(directory) / "herdr-client-connection"
            helper.write_text("#!/bin/sh\nexit 1\n")
            helper.chmod(0o755)
            env = {"PATH": directory, "SSH_CONNECTION": "192.0.2.8 1 10.0.0.3 22"}
            with self.assertRaisesRegex(ValueError, "possibly stale"):
                link_handler.rewrite_url("http://localhost/x", env)

    def test_active_helper_timeout_is_bounded_and_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            helper = Path(directory) / "herdr-client-connection"
            helper.write_text("#!/bin/sh\nexit 0\n")
            helper.chmod(0o755)
            with patch.object(link_handler.subprocess, "run", side_effect=subprocess.TimeoutExpired("helper", 2)) as run:
                with self.assertRaisesRegex(ValueError, "timed out after 2 seconds"):
                    link_handler.target_host({"PATH": directory})
            self.assertEqual(run.call_args.kwargs["timeout"], 2)

    def test_non_loopback_url_does_not_call_active_helper(self):
        with tempfile.TemporaryDirectory() as directory:
            record = Path(directory) / "url"
            helper_calls = Path(directory) / "helper-calls"
            helper = Path(directory) / "herdr-client-connection"
            opener = Path(directory) / "xdg-open"
            helper.write_text(f"#!/bin/sh\nprintf x >> '{helper_calls}'\nexit 1\n")
            helper.chmod(0o755)
            opener.write_text(f'#!{sys.executable}\nimport pathlib,sys\npathlib.Path({str(record)!r}).write_text(sys.argv[1])\n')
            opener.chmod(0o755)
            env = {"PATH": directory, "HERDR_PLUGIN_CLICKED_URL": "https://example.test/a"}
            with patch.dict(os.environ, env, clear=True):
                result = link_handler.main([])
            self.assertEqual(result, 0)
            self.assertEqual(record.read_text(), "https://example.test/a")
            self.assertFalse(helper_calls.exists())

    def test_explicit_target_survives_missing_helper_and_reports_stale_opener_context(self):
        with tempfile.TemporaryDirectory() as directory:
            record = Path(directory) / "opener-env"
            opener = Path(directory) / "xdg-open"
            opener.write_text(f'#!{sys.executable}\nimport os,pathlib,sys\npathlib.Path({str(record)!r}).write_text(os.environ.get("SSH_CONNECTION", "<absent>")+"|"+sys.argv[1])\n')
            opener.chmod(0o755)
            env = {"PATH": directory, "SSH_CONNECTION": "stale 1 192.0.2.1 22", "HERDR_LOCALHOST_LINK_HOST": "herdr.example.test", "HERDR_PLUGIN_CLICKED_URL": "http://localhost/a"}
            stderr = io.StringIO()
            with patch.dict(os.environ, env, clear=True), contextlib.redirect_stderr(stderr):
                result = link_handler.main([])
            self.assertEqual(result, 0)
            self.assertEqual(record.read_text(), "stale 1 192.0.2.1 22|http://herdr.example.test/a")
            self.assertIn("SSH context could not refresh", stderr.getvalue())

    def test_explicit_target_survives_active_helper_failure_and_reports_stale_opener_context(self):
        with tempfile.TemporaryDirectory() as directory:
            record = Path(directory) / "opener-env"
            helper = Path(directory) / "herdr-client-connection"
            opener = Path(directory) / "xdg-open"
            helper.write_text("#!/bin/sh\nexit 9\n")
            helper.chmod(0o755)
            opener.write_text(f'#!{sys.executable}\nimport os,pathlib,sys\npathlib.Path({str(record)!r}).write_text(os.environ.get("SSH_CONNECTION", "<absent>")+"|"+sys.argv[1])\n')
            opener.chmod(0o755)
            env = {"PATH": directory, "SSH_CONNECTION": "stale 1 192.0.2.1 22", "HERDR_LOCALHOST_LINK_HOST": "herdr.example.test", "HERDR_PLUGIN_CLICKED_URL": "http://localhost/a"}
            stderr = io.StringIO()
            with patch.dict(os.environ, env, clear=True), contextlib.redirect_stderr(stderr):
                result = link_handler.main([])
            self.assertEqual(result, 0)
            self.assertEqual(record.read_text(), "stale 1 192.0.2.1 22|http://herdr.example.test/a")
            self.assertIn("SSH context could not refresh", stderr.getvalue())

    def test_explicit_target_survives_active_helper_timeout(self):
        with tempfile.TemporaryDirectory() as directory:
            record = Path(directory) / "opener-env"
            helper = Path(directory) / "herdr-client-connection"
            opener = Path(directory) / "xdg-open"
            helper.write_text("#!/bin/sh\nexit 0\n")
            helper.chmod(0o755)
            opener.write_text(f'#!{sys.executable}\nimport os,pathlib,sys\npathlib.Path({str(record)!r}).write_text(os.environ.get("SSH_CONNECTION", "<absent>")+"|"+sys.argv[1])\n')
            opener.chmod(0o755)
            env = {"PATH": directory, "SSH_CONNECTION": "stale 1 192.0.2.1 22", "HERDR_LOCALHOST_LINK_HOST": "herdr.example.test", "HERDR_PLUGIN_CLICKED_URL": "http://localhost/a"}
            actual_run = subprocess.run
            def run_with_helper_timeout(command, **kwargs):
                if command == [str(helper)]:
                    raise subprocess.TimeoutExpired(command, 2)
                return actual_run(command, **kwargs)
            stderr = io.StringIO()
            with patch.dict(os.environ, env, clear=True), patch.object(link_handler.subprocess, "run", side_effect=run_with_helper_timeout), contextlib.redirect_stderr(stderr):
                result = link_handler.main([])
            self.assertEqual(result, 0)
            self.assertEqual(record.read_text(), "stale 1 192.0.2.1 22|http://herdr.example.test/a")
            self.assertIn("SSH context could not refresh", stderr.getvalue())

    def test_manifest_action_refreshes_opener_ssh_environment_from_active_helper(self):
        active = "198.51.100.8 52222 10.0.0.7 22"
        with tempfile.TemporaryDirectory() as directory:
            record = Path(directory) / "opener-env"
            helper_calls = Path(directory) / "helper-calls"
            helper = Path(directory) / "herdr-client-connection"
            opener = Path(directory) / "xdg-open"
            helper.write_text(f"#!/bin/sh\nprintf '%s' '{active}'\nprintf x >> '{helper_calls}'\n")
            helper.chmod(0o755)
            opener.write_text(f'#!{sys.executable}\nimport os,pathlib,sys\npathlib.Path({str(record)!r}).write_text(os.environ.get("SSH_CONNECTION", "<absent>")+"|"+sys.argv[1])\n')
            opener.chmod(0o755)
            env = {"PATH": directory, "SSH_CONNECTION": "stale 1 192.0.2.1 22", "HERDR_PLUGIN_CLICKED_URL": "http://localhost/a"}
            with patch.dict(os.environ, env, clear=True):
                result = link_handler.main([])
                self.assertEqual(os.environ["SSH_CONNECTION"], "stale 1 192.0.2.1 22")
            self.assertEqual(result, 0)
            self.assertEqual(record.read_text(), active + "|http://10.0.0.7/a")
            self.assertEqual(helper_calls.read_text(), "x")

    def test_successful_empty_helper_clears_stale_ssh_for_opener(self):
        with tempfile.TemporaryDirectory() as directory:
            record = Path(directory) / "opener-env"
            helper = Path(directory) / "herdr-client-connection"
            opener = Path(directory) / "xdg-open"
            helper.write_text("#!/bin/sh\nexit 0\n")
            helper.chmod(0o755)
            opener.write_text(f'#!{sys.executable}\nimport os,pathlib,sys\npathlib.Path({str(record)!r}).write_text(os.environ.get("SSH_CONNECTION", "<absent>")+"|"+sys.argv[1])\n')
            opener.chmod(0o755)
            env = {"PATH": directory, "SSH_CONNECTION": "stale 1 192.0.2.1 22", "HERDR_PLUGIN_CLICKED_URL": "http://localhost/a"}
            with patch.dict(os.environ, env, clear=True):
                result = link_handler.main([])
                self.assertEqual(os.environ["SSH_CONNECTION"], "stale 1 192.0.2.1 22")
            self.assertEqual(result, 0)
            self.assertEqual(record.read_text(), "<absent>|http://localhost/a")

    def test_manifest_action_reads_clicked_url_environment_without_arguments(self):
        with tempfile.TemporaryDirectory() as directory:
            record = Path(directory) / "url"
            opener = Path(directory) / "xdg-open"
            opener.write_text(f'#!{sys.executable}\nimport pathlib,sys\npathlib.Path({str(record)!r}).write_text(sys.argv[1])\n')
            opener.chmod(0o755)
            env = {
                "PATH": directory,
                "HERDR_LOCALHOST_LINK_HOST": "herdr.example.test",
                "HERDR_PLUGIN_CLICKED_URL": "https://localhost:443/path?#",
            }
            result = subprocess.run([sys.executable, str(MODULE)], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(record.read_text(), "https://herdr.example.test:443/path?#")

    def test_opener_receives_one_argument_and_propagates_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            record = Path(directory) / "args"
            opener = Path(directory) / "xdg-open"
            opener.write_text(f'#!{sys.executable}\nimport pathlib,sys\npathlib.Path({str(record)!r}).write_text(repr(sys.argv[1:]))\n')
            opener.chmod(0o755)
            env = {**os.environ, "PATH": directory}
            subprocess.run([sys.executable, str(MODULE), "https://example.test/a;touch%20x"], env=env, check=True)
            self.assertEqual(record.read_text(), "['https://example.test/a;touch%20x']")
            opener.write_text("#!/bin/sh\nexit 23\n")
            opener.chmod(0o755)
            failure = subprocess.run([sys.executable, str(MODULE), "https://example.test"], env=env, capture_output=True, text=True)
            self.assertEqual(failure.returncode, 23)


if __name__ == "__main__":
    unittest.main()
