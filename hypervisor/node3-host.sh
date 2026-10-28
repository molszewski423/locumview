#!/usr/bin/env bash
# LocumView hypervisor prep for node3: a Fedora laptop (operator-laptop) kept running as another hypervisor and
# k3s worker (node1 = the AI workstation, node2 = the k3s server). Stage 1 of the
# node3 plan (changelog #99): host only, no k3s (the k3s join is a separate, private homelab script), no VMs.
# Run as root on node3:  sudo bash hypervisor/node3-host.sh          (idempotent)
# Undo everything here:  sudo bash hypervisor/node3-host.sh --undo
#
#   1. Power: battery charges to 80% (starts again at 75%) because the laptop stays on AC; sleep, suspend and
#      hibernate are masked so the machine never sleeps (the lid switch must already be set to ignore).
#   2. Memory (ADR 0010): KSM always on with the kernel's advisor, zero-page merging.
#   3. Storage: VM disks in /var/lib/libvirt/images/locumview, created without btrfs copy-on-write (qcow2 on CoW
#      fragments badly), with the SELinux label of the images directory; libvirt pool "locumview".
#   4. Firewall: intra-zone forwarding in the wired NIC's firewalld zone, so frames bridged between desktop VMs and
#      the LAN pass once k3s loads br_netfilter. No port is opened.
#   5. LAN bridge br0 on the wired NIC (clones its MAC, so the router's DHCP reservation keeps the address; IPv6
#      DNS from the router ignored so .lan names resolve through the LAN DNS server). The switchover runs in a
#      transient systemd unit and rolls back to the original wired profile if br0 does not get the same address
#      and reach the gateway within 60 s. Node values are read from the running system, not from site.env.
set -euo pipefail
LOG=/var/log/locumview-node3-br0.log
IMAGES=/var/lib/libvirt/images/locumview
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
grep -q '^ID=fedora' /etc/os-release || { echo "node3 is the Fedora host"; exit 1; }

NIC=${NIC:-$(ip -o route show default | awk '$0 !~ / dev br0 /{print $5; exit}')}
NIC=${NIC:-$(nmcli -t -f DEVICE,TYPE con show --active | awk -F: '$2=="802-3-ethernet"{print $1; exit}')}

bridge_switch() { # runs inside the transient unit
  exec >>"$LOG" 2>&1
  set -x
  local old ip gw mac zone ok=0
  old=$(nmcli -t -f NAME,DEVICE con show --active | awk -F: -v n="$NIC" '$2==n{print $1; exit}')
  ip=$(ip -4 -o addr show "$NIC" | awk '{print $4; exit}' | cut -d/ -f1)
  gw=$(ip -o route show default dev "$NIC" | awk '{print $3; exit}')
  mac=$(cat "/sys/class/net/$NIC/address")
  zone=$(firewall-cmd --get-zone-of-interface="$NIC")
  [ -n "$old" ] && [ -n "$ip" ] && [ -n "$gw" ] || { echo "RESULT: NOT STARTED (no active wired profile/address on $NIC)"; exit 1; }
  echo "old=$old ip=$ip gw=$gw zone=$zone" > /var/lib/locumview-node3-br0.prev
  nmcli con show br0 >/dev/null 2>&1 || nmcli con add type bridge ifname br0 con-name br0 \
    bridge.stp no bridge.forward-delay 0 bridge.mac-address "$mac" ipv4.method auto ipv6.method auto \
    ipv6.ignore-auto-dns yes connection.zone "$zone" connection.autoconnect yes
  nmcli con show "br0-port-$NIC" >/dev/null 2>&1 || nmcli con add type ethernet ifname "$NIC" \
    con-name "br0-port-$NIC" slave-type bridge master br0 connection.autoconnect yes
  nmcli con mod "$old" connection.autoconnect no
  nmcli con up br0 || true
  nmcli con up "br0-port-$NIC"
  for _ in $(seq 60); do
    if ip -4 -br addr show br0 | grep -q " $ip/" && ping -c1 -W1 "$gw" >/dev/null; then ok=1; break; fi
    sleep 1
  done
  if [ "$ok" != 1 ]; then
    ip -4 -br addr
    nmcli con down "br0-port-$NIC" || true; nmcli con down br0 || true
    nmcli con mod br0 connection.autoconnect no; nmcli con mod "br0-port-$NIC" connection.autoconnect no
    nmcli con mod "$old" connection.autoconnect yes; nmcli con up "$old"
    echo "RESULT: ROLLED BACK (br0 did not get $ip and reach $gw). '$old' restored."
    exit 1
  fi
  echo "RESULT: OK br0 $ip, gateway $gw reachable, zone $(firewall-cmd --get-zone-of-interface=br0)"
}

undo() {
  rm -f /etc/udev/rules.d/90-locumview-battery.rules
  for b in /sys/class/power_supply/BAT*; do echo 100 > "$b/charge_control_end_threshold" 2>/dev/null || true
    echo 0 > "$b/charge_control_start_threshold" 2>/dev/null || true; done
  systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
  rm -f /etc/tmpfiles.d/locumview-ksm.conf; echo 0 > /sys/kernel/mm/ksm/run
  prev=/var/lib/locumview-node3-br0.prev
  [ -f "$prev" ] || prev=/var/lib/locumview-node2-br0.prev # the first run (2026-10-28) used the name node2
  if [ -f "$prev" ]; then
    # shellcheck disable=SC1090
    . "$prev"
    nmcli con mod "$old" connection.autoconnect yes; nmcli con up "$old" || true
    nmcli con delete "br0-port-$NIC" br0 || true
    firewall-cmd --permanent --zone="$zone" --remove-forward >/dev/null; firewall-cmd --reload >/dev/null
  fi
  virsh pool-destroy locumview 2>/dev/null || true; virsh pool-undefine locumview 2>/dev/null || true
  echo "undone (VM image directory $IMAGES kept; remove it by hand once it is empty)"
}

case ${1:-} in
  --bridge) bridge_switch; exit;;
  --undo) undo; exit;;
esac

[ -n "$NIC" ] && [ ! -d "/sys/class/net/$NIC/wireless" ] || { echo "no wired NIC with the default route (plug in Ethernet)"; exit 1; }
speed=$(cat "/sys/class/net/$NIC/speed" 2>/dev/null || echo 0)
echo "== wired NIC $NIC at ${speed} Mb/s"
[ "$speed" -ge 1000 ] || echo "   WARNING: below 1 Gb/s; try another cable or switch port (continuing)"
grep -q 'HandleLidSwitch=ignore' /etc/systemd/logind.conf /etc/systemd/logind.conf.d/*.conf 2>/dev/null \
  || { echo "   lid switch is not set to ignore; set HandleLidSwitch=ignore first"; exit 1; }

echo "== 1. power"
cat > /etc/udev/rules.d/90-locumview-battery.rules <<'RULE'
# LocumView node3: on AC all the time, keep the battery between 75 and 80%.
ACTION=="add|change", SUBSYSTEM=="power_supply", KERNEL=="BAT[0-9]", ATTR{charge_control_end_threshold}="80", ATTR{charge_control_start_threshold}="75"
RULE
for b in /sys/class/power_supply/BAT*; do
  echo 80 > "$b/charge_control_end_threshold"; echo 75 > "$b/charge_control_start_threshold"
  echo "   $(basename "$b"): charge $(cat "$b/charge_control_start_threshold")-$(cat "$b/charge_control_end_threshold")%, now $(cat "$b/capacity")%"
done
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target >/dev/null
echo "   sleep targets masked"

echo "== 2. KSM (ADR 0010)"
cat > /etc/tmpfiles.d/locumview-ksm.conf <<'CONF'
# LocumView (ADR 0010): merge identical guest pages across desktop VMs.
w /sys/kernel/mm/ksm/advisor_mode - - - - scan-time
w /sys/kernel/mm/ksm/use_zero_pages - - - - 1
w /sys/kernel/mm/ksm/run - - - - 1
CONF
systemd-tmpfiles --create /etc/tmpfiles.d/locumview-ksm.conf
echo "   run=$(cat /sys/kernel/mm/ksm/run) advisor=$(cat /sys/kernel/mm/ksm/advisor_mode)"

echo "== 3. VM storage"
if [ ! -d "$IMAGES" ]; then install -d -m 0711 "$IMAGES"; chattr +C "$IMAGES"; fi
restorecon -R "$IMAGES"
echo "   $(lsattr -d "$IMAGES" | awk '{print $1}') $(ls -Zd "$IMAGES" | awk '{print $1}') $IMAGES"
virsh pool-info locumview >/dev/null 2>&1 || virsh pool-define-as locumview dir --target "$IMAGES" >/dev/null
virsh pool-autostart locumview >/dev/null; virsh pool-start locumview >/dev/null 2>&1 || true
echo "   pool: $(virsh pool-info locumview | awk '/State|Autostart/{printf "%s %s ",$1,$2}')"

echo "== 4. firewalld"
zone=$(firewall-cmd --get-zone-of-interface="$NIC" 2>/dev/null || firewall-cmd --get-zone-of-interface=br0)
firewall-cmd --permanent --zone="$zone" --add-forward >/dev/null; firewall-cmd --reload >/dev/null
echo "   zone $zone: forward=$(firewall-cmd --zone="$zone" --query-forward)"

echo "== 5. bridge br0"
if ip -4 -br addr show br0 2>/dev/null | grep -q UP; then
  echo "   br0 already up: $(ip -4 -br addr show br0)"
else
  : > "$LOG"
  systemd-run --unit=locumview-node3-br0 --collect env NIC="$NIC" bash "$(readlink -f "$0")" --bridge
  echo "   switchover running in unit locumview-node3-br0 (SSH may drop for a few seconds); log $LOG"
  for _ in $(seq 120); do grep -q '^RESULT' "$LOG" && break; sleep 1; done
  grep '^RESULT' "$LOG" || { echo "   no result yet; see $LOG"; exit 1; }
fi
echo "done: SELinux $(getenforce); $(ip -4 -br addr show br0)"
