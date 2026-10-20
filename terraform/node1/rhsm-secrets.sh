#!/usr/bin/env bash
# Put the Red Hat subscription details for desktops into SOPS (rhsm.sops.yaml), from:
#   - an env file with RHSM_ORG and RHSM_KEY (the activation key; default ~/.config/locumview/rhsm.env), and
#   - the subscription API's offline token, typed in (not echoed): generate it at
#     https://access.redhat.com/management/api ("Generate token").
# Values go straight into sops --encrypt (public key only); nothing is printed or written in plain text.
set -euo pipefail
cd "$(dirname "$0")"
ENV_FILE=${1:-$HOME/.config/locumview/rhsm.env}
[ ! -e rhsm.sops.yaml ] || { echo "rhsm.sops.yaml exists; delete it first to replace it"; exit 1; }
# shellcheck disable=SC1090 # the operator's own env file
. "$ENV_FILE"
: "${RHSM_ORG:?missing in $ENV_FILE}" "${RHSM_KEY:?missing in $ENV_FILE}"
read -r -s -p "Red Hat API offline token: " token; echo
[ "${#token}" -gt 100 ] || { echo "that does not look like an offline token (too short)"; exit 1; }
printf 'rhsm_org: "%s"\nrhsm_activation_key: "%s"\nrhsm_offline_token: "%s"\n' "$RHSM_ORG" "$RHSM_KEY" "$token" |
  sops --encrypt --filename-override terraform/node1/rhsm.sops.yaml --input-type yaml --output-type yaml /dev/stdin > rhsm.sops.yaml.tmp
mv rhsm.sops.yaml.tmp rhsm.sops.yaml
unset token RHSM_KEY
python3 ../../scripts/check-sops-encrypted.py rhsm.sops.yaml && echo "== rhsm.sops.yaml written (encrypted) =="
