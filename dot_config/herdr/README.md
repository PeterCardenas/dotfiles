# Herdr 0.9.1 configuration contract

Herdr 0.9.1 is installed from `~/.local/bin/herdr`; the canonical config is
installed at `~/.config/herdr/config.toml`. `HERDR_CONFIG_PATH` is supported.
Validation is isolated with both `HOME`/`XDG_CONFIG_HOME` and the override.

## Active configuration

Herdr's prefix is **Ctrl-B** (`ctrl+b`), matching tmux. The explicit keymap
also mirrors tmux where Herdr has an equivalent: `prefix+c/,/p/n/1..9/&/[` for
tabs and copy mode, `prefix+h/j/k/l` plus arrows for pane focus,
`prefix+o/;/%/\"/x/r` for pane cycling, last-pane, splitting, closing, and
resizing, both `prefix+z` and `prefix+ctrl+z` for zooming, `prefix+d` to detach,
with `prefix+w` for workspace navigation and `ctrl+f` for an 80% searchable
spaces-and-agents popup. Herdr-only actions remain on non-tmux chords.

The desktop tab bar has one mandatory status command:
`~/.config/tmux/scripts/status_metrics.sh --format herdr --short`. The collector
first produces a versioned colored-run protocol (`--format protocol`), then
renders that same model as tmux styles, GNOME-terminal ANSI, or Herdr text.
Herdr 0.9.1 deliberately strips terminal control sequences from command status
output and exposes no per-command-run color field, so its text, icons, ordering,
and spacing match while per-run colors cannot. The `tokyo-night` Herdr theme
keeps the surrounding bar palette aligned with tmux. Herdr runs the command
every 10 seconds with a 25-second command timeout; this contract test also
enforces a 30-second test timeout and nonempty plain output. Entries are
separated by ` | `.

`agentic.nvim` reports its aggregate prompted-session lifecycle directly from
Neovim to the enclosing `HERDR_PANE_ID` as `working` or `idle`, and releases the
authority on suspend/exit. The active Agentic session's generated title renames
the enclosing `HERDR_WORKSPACE_ID` only when it is a linked-worktree workspace;
switching Neovim tabs reapplies that tab's existing title. Primary and non-Git
workspaces retain their labels. Herdr keeps renamed workspaces in their existing
Git worktree group because renaming changes only the label. This is
provider-independent and
covers embedded ACP providers that Herdr cannot detect as foreground terminal
agents. The installed Pi/Claude/Codex/OpenCode/Cursor integrations still cover
those harnesses when they run as standalone foreground processes; they are not
the authority for ACP children hosted inside Neovim.

`ctrl+f` opens an fzf popup modeled on the tmux `manage_sessions` picker. It
searches both Space and Agent rows, previews the selected target's pane, and
focuses the selected workspace or agent on Enter. `prefix+w` retains Herdr's
native workspace navigation. In a linked-worktree workspace, `prefix+shift+g`
asks for a branch name and creates a focused sibling worktree from the remote's
default branch, falling back to local `main` or `master` when `origin/HEAD` is
unavailable. `prefix+shift+d` asks for confirmation, removes the checkout when
the active workspace is a linked worktree, and otherwise performs a normal
workspace close. Refused dirty-worktree removal requires a second explicit
confirmation before retrying with `--force`.

## 0.9.1 support matrix

- CPU/disk/RAM status: **SUPPORTED / VALIDATED**.
- Cursor status: **SUPPORTED / VALIDATED**.
- Current-directory following and workspace switching: **SUPPORTED**.
- Navigation: **SUPPORTED**. Native Neovim navigation is
  installed by the canonical run-onchange installer, pinned to reviewed MIT
  commit `79679dacc791f70fc34de8b29a3cf9706c0f5b2f`.
- Direct `ctrl+h/j/k/l` bindings use `~/.local/bin/herdr-navigate`, which preserves
  Vim split navigation and clears pane zoom immediately before crossing into another
  Herdr pane. The `prefix+h/j/k/l` bindings are an explicit escape hatch for forced
  navigation with Herdr's native focus controls. There is no fallback path.
- Layout, focus, and cwds: **SUPPORTED NATIVELY** by Herdr session snapshots;
  autosave is part of the native session behavior.
- Persistence: **SUPPORTED NATIVELY** by session snapshots.
- Detach keeps running processes. A full Herdr restart restores the session
  shape and cwds, not processes.
- `pane_history = false`: **SUPPORTED** policy; no screen replay is configured.
- `resume_agents_on_restore = false`: agent resume remains excluded.
- Native agent integrations: **SUPPORTED / VALIDATED** where installed. Current installed integration versions: pi v9, claude v10, codex v8, opencode v12, cursor v1.
- Plugins: **SUPPORTED** for navigation and visible-buffer jumping.
  `vim-herdr-navigation` is pinned to reviewed MIT commit
  `79679dacc791f70fc34de8b29a3cf9706c0f5b2f`. `herdr-leap` replaces
  `roy2220/easyjump.tmux` on `prefix+s` in its default one-pick jump mode and is
  pinned to reviewed MIT commit `be238808187636a080b46c547b95cbac9ee9988e`
  (version `0.2.1`). `herdr plugin list --json` reports each plugin's matching
  `requested_ref`, `resolved_commit`, version, enabled state, and actions.
  Installers require an explicit `--ref` commit and `-y`; no plugin code is
  vendored.
- Local mouse selection to clipboard write: **SUPPORTED / CONFIGURED** by
  Herdr's native `mouse_capture = true` and `copy_on_select = true` settings.
  ordinary paste remains terminal-native.
- remote image paste via Herdr remote attach is documented, but it is not
  enabled or validated here.
- Full local/SSH bidirectional text synchronization remains **UNVERIFIED / BLOCKED**
  pending a named remote target. No OSC52 fallback is configured; this is not a
  claim of full clipboard completion.
- TUI verification: CPU/disk/RAM rendering is visually verified. Cursor
  rendering is command-validated, not visually captured in the isolated HOME.
- Ghostty outer-split synchronization remains explicitly unresolved.
- Full SSH text clipboard remains explicitly unresolved.

Fish exposes `SSH_AUTH_SOCK` through a stable per-host path under `~/.ssh`.
Before entering Herdr, an interactive shell retargets that path to the current
inherited or forwarded agent socket. Herdr panes keep the stable path, so a new
SSH connection can replace the backing socket without restarting pane shells.
When no live inherited agent exists, fish starts one at the stable path. This is
the same indirection used for persistent tmux sessions; Herdr 0.9.1 does not
natively refresh client environment variables in its long-lived server.

Fish applies the same bridge to `SSH_CONNECTION`. The `herdr` fish wrapper
records the attaching shell's value in `~/.ssh/ssh-connection.$hostname`, or
removes that state for a local attach. Persistent Herdr shells load it at startup
and before every command, so a newly attached SSH client updates existing panes
without restarting their shells.

Fish shells discard an inherited `TMUX`/`TMUX_PANE` pair only when the
referenced tmux socket is already gone. This prevents commands and prompt hooks
from repeatedly trying a stale migration/test socket while preserving live
nested tmux sessions.

The configuration intentionally contains no tmux fallback, no external picker,
no process replay, no agent replay, or screen replay. Native integrations use
no fallback path.
