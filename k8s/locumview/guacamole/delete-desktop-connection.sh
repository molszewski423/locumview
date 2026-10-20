#!/bin/bash
# Delete a Guacamole connection by name, with its parameters and permissions (cascade). Operator machine; kubectl
# uses KUBECONFIG, so the scoped operator account (k8s/locumview/operator.yaml) is enough. Called by the OpenTofu
# desktop module on destroy (ADR 0013).   k8s/locumview/guacamole/delete-desktop-connection.sh <connection-name>
set -euo pipefail
NAME=${1:?connection name}
q() { printf "%s" "$1" | sed "s/'/''/g"; }
printf "\\\\set name '%s'\nDELETE FROM guacamole_connection WHERE connection_name = :'name' AND parent_id IS NULL;\n" "$(q "$NAME")" |
  kubectl -n locumview exec -i guacamole-db-0 -c postgres -- psql -v ON_ERROR_STOP=1 -q -U postgres -d guacamole
echo "deleted Guacamole connection $NAME (if it existed)"
