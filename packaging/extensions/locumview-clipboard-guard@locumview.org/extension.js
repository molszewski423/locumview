// SPDX-License-Identifier: GPL-2.0-or-later
// LocumView Clipboard Guard (changelog #26): copied content may be PHI, and LocumView desktop sessions are
// always on (headless, never logged out), so the clipboard would otherwise keep its last item indefinitely.
// This clears CLIPBOARD and PRIMARY a fixed time after the last change, and immediately when the screen locks.
// The organization sets the time in /etc/locumview/clipboard.conf (CLIPBOARD_TTL_SECONDS=300 by default).
// It holds no clipboard history and never reads the clipboard contents.
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const CONF = '/etc/locumview/clipboard.conf';
const DEFAULT_TTL = 300;
const WATCHED = [Meta.SelectionType.SELECTION_CLIPBOARD, Meta.SelectionType.SELECTION_PRIMARY];

function readTtl() {
    try {
        const [, bytes] = GLib.file_get_contents(CONF);
        const m = new TextDecoder().decode(bytes).match(/^\s*CLIPBOARD_TTL_SECONDS\s*=\s*(\d+)\s*$/m);
        const ttl = m ? parseInt(m[1], 10) : DEFAULT_TTL;
        return ttl >= 10 ? ttl : DEFAULT_TTL;
    } catch {
        return DEFAULT_TTL;
    }
}

export default class LocumViewClipboardGuard extends Extension {
    enable() {
        this._ttl = readTtl();
        this._ignoreUntil = 0;
        this._selection = global.display.get_selection();
        this._ownerChangedId = this._selection.connect('owner-changed', (_sel, type) => {
            if (!WATCHED.includes(type) || GLib.get_monotonic_time() < this._ignoreUntil)
                return;
            this._arm();
        });
        if (Main.screenShield) {
            this._lockId = Main.screenShield.connect('active-changed', () => {
                if (Main.screenShield.active)
                    this._clear();
            });
        }
    }

    _arm() {
        if (this._timeoutId)
            GLib.source_remove(this._timeoutId);
        this._timeoutId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, this._ttl, () => {
            this._timeoutId = 0;
            this._clear();
            return GLib.SOURCE_REMOVE;
        });
    }

    _clear() {
        if (this._timeoutId) {
            GLib.source_remove(this._timeoutId);
            this._timeoutId = 0;
        }
        // Our own empty selection also fires owner-changed; don't re-arm for it.
        this._ignoreUntil = GLib.get_monotonic_time() + 2 * GLib.USEC_PER_SEC;
        const clipboard = St.Clipboard.get_default();
        clipboard.set_text(St.ClipboardType.CLIPBOARD, '');
        clipboard.set_text(St.ClipboardType.PRIMARY, '');
    }

    disable() {
        if (this._timeoutId) {
            GLib.source_remove(this._timeoutId);
            this._timeoutId = 0;
        }
        if (this._ownerChangedId) {
            this._selection.disconnect(this._ownerChangedId);
            this._ownerChangedId = 0;
        }
        if (this._lockId) {
            Main.screenShield.disconnect(this._lockId);
            this._lockId = 0;
        }
        this._selection = null;
    }
}
