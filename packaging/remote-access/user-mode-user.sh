#!/bin/bash
# LocumView: straight-to-desktop remote access, user part (changelog #19). Run as the desktop user (no sudo).
# The RDP credentials come on stdin (two lines: username, password), never as arguments:
#   sops -d --extract ... | ssh <user>@<vm> 'bash -s' < user-mode-user.sh   (see the operator wrapper)
# Configures the headless (user-mode) GNOME Remote Desktop on port 3390 with its own TLS certificate.
set -euo pipefail
read -r RDP_USER; read -r RDP_PASS
D=~/.local/share/gnome-remote-desktop
mkdir -p "$D"; chmod 700 "$D"
if [ ! -s "$D/rdp-tls.crt" ]; then
  ip=$(hostname -I | awk '{print $1}')
  openssl req -x509 -newkey rsa:3072 -nodes -days 825 -subj "/CN=$(hostname)" \
    -addext "subjectAltName=DNS:$(hostname),IP:$ip" -keyout "$D/rdp-tls.key" -out "$D/rdp-tls.crt" 2>/dev/null
  chmod 600 "$D/rdp-tls.key"
fi
grdctl --headless rdp set-tls-cert "$D/rdp-tls.crt"
grdctl --headless rdp set-tls-key "$D/rdp-tls.key"
grdctl --headless rdp set-port 3390
grdctl --headless rdp disable-port-negotiation
grdctl --headless rdp disable-view-only
# grdctl reads credentials from its interactive prompt only when it has a terminal (on a plain pipe it
# segfaults, GRD 49.3), and passing them as arguments would expose them in the process list. So: a pty
# via script(1), fed by bash builtins (no child process ever carries the values).
(sleep 1; printf '%s\n' "$RDP_USER"; sleep 1; printf '%s\n' "$RDP_PASS"; sleep 1) |
  script -qec "grdctl --headless rdp set-credentials" /dev/null >/dev/null 2>&1
grdctl --headless status --show-credentials 2>/dev/null | grep -q "Username: $RDP_USER\$" || { echo "credentials not set"; exit 1; }
grdctl --headless rdp enable
systemctl --user enable gnome-remote-desktop-headless.service
grdctl --headless status 2>/dev/null | grep -vE 'Password'
openssl x509 -in "$D/rdp-tls.crt" -noout -fingerprint -sha256
echo "USER PART DONE"
