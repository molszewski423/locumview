#!/usr/bin/env bash
# Run OpenTofu for node4 (ADR 0013; same module and secrets as node1, own state). From an operator machine that holds the age key (ADR 0003):
#   ./tofu.sh init | plan | apply | destroy ...
# The state passphrase and the IdM account's password come from SOPS; neither is written to disk.
set -euo pipefail
cd "$(dirname "$0")"
TF_VAR_state_passphrase=$(sops -d --extract '["state_passphrase"]' state.sops.yaml)
export TF_VAR_state_passphrase
case "${1:-}" in
  plan|apply|destroy|refresh|import|console)
    # The OpenTofu IdM account's password (idm.sops.yaml, written by idm-account.sh); typed in if there is none.
    if [ -z "${TF_VAR_ipa_password:-}" ]; then
      if [ -f idm.sops.yaml ]; then
        TF_VAR_ipa_password=$(sops -d --extract '["ipa_password"]' idm.sops.yaml)
      else
        read -r -s -p "IdM password: " TF_VAR_ipa_password; echo
      fi
      export TF_VAR_ipa_password
    fi ;;
esac
exec tofu "$@"
