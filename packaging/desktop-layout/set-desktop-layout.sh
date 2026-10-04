#!/bin/bash
# Organization-wide desktop layout (changelog #25; target: an Ansible "desktop" role variable).
# The organization chooses the layout for every user of this desktop image; users can't change it.
#   sudo set-desktop-layout.sh mac|windows|gnome                       set and lock the layout
#   sudo set-desktop-layout.sh mac|windows|gnome --allow-user-choice   set a default, users may switch
#   sudo set-desktop-layout.sh                                         re-apply the recorded choice (default: mac)
#
#   mac      Dash to Dock at the bottom, window buttons on the left
#   windows  Dash to Panel taskbar at the bottom, window buttons on the right
#   gnome    stock GNOME: no dock or taskbar extension, Activities overview, close button only
#
# Written to the "local" dconf system db. Unless user choice is allowed, the keys are LOCKED
# (/etc/dconf/db/local.d/locks), so the system value applies even where a user has their own setting,
# and neither the LocumView Layout tile nor the Extensions app can change it.
set -euo pipefail
CONF=/etc/locumview/desktop-layout.conf
DB=/etc/dconf/db/local.d/20-locumview-layout
LOCKS=/etc/dconf/db/local.d/locks/20-locumview-layout
DOCK=dash-to-dock@micxgx.gmail.com
PANEL=dash-to-panel@jderose9.github.com
# Always on in every style; the clipboard guard is a PHI control and stays enabled (the list is locked).
BASE="'tiling-assistant@leleat-on-github', 'locumview-activities@locumview.org', 'blur-my-shell@aunetx', 'locumview-layout@locumview.org', 'locumview-clipboard-guard@locumview.org'"
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }

style=${1:-}
allow=no
[ "${2:-}" = --allow-user-choice ] && allow=yes
if [ -z "$style" ]; then
  LAYOUT=mac; ALLOW_USER_CHOICE=no
  # shellcheck disable=SC1090
  [ -f "$CONF" ] && . "$CONF"
  style=$LAYOUT; allow=$ALLOW_USER_CHOICE
fi

case "$style" in
  mac)     enabled="'$DOCK', $BASE";  disabled="'$PANEL'";          buttons='close,minimize,maximize:appmenu' ;;
  windows) enabled="'$PANEL', $BASE"; disabled="'$DOCK'";           buttons='appmenu:minimize,maximize,close' ;;
  gnome)   enabled="$BASE";           disabled="'$DOCK', '$PANEL'"; buttons='appmenu:close' ;;
  *) echo "usage: $0 mac|windows|gnome [--allow-user-choice]"; exit 1 ;;
esac

install -d -m 755 /etc/locumview /etc/dconf/db/local.d/locks
printf 'LAYOUT=%s\nALLOW_USER_CHOICE=%s\n' "$style" "$allow" > "$CONF"
cat > "$DB" <<CONF
# Managed by set-desktop-layout.sh (layout: $style, user choice: $allow). Do not edit by hand.
[org/gnome/shell]
enabled-extensions=[$enabled]
disabled-extensions=['background-logo@fedorahosted.org', $disabled]

[org/gnome/desktop/wm/preferences]
button-layout='$buttons'
CONF
if [ "$allow" = yes ]; then
  rm -f "$LOCKS"
else
  cat > "$LOCKS" <<'LOCK'
/org/gnome/shell/enabled-extensions
/org/gnome/shell/disabled-extensions
/org/gnome/desktop/wm/preferences/button-layout
LOCK
fi
dconf update
restorecon -R /etc/dconf/db /etc/locumview 2>/dev/null || true
echo "desktop layout: $style (user choice: $allow)"
dconf dump /org/gnome/shell/ 2>/dev/null | grep -E 'enabled-extensions|disabled-extensions' || true
