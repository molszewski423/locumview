#!/bin/bash
# Install image/desktop/files/ into the image with explicit modes (directories 0755, executables under
# usr/libexec 0755, everything else 0644). A plain COPY keeps the builder's checkout modes (a umask of 002
# leaves directories group-writable), and a later chmod layer does not reliably reach the deployed system.
set -euo pipefail
SRC=${1:?usage: install-files.sh <files-dir>}
cd "$SRC"
find . -mindepth 1 -type d -printf '%P\n' | while read -r d; do install -d -m 0755 "/$d"; done
find . -type f -printf '%P\n' | while read -r f; do
  # Files a LocumView RPM now owns (packaging/rpm/) come from the package; copying them again would change them.
  if rpm -qf --qf '%{NAME}\n' "/$f" 2>/dev/null | grep -q '^locumview-'; then continue; fi
  case "$f" in usr/libexec/*) m=0755 ;; *) m=0644 ;; esac
  install -m "$m" "$f" "/$f"
done
