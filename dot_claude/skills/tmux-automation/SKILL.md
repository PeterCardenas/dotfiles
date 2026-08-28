---
name: tmux-automation
description: Use whenever automating or testing a disposable interactive terminal UI/TUI (including Neovim, lazygit, k9s, fzf, curses, or ncurses) through a wrapper or isolated private tmux server, including observing or capturing its screen. Always use it for requests to inspect, attach, resize, rename, or kill an existing user tmux session so it can enforce the non-execution/refusal boundary; ordinary noninteractive commands and conceptual tmux explanations do not trigger it.
---

# tmux automation

Use `scripts/executable_tmux_automation.py` only for disposable terminal UI workflows. It owns an exact private socket under a `0700` runtime/state directory, uses an atomic metadata replacement while holding a per-name lock, bounded subprocesses, and removes ambient `TMUX` variables.

| Contract | Behavior |
|---|---|
| Root | `$XDG_RUNTIME_DIR/tmux-automation`; without it, `/tmp/tmux-automation-$UID` |
| Terminal | Every created server is fixed at 200x50 |
| Ownership | Root must be same-UID/private and marked by regular 0600 `.tmux-automation-root` containing `tmux-automation-root-v1`; existing state is never adopted |
| Output/status | `create`/`info` print JSON; `exec` passes stdout/stderr and tmux status; wrapper errors exit 2 |
| Timing/regex | `--timeout`, `--wait-timeout`, and `--duration` are finite and nonnegative; `--regex` must compile |
| Missing tmux | Report the executable failure and exit 2; never fall back to another server |
| Close evidence | Missing/invalid metadata or unverifiable shutdown preserves state; natural exit reports `fallback: false`, verified kill cleanup `true` |
 It protects against accidental/default-server use, not hostile same-UID processes explicitly selecting another socket.

The interface is intentionally tmux-like: `create NAME [-- tmux options/initial command]`, `exec NAME -- <raw tmux argv>`, `info NAME`, `wait NAME -- <raw tmux argv>`, and `close NAME`. `-f FILE` selects config (the default loads the user's config); `-S` and `-L` are always rejected before the command boundary. `wait` parses its options before NAME and polls bounded raw tmux commands with return-code/regex/stable-duration predicates and last-observation timeout diagnostics. `exec` passes commands, targets, options, payloads, output, and exit status through unchanged (except wrapper-owned `-S`/`-L` global socket selectors). A server can contain multiple sessions and panes. Names are bounded safe ASCII identifiers.

Working flow: run `create`, parse its JSON `pane_id`, use `exec` to launch and drive the requested TUI, use wrapper `wait` for a regex/stability objective, then run a separate `capture-pane` for evidence. Preserve the requested application or fixture category: do not substitute Neovim for a generic deterministic fixture. If no application is named, prefer the smallest deterministic interactive fixture that emits a known marker, accepts one documented quit input, and exits on its own. Send one literal command with `send-keys -l`, then Enter.

When the user requests exact or verbatim command evidence, record every fully expanded wrapper invocation and its relevant stdout/stderr in execution order; labels such as “create,” “send marker,” or “close” are not command evidence. Include enough output to verify the runtime root, parsed pane ID, wait predicate, separate capture, application-specific exit input, and `close` result.

After the application-specific graceful exit, call `close`; it performs the bounded natural-exit wait. Natural disappearance reports `fallback: false`, while required kill-server cleanup reports `fallback: true`. Raw tmux is allowed only through wrapper `exec` for this disposable lifecycle; never administer a real user session.

The Neovim example below demonstrates wrapper mechanics only; choose the application or fixture from the task rather than defaulting to Neovim.

Example:

Replace the example value with the absolute directory containing the loaded `SKILL.md`, then assign it before running the commands:
```sh
skill_dir=/absolute/path/to/tmux-automation; script="$skill_dir/scripts/executable_tmux_automation.py"
pane=$(python3 "$script" create nvim-test -- nvim -u NONE -i NONE | python3 -c 'import json,sys; print(json.load(sys.stdin)["pane_id"])')
python3 "$script" exec nvim-test -- send-keys -l -t "$pane" ":echo 'TMUX_AUTOMATION_READY'"; python3 "$script" exec nvim-test -- send-keys -t "$pane" Enter
python3 "$script" wait --regex 'TMUX_AUTOMATION_READY' --duration 0.2 --wait-timeout 3 nvim-test -- capture-pane -p -t "$pane"
python3 "$script" exec nvim-test -- capture-pane -p -t "$pane"
python3 "$script" exec nvim-test -- send-keys -t "$pane" Escape; python3 "$script" exec nvim-test -- send-keys -l -t "$pane" ':qa!'; python3 "$script" exec nvim-test -- send-keys -t "$pane" Enter
python3 "$script" close nvim-test
```

Raw tmux is allowed only as argv under wrapper `exec` for disposable automation. Same-UID hostile TOCTOU replacement is outside the threat model; symlink/type/owner/mode checks are fail-closed.

Use `-f /dev/null` in app-only tests to bypass hostile/user tmux configuration; retain production config when testing tmux configuration behavior. For Neovim, launch with `nvim -i NONE`, use the real config when required, wait on deterministic output/markers, capture evidence, exit with `Escape`, `:qa!`, `Enter`, then call `close`; `close` is the bounded natural-exit wait and kill-server is fallback cleanup.

Do not use this for administration of a real user's existing tmux session. Do not broadly scan `/tmp` or delete outside the wrapper-owned state directory. The wrapper does not use `atexit`, so persistent CLI state remains inspectable.
