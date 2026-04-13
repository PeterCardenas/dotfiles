---
name: nvim-config
description: Use when editing, debugging, or testing Neovim configuration or plugins. Triggers when working with nvim/neovim config files, lua plugin config, lazy.nvim plugins, LSP setup, treesitter, keymaps, or anything under nvim_conf or ~/.config/nvim.
---

# Neovim Config Guidelines

## Editing

- DO NOT run `chezmoi apply`. It is not necessary after editing config files — and changes are automatically applied to the target after edits.
- Always read the plugin source in `~/.local/share/nvim/lazy/<plugin>/` before editing config that touches that plugin. Never guess at field names, APIs, or behavior.
- When adding functionality, `grep` across the existing config to find how similar things are done. Follow existing patterns.
- Prefer early returns over nested conditionals in Lua.
- No hacks or band-aid fixes. If a fix feels like a workaround, propose a proper architectural solution.
- Fix on the consumer side, not the producer side — put path resolution/normalization at the call site, not in the handler.
- Don't conflict with native keybindings. When there's a conflict risk, prefer commands over key shortcuts.

## Debugging

- Root cause before fix. Understand *why* something breaks before patching it.
- No speculative fixes. Reproduce the issue first, then fix.
- Use available debug infrastructure (env var flags, profiler tools, log output) rather than guessing at runtime behavior.

## Testing

- Verify changes by opening a new tmux session and launching nvim with the actual config. Never just read code and propose changes as done.
- Test both the broken state (without the fix) and the fixed state to confirm the fix actually addresses the issue.
- For experimental features, implement behind an env var config flag, test thoroughly, then remove the flag once verified.

### Launching tmux for testing

**Create a detached session with fixed dimensions:**
```bash
tmux new-session -d -s <session-name> -x 200 -y 50 "<command>"
```
- Always detach (`-d`) — never attach interactively.
- Make the session name unique to avoid conflicts with other agents.
- Always set dimensions (`-x 200 -y 50`) so capture-pane output is consistent and wide enough to avoid wrapping.
- The command string runs inside the session. Append `; sleep 5` to keep the session alive after nvim exits for output capture.

**Clean up stale sessions before creating:**
```bash
tmux kill-session -t <name> 2>/dev/null
tmux new-session -d -s <name> -x 200 -y 50 "nvim 2>&1; sleep 5"
```

**Two launch styles:**

1. **Inline command** — nvim runs as the session command (simpler, preferred for quick checks):
   ```bash
   tmux new-session -d -s nvim_test -x 200 -y 50 "nvim 2>&1; sleep 5"
   ```

2. **Send-keys** — create the session first, then send commands (needed when you must send multiple interactive keystrokes):
   ```bash
   tmux new-session -d -s nvim_test -x 200 -y 50
   tmux send-keys -t nvim_test "nvim /tmp/test.lua" Enter
   ```

**Capturing output:**
```bash
sleep 3 && tmux capture-pane -t <name> -p          # current visible pane
sleep 3 && tmux capture-pane -t <name> -p -S -50   # include scrollback (last 50 lines)
```
Always `sleep` before capture to let nvim settle — 3–5s for startup, longer for profiling or LSP-heavy operations.

**Sending keystrokes to an open nvim:**
```bash
tmux send-keys -t <name> ':messages' Enter     # ex command
tmux send-keys -t <name> Escape                # single key
tmux send-keys -t <name> ':autocmd Chezmoi BufWritePost' Enter
```

**With environment variables (e.g. profiling):**
```bash
tmux new-session -d -s nvim_prof -x 200 -y 50 "NVIM_PROFILE=start nvim 2>&1; sleep 5"
```

**Headless testing (no UI needed):**
```bash
tmux new-session -d -s test -x 200 -y 50 "nvim --headless -u tests/init.lua -c 'luafile /tmp/test_script.lua' 2>&1"
```

**Always clean up when done:**
```bash
tmux kill-session -t <name> 2>/dev/null
```

### Common tmux pitfalls

**Always create a new session — never add windows to existing sessions.**
`tmux new-window -t <existing-session>` fails with `create window failed: index in use` because the default target index is occupied. Even with `-a` or named windows (`-n`), targeting windows by name (`-t session:windowname`) is unreliable. Just create a fresh session — it's simpler and always works.

**Use `; ` not `||` for kill-before-create.**
```bash
# WRONG — kill only runs on failure, then second new-session also fails
tmux new-session -d -s test ... 2>/dev/null || tmux kill-session -t test && tmux new-session -d -s test ...

# RIGHT — always kill first, then create
tmux kill-session -t test 2>/dev/null; tmux new-session -d -s test -x 200 -y 50
```

**Inline commands die silently if nvim crashes.**
If nvim exits immediately (bad command, crash), the session disappears before `capture-pane` runs → `can't find pane: <name>`. When testing something that might crash, use the send-keys style so the session shell survives:
```bash
tmux new-session -d -s test -x 200 -y 50
tmux send-keys -t test 'nvim -c SomeCommand' Enter
sleep 5 && tmux capture-pane -t test -p
```

**If `capture-pane` returns stale content** (e.g. splash screen after sending commands), sleep longer. LSP, Octo, and plugin-heavy operations need 8–15s, not 3.

## Profiling

Profiling is controlled by env vars:

| Var | Effect |
|---|---|
| `NVIM_PROFILE=1` | Enable profile.nvim — instruments all modules, toggle recording manually with `:ToggleProfile` |
| `NVIM_PROFILE=start` | Enable profile.nvim — auto-records init→`VeryLazy`, then prompts to save |

**profile.nvim workflow:**
1. Launch: `NVIM_PROFILE=1 nvim` (on-demand) or `NVIM_PROFILE=start nvim` (startup capture)
2. `:ToggleProfile` to start/stop recording — on stop, prompts to save (default: `/tmp/neovim_lua_profile.json`)
3. Output is Chrome Trace Event Format (JSON array). Each entry has: `name` (function), `dur` (microseconds, on `ph:"X"` complete events), `ts` (timestamp µs), `cat` (e.g. `"function"`), `args` (call arguments).

**Analyzing traces with jq:**
```bash
# Top 20 slowest calls
jq '[.[] | select(.ph == "X")] | sort_by(-.dur) | .[0:20] | .[] | {name, dur_ms: (.dur/1000), cat}' /tmp/neovim_lua_profile.json

# Slowest module loads
jq '[.[] | select(.ph == "X" and .name == "require")] | sort_by(-.dur) | .[0:15] | .[] | {module: .args["1"], dur_ms: (.dur/1000)}' /tmp/neovim_lua_profile.json

# Total time per function name (aggregated)
jq '[.[] | select(.ph == "X")] | group_by(.name) | map({name: .[0].name, total_ms: ([.[].dur] | add / 1000), calls: length}) | sort_by(-.total_ms) | .[0:20]' /tmp/neovim_lua_profile.json
```

Key files: the `profile_env` block near top of `init.lua` (early-init bootstrap), `lua/plugins/misc.lua` `stevearc/profile.nvim` spec (plugin + `:ToggleProfile` command).
