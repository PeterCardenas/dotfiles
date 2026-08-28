---
name: nvim-config
description: Use when editing, debugging, or testing Neovim configuration or plugins. Triggers when working with nvim/neovim config files, lua plugin config, lazy.nvim plugins, LSP setup, treesitter, keymaps, or anything under nvim_conf or ~/.config/nvim.
---

## Delegation

For disposable interactive terminal workflows, delegate lifecycle and raw tmux operations to the local skill at `../tmux-automation/SKILL.md`. This skill owns Neovim configuration and validation; tmux-automation owns private server safety, IDs, waiting, capture, and cleanup.

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

- Verify changes by opening a new wrapper-owned private tmux server session and launching nvim with the actual config. Never just read code and propose changes as done.
- Test both the broken state (without the fix) and the fixed state to confirm the fix actually addresses the issue.
- When changing agentic.nvim behavior that is supposed to steer the agent, test a real model turn in tmux with the actual Neovim config. UI-only evidence such as `:messages`, notifications, or deterministic harnesses is not enough; verify the live agent observed the feedback and changed its next action.
- For hook feedback that should influence agentic.nvim, prefer a red/green check: first prove the agent would take the wrong follow-up without agent-visible feedback, then prove the live model skips that follow-up after receiving the hook context.
- Keep live model tests scoped to harmless files and prompts, and report exactly what data was sent to the model. Do not include secrets or broad repo context in the prompt.
- For experimental features, implement behind an env var config flag, test thoroughly, then remove the flag once verified.
- Treat every tmux test session as disposable: use a fresh runtime-root name; recover recognized state with `close`, and preserve unknown state.
- Launch test instances with `-i NONE`. Disposable tests must not read or write the user's ShaDa file.
- Exit Neovim with `:qa!` before killing its tmux session. Abruptly killing live Neovim instances can leave ShaDa temporary files behind; use `tmux kill-session` only as a timed-out fallback.

### Launching Neovim for testing

Use the `tmux-automation` skill for disposable TUI lifecycle and raw tmux commands. It provides a private socket, bounded cleanup, and stable pane metadata; do not administer a user's existing tmux server. Always launch disposable Neovim instances with `-i NONE`, use the real config when behavior depends on it, and preserve red/green checks and real model turns when semantically required. Exit with `Escape`, `:qa!`, `Enter` before wrapper cleanup.

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
