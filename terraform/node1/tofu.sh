#!/usr/bin/env bash
# Run OpenTofu for node1 (ADR 0013). From an operator machine that holds the age key (ADR 0003):
#   ./tofu.sh init | plan | apply | destroy ...
# The state passphrase comes from state.sops.yaml; the IdM password is asked for, never stored.
set -euo pipefail
cd "$(dirname "$0")"
TF_VAR_state_passphrase=$(sops -d --extract '["state_passphrase"]' state.sops.yaml)
export TF_VAR_state_passphrase
case "${1:-}" in
  plan|apply|destroy|refresh|import|console)
    if [ -z "${TF_VAR_ipa_password:-}" ]; then
      read -r -s -p "IdM password for $(sed -n 's/^ipa_username *= *"\(.*\)"/\1/p' site.auto.tfvars 2>/dev/null | grep . || echo admin): " TF_VAR_ipa_password
      echo
      export TF_VAR_ipa_password
    fi ;;
esac
exec tofu "$@"
