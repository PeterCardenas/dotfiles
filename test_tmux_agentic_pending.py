"""End-to-end coverage for the tmux pending-status publisher.

Every test owns an explicitly named tmux server.  No test can touch the user's
usual tmux server, and cleanup is performed even when an assertion fails.
"""
import hashlib
import os
import shlex
import shutil
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).parent
SCRIPT = ROOT / "dot_config/tmux/scripts/executable_agentic_pending.sh"
PID = str(os.getpid())
STAT_START = Path(f"/proc/{PID}/stat").read_text().split(") ", 1)[1].split()[19]
COLORS = ("#c0caf5", "#9ece6a", "#e0af68", "#f7768e")


def test_projected_runtime_matches_canonical_sources():
    """Catch stale ~/.config files before exercising their consumers."""
    pairs = [
        (ROOT / "dot_config/nvim_conf/kickstart.nvim/lua/plugins/sg.lua", Path.home() / ".config/nvim/lua/plugins/sg.lua"),
        (ROOT / "dot_config/nvim_conf/kickstart.nvim/lua/utils/agentic_pending.lua", Path.home() / ".config/nvim/lua/utils/agentic_pending.lua"),
        (ROOT / "dot_config/tmux/statusbar.conf", Path.home() / ".config/tmux/statusbar.conf"),
        (ROOT / "dot_config/tmux/scripts/executable_agentic_pending.sh", Path.home() / ".config/tmux/scripts/agentic_pending.sh"),
        (ROOT / "dot_config/fish/functions/manage_sessions.fish", Path.home() / ".config/fish/functions/manage_sessions.fish"),
    ]
    for canonical, runtime in pairs:
        assert canonical.read_bytes() == runtime.read_bytes(), (
            f"projection mismatch: {canonical} -> {runtime}; "
            f"canonical sha256={hashlib.sha256(canonical.read_bytes()).hexdigest()} "
            f"runtime sha256={hashlib.sha256(runtime.read_bytes()).hexdigest()}"
        )


def tmux(mode, socket, *args, check=True):
    return subprocess.run(
        ["tmux", mode, socket, *args], text=True, capture_output=True, check=check
    )


def pending(socket, target, *colors, scope=None):
    args = [str(SCRIPT), socket, target, *colors]
    if scope:
        args.append(scope)
    return subprocess.run(args, text=True, capture_output=True, check=True).stdout


def state(socket, target, scope="window"):
    return subprocess.run(
        [str(SCRIPT), "--state", socket, target, scope],
        text=True, capture_output=True, check=True,
    ).stdout.strip()


def set_marker(mode, socket, pane, value):
    tmux(mode, socket, "set-option", "-p", "-t", pane, "@agentic_pending", value)


def pane(mode, socket, target):
    return tmux(mode, socket, "list-panes", "-t", target, "-F", "#{pane_id}").stdout.splitlines()[0]


def check_statuses(mode, socket):
    statusbar = (ROOT / "dot_config/tmux/statusbar.conf").read_text()
    for format_name, neutral in (("window-status-current-format", "#c0caf5"), ("window-status-format", "#565f89")):
        line = next(line for line in statusbar.splitlines() if line.startswith(f"set -g {format_name} "))
        assert all(color in line for color in (neutral, "#9ece6a", "#e0af68", "#f7768e"))
    name = "status-" + uuid.uuid4().hex[:8]
    try:
        tmux(mode, socket, "new-session", "-d", "-s", name, "-n", "one")
        window = tmux(mode, socket, "display-message", "-p", "-t", f"{name}:one", "#{window_id}").stdout.strip()
        first = pane(mode, socket, window)
        assert pending(socket, window, *COLORS) == "#[fg=#c0caf5]"
        assert state(socket, window) == "none"
        set_marker(mode, socket, first, f"v1:{PID}:{STAT_START}:1:0")
        assert pending(socket, window, *COLORS) == "#[fg=#9ece6a]"
        tmux(mode, socket, "split-window", "-d", "-t", window)
        panes = tmux(mode, socket, "list-panes", "-t", window, "-F", "#{pane_id}").stdout.splitlines()
        set_marker(mode, socket, panes[1], f"v1:{PID}:{STAT_START}:0:1")
        assert pending(socket, window, *COLORS) == "#[fg=#e0af68]"
        assert state(socket, window) == "mixed"
        idle_window = tmux(mode, socket, "new-window", "-d", "-t", name, "-n", "idle").stdout.strip()
        idle_window = tmux(mode, socket, "display-message", "-p", "-t", f"{name}:idle", "#{window_id}").stdout.strip()
        idle_pane = pane(mode, socket, idle_window)
        set_marker(mode, socket, idle_pane, f"v1:{PID}:{STAT_START}:0:2")
        assert pending(socket, idle_window, *COLORS) == "#[fg=#f7768e]"
        assert pending(socket, name, *COLORS, scope="session") == "#[fg=#e0af68]"
    finally:
        tmux(mode, socket, "kill-server", check=False)


def capture_attached_status(server, output):
    """Capture the actual terminal stream; format expansion is only real on attach."""
    command = ["timeout", "5s", "script", "-qefc", f"tmux -L {shlex.quote(server)} attach-session -t render", "/dev/null"]
    with output.open("wb") as stream:
        subprocess.run(command, stdout=stream, stderr=subprocess.DEVNULL, check=False)
    return output.read_bytes()


def assert_label_color(capture, label, color):
    rgb = ";".join(str(int(color[index:index + 2], 16)) for index in (0, 2, 4))
    sgr = f"\x1b[38;2;{rgb}m".encode()
    label_bytes = label.encode()
    positions = [index for index in range(len(capture)) if capture.startswith(label_bytes, index)]
    assert positions, f"missing window label {label!r} in PTY capture"
    assert any(sgr in capture[max(0, index - 2048):index + len(label_bytes) + 32] for index in positions), (
        f"{color!r} is not attached to {label!r}; "
        f"nearby={capture[max(0, positions[0] - 100):positions[0] + len(label_bytes) + 32]!r}"
    )


def test_rendered_status_formats_use_active_and_inactive_palette():
    """Render real status formats through a private server and attached PTY."""
    server = "rendered-" + uuid.uuid4().hex[:12]
    output = Path(tempfile.mktemp(prefix="tmux-rendered-"))
    try:
        tmux("-L", server, "new-session", "-d", "-x", "160", "-y", "30", "-s", "render", "-n", "ACTIVE_UNIQUE")
        tmux("-L", server, "new-window", "-d", "-t", "render", "-n", "INACTIVE_UNIQUE")
        tmux("-L", server, "source-file", str(ROOT / "dot_config/tmux/statusbar.conf"))
        tmux("-L", server, "set-option", "-t", "render", "status-interval", "1")
        one = tmux("-L", server, "display-message", "-p", "-t", "render:ACTIVE_UNIQUE", "#{window_id}").stdout.strip()
        two = tmux("-L", server, "display-message", "-p", "-t", "render:INACTIVE_UNIQUE", "#{window_id}").stdout.strip()
        panes = {one: pane("-L", server, one), two: pane("-L", server, two)}
        states = {"none": None, "working": "1:0", "idle": "0:1", "mixed": "1:1"}
        expected = {"none": ("c0caf5", "565f89"), "working": ("9ece6a", "9ece6a"), "idle": ("f7768e", "f7768e"), "mixed": ("e0af68", "e0af68")}
        for state_name, counts in states.items():
            marker = None if counts is None else f"v1:{PID}:{STAT_START}:{counts}"
            for target in panes.values():
                tmux("-L", server, "set-option", "-p", "-t", target, *( ["-u", "@agentic_pending"] if marker is None else ["@agentic_pending", marker] ))
            tmux("-L", server, "select-window", "-t", one)
            tmux("-L", server, "refresh-client", "-S", check=False)
            capture = capture_attached_status(server, output)
            active, inactive = expected[state_name]
            assert_label_color(capture, "ACTIVE_UNIQUE", active)
            assert_label_color(capture, "INACTIVE_UNIQUE", inactive)
    finally:
        tmux("-L", server, "kill-server", check=False)
        output.unlink(missing_ok=True)


def check_rejects_bad_records(mode, socket):
    name = "malformed-" + uuid.uuid4().hex[:8]
    try:
        tmux(mode, socket, "new-session", "-d", "-s", name)
        target = tmux(mode, socket, "display-message", "-p", "#{window_id}").stdout.strip()
        p = pane(mode, socket, target)
        bad = [
            "bad",
            "v1:bad:1:1:0",
            f"v1:{PID}:1:1:0",
            f"v1:{PID}:{STAT_START}:1:0:extra",
            f"v1:{PID}:{STAT_START}:1:0:",
            f"v1:{PID}:{STAT_START}:09:0",
            f"v1:{PID}:{STAT_START}:0:00",
            f"v1:{PID}:{STAT_START}::1",
            f"v1:{PID}:{STAT_START}:-1:0",
            f"v1:{PID}:{STAT_START}:10001:0",
            f"v1:{PID}:{STAT_START}:0:10001",
        ]
        for record in bad:
            set_marker(mode, socket, p, record)
            assert pending(socket, target, *COLORS) == "#[fg=#c0caf5]", record
    finally:
        tmux(mode, socket, "kill-server", check=False)


def wait_for(predicate, timeout=8):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        last = predicate()
        if last:
            return last
        time.sleep(0.1)
    raise AssertionError(f"timed out; last diagnostic: {last!r}")


def test_prompt_hook_admission_allows_empty_text_but_not_absent_context():
    """A hook call with matching identity is admission proof, even with empty text."""
    server = "empty-" + uuid.uuid4().hex[:12]
    socket = Path(tempfile.gettempdir()) / ("agentic-nvim-" + uuid.uuid4().hex + ".sock")
    try:
        tmux("-L", server, "new-session", "-d", "-x", "120", "-y", "30", "-s", "nvim", "bash")
        window = tmux("-L", server, "display-message", "-p", "#{window_id}").stdout.strip()
        pane_id = tmux("-L", server, "display-message", "-p", "#{pane_id}").stdout.strip()
        tmux("-L", server, "set-option", "-p", "-t", pane_id, "@agentic_pending", "stale-marker")
        tmux_socket = tmux("-L", server, "display-message", "-p", "#{socket_path}").stdout.strip()
        sg_source = (ROOT / "dot_config/nvim_conf/kickstart.nvim/lua/plugins/sg.lua").read_text()
        assert "on_prompt_submit = function(data)\n            Pending.mark_prompt(data)" in sg_source
        command = shlex.join(["env", "TMUX=" + tmux_socket + ",0,0", "TMUX_PANE=" + pane_id, "nvim", "-i", "NONE", "-u", str(ROOT / "dot_config/nvim_conf/kickstart.nvim/init.lua"), "--listen", str(socket)])
        tmux("-L", server, "send-keys", "-t", pane_id, command, "Enter")
        def rpc(expression):
            return subprocess.run(["nvim", "--server", str(socket), "--remote-expr", expression], text=True, capture_output=True, check=False).stdout.strip()
        wait_for(lambda: rpc("luaeval(\"type(require('utils.agentic_pending').mark_prompt)\")") == "function", timeout=20)
        time.sleep(3.0)
        marker = tmux("-L", server, "show-options", "-p", "-v", "-t", pane_id, "@agentic_pending", check=False).stdout.strip()
        assert marker == "", marker
        assert state(server, window) == "none"
        assert rpc("luaeval(\"type(require('utils.agentic_pending').mark_prompt)\")") == "function"
        tmux("-L", server, "send-keys", "-t", pane_id, ":qa!", "Enter")
        wait_for(lambda: subprocess.run(["nvim", "--server", str(socket), "--remote-expr", "1"], capture_output=True).returncode != 0)
    finally:
        tmux("-L", server, "kill-server", check=False)
        assert tmux("-L", server, "has-session", "-t", "nvim", check=False).returncode != 0
        socket.unlink(missing_ok=True)
        assert not socket.exists()


def test_actual_nvim_without_prompt_leaves_pending_unset():
    """Canonical startup clears a pre-existing marker without a prompt."""
    server = "startup-" + uuid.uuid4().hex[:12]
    with tempfile.TemporaryDirectory(prefix="agentic-startup-") as directory:
        socket = Path(directory) / "nvim.sock"
        init = ROOT / "dot_config/nvim_conf/kickstart.nvim/init.lua"
        try:
            tmux("-L", server, "new-session", "-d", "-x", "160", "-y", "40", "-s", "nvim", "nvim", "-u", str(init), "-i", "NONE", "--listen", str(socket))
            window = tmux("-L", server, "display-message", "-p", "#{window_id}").stdout.strip()
            target = pane("-L", server, window)
            set_marker("-L", server, target, "stale-marker")
            def rpc(expression):
                return subprocess.run(["nvim", "--server", str(socket), "--remote-expr", expression], text=True, capture_output=True, check=False).stdout.strip()
            wait_for(lambda: rpc("1") == "1", timeout=20)
            wait_for(lambda: rpc("luaeval(\"type(require('utils.agentic_pending').mark_prompt)\")") == "function", timeout=20)
            wait_for(lambda: tmux("-L", server, "show-options", "-p", "-v", "-t", target, "@agentic_pending", check=False).stdout.strip() == "", timeout=20)
            assert state(server, window) == "none"
        finally:
            tmux("-L", server, "kill-server", check=False)
            socket.unlink(missing_ok=True)


def test_real_nvim_count_publisher():
    server = "nvim-" + uuid.uuid4().hex[:12]
    with tempfile.TemporaryDirectory(prefix="agentic-nvim-") as directory:
        directory = Path(directory)
        ready = directory / "ready"
        init = directory / "init.lua"
        production_module = (ROOT / "dot_config/nvim_conf/kickstart.nvim/lua/utils/agentic_pending.lua").resolve()
        init.write_text(f'''if vim.loader then vim.loader.enable(false) end
local tabs = vim.api.nvim_list_tabpages()
vim.cmd("tabnew")
tabs = vim.api.nvim_list_tabpages()
package.loaded["agentic.session_registry"] = {{ sessions = {{
  [tabs[1]] = {{ session_id = "a", is_generating = false }}, [tabs[2]] = {{ session_id = "b", is_generating = false }}
}} }}
local registry = package.loaded["agentic.session_registry"]
vim.api.nvim_create_user_command("GenA", function() registry.sessions[tabs[1]].is_generating = not registry.sessions[tabs[1]].is_generating end, {{}})
vim.api.nvim_create_user_command("GenB", function() registry.sessions[tabs[2]].is_generating = not registry.sessions[tabs[2]].is_generating end, {{}})
vim.api.nvim_create_user_command("RemoveBoth", function() registry.sessions = {{}} end, {{}})
vim.api.nvim_create_user_command("ReplaceA", function() registry.sessions[tabs[1]] = {{ session_id = "replacement", is_generating = true }}; registry.sessions[tabs[2]] = nil end, {{}})
vim.api.nvim_create_user_command("RestoreA", function() registry.sessions[tabs[1]] = {{ session_id = "replacement", is_generating = false }} end, {{}})
package.loaded['utils.agentic_pending'] = nil
local pending = assert(loadfile({str(production_module)!r}))()
pending.setup()
vim.api.nvim_create_user_command("SuspendResume", function()
  pending.clear()
  vim.cmd("doautocmd VimResume")
end, {{}})
vim.api.nvim_create_user_command("ClearOnly", pending.clear, {{}})
vim.api.nvim_create_user_command("EmptyPrompt", function() pending.mark_prompt({{ session_id = "a", prompt = "", tab_page_id = tabs[1] }}) end, {{}})
vim.api.nvim_create_user_command("AbsentPrompt", function() pending.mark_prompt({{ session_id = "a", tab_page_id = tabs[1] }}) end, {{}})
vim.api.nvim_create_user_command("PromptA", function() pending.mark_prompt({{ session_id = "a", prompt = "real prompt", tab_page_id = tabs[1] }}) end, {{}})
vim.api.nvim_create_user_command("PromptReplacement", function() pending.mark_prompt({{ session_id = "replacement", prompt = "replacement prompt", tab_page_id = tabs[1] }}) end, {{}})
vim.api.nvim_create_user_command("PromptB", function() pending.mark_prompt({{ session_id = "b", prompt = "another prompt", tab_page_id = tabs[2] }}) end, {{}})
vim.fn.writefile({{ "ready", debug.getinfo(pending.setup, "S").source }}, {str(ready)!r})
''')
        try:
            nvim_command = "exec " + shlex.join(["nvim", "-i", "NONE", "-u", str(init)])
            tmux("-L", server, "new-session", "-d", "-x", "200", "-y", "50", "-s", "nvim", nvim_command)
            try:
                wait_for(lambda: ready.exists())
            except AssertionError as error:
                diagnostics = tmux("-L", server, "capture-pane", "-p", "-t", "nvim:0", check=False).stdout
                raise AssertionError(f"{error}; pane:\\n{diagnostics}") from error
            window = tmux("-L", server, "display-message", "-p", "#{window_id}").stdout.strip()
            nvim_pane = pane("-L", server, window)
            def marker():
                return tmux("-L", server, "show-options", "-p", "-v", "-t", nvim_pane, "@agentic_pending", check=False).stdout.strip()
            try:
                wait_for(lambda: marker() == "")
            except AssertionError as error:
                diagnostics = tmux("-L", server, "capture-pane", "-p", "-t", "nvim:0", check=False).stdout
                options = tmux("-L", server, "list-panes", "-a", "-F", "#{pane_id} #{pane_pid} #{@agentic_pending}", check=False).stdout
                raise AssertionError(f"{error}; marker={marker()!r}; panes={options!r}; pane:\\n{diagnostics}") from error
            assert pending(server, window, *COLORS) == "#[fg=#c0caf5]"
            tmux("-L", server, "send-keys", "-t", nvim_pane, ":EmptyPrompt", "Enter")
            wait_for(lambda: marker().endswith(":0:1"))
            assert pending(server, window, *COLORS) == "#[fg=#f7768e]"
            tmux("-L", server, "send-keys", "-t", nvim_pane, ":AbsentPrompt", "Enter")
            wait_for(lambda: marker().endswith(":0:1"))
            assert pending(server, window, *COLORS) == "#[fg=#f7768e]"
            tmux("-L", server, "send-keys", "-t", nvim_pane, ":PromptA", "Enter")
            wait_for(lambda: marker().endswith(":0:1"))
            tmux("-L", server, "send-keys", "-t", nvim_pane, ":GenA", "Enter")
            wait_for(lambda: marker().endswith(":1:0"))
            tmux("-L", server, "send-keys", "-t", nvim_pane, ":PromptB", "Enter")
            wait_for(lambda: marker().endswith(":1:1"))
            tmux("-L", server, "send-keys", "-t", nvim_pane, ":GenB", "Enter")
            wait_for(lambda: marker().endswith(":2:0"))
            assert pending(server, window, *COLORS) == "#[fg=#9ece6a]"
            tmux("-L", server, "send-keys", "-t", nvim_pane, ":GenA", "Enter")
            wait_for(lambda: marker().endswith(":1:1"))
            assert pending(server, window, *COLORS) == "#[fg=#e0af68]"
            tmux("-L", server, "send-keys", "-t", nvim_pane, ":GenB", "Enter")
            wait_for(lambda: marker().endswith(":0:2"))
            assert pending(server, window, *COLORS) == "#[fg=#f7768e]"
            tmux("-L", server, "send-keys", "-t", nvim_pane, ":ReplaceA", "Enter")
            wait_for(lambda: marker() == "")
            assert pending(server, window, *COLORS) == "#[fg=#c0caf5]"
            tmux("-L", server, "send-keys", "-t", nvim_pane, ":RestoreA", "Enter")
            tmux("-L", server, "send-keys", "-t", nvim_pane, ":PromptReplacement", "Enter")
            wait_for(lambda: marker().endswith(":0:1"))
            assert pending(server, window, *COLORS) == "#[fg=#f7768e]"
            tmux("-L", server, "send-keys", "-t", nvim_pane, ":RemoveBoth", "Enter")
            wait_for(lambda: marker() == "")
            assert pending(server, window, *COLORS) == "#[fg=#c0caf5]"
            nvim_pid = tmux("-L", server, "display-message", "-p", "-t", nvim_pane, "#{pane_pid}").stdout.strip()
            nvim_start = Path(f"/proc/{nvim_pid}/stat").read_text().split(") ", 1)[1].split()[19]
            tmux("-L", server, "set-option", "-p", "-t", nvim_pane, "@agentic_pending", f"v1:{nvim_pid}:{nvim_start}:0:1")
            tmux("-L", server, "send-keys", "-t", nvim_pane, ":ClearOnly", "Enter")
            wait_for(lambda: marker() == "")
            tmux("-L", server, "set-option", "-p", "-t", nvim_pane, "@agentic_pending", "stale-marker")
            tmux("-L", server, "send-keys", "-t", nvim_pane, ":SuspendResume", "Enter")
            wait_for(lambda: marker() == "")
            assert pending(server, window, *COLORS) == "#[fg=#c0caf5]"
            tmux("-L", server, "send-keys", "-t", nvim_pane, ":qa!", "Enter")
        finally:
            tmux("-L", server, "kill-server", check=False)
            assert not tmux("-L", server, "has-session", check=False).returncode == 0


def test_real_agentic_acp_workflow():
    """Run the installed agentic.nvim widget against a wholly local ACP."""
    server = "acp-" + uuid.uuid4().hex[:12]
    with tempfile.TemporaryDirectory(prefix="agentic-acp-") as directory:
        directory = Path(directory); fake = directory / "pi-acp"; log = directory / "acp.log"; ready = directory / "ready"
        fake.write_text('''#!/usr/bin/env python3
import json, os, sys, time
log = open(os.environ["ACP_LOG"], "a", buffering=1)
def out(x): print(json.dumps(x), flush=True)
def event(name): print(name, file=log, flush=True)
for line in sys.stdin:
    msg=json.loads(line); print(line, file=log)
    method=msg.get("method"); ident=msg.get("id"); params=msg.get("params", {})
    if method == "initialize": out({"jsonrpc":"2.0","id":ident,"result":{"protocolVersion":1,"agentCapabilities":{}}})
    elif method == "session/new": out({"jsonrpc":"2.0","id":ident,"result":{"sessionId":"local-session"}})
    elif method == "session/prompt":
        prompt=params.get("prompt", [])
        valid=(params.get("sessionId") == "local-session" and len(prompt) == 1 and prompt[0].get("type") == "text" and prompt[0].get("text") == "local test")
        if not valid:
            event("validation-failed")
            out({"jsonrpc":"2.0","id":ident,"error":{"code":-32602,"message":"invalid test prompt"}})
            continue
        event("validation-succeeded")
        time.sleep(float(os.environ.get("ACP_DELAY", "4")))
        event("response-emitted")
        out({"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"local-session","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"done"}}}})
        out({"jsonrpc":"2.0","id":ident,"result":{}})
'''); fake.chmod(0o755)
        init = directory / "init.lua"
        plugin = Path.home() / ".local/share/nvim/lazy/agentic.nvim"
        init.write_text(f'''vim.opt.rtp:prepend({str(plugin)!r})
vim.opt.rtp:prepend({str(Path.home() / ".local/share/nvim/lazy/plenary.nvim")!r})
vim.opt.rtp:prepend({str(Path.home() / ".local/share/nvim/lazy/nvim-treesitter")!r})
local Pending = dofile({str((ROOT / "dot_config/nvim_conf/kickstart.nvim/lua/utils/agentic_pending.lua").resolve())!r})
vim.env.TMUX_PANE = vim.fn.system("tmux display-message -p '#{{pane_id}}'"):gsub("%s+$", "")
Pending.setup()
local A = require("agentic")
A.setup({{provider="pi-acp", acp_providers={{["pi-acp"]={{command="pi-acp", args={{}}}}}}, hooks={{on_prompt_submit=function(data) Pending.mark_prompt(data); vim.schedule(Pending.recompute) end, on_session_update=function(data)\n  local update=data.update or {{}}; local content=update.content or {{}}\n  if update.sessionUpdate == "agent_message_chunk" and content.type == "text" and content.text == "done" then vim.fn.writefile({{"client-done"}}, {str(ready)!r}, "a") end\nend, on_response_complete=function(data) Pending.recompute(); vim.fn.writefile({{"response-complete", data.session_id or "unknown", tostring(data.tab_page_id or "unknown")}}, {str(ready)!r}, "a") end}}}})
vim.defer_fn(function() A.toggle({{auto_add_to_context=false}}) end, 100)
local command_created=false
local function publish_ready()
  local s=require("agentic.session_registry").get_session_for_tab_page(nil)
  if not s or not s.widget or not s.widget.buf_nrs or not s.widget.buf_nrs.input or not vim.api.nvim_buf_is_valid(s.widget.buf_nrs.input) then return false end
  if command_created then return true end
  command_created=true
  vim.api.nvim_create_user_command("AgenticSubmit", function()
    local current=require("agentic.session_registry").get_session_for_tab_page(nil)
    assert(current == s and vim.api.nvim_buf_is_valid(current.widget.buf_nrs.input))
    vim.api.nvim_buf_set_lines(current.widget.buf_nrs.input,0,-1,false,{{"local test"}})
    current.widget:_submit_input()
    vim.fn.writefile({{"submitted"}}, {str(ready)!r}, "a")
  end, {{}})
  vim.fn.writefile({{"widget-ready", s.session_id or "unknown", tostring(s.tab_page_id)}}, {str(ready)!r}, "a")
  return true
end
vim.defer_fn(function()
  local deadline=vim.loop.now()+8000
  local function wait() if publish_ready() or vim.loop.now()>deadline then return end; vim.defer_fn(wait,50) end
  wait()
end, 100)
''')
        env = os.environ.copy(); env.update(PATH=str(directory)+os.pathsep+env["PATH"], ACP_LOG=str(log), ACP_DELAY="4")
        try:
            tmux("-L", server, "new-session", "-d", "-x", "200", "-y", "50", "-s", "nvim", "env", "HOME="+env["HOME"], "PATH="+env["PATH"], "ACP_LOG="+str(log), "ACP_DELAY=4", "nvim", "-u", str(init), "-i", "NONE")
            window = tmux("-L", server, "display-message", "-p", "#{window_id}").stdout.strip(); p = pane("-L", server, window)
            assert pending(server, window, *COLORS) == "#[fg=#c0caf5]"
            try:
                wait_for(lambda: ready.exists() and "widget-ready" in ready.read_text())
            except AssertionError as error:
                diagnostics = tmux("-L", server, "capture-pane", "-p", "-t", p, check=False).stdout
                raise AssertionError(f"{error}; log={log.read_text() if log.exists() else ''!r}; pane={diagnostics!r}") from error
            assert pending(server, window, *COLORS) == "#[fg=#c0caf5]"
            wait_for(lambda: log.exists() and all(method in log.read_text() for method in ("initialize", "session/new")), timeout=5)
            assert pending(server, window, *COLORS) == "#[fg=#c0caf5]"
            tmux("-L", server, "send-keys", "-t", p, "Escape", ":AgenticSubmit", "Enter")
            marker = lambda: tmux("-L", server, "show-options", "-p", "-v", "-t", p, "@agentic_pending", check=False).stdout
            diagnostics = []
            def submitted_marker():
                value = marker()
                if not value:
                    diagnostics.append(tmux("-L", server, "capture-pane", "-p", "-t", p, check=False).stdout)
                return ":1:0" in value
            try:
                wait_for(submitted_marker, timeout=8)
            except AssertionError as error:
                raise AssertionError(f"{error}; marker={marker()!r}; log={log.read_text() if log.exists() else ''!r}; pane={diagnostics[-1] if diagnostics else ''}") from error
            assert pending(server, window, *COLORS) == "#[fg=#9ece6a]"
            wait_for(lambda: log.exists() and 'session/prompt' in log.read_text(), timeout=5)
            assert "validation-succeeded" in log.read_text()
            assert "validation-failed" not in log.read_text()
            wait_for(lambda: "response-emitted" in log.read_text(), timeout=8)
            wait_for(lambda: ready.exists() and "client-done" in ready.read_text(), timeout=8)
            wait_for(lambda: ":0:1" in marker(), timeout=8)
            assert pending(server, window, *COLORS) == "#[fg=#f7768e]"
        finally:
            tmux("-L", server, "kill-server", check=False)


def test_configured_agentic_lifecycle_raw_tmux():
    """Exercise canonical init.lua/sg.lua through the real Agentic UI."""
    server = "configured-" + uuid.uuid4().hex[:12]
    with tempfile.TemporaryDirectory(prefix="agentic-configured-") as directory:
        directory = Path(directory); fake = directory / "pi-acp"; log = directory / "acp.log"; release1 = directory / "release1"; release2 = directory / "release2"
        fake.write_text("""#!/usr/bin/env python3
import json, os, sys, time
log = open(os.environ['ACP_LOG'], 'a', buffering=1)
model = {'modelId':'gpt-5.6-sol','name':'gpt-5.6-sol'}
def options():
    return {'configOptions':[{'id':'model','category':'model','name':'Model','type':'select','options':[{'value':model['modelId'],'name':model['name']}],'currentValue':model['modelId']}]}
def out(x): print(json.dumps(x), flush=True)
prompt_count = 0
for line in sys.stdin:
    msg=json.loads(line); method=msg.get('method'); ident=msg.get('id'); p=msg.get('params', {})
    print(json.dumps({'method': method, 'params': p}), file=log)
    if method == 'initialize': out({'jsonrpc':'2.0','id':ident,'result':{'protocolVersion':1,'agentCapabilities':{}}})
    elif method == 'session/new': out({'jsonrpc':'2.0','id':ident,'result':{'sessionId':'fake-'+str(ident), 'models': {'availableModels':[model], 'currentModelId':model['modelId']}, **options()}})
    elif method == 'session/set_config_option': out({'jsonrpc':'2.0','id':ident,'result':options()})
    elif method == 'session/set_model': out({'jsonrpc':'2.0','id':ident,'result':{'model':model}})
    elif method == 'session/prompt':
        prompt_count += 1
        release = os.environ['ACP_RELEASE' + str(prompt_count)]
        while not os.path.exists(release): time.sleep(0.01)
        out({'jsonrpc':'2.0','id':ident,'result':{}})
"""); fake.chmod(0o755)
        env = os.environ.copy(); env.update(PATH=str(directory)+os.pathsep+env['PATH'], ACP_LOG=str(log), ACP_RELEASE1=str(release1), ACP_RELEASE2=str(release2))
        init = ROOT / "dot_config/nvim_conf/kickstart.nvim/init.lua"; sock = directory / "nvim.sock"; target = None
        try:
            tmux("-L", server, "new-session", "-d", "-x", "200", "-y", "50", "-s", "nvim", "env", "PATH="+env['PATH'], "ACP_LOG="+str(log), "ACP_RELEASE1="+str(release1), "ACP_RELEASE2="+str(release2), "nvim", "-u", str(init), "-i", "NONE", "--listen", str(sock))
            window = tmux("-L", server, "display-message", "-p", "#{window_id}").stdout.strip(); target = pane("-L", server, window)
            def rpc(expr): return subprocess.run(["nvim", "--server", str(sock), "--remote-expr", expr], text=True, capture_output=True, check=False).stdout.strip()
            marker = lambda p=target: tmux("-L", server, "show-options", "-p", "-v", "-t", p, "@agentic_pending", check=False).stdout.strip()
            ready = lambda: rpc("luaeval(\"return vim.bo.filetype\")").strip("'\"") == 'AgenticInput'
            wait_for(lambda: rpc('1') == '1', 20); assert pending(server, window, *COLORS) == "#[fg=#c0caf5]"
            tmux("-L", server, "send-keys", "-t", target, "Space", "a", "t")
            wait_for(lambda: rpc("luaeval(\"#vim.tbl_keys(require('agentic.session_registry').sessions)\")") == '1', 20)
            wait_for(lambda: 'AgenticInput' in tmux("-L", server, "capture-pane", "-p", "-t", target, check=False).stdout, 20)
            wait_for(lambda: log.exists() and 'session/new' in log.read_text(), 10)
            tmux("-L", server, "send-keys", "-t", target, "local test", "C-s")
            wait_for(lambda: marker().endswith(':1:0'), 8); assert pending(server, window, *COLORS) == "#[fg=#9ece6a]"
            release1.touch(); wait_for(lambda: marker().endswith(':0:1'), 8); assert pending(server, window, *COLORS) == "#[fg=#f7768e]"
            tmux("-L", server, "send-keys", "-t", target, "Escape", ":tabnew", "Enter", "Space", "a", "t")
            wait_for(lambda: rpc("luaeval(\"#vim.tbl_keys(require('agentic.session_registry').sessions)\")") == '2', 20)
            wait_for(lambda: rpc("luaeval(\"vim.bo.filetype\")").strip("'\\\"") == 'AgenticInput', 20)
            wait_for(lambda: log.exists() and log.read_text().count('session/new') == 2, 10)
            tmux("-L", server, "send-keys", "-t", target, "second test", "C-s")
            wait_for(lambda: marker().endswith(':1:1'), 8); assert pending(server, window, *COLORS) == "#[fg=#e0af68]"
            release2.touch(); wait_for(lambda: marker().endswith(':0:2'), 8); assert pending(server, window, *COLORS) == "#[fg=#f7768e]"
            entries = log.read_text(); assert entries.count('session/new') == 2 and entries.count('session/prompt') == 2, entries
            tmux("-L", server, "send-keys", "-t", target, "Escape", ":qa!", "Enter")
            wait_for(lambda: marker() == '', 8); assert pending(server, window, *COLORS) == "#[fg=#c0caf5]"
        finally:
            if target: tmux("-L", server, "send-keys", "-t", target, "Escape", ":qa!", "Enter", check=False)
            tmux("-L", server, "kill-server", check=False)


def test_fish_session_picker_rows():
    server = "fish-" + uuid.uuid4().hex[:12]
    with tempfile.TemporaryDirectory(prefix="agentic-fish-") as directory:
        directory = Path(directory); home = directory / "home"; home.mkdir(); config = home / ".config/tmux/scripts"; config.mkdir(parents=True)
        config.joinpath("agentic_pending.sh").symlink_to(SCRIPT)
        assert config.joinpath("agentic_pending.sh").resolve() == SCRIPT.resolve()
        assert os.access(config.joinpath("agentic_pending.sh"), os.X_OK)
        args_log = directory / "fzf.args"
        stdin_log = directory / "fzf.stdin"
        stub = directory / "fzf"; stub.write_text(f'''#!/bin/sh
printf '%s\\n' "$@" > {shlex.quote(str(args_log))}
cat > {shlex.quote(str(stdin_log))}
'''); stub.chmod(0o755)
        try:
            tmux("-L", server, "new-session", "-d", "-s", "current")
            for name in ["work space", "mixed|pipe", "idle agent", "neutral"]: tmux("-L", server, "new-session", "-d", "-s", name)
            for name, value in [("work space", "1:0"), ("mixed|pipe", "1:1"), ("idle agent", "0:1")]:
                p = pane("-L", server, name); set_marker("-L", server, p, f"v1:{PID}:{STAT_START}:{value}")
            fish = ROOT / "dot_config/fish/functions/manage_sessions.fish"
            current_pane = pane("-L", server, "current")
            socket_path = tmux("-L", server, "display-message", "-p", "#{socket_path}").stdout.strip()
            environment = os.environ.copy()
            environment.update({
                "HOME": str(home),
                "TMUX": socket_path + ",0,0",
                "TMUX_PANE": current_pane,
                "PATH": str(directory) + os.pathsep + environment["PATH"],
            })
            fish_command = f"function fzf; {stub} $argv; end; source {fish}; manage_sessions"
            result = subprocess.run(
                ["fish", "-c", fish_command],
                text=True,
                capture_output=True,
                env=environment,
                timeout=15,
            )
            assert result.returncode == 0, result.stderr
            assert stdin_log.exists(), result.stdout + result.stderr
            rows = stdin_log.read_bytes().splitlines()
            assert len(rows) == 4
            fields = [row.split(b"\t") for row in rows]
            assert all(len(row) == 2 for row in fields)
            assert {row[0].decode() for row in fields} == {"work space", "mixed|pipe", "idle agent", "neutral"}
            expected = {"work space": "158;203;106", "mixed|pipe": "224;174;104", "idle agent": "247;118;142", "neutral": None}
            for raw, display in fields:
                text = display.decode(); color = expected[raw.decode()]
                assert (f"\x1b[38;2;{color}m" in text) if color else "\x1b" not in text
            args = args_log.read_text().splitlines()
            assert "--ansi" in args and "--delimiter=\\t" in args and "--with-nth=2.." in args
            assert any("{1}" in arg for arg in args)
        finally:
            tmux("-L", server, "kill-server", check=False)


def main():
    servers = [("-L", "agentic-" + uuid.uuid4().hex[:12])]
    socket_dir = Path(tempfile.mkdtemp(prefix="agentic socket "))
    servers.append(("-S", str(socket_dir / "server.sock")))
    try:
        test_projected_runtime_matches_canonical_sources()
        test_rendered_status_formats_use_active_and_inactive_palette()
        test_prompt_hook_admission_allows_empty_text_but_not_absent_context()
        for mode, socket in servers:
            check_statuses(mode, socket)
            check_rejects_bad_records(mode, socket)
        test_actual_nvim_without_prompt_leaves_pending_unset()
        test_real_nvim_count_publisher()
        test_real_agentic_acp_workflow()
        test_configured_agentic_lifecycle_raw_tmux()
        test_fish_session_picker_rows()
    finally:
        shutil.rmtree(socket_dir, ignore_errors=True)
    print("ok")


if __name__ == "__main__":
    main()
