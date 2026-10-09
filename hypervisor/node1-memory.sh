#!/usr/bin/env bash
# node1 VM memory settings (ADR 0010). Run on node1 as root; idempotent.
#   1. KSM always on, scan rate tuned by the kernel's KSM advisor.
#   2. virtio-balloon free page reporting (+ 10 s guest stats) on every
#      listed VM; a running VM is shut down cleanly and started again,
#      because the balloon device is only rebuilt on a cold start.
# Usage: sudo ./node1-memory.sh [vm ...]   (default: locumview-ref-dev idm01)
set -euo pipefail

VMS=("${@:-locumview-ref-dev idm01}")
read -r -a VMS <<<"${VMS[*]}"

# --- 1. KSM -----------------------------------------------------------------
cat >/etc/tmpfiles.d/locumview-ksm.conf <<'CONF'
# LocumView (ADR 0010): merge identical guest pages across desktop VMs.
w /sys/kernel/mm/ksm/advisor_mode - - - - scan-time
w /sys/kernel/mm/ksm/use_zero_pages - - - - 1
w /sys/kernel/mm/ksm/run - - - - 1
CONF
systemd-tmpfiles --create /etc/tmpfiles.d/locumview-ksm.conf
echo "ksm: run=$(cat /sys/kernel/mm/ksm/run) advisor=$(cat /sys/kernel/mm/ksm/advisor_mode)"

# --- 2. Free page reporting -------------------------------------------------
for vm in "${VMS[@]}"; do
  if virsh dumpxml --inactive "$vm" | grep -q "freePageReporting='on'"; then
    echo "$vm: free page reporting already on"
    continue
  fi
  virt-xml "$vm" --edit --memballoon model=virtio,freePageReporting=on,stats.period=10
  if [[ $(virsh domstate "$vm") == running ]]; then
    echo "$vm: shutting down"
    virsh shutdown "$vm" >/dev/null
    for _ in $(seq 1 180); do
      [[ $(virsh domstate "$vm") == "shut off" ]] && break
      sleep 1
    done
    [[ $(virsh domstate "$vm") == "shut off" ]] || { echo "$vm: did not shut down in 180 s" >&2; exit 1; }
    virsh start "$vm" >/dev/null
    echo "$vm: started"
  fi
done

for vm in "${VMS[@]}"; do
  printf '%s: ' "$vm"; virsh dumpxml "$vm" | grep -o "<memballoon[^>]*>"
done
