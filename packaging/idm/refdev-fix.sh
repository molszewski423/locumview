#!/bin/bash
# Finish #36 after usermod stopped the enrollment script; rotate lvadmin (its password was echoed by shell tracing).
# Run as root: sudo bash /var/tmp/lv-idm/refdev-fix.sh     (no tracing: secrets must not reach the log)
set -euo pipefail
DIR=/var/tmp/lv-idm
. "$DIR/secrets.env"; shred -u "$DIR/secrets.env"
getent group molszewski | grep -q ':1000:' && groupmod -n molszewski-legacy molszewski && echo "group 1000 renamed to molszewski-legacy"
restorecon -R /home/molszewski-legacy && echo "SELinux labels restored on /home/molszewski-legacy"
printf 'lvadmin:%s\n' "$LVADMIN_PASSWORD" | chpasswd && echo "lvadmin password rotated"
unset LVADMIN_PASSWORD
sed -i -E "s/^(\+ printf 'lvadmin:%s\\\\n' ).*/\1<redacted>/; s/--password=[^ ]+/--password=<redacted>/g" /var/log/lv-idm-enroll.log
grep -c '<redacted>' /var/log/lv-idm-enroll.log | sed 's/^/log lines redacted: /'
echo "--- state"; id molszewski-legacy; id molszewski; getent group molszewski-legacy molszewski | cut -d: -f1,3
ls -ldZ /home/molszewski-legacy
echo "FIX DONE $(date -Is)"
