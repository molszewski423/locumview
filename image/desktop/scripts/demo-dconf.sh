#!/bin/bash
# The guest demo user's dconf database (changelog #61). Run at image build time, after the STIG step.
# The guest knows no Linux password (demo-user-root.sh locks it), so a screen lock would trap every later guest in
# a locked session. The STIG locks the screen lock on in the system database "local", so the guest gets its own
# database instead: a copy of "local" with every setting and lock, except that the screen lock is locked off.
# Profile "locumview-demo" uses it in place of "local"; demo-user-root.sh points only the demo user at it
# (DCONF_PROFILE, set through environment.d). Every other account keeps the "user" profile. STIG exception for the
# guest account only: hardening/stig/README.md.
set -euo pipefail
DB=/etc/dconf/db
[ -d "$DB/local.d/locks" ] || { echo "no $DB/local.d/locks: run after the STIG step"; exit 1; }
rm -rf "$DB/locumview-demo.d"
cp -a "$DB/local.d" "$DB/locumview-demo.d"
# Later files win, so this overrides the STIG values; the STIG's locks then hold these values.
printf '%s\n' '# Guest demo user only (image/desktop/scripts/demo-dconf.sh): no screen lock, and the guest cannot turn it on.' \
  '[org/gnome/desktop/screensaver]' 'lock-enabled=false' '' '[org/gnome/desktop/lockdown]' 'disable-lock-screen=true' \
  > "$DB/locumview-demo.d/99-locumview-demo"
printf '%s\n' /org/gnome/desktop/screensaver/lock-enabled /org/gnome/desktop/lockdown/disable-lock-screen \
  > "$DB/locumview-demo.d/locks/99-locumview-demo"
chmod 0644 "$DB/locumview-demo.d/99-locumview-demo" "$DB/locumview-demo.d/locks/99-locumview-demo"
sed 's/^system-db:local$/system-db:locumview-demo/' /etc/dconf/profile/user > /etc/dconf/profile/locumview-demo
chmod 0644 /etc/dconf/profile/locumview-demo
grep -qx 'system-db:locumview-demo' /etc/dconf/profile/locumview-demo
dconf update
