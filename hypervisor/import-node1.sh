#!/usr/bin/env bash
# LocumView: import locumview-ref-dev on node1 (Debian 13) after export-thinkpad.sh. See changelog #15.
# Run as root:  sudo bash hypervisor/import-node1.sh
# Expects ~/locumview-import/ of the invoking user (export files + locumview-ref-dev.node1.xml). Disk goes under /home
# (root has 30 GiB free, and a full root has caused outages on this cluster before).
set -euo pipefail
DOM=locumview-ref-dev
UUID=2604cc64-67d1-40eb-850c-940d67c13402
IN=${IN:-/home/${SUDO_USER:?run with sudo}/locumview-import}
POOL_DIR=/home/libvirt/images
V="virsh -c qemu:///system"
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
exec > >(tee "$IN/import.log") 2>&1
set -x
date -Is; hostname; dpkg-query -W libvirt-daemon-system qemu-system-x86 ovmf swtpm

cd "$IN"
sha256sum -c SHA256SUMS
if $V dominfo "$DOM" >/dev/null 2>&1; then echo "$DOM already defined here; aborting"; exit 1; fi

# Storage pool under /home.
install -d -m 711 /home/libvirt "$POOL_DIR"
if ! $V pool-info locumview >/dev/null 2>&1; then
  $V pool-define-as locumview dir --target "$POOL_DIR"
  $V pool-autostart locumview
fi
$V pool-start locumview 2>/dev/null || true
mv "$IN/$DOM.qcow2" "$POOL_DIR/$DOM.qcow2"          # same filesystem: a rename, no second copy
chown root:root "$POOL_DIR/$DOM.qcow2"; chmod 600 "$POOL_DIR/$DOM.qcow2"
$V pool-refresh locumview

# UEFI vars (converted from the ThinkPad's qcow2 store).
install -m 600 "$IN/${DOM}_VARS.fd" "/var/lib/libvirt/qemu/nvram/${DOM}_VARS.fd"

# vTPM state; libvirt re-owns it for the swtpm user at start.
install -d /var/lib/libvirt/swtpm
tar -C /var/lib/libvirt/swtpm --no-same-owner -xpf "$IN/swtpm-$UUID.tar"

$V define "$IN/$DOM.node1.xml"
if ! $V start "$DOM"; then
  # swtpm 0.7.1 may not read state written by 0.10.2. Keep that state, start with a fresh vTPM.
  journalctl -u libvirtd -u virtqemud --since -2min --no-pager | tail -20 || true
  mv "/var/lib/libvirt/swtpm/$UUID" "/var/lib/libvirt/swtpm/$UUID.from-thinkpad-swtpm-0.10.2"
  echo "RETRY with a fresh vTPM (old state kept beside it)"
  $V start "$DOM"
fi
$V autostart "$DOM"

# Wait for the guest agent to report the new LAN address (DHCP on br0).
for _ in $(seq 180); do
  $V domifaddr "$DOM" --source agent 2>/dev/null | grep -q '192\.168\.' && break
  sleep 2
done
$V domifaddr "$DOM" --source agent
$V dominfo "$DOM"
echo "IMPORT DONE"
