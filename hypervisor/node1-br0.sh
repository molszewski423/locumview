#!/usr/bin/env bash
# LocumView hypervisor prep (Phase 2, manual step; target: Ansible "hypervisor" role).
# MikePC (Debian 13, k3s server, --node-ip=192.168.4.54): LAN bridge br0 so desktop VMs get LAN addresses
# that guacd pods on any k3s node can reach. See changelog #15.
# Run as root:  sudo bash hypervisor/mikepc-br0.sh
#
# br0 clones the NIC's MAC, so the router's DHCP hands back the same 192.168.4.54 and k3s is unaffected.
# The switchover runs in a transient systemd unit (an SSH drop can't stop it halfway) and rolls back to the
# original wired profile if br0 doesn't get 192.168.4.54 and reach the gateway within 60 s.
set -euo pipefail
NIC=enp8s0
OLD="Wired connection 1"
EXPECT_IP=192.168.4.54
GW=192.168.4.1
LOG=/var/log/locumview-br0.log
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }

if [ "${1:-}" != --apply ]; then
  : > "$LOG"
  systemd-run --unit=locumview-br0 --collect bash "$(readlink -f "$0")" --apply
  echo "Switchover running in unit locumview-br0; log: $LOG (SSH may drop for a few seconds)"
  for _ in $(seq 120); do grep -q '^RESULT' "$LOG" && break; sleep 1; done
  cat "$LOG"
  exit 0
fi

exec >>"$LOG" 2>&1
set -x
MAC=$(cat /sys/class/net/$NIC/address)
nmcli con show br0 >/dev/null 2>&1 || nmcli con add type bridge ifname br0 con-name br0 \
  bridge.stp no bridge.forward-delay 0 bridge.mac-address "$MAC" \
  ipv4.method auto ipv6.method auto connection.autoconnect yes
nmcli con show "br0-port-$NIC" >/dev/null 2>&1 || nmcli con add type ethernet ifname "$NIC" \
  con-name "br0-port-$NIC" slave-type bridge master br0 connection.autoconnect yes
nmcli con mod "$OLD" connection.autoconnect no
nmcli con up br0 || true
nmcli con up "br0-port-$NIC"

ok=0
for _ in $(seq 60); do
  if ip -4 -br addr show br0 | grep -q "$EXPECT_IP/" && ping -c1 -W1 "$GW" >/dev/null; then ok=1; break; fi
  sleep 1
done
if [ "$ok" != 1 ]; then
  ip -4 -br addr
  nmcli con down "br0-port-$NIC" || true
  nmcli con down br0 || true
  nmcli con mod "$OLD" connection.autoconnect yes
  nmcli con mod br0 connection.autoconnect no
  nmcli con mod "br0-port-$NIC" connection.autoconnect no
  nmcli con up "$OLD"
  echo "RESULT: ROLLED BACK (br0 did not get $EXPECT_IP + gateway). Original profile restored."
  exit 1
fi

# k3s loads br_netfilter (bridge-nf-call-iptables=1), so frames bridged inside br0 traverse iptables FORWARD.
# Accept them explicitly; a oneshot unit re-adds the rule at boot (after k3s, which owns other FORWARD rules).
iptables -S FORWARD | head -1
cat > /etc/systemd/system/locumview-br0-forward.service <<'UNIT'
[Unit]
Description=LocumView: accept VM traffic bridged within br0 (br_netfilter is on for k3s)
After=network-online.target k3s.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'iptables -C FORWARD -i br0 -o br0 -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -i br0 -o br0 -j ACCEPT'

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now locumview-br0-forward.service

# flannel picks its VXLAN interface from --node-ip at start; that address now lives on br0.
systemctl restart k3s
for _ in $(seq 90); do
  kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get node mikepc -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q True && break
  sleep 2
done
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get nodes -o wide
bridge link show
ip -4 -br addr show br0
echo "RESULT: OK"
