#!/bin/bash
# LocumView: straight-to-desktop remote access, root part (changelog #19; target: Ansible "remote_access" role).
# Run as root on the desktop VM:  sudo packaging/remote-access/user-mode-root.sh <desktop-user>
# Run user-mode-user.sh as that user first (it configures the headless GRD the session will start).
#  1. The user's GNOME session runs headless from boot (gnome-headless-session@<user>), so GNOME Remote
#     Desktop in user mode (port 3390) serves it directly: no GDM, no server redirections.
#  2. firewalld: RDP (3389 system/GDM admin fallback, 3390 user mode) only from the k3s nodes, where guacd
#     runs (pod traffic leaves the cluster SNATed to the node address). SSH is allowed only from those
#     nodes too, and so is Cockpit (9090): both leave the public zone (changelog #30); reach the VM with
#     ssh -J mikepc, and Cockpit with ssh -L 9090:<vm-ip>:9090 mikepc.
set -euo pipefail
U=${1:?usage: user-mode-root.sh <desktop-user>}
K3S_NODES="192.168.4.54/32 192.168.4.45/32"   # mikepc, debianbox (centosbook removed 2026-10-04, changelog #29)
ZONE=locumview-gateways
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
id "$U" >/dev/null
set -x

# Only one graphical session per user: end the user's existing graphical sessions (SSH/tty sessions stay).
for s in $(loginctl list-sessions --no-legend | awk -v u="$U" '$3 == u {print $1}'); do
  t=$(loginctl show-session "$s" -p Type --value)
  if [ "$t" = wayland ] || [ "$t" = x11 ]; then loginctl terminate-session "$s"; fi
done
sleep 3

# firewalld: source-based zone for the k3s nodes; RDP leaves the public zone.
firewall-cmd --zone=public --list-all
firewall-cmd --permanent --get-zones | tr ' ' '\n' | grep -qx "$ZONE" || firewall-cmd --permanent --new-zone="$ZONE"
for src in $K3S_NODES; do firewall-cmd --permanent --zone="$ZONE" --add-source="$src"; done
firewall-cmd --permanent --zone="$ZONE" --add-port=3389/tcp --add-port=3390/tcp
firewall-cmd --permanent --zone="$ZONE" --add-service=ssh
firewall-cmd --permanent --zone="$ZONE" --add-service=cockpit
firewall-cmd --permanent --zone=public --remove-service=rdp || true
firewall-cmd --permanent --zone=public --remove-service=ssh || true
firewall-cmd --permanent --zone=public --remove-service=cockpit || true
firewall-cmd --reload
firewall-cmd --zone="$ZONE" --list-all
firewall-cmd --zone=public --list-all

# Always-on: restart the headless session whenever it ends. The stock unit only restarts on failure, and a
# `systemctl restart` can race the old session's teardown so the new one exits cleanly and stays down (#22).
install -d /etc/systemd/system/gnome-headless-session@.service.d
printf '[Service]\nRestart=always\nRestartSec=5\n' > /etc/systemd/system/gnome-headless-session@.service.d/10-locumview-restart.conf
systemctl daemon-reload
systemctl enable --now "gnome-headless-session@$U.service"
for _ in $(seq 60); do ss -ltn | grep -q ':3390 ' && break; sleep 2; done
systemctl --no-pager status "gnome-headless-session@$U.service" | head -5
ss -ltnp | grep -E ':(3389|3390) '
echo "ROOT PART DONE"
