# Terminal-browser shortcuts

`shortcuts.json` is managed at `~/.config/terminal-browser/shortcuts.json`.
It targets terminal-browser v0.13.4's configurable commands. Settings such as
telemetry and rendering remain at their defaults; this change only owns shortcuts.

The reference is the local Zen release profile's `zen-keyboard-shortcuts.json`:
new tab stays **Ctrl-P** (not Ctrl-T), close tab **Ctrl-W**, reload **Ctrl-R / F5**,
and back/forward **Ctrl-[ / Ctrl-]**. The remaining actions use function keys:
Alt does not work reliably in this terminal setup, Super may be intercepted by
the desktop, and many Ctrl-Shift combinations belong to Ghostty.

- **F2**: command palette; **Shift-F2**: send to agent.
- **F3**: find in page.
- **F4**: browser settings.
- **F5**: reload (also Ctrl-R).
- **F6**: address bar, a standard browser alternative to Ctrl-L.
- **F7 / F8 / F9**: reset / decrease / increase page zoom.
  Add Shift to change browser UI zoom instead.
- **F10**: quit browser, not the terminal.
- **F11**: record page (not Zen's fullscreen action).
- **F12**: devtools; **Shift-F12**: web console.

Terminal bindings take precedence, so exact Zen parity is intentionally limited.
Herdr keeps Ctrl-H/J/K/L for pane navigation, Ctrl-F for the workspace switcher,
and Ctrl-B as its prefix. Ghostty keeps Ctrl-Q to quit, Ctrl-, for config,
Ctrl-Shift-F for terminal search, Ctrl-Shift-I for its inspector, and Ctrl-=/-/0
for font sizing. The browser has no Alt or Super bindings, and no Ctrl-Shift
bindings that need extended keyboard-protocol support. Shift-function keys are
only needed for secondary actions.

Zen features without a configurable terminal-browser command (workspace switching,
numbered tabs, restore closed tab, split views, and so on) are not emulated.
An unassigned Zen gesture is not a promise that terminal-browser implements it.
Ghostty's terminal tab navigation stays unchanged.

Run the source and installed-Ghostty collision checks from the repo root:

```sh
python3 -m unittest test_terminal_browser_config -v
```

References:
- `../ghostty/config`: explicit terminal bindings (Ghostty defaults also apply).
- `../herdr/config.toml`: multiplexer prefix, pane navigation, workspace switcher.
- `terminal-browser config list`: effective browser shortcuts and validation.
