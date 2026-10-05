#!/bin/bash
# Copy selected data from the retired local account into the IdM account's home (changelog #36).
# Run as root from the IdM molszewski session, with Firefox closed: sudo bash /var/tmp/lv-idm/refdev-migrate-home.sh
set -euo pipefail
SRC=/home/molszewski-legacy; DST=/home/molszewski
id molszewski | grep -q 'uid=1796800007' || { echo "molszewski is not the IdM account; stop"; exit 1; }
[ -d "$DST" ] || { echo "$DST missing: log in once as the IdM user first"; exit 1; }
pgrep -u molszewski -x firefox >/dev/null && { echo "close Firefox first"; exit 1; }
for p in .ssh .gitconfig Projects Pictures Downloads .local/share/backgrounds .mozilla .var; do
  [ -e "$SRC/$p" ] || continue
  mkdir -p "$DST/$(dirname "$p")"
  cp -a "$SRC/$p" "$DST/$(dirname "$p")/"
  echo "copied $p"
done
rm -f "$DST/.ssh/authorized_keys"          # SSH keys now come from IdM (ipa user-mod --sshpubkey)
chown -R molszewski:molszewski "$DST"
chmod 700 "$DST/.ssh"; chmod 600 "$DST/.ssh/id_ed25519_gitea" "$DST/.ssh/config" 2>/dev/null || true
restorecon -R "$DST"
du -sh "$DST"; ls -la "$DST" | head -20
echo "MIGRATE DONE $(date -Is)"
