#!/usr/bin/env bash
# Create and provision a LocumView desktop from the installer ISO (version-one item 1). Run on node1 as a user in
# group libvirt. The per-desktop values (image/desktop/README.md, "Provisioning") come on stdin, never as
# arguments or files in the repository, for example from the operator's machine:
#   sops -d --output-type dotenv desktops/<name>.sops.env | ssh <node1> locumview/hypervisor/new-desktop.sh <name>
# (IDM_OTP, from `ipa host-add <fqdn> --random`, is appended to that stream: it is one-time, not kept in SOPS.)
#
# It builds a NoCloud seed ISO (label CIDATA: meta-data and user-data for cloud-init, locumview/provision.env for
# locumview-provision.service), installs from the installer ISO with the seed attached, and waits until the desktop
# ejects the seed, which it does only after provisioning succeeded. Then the seed is detached and deleted.
# Site values (site.env): INSTALLER_ISO, DESKTOP_NETWORK (virt-install --network value, default network=default).
set -euo pipefail
NAME=${1:?usage: new-desktop.sh <name>   (provision.env on stdin)}
HERE=$(cd "$(dirname "$0")" && pwd)
SITE=${SITE_ENV:-$HERE/../site.env}; [ -f "$SITE" ] && . "$SITE"
ISO=${INSTALLER_ISO:?set INSTALLER_ISO in site.env}
NET=${DESKTOP_NETWORK:-network=default}
POOL=${DESKTOP_POOL:-locumview}
V=(virsh -q -c qemu:///system)
[[ $NAME =~ ^[a-z][a-z0-9-]{0,62}$ ]] || { echo "bad name: $NAME"; exit 1; }
! "${V[@]}" dominfo "$NAME" >/dev/null 2>&1 || { echo "domain $NAME exists"; exit 1; }

T=$(mktemp -d); chmod 700 "$T"
trap 'find "$T" -type f -exec shred -u {} + 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/seed/locumview"
cat > "$T/seed/locumview/provision.env"
fqdn=$(sed -n 's/^LV_FQDN=//p' "$T/seed/locumview/provision.env")
[ -n "$fqdn" ] || { echo "provision.env on stdin has no LV_FQDN"; exit 1; }
printf 'instance-id: %s-%s\nlocal-hostname: %s\n' "$NAME" "$(date +%Y%m%d%H%M%S)" "$fqdn" > "$T/seed/meta-data"
printf '#cloud-config\nfqdn: %s\nprefer_fqdn_over_hostname: true\n' "$fqdn" > "$T/seed/user-data"
xorriso -as mkisofs -quiet -o "$T/seed.iso" -V cidata -J -R "$T/seed"

# Seed and disk as volumes in the pool (libvirt owns the files; the seed holds secrets until it is deleted).
"${V[@]}" vol-create-as "$POOL" "$NAME-seed.iso" "$(stat -c %s "$T/seed.iso")" --format raw >/dev/null
"${V[@]}" vol-upload --pool "$POOL" "$NAME-seed.iso" "$T/seed.iso"
"${V[@]}" vol-create-as "$POOL" "$NAME.qcow2" "${DESKTOP_DISK:-50G}" --format qcow2 >/dev/null
seed_path=$("${V[@]}" vol-path --pool "$POOL" "$NAME-seed.iso")

# Same machine as the reference desktop: q35, UEFI Secure Boot, a TPM 2.0 for the LUKS key. --wait: virt-install
# boots the installed system itself once the installer reboots.
echo "installing $NAME ($fqdn)"
virt-install --connect qemu:///system --name "$NAME" --osinfo detect=on,require=off \
  --memory "${DESKTOP_MEMORY:-6144}" --vcpus "${DESKTOP_VCPUS:-4}" --cpu host-passthrough --machine q35 \
  --features smm.state=on \
  --boot loader=/usr/share/OVMF/OVMF_CODE_4M.ms.fd,loader.readonly=yes,loader.type=pflash,loader.secure=yes,nvram.template=/usr/share/OVMF/OVMF_VARS_4M.ms.fd \
  --tpm emulator,model=tpm-crb,version=2.0 \
  --disk vol="$POOL/$NAME.qcow2",bus=virtio \
  --disk path="$seed_path",device=cdrom,bus=sata,target.dev=sdz,readonly=on \
  --cdrom "$ISO" --network "$NET",model=virtio --graphics spice --video virtio \
  --autostart --noautoconsole --wait "${INSTALL_WAIT_MINUTES:-45}" 2>&1 | grep -vE 'WARNING|Please file|osinfo' || true
[ "$("${V[@]}" domstate "$NAME")" = running ] || { echo "$NAME is not running after the install"; exit 1; }

# Provisioning ejects the seed when it has finished. Wait for the open tray.
echo "waiting for first-boot provisioning"
for _ in $(seq "${PROVISION_WAIT_SECONDS:-1800}"); do
  "${V[@]}" dumpxml "$NAME" | grep -q "<target dev='sdz' bus='sata' tray='open'/>" && break
  sleep 1
done
if ! "${V[@]}" dumpxml "$NAME" | grep -q "<target dev='sdz' bus='sata' tray='open'/>"; then
  echo "provisioning did not finish; the seed stays attached. On the desktop: journalctl -u locumview-provision"
  exit 1
fi
"${V[@]}" change-media "$NAME" sdz --eject --live --config --force >/dev/null
"${V[@]}" vol-wipe --pool "$POOL" "$NAME-seed.iso" >/dev/null
"${V[@]}" vol-delete --pool "$POOL" "$NAME-seed.iso" >/dev/null
"${V[@]}" domifaddr "$NAME" --source arp 2>/dev/null || true
echo "PROVISIONED $NAME ($fqdn); seed deleted"
