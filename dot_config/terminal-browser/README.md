# Terminal-browser shortcuts

`shortcuts.json` is managed at `~/.config/terminal-browser/shortcuts.json`.
It targets terminal-browser v0.13.4's configurable commands. Settings such as
telemetry and rendering remain at their defaults; this change only owns shortcuts.

The reference is the local Zen release profile's `zen-keyboard-shortcuts.json`:
new tab is **Ctrl-P** (not Ctrl-T), close tab **Ctrl-W**, address bar **Alt-D**,
reload **Ctrl-R / F5**, and back/forward **Alt-Left / Alt-Right** or **Ctrl-[ / Ctrl-]**.
The web console uses Zen's **Ctrl-Shift-K**.

Terminal bindings take precedence, so exact Zen parity is intentionally limited:

- **Alt-K**: command palette; Ctrl-K belongs to Herdr pane navigation.
- **Alt-F**: find in page; Ctrl-F belongs to Herdr's workspace switcher, and
  Ghostty consumes terminal-browser's default Ctrl-Shift-F for terminal search.
- **Alt-D** only: address bar; Ctrl-L belongs to Herdr pane navigation.
- **Alt-,**: browser settings; Ghostty consumes Ctrl-, for its own config.
- **F12** only: devtools; Ghostty consumes Ctrl-Shift-I for its inspector.
- **Alt-= / Alt-- / Alt-0**: page zoom; Ghostty consumes the Ctrl variants
  for font sizing. Add Shift to zoom the browser UI instead.
- **Alt-Q**: quit browser; Ctrl-Q belongs to Ghostty and would quit the terminal.
- **Alt-Shift-R**: record; leaves Zen's Ctrl-Shift-R reload-without-cache gesture free.
- **Alt-G**: send to agent; leaves Zen's Ctrl-G find-again gesture free.

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
