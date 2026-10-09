#!/usr/bin/env bash
# Create idm01 on node1 (ADR 0006, changelog #32). Run on node1 as a user in group libvirt.
# Needs: base image in pool `locumview` as idm01.qcow2 (RHEL 10.2 qcow2 from Image Builder, resized to 40G),
# RHSM_ORG / RHSM_KEY (activation key) and ADMIN_PASSWORD_HASH (`openssl passwd -6`) in the environment, never
# committed, and site.env (see site.env.example) for the addresses and ADMIN_SSH_KEYS_FILE.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "${SITE_ENV:-$HERE/../../site.env}"
: "${RHSM_ORG:?}" "${RHSM_KEY:?}" "${ADMIN_PASSWORD_HASH:?}" "${IDM_IP:?}" "${LAN_PREFIX:?}" "${GATEWAY_IP:?}" "${DNS_IP:?}" "${ADMIN_SSH_KEYS_FILE:?}"
ADMIN_SSH_KEYS=$(grep -v -e "^#" -e "^$" "$ADMIN_SSH_KEYS_FILE" | sed "s/^/      - /"); export ADMIN_SSH_KEYS IDM_IP LAN_PREFIX GATEWAY_IP DNS_IP ADMIN_PASSWORD_HASH RHSM_ORG RHSM_KEY
T=$(mktemp -d); chmod 700 "$T"; trap 'shred -u "$T/user-data" 2>/dev/null; rm -rf "$T"' EXIT
envsubst '${RHSM_ORG} ${RHSM_KEY} ${ADMIN_PASSWORD_HASH} ${ADMIN_SSH_KEYS} ${IDM_IP}' < "$HERE/user-data.template" > "$T/user-data"
envsubst '${IDM_IP} ${LAN_PREFIX} ${GATEWAY_IP} ${DNS_IP}' < "$HERE/network-config.template" > "$T/network-config"
virt-install --connect qemu:///system --name idm01 --osinfo rhel10-unknown \
  --memory 4096 --vcpus 2 --cpu host-passthrough --machine q35 \
  --boot uefi,loader=/usr/share/OVMF/OVMF_CODE_4M.ms.fd,loader.readonly=yes,loader.type=pflash,loader.secure=yes,nvram.template=/usr/share/OVMF/OVMF_VARS_4M.ms.fd \
  --features smm.state=on \
  --disk vol=locumview/idm01.qcow2,bus=virtio \
  --network bridge=br0,model=virtio,mac=52:54:00:4c:56:47 \
  --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0 \
  --memballoon model=virtio,freePageReporting=on,stats.period=10 \
  --graphics none --console pty,target.type=serial,log.file=/var/log/libvirt/qemu/idm01-serial.log \
  --import --cloud-init user-data="$T/user-data",network-config="$T/network-config" \
  --autostart --noautoconsole
