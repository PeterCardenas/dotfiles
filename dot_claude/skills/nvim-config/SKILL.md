---
name: nvim-config
description: Use when editing, debugging, or testing Neovim configuration or plugins. Triggers when working with nvim/neovim config files, lua plugin config, lazy.nvim plugins, LSP setup, treesitter, keymaps, or anything under nvim_conf or ~/.config/nvim.
---

# Neovim Config Guidelines

## Editing

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
