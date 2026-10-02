#!/bin/bash
# LocumView reference desktop setup (Phase 1 manual step; target: Ansible "desktop"/"branding" roles).
# Run as root:  sudo packaging/install-desktop.sh
# Branding and icon themes go only under /usr/local and /etc/dconf, never over package-owned files.
# Apps: RPMs from AppStream; Flatpaks from Red Hat's "rhel" remote when available, else Flathub.
set -euo pipefail
SRC=$(cd "$(dirname "$0")" && pwd)/branding
ICONS=/usr/local/share/icons/hicolor
BG=/usr/local/share/backgrounds/locumview
PROPS=/usr/local/share/gnome-background-properties/locumview.xml
DEFAULT_WALLPAPER=nested
PAPIRUS_VERSION=20260801
# Not a secret: published sha256 of the public release archive (gitleaks generic-api-key false positive).
PAPIRUS_SHA256=646f622e9e7e9e65eef9d0ab58999d4920ddb33d98e6a75232627cfe3bd508f9  # gitleaks:allow
PAPIRUS_TARBALL=${PAPIRUS_TARBALL:-/home/molszewski/Downloads/papirus-icon-theme-$PAPIRUS_VERSION.tar.gz}

# 1. GNOME Shell extensions (AppStream RPMs). They conflict if both are on, so only Dash to Dock is enabled.
DOCK=dash-to-dock@micxgx.gmail.com
PANEL=dash-to-panel@jderose9.github.com
dnf install -y gnome-shell-extension-dash-to-dock gnome-shell-extension-dash-to-panel
for uuid in $DOCK $PANEL; do
  [ -d "/usr/share/gnome-shell/extensions/$uuid" ] || { echo "missing extension $uuid (UUID changed?)"; exit 1; }
done

# 2. Flatpak apps, system-wide. Prefer the Red Hat remote; fall back to Flathub.
FLATPAKS="org.gnome.Extensions org.onlyoffice.desktopeditors"
flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
for app in $FLATPAKS; do
  if flatpak remote-info --system rhel "$app" >/dev/null 2>&1; then remote=rhel; else remote=flathub; fi
  echo "== $app from $remote"
  flatpak install --system -y --noninteractive "$remote" "$app"
done

# 3. Papirus icon theme from the pinned upstream release (not packaged in RHEL; EPEL avoided, see changelog #10).
if [ ! -f "$PAPIRUS_TARBALL" ]; then
  PAPIRUS_TARBALL=$(mktemp --suffix=.tar.gz)
  curl -fsSLo "$PAPIRUS_TARBALL" "https://github.com/PapirusDevelopmentTeam/papirus-icon-theme/archive/refs/tags/$PAPIRUS_VERSION.tar.gz"
fi
echo "$PAPIRUS_SHA256  $PAPIRUS_TARBALL" | sha256sum -c -
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
tar xzf "$PAPIRUS_TARBALL" -C "$TMP"
for t in Papirus Papirus-Dark Papirus-Light; do
  rm -rf "/usr/local/share/icons/$t"
  cp -a "$TMP/papirus-icon-theme-$PAPIRUS_VERSION/$t" /usr/local/share/icons/
  chown -R root:root "/usr/local/share/icons/$t"
  gtk-update-icon-cache -f -q "/usr/local/share/icons/$t"
done

# 4. Top-bar logo. gnome-shell shows the icon named by LOGO= in /etc/os-release ("fedora-logo-icon" on RHEL).
#    /usr/local/share precedes /usr/share in XDG_DATA_DIRS, so same-named hicolor icons here win.
for s in 16 22 24 32 36 48 64 96 128 256; do
  install -d "$ICONS/${s}x${s}/apps"
  for name in fedora-logo-icon system-logo-icon; do
    rsvg-convert -w "$s" -h "$s" "$SRC/locumview-logo.svg" -o "$ICONS/${s}x${s}/apps/$name.png"
  done
done
install -d "$ICONS/scalable/apps"
for name in fedora-logo-icon system-logo-icon locumview; do
  install -m 644 "$SRC/locumview-logo.svg" "$ICONS/scalable/apps/$name.svg"
done
gtk-update-icon-cache -f -t "$ICONS"

# 5. Wallpapers: every wallpapers/<name>-{light,dark}.svg pair (text pre-outlined, see branding/README), rendered to PNG (no font dependency at
#    runtime) and listed in Settings > Appearance. Stale PNGs from earlier runs are removed.
rm -rf "$BG"; install -d "$BG"
install -d "$(dirname "$PROPS")"
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<!DOCTYPE wallpapers SYSTEM "gnome-wp-list.dtd">'
  echo '<wallpapers>'
  for light in "$SRC"/wallpapers/*-light.svg; do
    name=$(basename "$light" -light.svg)
    label=$(echo "$name" | sed -E 's/-/ /g; s/\b(.)/\u\1/g')
    rsvg-convert -w 3840 -h 2160 "$light" -o "$BG/$name-light.png"
    rsvg-convert -w 3840 -h 2160 "$SRC/wallpapers/$name-dark.svg" -o "$BG/$name-dark.png"
    echo "  <wallpaper deleted=\"false\">"
    echo "    <name>LocumView $label</name>"
    echo "    <filename>$BG/$name-light.png</filename>"
    echo "    <filename-dark>$BG/$name-dark.png</filename-dark>"
    echo "    <options>zoom</options>"
    echo "    <shade_type>solid</shade_type>"
    echo "    <pcolor>#0E141C</pcolor>"
    echo "    <scolor>#0E141C</scolor>"
    echo "  </wallpaper>"
  done
  echo '</wallpapers>'
} > "$PROPS"
chmod 644 "$BG"/*.png "$PROPS"

# 6. System-wide defaults via the "local" dconf db (already in /etc/dconf/profile/user).
#    picture-uri / picture-uri-dark switch automatically with the light/dark color-scheme.
#    Icon theme: Papirus (works in light and dark; symbolic icons are recoloured by GTK).
#    Extensions: Dash to Dock on, Dash to Panel installed but off (switch in the Extensions app).
#    The background-logo extension (Red Hat mark on the wallpaper) is disabled.
cat > /etc/dconf/db/local.d/10-locumview-branding <<CONF
[org/gnome/desktop/background]
picture-uri='file://$BG/$DEFAULT_WALLPAPER-light.png'
picture-uri-dark='file://$BG/$DEFAULT_WALLPAPER-dark.png'
picture-options='zoom'
primary-color='#0E141C'

[org/gnome/desktop/interface]
icon-theme='Papirus'

[org/gnome/desktop/screensaver]
picture-uri='file://$BG/$DEFAULT_WALLPAPER-dark.png'
picture-options='zoom'

[org/gnome/shell]
enabled-extensions=['$DOCK']
disabled-extensions=['background-logo@fedorahosted.org', '$PANEL']
CONF
dconf update
restorecon -R /usr/local/share/icons /usr/local/share/backgrounds /usr/local/share/gnome-background-properties /etc/dconf/db
ls "$BG"
flatpak list --system --app --columns=application,origin
echo DONE
