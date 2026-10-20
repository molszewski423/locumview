#!/usr/bin/env bash
# Build the LocumView installer ISO: bootc-image-builder's Anaconda ISO with the desktop image embedded and
# kickstart.ks. Root is needed for bootc-image-builder. Run on the build host:
#   sudo image/desktop/install/build-installer-iso.sh <image> <output.iso>
# The image is copied from the invoking user's podman storage; the registry login for the builder image is
# reused from that user's podman. The LUKS installer passphrase is random, used only inside this ISO, and
# replaced at each desktop's first boot.
#
# The installer is built from RHEL packages, so the builder needs RHEL repositories. A subscribed RHEL host
# provides them under /run/secrets; on any other host this script registers a short-lived container with the
# activation key in ~/.config/locumview/rhsm.env (RHSM_ORG, RHSM_KEY), hands its entitlement to the builder in
# the same layout, and unregisters it when the script ends, even on failure.
set -euo pipefail
IMG=${1:?usage: build-installer-iso.sh <image> <output.iso>}
OUT_ISO=${2:?usage: build-installer-iso.sh <image> <output.iso>}
HERE=$(cd "$(dirname "$0")" && pwd)
BASE=registry.redhat.io/rhel10/rhel-bootc:10.2@sha256:e80d87d7eba68cdd0277d37214144adeef854ebb4343e5f410d7b8874e17d7a7
BIB=registry.redhat.io/rhel10/bootc-image-builder:10.2@sha256:ceb3f1329b4849b46b0091aebc17bf25ed95a4cae65c980d16e78d91da844e6c
U=${SUDO_USER:?run with sudo from your own account}
UID_=$(id -u "$U")
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
# Big scratch space (the image archive, osbuild's store, the ISO tree) goes next to the output ISO, not on /var/tmp:
# the root file system filled up during an ISO build (2026-10-20).
WORK=$(mktemp -d -p "$(dirname "$OUT_ISO")" locumview-iso.XXXXXX)
ENT=""
cleanup() {
  if [ -n "$ENT" ] && [ -d "$ENT/pki/consumer" ]; then
    runuser -u "$U" -- podman run --rm -v "$ENT/pki/consumer:/etc/pki/consumer" -v "$ENT/pki/entitlement:/etc/pki/entitlement" \
      "$BASE" subscription-manager unregister >/dev/null 2>&1 && echo "== build entitlement unregistered ==" \
      || echo "WARNING: could not unregister locumview-iso-build; remove it at console.redhat.com (Systems)"
  fi
  [ -n "$ENT" ] && rm -rf "$ENT"
  rm -rf "$WORK"
  # Root's copy of the image is only for this build: drop it, and untagged copies from earlier builds.
  podman rmi -f "$IMG" >/dev/null 2>&1 || true
  podman image prune -f >/dev/null 2>&1 || true
}
trap cleanup EXIT
chmod 700 "$WORK"

echo "== copy $IMG into root's container storage =="
SAVE=$(runuser -u "$U" -- mktemp -d -p "$(getent passwd "$U" | cut -d: -f6)" .locumview-img.XXXXXX)   # the user's own, on /home
runuser -u "$U" -- podman save -q --format oci-archive -o "$SAVE/img.tar" "$IMG"
podman load -q -i "$SAVE/img.tar"; rm -rf "$SAVE"

SECRETS=()
if [ ! -s /usr/share/rhel/secrets/redhat.repo ]; then
  echo "== temporary RHEL entitlement for the build =="
  RHSM_ENV=$(getent passwd "$U" | cut -d: -f6)/.config/locumview/rhsm.env
  [ -s "$RHSM_ENV" ] || { echo "missing $RHSM_ENV"; exit 1; }
  ENT=$(runuser -u "$U" -- mktemp -d -p /var/tmp locumview-rhsm.XXXXXX)
  runuser -u "$U" -- podman run --rm -v "$RHSM_ENV:/run/secrets/rhsm:ro" -v "$ENT:/out" "$BASE" bash -c '
    set -e; . /run/secrets/rhsm
    subscription-manager register --org="$RHSM_ORG" --activationkey="$RHSM_KEY" --name=locumview-iso-build >/dev/null
    mkdir -p /out/pki; cp -a /etc/pki/entitlement /etc/pki/consumer /out/pki/; cp -a /etc/rhsm /out/rhsm
    cp /etc/yum.repos.d/redhat.repo /out/redhat.repo'
  SECRETS=(-v "$ENT/pki/entitlement:/run/secrets/etc-pki-entitlement:ro" -v "$ENT/rhsm:/run/secrets/rhsm:ro"
           -v "$ENT/redhat.repo:/run/secrets/redhat.repo:ro")
fi

echo "== builder image =="
podman pull -q --authfile "/run/user/$UID_/containers/auth.json" "$BIB" >/dev/null

PASS=$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 40)
{
  echo '[customizations.installer.kickstart]'
  echo 'contents = """'
  sed "s/@LUKS_INSTALL_PASSPHRASE@/$PASS/g" "$HERE/kickstart.ks"
  echo '"""'
} > "$WORK/config.toml"
unset PASS
chmod 600 "$WORK/config.toml"

echo "== bootc-image-builder: anaconda-iso =="
install -d -m 700 "$WORK/output" "$WORK/store"
podman run --rm --privileged --pull=never --security-opt label=type:unconfined_t \
  -v "$WORK/config.toml:/config.toml:ro" -v "$WORK/output:/output" -v "$WORK/store:/store" \
  -v /var/lib/containers/storage:/var/lib/containers/storage "${SECRETS[@]}" \
  "$BIB" --type anaconda-iso --use-librepo=True "$IMG"
install -m 600 "$WORK/output/bootiso/install.iso" "$OUT_ISO"
ls -l "$OUT_ISO"
echo DONE
