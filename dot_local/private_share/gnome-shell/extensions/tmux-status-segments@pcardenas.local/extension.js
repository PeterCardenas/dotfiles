import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';

const REFRESH_SECONDS = 2;
const DEFAULT_COLOR = '#c0caf5';

// GNOME 46/Wayland refreshes command output live, but extension JS changes
// require logging out and back in; ReloadExtension is deprecated/non-working.
const TmuxStatusIndicator = GObject.registerClass(
class TmuxStatusIndicator extends PanelMenu.Button {
  _init(commandArgs) {
    super._init(0.0, 'Tmux Status');

    this._commandArgs = commandArgs;
    this._refreshing = false;
    this._timeoutId = 0;
    this._box = new St.BoxLayout({
      y_align: Clutter.ActorAlign.CENTER,
      y_expand: true,
    });
    this.add_child(this._box);
    this._setStatusText('tmux status', DEFAULT_COLOR);

    this._refresh();
    this._timeoutId = GLib.timeout_add_seconds(
      GLib.PRIORITY_DEFAULT,
      REFRESH_SECONDS,
      () => {
        this._refresh();
        return GLib.SOURCE_CONTINUE;
      },
    );
  }

  _refresh() {
    if (this._refreshing)
      return;

    this._refreshing = true;

    let proc;
    try {
      proc = Gio.Subprocess.new(
        this._commandArgs,
        Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE,
      );
    } catch (error) {
      this._setStatusText('tmux status unavailable', DEFAULT_COLOR);
      this._refreshing = false;
      return;
    }

    proc.communicate_utf8_async(null, null, (subprocess, result) => {
      try {
        const [, stdout] = subprocess.communicate_utf8_finish(result);
        this._setStatusSegments(stdout.trim());
      } catch (error) {
        this._setStatusText('tmux status unavailable', DEFAULT_COLOR);
      } finally {
        this._refreshing = false;
      }
    });
  }

  _clearStatus() {
    for (const child of this._box.get_children())
      child.destroy();
  }

  _addStatusText(statusText, color) {
    this._box.add_child(new St.Label({
      text: statusText,
      style: `color: ${color};`,
      y_align: Clutter.ActorAlign.CENTER,
      y_expand: true,
    }));
  }

  _setStatusText(statusText, color) {
    this._clearStatus();
    this._addStatusText(statusText, color);
  }

  _setStatusSegments(output) {
    if (!output) {
      this._setStatusText('tmux status unavailable', DEFAULT_COLOR);
      return;
    }

    this._clearStatus();
    for (const line of output.split('\n')) {
      const separatorIndex = line.indexOf('\t');
      if (separatorIndex === -1)
        continue;

      const color = line.slice(0, separatorIndex) || DEFAULT_COLOR;
      const text = line.slice(separatorIndex + 1);
      if (text)
        this._addStatusText(text, color);
    }

    if (this._box.get_children().length === 0)
      this._addStatusText('tmux status unavailable', DEFAULT_COLOR);
  }

  destroy() {
    if (this._timeoutId !== 0) {
      GLib.Source.remove(this._timeoutId);
      this._timeoutId = 0;
    }

    super.destroy();
  }
});

export default class TmuxStatusExtension extends Extension {
  enable() {
    const command = GLib.build_filenamev([
      GLib.get_home_dir(),
      '.local',
      'bin',
      'gnome-tmux-status',
    ]);

    this._indicator = new TmuxStatusIndicator([command, '--segments']);
    Main.panel.addToStatusArea(this.uuid, this._indicator, 0, 'right');
  }

  disable() {
    this._indicator?.destroy();
    this._indicator = null;
  }
}
