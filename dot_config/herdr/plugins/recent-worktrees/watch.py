"""Promote the focused linked worktree within its existing sidebar group."""

import json
import os
from pathlib import Path
import re
import socket
import time


def promotion_index(workspaces):
    focused = next((row for row in workspaces if row.get("focused")), None)
    worktree = focused.get("worktree") if focused else None
    if (
        not worktree
        or not worktree.get("is_linked_worktree")
        or not worktree.get("repo_key")
    ):
        return None
    for index, row in enumerate(workspaces):
        parent = row.get("worktree")
        if (
            parent
            and not parent.get("is_linked_worktree")
            and parent.get("repo_key") == worktree["repo_key"]
        ):
            if index + 1 != workspaces.index(focused):
                return focused["workspace_id"], index + 1
            break
    return None


def focus_history(log_path):
    last_focus = {}
    try:
        with log_path.open() as log:
            for position, line in enumerate(log):
                match = re.search(
                    r'workspace focused[^\n]*workspace_id="([^"]+)"', line
                )
                if match:
                    last_focus[match.group(1)] = position
    except FileNotFoundError:
        pass
    return last_focus


def historical_order(workspaces, last_focus):
    ordered = [row["workspace_id"] for row in workspaces]
    parents = {
        row["worktree"]["repo_key"]
        for row in workspaces
        if row.get("worktree") and not row["worktree"]["is_linked_worktree"]
    }
    for repo_key in parents:
        positions = [
            index
            for index, row in enumerate(workspaces)
            if row.get("worktree")
            and row["worktree"]["is_linked_worktree"]
            and row["worktree"]["repo_key"] == repo_key
        ]
        children = sorted(
            (ordered[index] for index in positions),
            key=lambda workspace_id: (
                workspace_id not in last_focus,
                -last_focus.get(workspace_id, 0),
            ),
        )
        for index, workspace_id in zip(positions, children):
            ordered[index] = workspace_id
    return ordered


def request(method, params):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(5)
        connection.connect(os.environ["HERDR_SOCKET_PATH"])
        connection.sendall(
            (
                json.dumps(
                    {"id": "recent-worktrees", "method": method, "params": params}
                )
                + "\n"
            ).encode()
        )
        with connection.makefile("r") as response:
            result = json.loads(response.readline())
    if "error" in result:
        raise RuntimeError(result["error"])
    return result["result"]


def watch():
    # Herdr 0.9.1 does not dispatch UI-driven focus changes to plugin event hooks.
    rows = request("workspace.list", {})["workspaces"]
    socket_path = Path(os.environ["HERDR_SOCKET_PATH"])
    server_socket = socket_path.stat()
    log_path = socket_path.with_name("herdr-server.log")
    wanted = historical_order(rows, focus_history(log_path))
    if wanted != [row["workspace_id"] for row in rows]:
        request("workspace.move_block", {"workspace_ids": wanted})
    previous_focus = next(
        (row["workspace_id"] for row in rows if row.get("focused")), None
    )
    while True:
        # A manually started watcher must not follow a restarted server's socket.
        try:
            current_socket = socket_path.stat()
        except FileNotFoundError:
            return
        if (current_socket.st_dev, current_socket.st_ino) != (
            server_socket.st_dev,
            server_socket.st_ino,
        ):
            return
        rows = request("workspace.list", {})["workspaces"]
        focus = next((row["workspace_id"] for row in rows if row.get("focused")), None)
        if focus != previous_focus:
            move = promotion_index(rows)
            if move:
                request(
                    "workspace.move", {"workspace_id": move[0], "insert_index": move[1]}
                )
            previous_focus = focus
        time.sleep(2)


if __name__ == "__main__":
    watch()
