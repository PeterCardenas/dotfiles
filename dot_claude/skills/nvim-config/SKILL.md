---
name: nvim-config
description: Use when editing, debugging, or testing Neovim configuration or plugins. Triggers when working with nvim/neovim config files, lua plugin config, lazy.nvim plugins, LSP setup, treesitter, keymaps, or anything under nvim_conf or ~/.config/nvim.
---

# Neovim Config Guidelines

## Editing

- Edit chezmoi-managed source paths in this repository, not runtime targets such as `~/.config/nvim` or `~/.claude`; do not edit generated targets directly.
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
- When changing agentic.nvim behavior that is supposed to steer the agent, test a real model turn in tmux with the actual Neovim config. UI-only evidence such as `:messages`, notifications, or deterministic harnesses is not enough; verify the live agent observed the feedback and changed its next action.
- For hook feedback that should influence agentic.nvim, prefer a red/green check: first prove the agent would take the wrong follow-up without agent-visible feedback, then prove the live model skips that follow-up after receiving the hook context.
- Keep live model tests scoped to harmless files and prompts, and report exactly what data was sent to the model. Do not include secrets or broad repo context in the prompt.
- For experimental features, implement behind an env var config flag, test thoroughly, then remove the flag once verified.
- Treat every tmux test session as disposable. Clean it before create, clean it again when done, and verify the cleanup succeeded before you move on.
- Launch test instances with `-i NONE`. Disposable tests must not read or write the user's ShaDa file.
- Exit Neovim with `:qa!` before killing its tmux session. Abruptly killing live Neovim instances can leave ShaDa temporary files behind; use `tmux kill-session` only as a timed-out fallback.

### Launching tmux for testing

**Prefer a disposable session lifecycle over ad hoc commands:**
```bash
session="agentic-nvim-$$"
cleanup() {
  tmux has-session -t "$session" 2>/dev/null || return
  tmux send-keys -t "$session" Escape ':qa!' Enter
  for _ in $(seq 1 70); do
    tmux has-session -t "$session" 2>/dev/null || return
    sleep 0.1
  done
  tmux kill-session -t "$session" 2>/dev/null || true
}
tmux kill-session -t "$session" 2>/dev/null || true
trap cleanup EXIT INT TERM

tmux new-session -d -s "$session" -x 200 -y 50 "nvim -i NONE 2>&1; sleep 5"
# ... tmux send-keys / capture-pane against "$session" ...

cleanup
trap - EXIT INT TERM
tmux has-session -t "$session" 2>/dev/null && exit 1
```
- Pair session creation and cleanup in the same shell snippet whenever possible. Do not rely on remembering to kill the session later.
- Use a unique name every time. Avoid reusable names like `nvim_test` or stable prefixes like `agentic-tool-*` that tend to linger and collide.

**Create a detached session with fixed dimensions:**
```bash
tmux new-session -d -s <session-name> -x 200 -y 50 "nvim -i NONE <args> 2>&1; sleep 5"
```
- Always detach (`-d`) — never attach interactively.
- Make the session name unique to avoid conflicts with other agents.
- Always set dimensions (`-x 200 -y 50`) so capture-pane output is consistent and wide enough to avoid wrapping.
- The command string runs inside the session. Append `; sleep 5` to keep the session alive after nvim exits for output capture.

**Clean up stale sessions before creating:**
```bash
tmux kill-session -t <name> 2>/dev/null || true
tmux new-session -d -s <name> -x 200 -y 50 "nvim -i NONE 2>&1; sleep 5"
```

**Launching**

Send-keys — create the session first, then send commands:
   ```bash
   session="agentic-nvim-$$"
   tmux kill-session -t "$session" 2>/dev/null || true
   tmux new-session -d -s "$session" -x 200 -y 50
   tmux send-keys -t "$session" "nvim -i NONE /tmp/test.lua" Enter
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
tmux new-session -d -s nvim_prof -x 200 -y 50 "NVIM_PROFILE=start nvim -i NONE 2>&1; sleep 5"
```

**Always clean up when done:**
```bash
tmux send-keys -t <name> Escape ':qa!' Enter
for _ in $(seq 1 70); do
  tmux has-session -t <name> 2>/dev/null || break
  sleep 0.1
done
tmux kill-session -t <name> 2>/dev/null || true
tmux has-session -t <name> 2>/dev/null && exit 1
```
The final `kill-session` is fallback cleanup after Neovim had time to exit, not the normal exit path.

### Common tmux pitfalls

**Always create a new session — never add windows to existing sessions.**
`tmux new-window -t <existing-session>` fails with `create window failed: index in use` because the default target index is occupied. Even with `-a` or named windows (`-n`), targeting windows by name (`-t session:windowname`) is unreliable. Just create a fresh session — it's simpler and always works.

**Use `; ` not `||` for kill-before-create.**
```bash
# WRONG — kill only runs on failure, then second new-session also fails
tmux new-session -d -s test ... 2>/dev/null || tmux kill-session -t test && tmux new-session -d -s test ...

# RIGHT — remove a stale pre-existing session, then create a ShaDa-isolated test
# After testing, exit Neovim gracefully as shown above before fallback cleanup.
tmux kill-session -t test 2>/dev/null; tmux new-session -d -s test -x 200 -y 50 "nvim -i NONE"
```

**Do not leave cleanup to memory.**
If a repro needs multiple tmux variants, give each one its own disposable session name and kill it before starting the next variant. Before finishing, verify there are no leftover test sessions from your run.

**If `capture-pane` returns stale content** (e.g. splash screen after sending commands), sleep longer. LSP, Octo, and plugin-heavy operations need 8–15s, not 3.

## Profiling

For the `profile.nvim` path, `NVIM_PROFILE` must be set before Neovim starts. Without it, `profile.nvim` and `:ToggleProfile` are not configured; setting it inside Neovim cannot enable them.

Launch with:

- `NVIM_PROFILE=1 nvim` — instruments modules; use `:ToggleProfile` to start/stop, then choose the JSON output path.
- `NVIM_PROFILE=start nvim` — starts recording and registers a one-shot `VeryLazy` autocmd that invokes `:ToggleProfile` to stop and prompt for output; this does not promise a complete startup lifecycle.

Set `NVIM_PROFILE` in the shell before launch (or `export NVIM_PROFILE=1`/`start`); relaunch after changing it. Traces are Chrome Trace Event JSON, e.g. `/tmp/neovim_lua_profile.json`.

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
