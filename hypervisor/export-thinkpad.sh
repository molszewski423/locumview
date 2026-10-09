#!/usr/bin/env bash
# LocumView: export locumview-ref-dev from the ThinkPad (Fedora 45) for the move to node1. See changelog #15.
# Run as root:  sudo bash hypervisor/export-thinkpad.sh
# Read-only for the source VM: it is shut down gracefully, never undefined or modified, and its
# autostart is turned off, so it stays a complete rollback copy (with its snapshots) until node1 is verified.
set -euo pipefail
DOM=locumview-ref-dev
UUID=2604cc64-67d1-40eb-850c-940d67c13402
SRC=/var/lib/libvirt/images/$DOM.qcow2
NVRAM=/var/lib/libvirt/qemu/nvram/${DOM}_VARS.qcow2
OUT=${OUT:-/home/${SUDO_USER:?run with sudo}/locumview-export}
V="virsh -c qemu:///system"
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
install -d -o mike -g mike "$OUT"
exec > >(tee "$OUT/export.log") 2>&1
set -x
date -Is; hostname; rpm -q libvirt-daemon qemu-kvm-core edk2-ovmf swtpm

# 1. Record the source definition and snapshot metadata (evidence; the snapshots are not migrated).
$V dumpxml --inactive "$DOM" > "$OUT/domain.thinkpad.xml"
$V snapshot-list "$DOM"
for s in $($V snapshot-list "$DOM" --name); do $V snapshot-dumpxml "$DOM" "$s" > "$OUT/snapshot-$s.thinkpad.xml"; done

# 2. Graceful shutdown (never destroy). Autostart off so the rollback copy can't come up beside the new one.
if [ "$($V domstate "$DOM")" = running ]; then
  $V shutdown "$DOM"
  for _ in $(seq 180); do [ "$($V domstate "$DOM")" = "shut off" ] && break; sleep 1; done
fi
[ "$($V domstate "$DOM")" = "shut off" ] || { echo "VM did not shut down in 180 s; aborting, nothing exported"; exit 1; }
$V autostart --disable "$DOM" || true

# 3. Disk: active layer only (internal snapshots carry memory state that can't resume on another QEMU/firmware).
qemu-img check "$SRC"
qemu-img info --output=json "$SRC" > "$OUT/disk-info.thinkpad.json"
qemu-img convert -p -O qcow2 "$SRC" "$OUT/$DOM.qcow2"
qemu-img check "$OUT/$DOM.qcow2"

# 4. UEFI variable store (enrolled Secure Boot keys + boot entries): qcow2 -> raw for Debian's OVMF.
qemu-img convert -f qcow2 -O raw "$NVRAM" "$OUT/${DOM}_VARS.fd"
stat -c '%s %n' "$OUT/${DOM}_VARS.fd"

# 5. vTPM state (swtpm 0.10.2 here; node1 has 0.7.1, which may not read it; the import handles that).
tar -C /var/lib/libvirt/swtpm -cpf "$OUT/swtpm-$UUID.tar" "$UUID"

cd "$OUT"
sha256sum "$DOM.qcow2" "${DOM}_VARS.fd" "swtpm-$UUID.tar" > SHA256SUMS
cat SHA256SUMS
chown -R mike:mike "$OUT"
echo "EXPORT DONE"
