// SPDX-License-Identifier: GPL-2.0-or-later
// LocumView Layout: switch between Mac-style and Windows-style desktops from Quick Settings (changelog #23).
// Uses GNOME Shell's own extension manager (as the Extensions app does), so the switch is instant and saved
// per user. Dash to Dock and Dash to Panel conflict, so exactly one of them is enabled at a time.
import Gio from 'gi://Gio';
import GObject from 'gi://GObject';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {QuickMenuToggle, SystemIndicator} from 'resource:///org/gnome/shell/ui/quickSettings.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const DOCK = 'dash-to-dock@micxgx.gmail.com';
const PANEL = 'dash-to-panel@jderose9.github.com';

const MODES = {
    mac: {
        label: 'Mac style',
        detail: 'Dock at the bottom, window buttons on the left',
        enable: DOCK,
        disable: PANEL,
        buttons: 'close,minimize,maximize:appmenu',
    },
    windows: {
        label: 'Windows style',
        detail: 'Taskbar at the bottom, window buttons on the right',
        enable: PANEL,
        disable: DOCK,
        buttons: 'appmenu:minimize,maximize,close',
    },
};

const ICON = 'view-paged-symbolic';

const LayoutToggle = GObject.registerClass(
class LayoutToggle extends QuickMenuToggle {
    constructor() {
        super({title: 'Layout', iconName: ICON, toggleMode: false});

        this._shell = new Gio.Settings({schema_id: 'org.gnome.shell'});
        this._wm = new Gio.Settings({schema_id: 'org.gnome.desktop.wm.preferences'});

        this.menu.setHeader(ICON, 'Desktop layout', 'Choose how your desktop looks');
        this._items = {};
        for (const [id, mode] of Object.entries(MODES)) {
            const item = new PopupMenu.PopupMenuItem(`${mode.label}  ·  ${mode.detail}`);
            item.connect('activate', () => this._apply(id));
            this.menu.addMenuItem(item);
            this._items[id] = item;
        }

        // Clicking the tile itself flips to the other layout.
        this.connect('clicked', () => this._apply(this._current() === 'windows' ? 'mac' : 'windows'));

        this._shellChangedId = this._shell.connect('changed::enabled-extensions', () => this._sync());
        this._sync();
    }

    _current() {
        return this._shell.get_strv('enabled-extensions').includes(PANEL) ? 'windows' : 'mac';
    }

    _apply(id) {
        const mode = MODES[id];
        const manager = Main.extensionManager;
        manager.disableExtension(mode.disable);
        manager.enableExtension(mode.enable);
        this._wm.set_string('button-layout', mode.buttons);
        this._sync();
    }

    _sync() {
        const current = this._current();
        this.subtitle = MODES[current].label;
        this.checked = false;
        for (const [id, item] of Object.entries(this._items))
            item.setOrnament(id === current ? PopupMenu.Ornament.CHECK : PopupMenu.Ornament.NONE);
    }

    destroy() {
        if (this._shellChangedId) {
            this._shell.disconnect(this._shellChangedId);
            this._shellChangedId = 0;
        }
        super.destroy();
    }
});

const LayoutIndicator = GObject.registerClass(
class LayoutIndicator extends SystemIndicator {
    constructor() {
        super();
        this.quickSettingsItems.push(new LayoutToggle());
    }

    destroy() {
        this.quickSettingsItems.forEach(item => item.destroy());
        super.destroy();
    }
});

export default class LocumViewLayoutExtension extends Extension {
    enable() {
        this._indicator = new LayoutIndicator();
        Main.panel.statusArea.quickSettings.addExternalIndicator(this._indicator);
    }

    disable() {
        this._indicator?.destroy();
        this._indicator = null;
    }
}
