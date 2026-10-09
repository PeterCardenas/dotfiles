---
name: herdr-automation
description: Prefer this for disposable interactive CLI/TUI automation and testing (Neovim, lazygit, fzf, k9s, or Herdr itself) in an isolated Herdr session. Herdr runs with private state while pane apps use the user's real HOME and config. Owns creation, keyboard/mouse input, capture, and cleanup. Use instead of tmux-automation except for tmux-specific tests or when Herdr is unavailable; never control the user's existing Herdr session, panes, or agents.
---

# Herdr automation

Use `scripts/herdr_automation.py` as the sole lifecycle owner for disposable Herdr experiments. The Herdr server/client run under a private HOME/XDG tree with an exact named session and private socket; the TUI runs in a private tmux transport. New pane shells use a private launcher that restores the account's real HOME/XDG paths, so Neovim, Pi, and other pane apps read and **may write** normal user config, caches, and credentials. Only Herdr's session is isolated—not the app filesystem or model context. Do not claim that prompts, downloads, plugin updates, or agent sessions are sandboxed. The launcher leaves `HERDR_CONFIG_PATH` and `HERDR_SOCKET_PATH` pointed at the private session so pane-local Herdr commands remain scoped. No credential files are copied.

This skill is separate from both neighboring tools:

- Use the built-in **Herdr** skill to control the user's existing live Herdr session.
- Prefer herdr-automation for disposable CLI/TUI workflows, including Neovim, when normal user app state is acceptable.
- Use **tmux-automation** for tmux-specific behavior or when Herdr is unavailable. Neither tool provides full filesystem isolation; request a disposable VM when user files must stay untouched.

Never use the built-in Herdr control workflow or invoke tmux-automation directly after this skill triggers. Doing so loses the ownership boundary that makes cleanup reliable.

## Resolve the script

Set the script from the directory containing this loaded `SKILL.md`:

```sh
skill_dir=/absolute/path/to/herdr-automation; script="$skill_dir/scripts/herdr_automation.py"
```

The chezmoi source is named `executable_herdr_automation.py`, but the installed skill path is `herdr_automation.py`. Use the installed path above; do not guess the source filename.

## Lifecycle

### 1. Create

Choose one safe, task-specific name and create exactly once:

```sh
python3 "$script" create resize-repro
```

`create` prints JSON containing the exact `session_name`, private Herdr `home`, real `pane_home`, transport `pane_id`, and `transport_name`. Parse those values rather than predicting Herdr workspace or pane IDs.

To test a specific Herdr configuration:

```sh
python3 "$script" create resize-repro --config /absolute/path/config.toml
```

Without `--config`, the controller copies the current canonical Herdr config into the private session. It never writes the original.

### 2. Control Herdr by exact session

Run Herdr API/CLI commands through `herdr`; the controller supplies the private environment and exact session selector:

```sh
python3 "$script" herdr resize-repro -- workspace list
python3 "$script" herdr resize-repro -- pane list
```

Do not run plain `herdr workspace ...` during the experiment. Ambient commands can target the user's default session.

### 3. Drive or inspect the TUI

Use `terminal` for raw terminal interaction inside the owned transport:

```sh
python3 "$script" terminal resize-repro -- send-keys -t %0 C-b w
python3 "$script" terminal resize-repro -- capture-pane -p -t %0
```

Use `wait-screen` for bounded readiness instead of sleeps:

```sh
python3 "$script" wait-screen --regex 'expected text' --duration 0.2 --wait-timeout 10 resize-repro
python3 "$script" terminal resize-repro -- capture-pane -p -t %0
```

Keep the separate capture after a successful wait when screen contents are evidence. `wait-screen` proves readiness; `capture-pane` records it.

`terminal` intentionally exposes tmux commands because tmux is only the private terminal transport. For CLI/TUI tests, start the application inside a pane of the owned Herdr session and drive it through this wrapper, not a separate tmux server. The automation remains a Herdr lifecycle, and callers must not invoke the tmux-automation script directly.

### 4. Inspect ownership

```sh
python3 "$script" info resize-repro
```

`info` performs a Herdr health check. Metadata alone is not treated as a live session.

### 5. Always close

Gracefully exit the application running inside a Herdr pane when the experiment requires application-specific shutdown, then run:

```sh
python3 "$script" close resize-repro
```

`close` targets only the recorded named Herdr session, stops it, deletes it, closes the private tmux transport, and removes its private state after verified commands succeed. It is idempotent when state is already absent. After stopping owned resources it writes a private cleanup marker outside the removable tree; if removal fails (for example on read-only Go module directories), correct the private filesystem issue and retry the same `close` command. That marker authorizes cleanup only for the exact owned name and path; do not create a marker for legacy or unknown state.

Run `close` in a separate tool call even after a failed wait or command. If close fails, report the error and preserve the private state as evidence; do not fall back to broad `pkill`, default-session commands, or `/tmp` scans.

## Safety boundaries

- Never pass `default` as an automation name or operate on the default Herdr session.
- Never reuse a name whose state directory already exists; inspect or close it first.
- Never close a workspace, pane, or session not created by this controller.
- Never broadly remove Herdr state or kill Herdr processes by name.
- Keep timeouts finite.
- Prefer controller JSON and Herdr JSON responses over sidebar labels or guessed IDs.
- A timeout does not prove an input was not delivered. Capture and inspect before retrying.
- Keep automation names at 16 safe ASCII characters or fewer so Herdr's Unix socket paths stay portable.
- The controller depends on the adjacent tmux-automation transport implementation, but owns a distinct `herdr-automation` runtime root and `ha-<name>` Herdr session namespace.
