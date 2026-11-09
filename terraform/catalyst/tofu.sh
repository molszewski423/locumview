#!/usr/bin/env bash
# Run OpenTofu for the Catalyst contributor VMs on node1. From an operator machine that holds the age key (ADR 0003):
#   ./tofu.sh bundle <Catalyst checkout>   a git bundle of Catalyst's main for the VMs' first provisioning
#   ./tofu.sh init | plan | apply | destroy ...
# The state passphrase and the IdM account's password come from SOPS; neither is written to disk. The IdM account is
# node1's (../node1/idm.sops.yaml, written by ../node1/idm-account.sh).
set -euo pipefail
cd "$(dirname "$0")"
BUNDLE=${CATALYST_BUNDLE:-$HOME/.cache/locumview/catalyst.bundle}
if [ "${1:-}" = bundle ]; then
  src=${2:?usage: tofu.sh bundle <Catalyst checkout>}
  git -C "$src" fetch -q origin main
  mkdir -p "$(dirname "$BUNDLE")"
  git -C "$src" bundle create -q "$BUNDLE.tmp" origin/main
  git bundle verify -q "$BUNDLE.tmp"
  mv "$BUNDLE.tmp" "$BUNDLE"
  echo "wrote $BUNDLE: Catalyst main at $(git -C "$src" rev-parse --short origin/main)"
  exit 0
fi
TF_VAR_state_passphrase=$(sops -d --extract '["state_passphrase"]' state.sops.yaml)
export TF_VAR_state_passphrase
case "${1:-}" in
  plan|apply|destroy|refresh|import|console)
    if [ -z "${TF_VAR_ipa_password:-}" ]; then
      TF_VAR_ipa_password=$(sops -d --extract '["ipa_password"]' ../node1/idm.sops.yaml)
      export TF_VAR_ipa_password
    fi
    export TF_VAR_catalyst_bundle=${TF_VAR_catalyst_bundle:-$BUNDLE} ;;
esac
exec tofu "$@"
