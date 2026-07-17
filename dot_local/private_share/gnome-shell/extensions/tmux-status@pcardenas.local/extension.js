import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';

const REFRESH_SECONDS = 2;

// GNOME 46/Wayland refreshes command output live, but extension JS changes
// require logging out and back in; ReloadExtension is deprecated/non-working.
const TmuxStatusIndicator = GObject.registerClass(
class TmuxStatusIndicator extends PanelMenu.Button {
  _init(commandArgs) {
    super._init(0.0, 'Tmux Status');

    this._commandArgs = commandArgs;
    this._refreshing = false;
    this._timeoutId = 0;
    this._label = new St.Label({
      text: 'tmux status',
      y_align: Clutter.ActorAlign.CENTER,
      y_expand: true,
    });
    this.add_child(this._label);

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
      this._setStatusMarkup('tmux status unavailable');
      this._refreshing = false;
      return;
    }

    proc.communicate_utf8_async(null, null, (subprocess, result) => {
      try {
        const [, stdout] = subprocess.communicate_utf8_finish(result);
        this._setStatusMarkup(stdout.trim() || 'tmux status unavailable');
      } catch (error) {
        this._setStatusMarkup('tmux status unavailable');
      } finally {
        this._refreshing = false;
      }
    });
  }

  _setStatusMarkup(statusMarkup) {
    this._label.clutter_text.set_markup(statusMarkup);
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

    this._indicator = new TmuxStatusIndicator([command, '--markup']);
    Main.panel.addToStatusArea(this.uuid, this._indicator, 0, 'right');
  }

  disable() {
    this._indicator?.destroy();
    this._indicator = null;
  }
}
