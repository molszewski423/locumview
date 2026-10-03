#!/bin/bash
# LocumView demo/guest desktop on the reference VM (changelog #22). Run as root on the desktop VM:
#   sudo bash demo-user-root.sh        (expects ~molszewski/.locumview-demo-rdp: 2 lines, RDP user + password,
#                                       staged by the operator from SOPS; shredded here after use)
# Creates local user "demo": same system-wide desktop as everyone (branding, apps, extensions), its own
# headless GNOME session with user-mode GNOME Remote Desktop on port 3391; no sudo, locked password,
# no screen lock, and an egress fence (nftables, by uid): internet yes, home LAN / cluster / VPN ranges no.
set -euo pipefail
U=demo PORT=3391 DNS=192.168.4.45
CRED=/home/molszewski/.locumview-demo-rdp
HERE=$(cd "$(dirname "$0")" && pwd)
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
[ -s "$CRED" ] || { echo "missing $CRED"; exit 1; }
set -x

# 1. Account: no wheel, password locked (no console/SSH login), home 700.
id "$U" >/dev/null 2>&1 || useradd -m -c "LocumView demo (guest)" -s /bin/bash "$U"
passwd -l "$U"
chmod 700 "/home/$U"
id "$U"; ! id -nG "$U" | grep -qw wheel

# 2. Egress fence for the demo uid (outbound only; replies on established flows allowed).
cat > /etc/nftables/locumview-demo.nft <<NFT
table inet locumview_demo
delete table inet locumview_demo
table inet locumview_demo {
  chain output {
    type filter hook output priority 0; policy accept;
    meta skuid != "$U" accept
    oif "lo" accept
    ct state established,related accept
    ip daddr $DNS udp dport 53 accept
    ip daddr $DNS tcp dport 53 accept
    ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10, 169.254.0.0/16 } counter drop
    ip6 daddr { fc00::/7, fe80::/10 } counter drop
  }
}
NFT
cat > /etc/systemd/system/locumview-demo-egress.service <<UNIT
[Unit]
Description=LocumView: egress fence for the demo user (no LAN/cluster access)
After=nftables.service firewalld.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f /etc/nftables/locumview-demo.nft
ExecStop=/usr/sbin/nft delete table inet locumview_demo
[Install]
WantedBy=multi-user.target
UNIT
restorecon -v /etc/nftables/locumview-demo.nft /etc/systemd/system/locumview-demo-egress.service || true
systemctl daemon-reload
systemctl enable --now locumview-demo-egress.service
systemctl restart locumview-demo-egress.service
nft list table inet locumview_demo

# 3. Firewall: guacd (k3s nodes) may reach the demo RDP port.
firewall-cmd --permanent --zone=locumview-gateways --add-port=$PORT/tcp
firewall-cmd --reload
firewall-cmd --zone=locumview-gateways --list-ports

# 4. Headless session (starts the demo user's systemd --user and session bus).
systemctl enable --now "gnome-headless-session@$U.service"
UIDN=$(id -u "$U")
for _ in $(seq 60); do [ -S "/run/user/$UIDN/bus" ] && break; sleep 2; done
as_demo() { runuser -u "$U" -- env XDG_RUNTIME_DIR="/run/user/$UIDN" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UIDN/bus" "$@"; }

# 5. No screen lock for guests (they know no Linux password); front-door timeouts apply instead.
as_demo gsettings set org.gnome.desktop.screensaver lock-enabled false
as_demo gsettings set org.gnome.desktop.lockdown disable-lock-screen true

# 6. User-mode GRD on $PORT with the staged credentials, then start it.
set +x
install -m 755 "$HERE/user-mode-user.sh" /tmp/lv-user-mode-user.sh   # demo cannot read molszewski's home
as_demo env RDP_PORT=$PORT bash /tmp/lv-user-mode-user.sh < "$CRED"
rm -f /tmp/lv-user-mode-user.sh
shred -u "$CRED"
set -x
as_demo systemctl --user restart gnome-remote-desktop-headless.service
for _ in $(seq 30); do ss -ltn | grep -q ":$PORT " && break; sleep 2; done
ss -ltn | grep -E ":(3389|3390|$PORT) "
echo "DEMO ROOT PART DONE"
