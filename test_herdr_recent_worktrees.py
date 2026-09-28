"""Keep linked worktrees MRU without moving their top-level sidebar groups."""

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).parent / "dot_config/herdr/plugins/recent-worktrees/watch.py"


class RecentWorktreesTest(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT.is_file(), "recent-worktrees plugin is missing")
        spec = importlib.util.spec_from_file_location("recent_worktrees", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.plugin = module
        self.promote = module.promotion_index

    def test_focused_child_moves_behind_its_parent(self):
        rows = [
            {"workspace_id": "other"},
            {
                "workspace_id": "parent",
                "worktree": {"repo_key": "repo", "is_linked_worktree": False},
            },
            {
                "workspace_id": "child-a",
                "worktree": {"repo_key": "repo", "is_linked_worktree": True},
            },
            {"workspace_id": "unrelated"},
            {
                "workspace_id": "child-b",
                "focused": True,
                "worktree": {"repo_key": "repo", "is_linked_worktree": True},
            },
            {
                "workspace_id": "second-parent",
                "worktree": {"repo_key": "different", "is_linked_worktree": False},
            },
        ]
        self.assertEqual(self.promote(rows), ("child-b", 2))
        rows.insert(2, rows.pop(4))
        self.assertIsNone(self.promote(rows))
        self.assertIsNone(
            self.promote(
                [
                    {**rows[2], "focused": False},
                    {"workspace_id": "plain", "focused": True},
                ]
            )
        )
        self.assertIsNone(
            self.promote(
                [
                    {
                        "workspace_id": "orphan",
                        "focused": True,
                        "worktree": {"repo_key": "missing", "is_linked_worktree": True},
                    }
                ]
            )
        )

    def test_log_history_uses_last_focus_and_handles_missing_log(self):
        self.assertTrue(
            hasattr(self.plugin, "focus_history"), "historical focus reader missing"
        )
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "herdr-server.log"
            self.assertEqual(self.plugin.focus_history(log), {})
            log.write_text(
                'workspace focused event="workspace.focus" workspace_id="a"\n'
                'tab focused workspace_id="b"\n'
                'workspace focused event="workspace.focus" workspace_id="b"\n'
                'workspace focused event="workspace.focus" workspace_id="a"\n'
            )
            self.assertGreater(
                self.plugin.focus_history(log)["a"], self.plugin.focus_history(log)["b"]
            )

    def test_startup_does_not_promote_the_already_focused_child_again(self):
        with tempfile.TemporaryDirectory() as directory:
            socket_path = Path(directory) / "herdr.sock"
            socket_path.touch()
            socket_path.with_name("herdr-server.log").write_text(
                'workspace focused workspace_id="old"\n'
                'workspace focused workspace_id="new"\n'
            )

            def child(workspace_id, focused=False):
                return {
                    "workspace_id": workspace_id,
                    "focused": focused,
                    "worktree": {"repo_key": "repo", "is_linked_worktree": True},
                }

            parent = {
                "workspace_id": "parent",
                "worktree": {"repo_key": "repo", "is_linked_worktree": False},
            }
            rows = [parent, child("old"), {"workspace_id": "other"}, child("new", True)]
            calls = []

            def request(method, params):
                calls.append((method, params))
                return {"workspaces": rows}

            with (
                patch.dict(os.environ, {"HERDR_SOCKET_PATH": str(socket_path)}),
                patch.object(self.plugin, "request", side_effect=request),
                patch.object(self.plugin.time, "sleep", side_effect=StopIteration),
            ):
                with self.assertRaises(StopIteration):
                    self.plugin.watch()
            self.assertEqual(
                [method for method, _ in calls],
                ["workspace.list", "workspace.move_block", "workspace.list"],
            )
            self.assertEqual(
                calls[1][1]["workspace_ids"], ["parent", "new", "other", "old"]
            )

    def test_watcher_stops_when_server_socket_is_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            socket_path = Path(directory) / "herdr.sock"
            socket_path.write_text("old server")
            calls = []

            def request(method, params):
                calls.append(method)
                return {"workspaces": [{"workspace_id": "parent", "focused": True}]}

            def restart_server(seconds):
                replacement = socket_path.with_name("replacement.sock")
                replacement.write_text("new server")
                replacement.replace(socket_path)
                if calls.count("workspace.list") > 2:
                    self.fail("watcher continued after server restart")

            with (
                patch.dict(os.environ, {"HERDR_SOCKET_PATH": str(socket_path)}),
                patch.object(self.plugin, "request", side_effect=request),
                patch.object(self.plugin.time, "sleep", side_effect=restart_server),
            ):
                self.plugin.watch()
            self.assertEqual(calls, ["workspace.list", "workspace.list"])

    def test_restore_only_sorts_children_in_their_original_slots(self):
        self.assertTrue(
            hasattr(self.plugin, "historical_order"), "historical sort missing"
        )

        def row(workspace_id, repo_key=None, linked=False):
            result = {"workspace_id": workspace_id}
            if repo_key:
                result["worktree"] = {
                    "repo_key": repo_key,
                    "is_linked_worktree": linked,
                }
            return result

        rows = [
            row("parent-a", "a"),
            row("a-old", "a", True),
            row("parent-b", "b"),
            row("b-idle", "b", True),
            row("a-new", "a", True),
            row("plain"),
            row("a-unseen", "a", True),
            row("b-new", "b", True),
            row("orphan", "missing", True),
        ]
        original = [entry["workspace_id"] for entry in rows]
        self.assertEqual(self.plugin.historical_order(rows, {}), original)
        self.assertEqual(
            self.plugin.historical_order(rows, {"a-old": 2, "a-new": 5, "b-new": 3}),
            [
                "parent-a",
                "a-new",
                "parent-b",
                "b-new",
                "a-old",
                "plain",
                "a-unseen",
                "b-idle",
                "orphan",
            ],
        )


if __name__ == "__main__":
    unittest.main()
