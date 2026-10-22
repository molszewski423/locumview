# LocumView's own desktop pieces as RPMs (Phase 4, changelog #62). Built from a git archive of the repository by
# packaging/rpm/build-rpms.sh, in a clean CentOS Stream 10 container; the files come from the same places that
# packaging/install-desktop.sh and the image use today, so nothing moves.
# Third-party pieces (Papirus, Tiling Assistant, Blur my Shell), dconf defaults, the organization's layout and the
# STIG stay with the image for now.

%global lv_ext activities clipboard-guard layout

Name:           locumview-desktop
Version:        0.1.0
Release:        %{?lv_release}%{!?lv_release:1}%{?dist}
Summary:        LocumView desktop components
License:        Apache-2.0
URL:            https://locumview.com
Source0:        locumview-%{version}.tar.gz
BuildArch:      noarch

BuildRequires:  librsvg2-tools
BuildRequires:  gtk-update-icon-cache
BuildRequires:  desktop-file-utils
BuildRequires:  python3
BuildRequires:  systemd-rpm-macros

%description
LocumView's own components for its GNOME desktop: shell extensions, branding, the LocumView Tour and the EHR
launcher.

%package -n locumview-shell-extensions
Summary:        LocumView GNOME Shell extensions: Activities button, clipboard guard, desktop layout
License:        GPL-2.0-or-later
Requires:       gnome-shell

%description -n locumview-shell-extensions
GNOME Shell extensions for LocumView desktops: the Activities button with the LocumView logo and workspace dots,
the clipboard guard (clears copied content after the time set in /etc/locumview/clipboard.conf, for PHI), and the
organization's desktop layout switch.

%package -n locumview-branding
Summary:        LocumView logo, login logo and wallpapers

%description -n locumview-branding
The LocumView logo in place of the distribution logo (through an override directory first in XDG_DATA_DIRS, so
no package's files are changed), the login and lock screen logo, and the LocumView wallpapers in light and dark
variants, listed in Settings.

%package -n locumview-tour
Summary:        LocumView Tour, a first-login walkthrough of the desktop
Requires:       python3-gobject
Requires:       gtk4
Requires:       libadwaita
Requires:       locumview-branding = %{version}-%{release}

%description -n locumview-tour
A walkthrough of the LocumView desktop and its shortcuts. It opens once per user at first sign-in and from the
app grid at any time; for the guest demo account it reopens on every connection.

%package -n locumview-ehr-launcher
Summary:        LocumView EHR launcher: the organization's EHR in Google Chrome app mode
Requires:       google-chrome-stable

%description -n locumview-ehr-launcher
Opens the organization's EHR (EHR_URL in /etc/locumview/ehr.conf) in Google Chrome in app mode. Until an EHR is
set, a local page explains how to set one. Chrome's managed policies, which allow only the EHR's sites, come with
the LocumView image.

%prep
%autosetup -n locumview-%{version}

%build
B=packaging/branding
mkdir -p build/icons build/wallpapers
for s in 16 22 24 32 36 48 64 96 128 256; do
  rsvg-convert -w $s -h $s $B/locumview-logo.svg -o build/icons/logo-$s.png
done
# Rendered at 2x: GDM scales the logo to a 48 px logical height.
rsvg-convert -h 96 $B/locumview-gdm-logo.svg -o build/locumview-gdm-logo.png
python3 - <<'PY'
import pathlib, re, subprocess
src = pathlib.Path("packaging/branding/wallpapers")
bg = "%{_datadir}/backgrounds/locumview"
items = []
for light in sorted(src.glob("*-light.svg")):
    name = light.name[: -len("-light.svg")]
    for v in ("light", "dark"):
        subprocess.run(["rsvg-convert", "-w", "3840", "-h", "2160", str(src / f"{name}-{v}.svg"),
                        "-o", f"build/wallpapers/{name}-{v}.png"], check=True)
    label = " ".join(w.capitalize() for w in name.split("-"))
    items.append(f"""  <wallpaper deleted="false">
    <name>LocumView {label}</name>
    <filename>{bg}/{name}-light.png</filename>
    <filename-dark>{bg}/{name}-dark.png</filename-dark>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#0E141C</pcolor>
    <scolor>#0E141C</scolor>
  </wallpaper>""")
pathlib.Path("build/locumview.xml").write_text(
    '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE wallpapers SYSTEM "gnome-wp-list.dtd">\n<wallpapers>\n'
    + "\n".join(items) + "\n</wallpapers>\n")
PY

%install
# Shell extensions
for e in %{lv_ext}; do
  d=%{buildroot}%{_datadir}/gnome-shell/extensions/locumview-$e@locumview.org
  install -d $d
  install -m 0644 packaging/extensions/locumview-$e@locumview.org/* $d/
done
install -d %{buildroot}%{_sysconfdir}/locumview
printf '# Seconds before copied content is cleared from the clipboard (organization policy; PHI).\nCLIPBOARD_TTL_SECONDS=300\n' \
  > %{buildroot}%{_sysconfdir}/locumview/clipboard.conf

# Branding: the logo under the names gnome-shell and GDM look up, in the override directory
O=%{buildroot}%{_datadir}/locumview/override/icons/hicolor
for s in 16 22 24 32 36 48 64 96 128 256; do
  install -d $O/${s}x$s/apps
  for n in fedora-logo-icon system-logo-icon; do install -m 0644 build/icons/logo-$s.png $O/${s}x$s/apps/$n.png; done
done
install -d $O/scalable/apps
for n in fedora-logo-icon system-logo-icon locumview; do
  install -m 0644 packaging/branding/locumview-logo.svg $O/scalable/apps/$n.svg
done
# No index.theme here: the system's hicolor index must stay the only one (this directory comes first in
# XDG_DATA_DIRS); -t builds the cache without it, as install-desktop.sh does.
gtk-update-icon-cache -f -q -t $O
install -D -m 0644 image/desktop/files/usr/lib/environment.d/50-locumview.conf \
  %{buildroot}%{_prefix}/lib/environment.d/50-locumview.conf
install -D -m 0644 build/locumview-gdm-logo.png %{buildroot}%{_datadir}/pixmaps/locumview-gdm-logo.png
install -d %{buildroot}%{_datadir}/backgrounds/locumview
install -m 0644 build/wallpapers/*.png %{buildroot}%{_datadir}/backgrounds/locumview/
install -D -m 0644 build/locumview.xml %{buildroot}%{_datadir}/gnome-background-properties/locumview.xml

# Tour (the /usr/local paths of the hand-built desktop become /usr)
T=packaging/tour
install -d %{buildroot}%{_datadir}/locumview-tour
install -m 0644 $T/art/*.svg %{buildroot}%{_datadir}/locumview-tour/
sed 's|/usr/local/share/locumview-tour|%{_datadir}/locumview-tour|g' $T/locumview-tour > locumview-tour
sed 's|/usr/local/bin/|%{_bindir}/|g' $T/locumview-tour-on-connect > locumview-tour-on-connect
install -D -m 0755 locumview-tour %{buildroot}%{_bindir}/locumview-tour
install -D -m 0755 locumview-tour-on-connect %{buildroot}%{_bindir}/locumview-tour-on-connect
install -d %{buildroot}%{_datadir}/applications %{buildroot}%{_sysconfdir}/xdg/autostart %{buildroot}%{_userunitdir}
sed 's|/usr/local/bin/|%{_bindir}/|g' $T/org.locumview.Tour.desktop > %{buildroot}%{_datadir}/applications/org.locumview.Tour.desktop
sed 's|/usr/local/bin/|%{_bindir}/|g' $T/org.locumview.Tour-autostart.desktop > %{buildroot}%{_sysconfdir}/xdg/autostart/org.locumview.Tour-autostart.desktop
sed 's|/usr/local/bin/|%{_bindir}/|g' $T/locumview-tour-on-connect.service > %{buildroot}%{_userunitdir}/locumview-tour-on-connect.service
chmod 0644 %{buildroot}%{_datadir}/applications/*.desktop %{buildroot}%{_sysconfdir}/xdg/autostart/*.desktop \
  %{buildroot}%{_userunitdir}/*.service

# EHR launcher
F=image/desktop/files
install -D -m 0755 $F/usr/libexec/locumview/ehr-browser %{buildroot}%{_libexecdir}/locumview/ehr-browser
install -D -m 0644 $F/usr/share/applications/locumview-ehr.desktop %{buildroot}%{_datadir}/applications/locumview-ehr.desktop
install -D -m 0644 $F/etc/locumview/ehr.conf %{buildroot}%{_sysconfdir}/locumview/ehr.conf
install -D -m 0644 $F/usr/share/locumview/ehr/index.html %{buildroot}%{_datadir}/locumview/ehr/index.html

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/org.locumview.Tour.desktop
desktop-file-validate %{buildroot}%{_datadir}/applications/locumview-ehr.desktop
desktop-file-validate %{buildroot}%{_sysconfdir}/xdg/autostart/org.locumview.Tour-autostart.desktop
for e in %{lv_ext}; do
  python3 -c "import json,sys; m=json.load(open(sys.argv[1])); assert m['uuid']==sys.argv[2], m['uuid']" \
    %{buildroot}%{_datadir}/gnome-shell/extensions/locumview-$e@locumview.org/metadata.json locumview-$e@locumview.org
done
python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])" %{buildroot}%{_bindir}/locumview-tour
if grep -rl /usr/local %{buildroot}%{_bindir} %{buildroot}%{_datadir}/applications %{buildroot}%{_userunitdir} \
    %{buildroot}%{_sysconfdir}/xdg; then
  echo "a /usr/local path is left in the files above"; exit 1
fi

%files -n locumview-shell-extensions
%license packaging/extensions/COPYING
%{_datadir}/gnome-shell/extensions/locumview-*@locumview.org/
%dir %{_sysconfdir}/locumview
%config(noreplace) %{_sysconfdir}/locumview/clipboard.conf

%files -n locumview-branding
%license LICENSE
%dir %{_datadir}/locumview
%{_datadir}/locumview/override/
%{_prefix}/lib/environment.d/50-locumview.conf
%{_datadir}/pixmaps/locumview-gdm-logo.png
%{_datadir}/backgrounds/locumview/
%{_datadir}/gnome-background-properties/locumview.xml

%files -n locumview-tour
%license LICENSE
%{_bindir}/locumview-tour
%{_bindir}/locumview-tour-on-connect
%{_datadir}/locumview-tour/
%{_datadir}/applications/org.locumview.Tour.desktop
%{_sysconfdir}/xdg/autostart/org.locumview.Tour-autostart.desktop
%{_userunitdir}/locumview-tour-on-connect.service

%files -n locumview-ehr-launcher
%license LICENSE
%dir %{_libexecdir}/locumview
%{_libexecdir}/locumview/ehr-browser
%{_datadir}/applications/locumview-ehr.desktop
%dir %{_sysconfdir}/locumview
%config(noreplace) %{_sysconfdir}/locumview/ehr.conf
%dir %{_datadir}/locumview
%{_datadir}/locumview/ehr/

%changelog
* Wed Oct 21 2026 Michael Olszewski <hello@locumview.com> - 0.1.0-1
- First packaging of LocumView's own desktop pieces (changelog #62)
