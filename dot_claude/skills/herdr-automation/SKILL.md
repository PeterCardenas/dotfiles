---
name: herdr-automation
description: Create, drive, inspect, and reliably clean up disposable isolated Herdr sessions for reproduction, benchmarking, E2E testing, configuration validation, or Herdr TUI experiments. Use this instead of the built-in Herdr skill whenever the task asks for an isolated, temporary, disposable, test, benchmark, or reproduction Herdr session. Use this instead of tmux-automation when Herdr itself is the application under test. Do not use it to control the user's existing Herdr session, workspace, panes, or agents.
---

# Herdr automation

Use `scripts/herdr_automation.py` as the sole lifecycle owner for disposable Herdr experiments. It creates a private HOME/XDG tree, removes inherited Herdr and tmux context, selects an exact named Herdr session, hosts the TUI in a private tmux transport, and owns stop/delete/transport cleanup.

This skill is separate from both neighboring tools:

- Use the built-in **Herdr** skill to control the user's existing live Herdr session.
- Use **tmux-automation** for disposable TUIs other than Herdr.
- Use **herdr-automation** when Herdr itself needs an isolated session.

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

`create` prints JSON containing the exact `session_name`, private `home`, transport `pane_id`, and `transport_name`. Parse those values rather than predicting Herdr workspace or pane IDs.

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

`terminal` intentionally exposes tmux commands because tmux is only the private terminal transport. The automation remains a Herdr lifecycle, and callers must not invoke the tmux-automation script directly.

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

`close` targets only the recorded named Herdr session, stops it, deletes it, closes the private tmux transport, and removes its private state after verified commands succeed. It is idempotent when state is already absent.

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
