#!/bin/bash
# Entitlement for dnf inside one RUN step of the image build, then gone again. Usage inside a RUN:
#   source /src/image/desktop/scripts/rhsm.sh; rhsm_on; dnf ...; rhsm_off
# The activation key comes from the build secret "rhsm" (lines RHSM_ORG=... and RHSM_KEY=...), mounted at
# /run/secrets/rhsm only for that step, so it never lands in an image layer. On a subscribed RHEL host podman
# shares the host's entitlement instead and no secret is needed: then this does nothing.
rhsm_on() {
  if [ -s /run/secrets/rhsm ]; then
    # shellcheck disable=SC1091
    . /run/secrets/rhsm
    # A fixed name, so a registration left by a build that died can be found and removed by name
    # (terraform/modules/libvirt-desktop/scripts/rhsm-systems.sh remove locumview-image-build).
    subscription-manager register --org="${RHSM_ORG:?}" --activationkey="${RHSM_KEY:?}" --name=locumview-image-build --force >/dev/null
    unset RHSM_ORG RHSM_KEY
    LV_RHSM_REGISTERED=1
    # Unregister even when a later command in this RUN step fails (set -e): the subscription counts systems.
    trap rhsm_off EXIT
  fi
}
rhsm_off() {
  dnf clean all >/dev/null
  if [ "${LV_RHSM_REGISTERED:-0}" = 1 ]; then
    subscription-manager unregister >/dev/null || true
    subscription-manager clean >/dev/null || true
  fi
  rm -rf /var/cache/dnf /var/log/rhsm /var/lib/rhsm/* 2>/dev/null || true
}
