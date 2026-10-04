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
TILING_VERSION_TAG=75405   # Tiling Assistant v55 (GNOME 48-51), extensions.gnome.org
# Not a secret: published sha256 of the public extension zip (gitleaks generic-api-key false positive).
TILING_SHA256=4cd9b848e399b0bdcf09302044f2420cf86c63fef2857a70a5be88ca04ad88de  # gitleaks:allow
BLUR_VERSION_TAG=69740     # Blur my Shell v72 (GNOME 46-50), extensions.gnome.org
# Not a secret: published sha256 of the public extension zip.
BLUR_SHA256=4b82a0a0be4f2f917bff88e0952fab4d6c347d1128e7d8487caef240b699a910  # gitleaks:allow
EXT_DIR=/usr/local/share/gnome-shell/extensions
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

# 2b. Window management extensions, system-wide under /usr/local (in XDG_DATA_DIRS).
#     Tiling Assistant: quarter tiling (Alt+I/O/K/L). Pinned extensions.gnome.org build, checksum verified.
#     LocumView Activities (ours, packaging/extensions/): logo + workspace dots in the top-left button.
install -d "$EXT_DIR"
TZIP=$(mktemp --suffix=.zip)
curl -fsSL -A "Mozilla/5.0" -o "$TZIP" "https://extensions.gnome.org/download-extension/tiling-assistant@leleat-on-github.shell-extension.zip?version_tag=$TILING_VERSION_TAG"
echo "$TILING_SHA256  $TZIP" | sha256sum -c -
rm -rf "$EXT_DIR/tiling-assistant@leleat-on-github"
install -d "$EXT_DIR/tiling-assistant@leleat-on-github"
unzip -q "$TZIP" -d "$EXT_DIR/tiling-assistant@leleat-on-github"; rm -f "$TZIP"
glib-compile-schemas "$EXT_DIR/tiling-assistant@leleat-on-github/schemas"
# Blur my Shell: blurred panel/overview/dock (look and feel only). Pinned build, checksum verified.
BZIP=$(mktemp --suffix=.zip)
curl -fsSL -A "Mozilla/5.0" -o "$BZIP" "https://extensions.gnome.org/download-extension/blur-my-shell@aunetx.shell-extension.zip?version_tag=$BLUR_VERSION_TAG"
echo "$BLUR_SHA256  $BZIP" | sha256sum -c -
rm -rf "$EXT_DIR/blur-my-shell@aunetx"
install -d "$EXT_DIR/blur-my-shell@aunetx"
unzip -q "$BZIP" -d "$EXT_DIR/blur-my-shell@aunetx"; rm -f "$BZIP"
glib-compile-schemas "$EXT_DIR/blur-my-shell@aunetx/schemas"
rm -rf "$EXT_DIR/locumview-activities@locumview.org"
cp -r "$SRC/../extensions/locumview-activities@locumview.org" "$EXT_DIR/"
rm -rf "$EXT_DIR/locumview-clipboard-guard@locumview.org"
cp -r "$SRC/../extensions/locumview-clipboard-guard@locumview.org" "$EXT_DIR/"   # clears the clipboard after a timeout (PHI)
install -d -m 755 /etc/locumview
[ -f /etc/locumview/clipboard.conf ] || printf '# Seconds before copied content is cleared from the clipboard (organization policy; PHI).\nCLIPBOARD_TTL_SECONDS=300\n' > /etc/locumview/clipboard.conf
rm -rf "$EXT_DIR/locumview-layout@locumview.org"
cp -r "$SRC/../extensions/locumview-layout@locumview.org" "$EXT_DIR/"   # Mac/Windows layout switch (Quick Settings)
chmod -R u=rwX,go=rX "$EXT_DIR"

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
# 3b. Folder colour: LocumView teal (#5EEAD4, the GDM logo accent). Papirus' own teal folders
#     (#16a085 front, #12806a back, #08382e glyph) are recoloured in our /usr/local copy, then the
#     vendored papirus-folders (upstream v1.14.0, MIT) points the default folder icons at them.
#     XDG_DATA_DIRS pinned so it only ever touches /usr/local/share/icons.
for t in Papirus Papirus-Dark Papirus-Light; do
  find "/usr/local/share/icons/$t" -type f -name '*-teal*.svg' \
    -exec sed -i 's/#16a085/#5EEAD4/gI; s/#12806a/#2DD4BF/gI; s/#08382e/#134E4A/gI' {} +
done
XDG_DATA_DIRS=/usr/local/share "$SRC/../vendor/papirus-folders" -o -C teal --theme Papirus

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

# GDM greeter + lock-screen logo (org.gnome.login-screen logo; RHEL default is the Red Hat mark).
# Rendered at 2x: GDM scales it to a fixed 48px logical height.
install -d /usr/local/share/pixmaps
rsvg-convert -h 96 "$SRC/locumview-gdm-logo.svg" -o /usr/local/share/pixmaps/locumview-gdm-logo.png
chmod 644 /usr/local/share/pixmaps/locumview-gdm-logo.png

# 4b. LocumView Tour (packaging/tour): replaces GNOME Tour, whose pages are compiled in. Opens once per user at
#     first login (autostart, --first-run marker in ~/.local/state/locumview), and from the app grid any time.
#     GNOME's own welcome dialog is suppressed below (welcome-dialog-last-shown-version) and GNOME Tour hidden.
TOUR=$SRC/../tour
install -d /usr/local/share/locumview-tour /usr/local/share/applications /etc/xdg/autostart
install -m 644 "$TOUR"/art/*.svg /usr/local/share/locumview-tour/
install -m 755 "$TOUR/locumview-tour" /usr/local/bin/locumview-tour
install -m 644 "$TOUR/org.locumview.Tour.desktop" /usr/local/share/applications/
install -m 644 "$TOUR/org.locumview.Tour-autostart.desktop" /etc/xdg/autostart/
# Demo account only (enabled per user by remote-access/demo-user-root.sh): reopen the tour on every guest connection.
install -m 755 "$TOUR/locumview-tour-on-connect" /usr/local/bin/locumview-tour-on-connect
install -d /etc/systemd/user
install -m 644 "$TOUR/locumview-tour-on-connect.service" /etc/systemd/user/
# /usr/local/share precedes /usr/share in XDG_DATA_DIRS: this copy hides GNOME Tour from the app grid.
sed '/^\[Desktop Entry\]/a NoDisplay=true' /usr/share/applications/org.gnome.Tour.desktop > /usr/local/share/applications/org.gnome.Tour.desktop
update-desktop-database -q /usr/local/share/applications || true
restorecon -R /usr/local/bin/locumview-tour /usr/local/bin/locumview-tour-on-connect /usr/local/share/locumview-tour /usr/local/share/applications /etc/xdg/autostart /etc/systemd/user/locumview-tour-on-connect.service

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
#    Extensions and window buttons are NOT set here: the organization's desktop layout (mac, windows or
#    gnome) owns them, locked, via desktop-layout/set-desktop-layout.sh (step 7, changelog #25).
#    login-screen logo is read by GDM (gdm profile includes system-db:local) and the lock screen.
#    The background-logo extension (Red Hat mark on the wallpaper) is disabled.
cat > /etc/dconf/db/local.d/10-locumview-branding <<CONF
[org/gnome/desktop/background]
picture-uri='file://$BG/$DEFAULT_WALLPAPER-light.png'
picture-uri-dark='file://$BG/$DEFAULT_WALLPAPER-dark.png'
picture-options='zoom'
primary-color='#0E141C'

[org/gnome/login-screen]
logo='/usr/local/share/pixmaps/locumview-gdm-logo.png'

[org/gnome/desktop/interface]
icon-theme='Papirus'
color-scheme='prefer-dark'
accent-color='teal'

[org/gnome/desktop/screensaver]
picture-uri='file://$BG/$DEFAULT_WALLPAPER-dark.png'
picture-options='zoom'

# Keymap: Alt is the LocumView modifier (Super is usually eaten by the client OS/browser over Guacamole).
# Alt+1..0 workspace, Shift+Alt+1..0 move window there, Alt+PgUp/PgDn prev/next workspace, Alt+I/O/K/L quarter tiles, Alt+Return terminal,
# Ctrl+Alt+Q lock. Workspaces stay dynamic: Alt+N only reaches workspaces that already exist.
[org/gnome/mutter]
dynamic-workspaces=true

[org/gnome/desktop/wm/keybindings]
switch-to-workspace-1=['<Alt>1']
move-to-workspace-1=['<Shift><Alt>1']
switch-to-workspace-2=['<Alt>2']
move-to-workspace-2=['<Shift><Alt>2']
switch-to-workspace-3=['<Alt>3']
move-to-workspace-3=['<Shift><Alt>3']
switch-to-workspace-4=['<Alt>4']
move-to-workspace-4=['<Shift><Alt>4']
switch-to-workspace-5=['<Alt>5']
move-to-workspace-5=['<Shift><Alt>5']
switch-to-workspace-6=['<Alt>6']
move-to-workspace-6=['<Shift><Alt>6']
switch-to-workspace-7=['<Alt>7']
move-to-workspace-7=['<Shift><Alt>7']
switch-to-workspace-8=['<Alt>8']
move-to-workspace-8=['<Shift><Alt>8']
switch-to-workspace-9=['<Alt>9']
move-to-workspace-9=['<Shift><Alt>9']
switch-to-workspace-10=['<Alt>0']
move-to-workspace-10=['<Shift><Alt>0']
# Alt+PgUp/PgDn: previous/next workspace (Shift moves the window). GNOME defaults kept alongside.
switch-to-workspace-left=['<Alt>Page_Up', '<Super>Page_Up', '<Super><Alt>Left', '<Control><Alt>Left']
switch-to-workspace-right=['<Alt>Page_Down', '<Super>Page_Down', '<Super><Alt>Right', '<Control><Alt>Right']
move-to-workspace-left=['<Shift><Alt>Page_Up', '<Super><Shift>Page_Up', '<Super><Shift><Alt>Left', '<Control><Shift><Alt>Left']
move-to-workspace-right=['<Shift><Alt>Page_Down', '<Super><Shift>Page_Down', '<Super><Shift><Alt>Right', '<Control><Shift><Alt>Right']

[org/gnome/shell/extensions/tiling-assistant]
tile-topleft-quarter=['<Alt>i']
tile-topright-quarter=['<Alt>o']
tile-bottomleft-quarter=['<Alt>k']
tile-bottomright-quarter=['<Alt>l']
focus-hint-color='rgb(145,65,172)'

# Dock and panel look, promoted from the reference user's settings (changelog #22) so every user gets them.
[org/gnome/shell/extensions/dash-to-dock]
hot-keys=false
dock-position='BOTTOM'
dash-max-icon-size=48
dock-fixed=false
intellihide-mode='FOCUS_APPLICATION_WINDOWS'
height-fraction=0.9
background-opacity=0.8
transparency-mode='DYNAMIC'
autohide-in-fullscreen=false
require-pressure-to-show=false
preview-size-scale=0.34

[org/gnome/settings-daemon/plugins/media-keys]
screensaver=['<Control><Alt>q']
custom-keybindings=['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/locumview-terminal/']

[org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/locumview-terminal]
name='Terminal'
command='ptyxis --new-window'
binding='<Alt>Return'

[org/gnome/shell]
welcome-dialog-last-shown-version='999'
favorite-apps=['org.gnome.Nautilus.desktop', 'org.gnome.Calculator.desktop', 'org.onlyoffice.desktopeditors.desktop', 'org.mozilla.firefox.desktop']
CONF
dconf update

# 7. Organization desktop layout: re-applies the recorded choice (first install: mac, locked).
#    To change it for everyone: sudo packaging/desktop-layout/set-desktop-layout.sh mac|windows|gnome
bash "$SRC/../desktop-layout/set-desktop-layout.sh"
restorecon -R /usr/local/share/pixmaps /usr/local/share/icons /usr/local/share/backgrounds /usr/local/share/gnome-background-properties /etc/dconf/db
ls "$BG"
flatpak list --system --app --columns=application,origin
echo DONE
