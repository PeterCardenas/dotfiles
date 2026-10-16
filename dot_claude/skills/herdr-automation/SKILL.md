---
name: herdr-automation
description: Prefer this for disposable interactive CLI/TUI automation and testing (Neovim, lazygit, fzf, k9s, or Herdr itself) in an isolated Herdr session. Test apps with native Herdr pane APIs only; use the explicit --visual mode and private tmux transport only to test Herdr's own rendered UI. Herdr runs with private state while pane apps use the user's real HOME and config. Owns creation, input, output inspection, and cleanup. Use instead of tmux-automation except for tmux-specific tests or when Herdr is unavailable; never control the user's existing Herdr session, panes, or agents.
---

# Herdr automation

Use `scripts/herdr_automation.py` as the sole lifecycle owner for disposable Herdr experiments. Choose the mode by **what is being tested**, not whether the application is a TUI:

- **Apps inside Herdr (default):** `create NAME` starts a headless Herdr server, without tmux. Launch and drive Neovim, lazygit, fzf, agents, and other apps through native Herdr pane APIs. Use the wrapper's explicit `capture NAME PANE` command for agent-facing output; it defaults to the latest 200 unwrapped lines in plain text. Choose `--format ansi` only when terminal color/styling matters, or `--source visible|recent|detection` and `--lines N` when those capture boundaries are needed. An app screen assertion does not require visual mode.
- **Herdr's own rendered UI:** `create NAME --visual` hosts the Herdr client in a private tmux terminal. Use this only for Herdr sidebar/rendering, outer-client keybindings, mouse interactions, or full-client resize/visual assertions. Native pane APIs do not exercise that outer UI.

Both modes use a private HOME/XDG tree, exact named Herdr session, and private socket. New pane shells restore the account's real HOME/XDG paths, so Neovim, Pi, and other pane apps read and **may write** normal user config, caches, and credentials. Only Herdr's session is isolated—not the app filesystem or model context. Do not claim that prompts, downloads, plugin updates, or agent sessions are sandboxed. The launcher leaves `HERDR_CONFIG_PATH` and `HERDR_SOCKET_PATH` pointed at the private session so pane-local Herdr commands remain scoped. No credential files are copied.

This skill is separate from both neighboring tools:

- Use the built-in **Herdr** skill to control the user's existing live Herdr session.
- Prefer herdr-automation for disposable CLI/TUI workflows when normal user app state is acceptable.
- Use **tmux-automation** for tmux-specific behavior or when Herdr is unavailable. Neither tool provides full filesystem isolation; request a disposable VM when user files must stay untouched.

Do not invoke the built-in Herdr control workflow or tmux-automation directly for an experiment owned by this controller. Keeping one lifecycle owner makes cleanup reliable.

## Resolve the script

Set the script from the directory containing this loaded `SKILL.md`:

```sh
skill_dir=/absolute/path/to/herdr-automation; script="$skill_dir/scripts/herdr_automation.py"
```

The chezmoi source is named `executable_herdr_automation.py`, but the installed skill path is `herdr_automation.py`. Use the installed path above; do not guess the source filename.

## Lifecycle

### 1. Create once in the appropriate mode

For app testing, use the default without tmux:

```sh
python3 "$script" create app-repro
```

For Herdr UI testing, opt in explicitly:

```sh
python3 "$script" create ui-repro --visual
```

Either mode accepts `--config /absolute/path/config.toml`. Without `--config`, the controller copies the current canonical Herdr config into the private session; it never writes the original.

`create` prints JSON with the exact `session_name`, `mode`, private Herdr `home`, and real `pane_home`. In app mode, `transport_name`, `pane_id`, and `tmux_runtime` are null: there is no tmux transport. In visual mode, `pane_id` identifies the **outer tmux pane**, not an application pane inside Herdr. Parse IDs rather than predicting them.

### 2. Control the exact owned Herdr session

Run every Herdr API/CLI command through `herdr`; the controller supplies the private environment and exact session selector:

```sh
python3 "$script" herdr app-repro -- workspace list
python3 "$script" herdr app-repro -- pane list
python3 "$script" capture app-repro w1:p1
```

If no workspace exists, create one with `herdr NAME -- workspace create --cwd /absolute/path`. Parse its output and `pane list` to obtain the app pane ID. Do not run plain `herdr workspace ...` during the experiment: ambient commands can target the user's default session.

### 3a. App testing: native pane input and output only

Use the app pane ID returned by Herdr, not an outer tmux ID. For example, after assigning that ID to `pane`:

```sh
python3 "$script" herdr app-repro -- pane run "$pane" nvim -i NONE
python3 "$script" herdr app-repro -- pane send-keys "$pane" esc
python3 "$script" herdr app-repro -- pane send-text "$pane" ":echo 'APP_READY'"
python3 "$script" herdr app-repro -- pane send-keys "$pane" enter
python3 "$script" --timeout 12 herdr app-repro -- pane wait-output --match APP_READY --source visible --timeout 10000 "$pane"
python3 "$script" herdr app-repro -- pane read --source visible "$pane"
```

Keep waits finite at both layers: `pane wait-output --timeout` is in milliseconds, and the controller's global `--timeout` is in seconds. Keep the separate read after a successful wait when screen contents are evidence. Use native `pane resize`, `send-text`, `send-keys`, `read`, and `wait-output` as needed; check subcommand help for exact syntax. The wrapper `capture` command is a concise agent-facing shortcut over `herdr pane read`; it emits rendered text, not structured content or a screenshot. `--format json` is not supported. Herdr has no pane screenshot/image capture in this headless workflow: do not claim pixel, image, or graphical evidence. Use `herdr NAME -- api snapshot` separately for structured session/layout metadata, not screen contents. Do not create tmux or use `terminal`/`wait-screen` for app testing. Those actions reject app-mode sessions.

### 3b. Herdr visual testing: private terminal transport

Only for a session created with `--visual`, send outer-client input and capture the Herdr UI through `terminal`. Assign the returned outer tmux `pane_id` to `transport_pane`:

```sh
python3 "$script" terminal ui-repro -- send-keys -t "$transport_pane" C-b w
python3 "$script" wait-screen --regex 'expected text' --duration 0.2 --wait-timeout 10 ui-repro
python3 "$script" terminal ui-repro -- capture-pane -p -t "$transport_pane"
```

Use the keybinding under test rather than assuming the example matches the copied config. Keep the separate capture after a successful wait: `wait-screen` proves readiness; `capture-pane` records it. Herdr pane commands remain available through `herdr ui-repro -- ...` for fixture setup.

**Tmux isolation is the same implementation as tmux-automation, not the same live session.** The controller delegates transport creation, commands, waits, and cleanup to the adjacent tmux-automation script, with a distinct runtime root at `<owned Herdr state>/tmux-runtime` and name `herdr-<NAME>`. That wrapper owns a private `tmux.sock`, passes `tmux -S <exact socket>`, removes ambient `TMUX`/`TMUX_PANE`, validates private ownership/metadata, rejects caller socket overrides, and uses locked, bounded operations with verified cleanup. It does not attach to your existing tmux or another automation session. The transport uses `-f /dev/null` because user tmux config is not under test. Never invoke the tmux-automation lifecycle separately for this transport.

### 4. Inspect ownership

```sh
python3 "$script" info app-repro
```

`info` performs a Herdr health check. Metadata alone is not treated as a live session. Headless startup diagnostics are saved to the owned state's `server.log`.

### 5. Always close

Gracefully exit the app through native pane APIs when app-specific shutdown is required, then run:

```sh
python3 "$script" close app-repro
```

Use the corresponding name for visual experiments. `close` stops and deletes only the recorded named Herdr session, closes its private tmux transport **only in visual mode**, and removes private state after verified commands succeed. It also supports cleanup of older sessions created by the always-tmux controller. It is idempotent when state is absent. After stopping owned resources it writes a private cleanup marker outside the removable tree; if removal fails (for example on read-only Go module directories), correct the private filesystem issue and retry the same `close` command. That marker authorizes cleanup only for the exact owned name and path; do not create one for legacy or unknown state.

Run `close` in a separate tool call even after a failed wait or command. If close fails, report the error and preserve private state as evidence; do not fall back to broad `pkill`, default-session commands, or `/tmp` scans.

## Safety boundaries

- Never pass `default` as an automation name or operate on the default Herdr session.
- Never reuse a name whose state directory already exists; inspect or close it first.
- Never close a workspace, pane, or session not created by this controller.
- Never broadly remove Herdr state or kill Herdr processes by name.
- Keep timeouts finite.
- Prefer controller JSON and Herdr JSON responses over sidebar labels or guessed IDs.
- A timeout does not prove an input was not delivered. Read/capture and inspect before retrying.
- Keep automation names at 16 safe ASCII characters or fewer so Herdr's Unix socket paths stay portable.
- The controller owns a distinct `herdr-automation` runtime root and `ha-<NAME>` Herdr session namespace in both modes. Only visual mode depends on tmux-automation.
