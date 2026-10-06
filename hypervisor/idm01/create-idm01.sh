#!/usr/bin/env bash
# Create idm01 on MikePC (ADR 0006, changelog #32). Run on MikePC as a user in group libvirt.
# Needs: base image in pool `locumview` as idm01.qcow2 (RHEL 10.2 qcow2 from Image Builder, resized to 40G),
# and RHSM_ORG / RHSM_KEY in the environment (activation key; never committed).
set -euo pipefail
: "${RHSM_ORG:?}" "${RHSM_KEY:?}"
HERE=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d); chmod 700 "$T"; trap 'shred -u "$T/user-data" 2>/dev/null; rm -rf "$T"' EXIT
envsubst '${RHSM_ORG} ${RHSM_KEY}' < "$HERE/user-data.template" > "$T/user-data"
virt-install --connect qemu:///system --name idm01 --osinfo rhel10-unknown \
  --memory 4096 --vcpus 2 --cpu host-passthrough --machine q35 \
  --boot uefi,loader=/usr/share/OVMF/OVMF_CODE_4M.ms.fd,loader.readonly=yes,loader.type=pflash,loader.secure=yes,nvram.template=/usr/share/OVMF/OVMF_VARS_4M.ms.fd \
  --features smm.state=on \
  --disk vol=locumview/idm01.qcow2,bus=virtio \
  --network bridge=br0,model=virtio,mac=52:54:00:4c:56:47 \
  --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0 \
  --memballoon model=virtio,freePageReporting=on,stats.period=10 \
  --graphics none --console pty,target.type=serial,log.file=/var/log/libvirt/qemu/idm01-serial.log \
  --import --cloud-init user-data="$T/user-data",network-config="$HERE/network-config" \
  --autostart --noautoconsole
