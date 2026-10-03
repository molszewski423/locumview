#!/bin/bash
# Guacamole break-glass account (ADR 0004/0005). "locumadmin" is DISABLED by default: normal admin access is
# Keycloak SSO + TOTP via group locumview-admins. Enabling it requires cluster-admin (this script) and is
# recorded in the database and Guacamole's logs. Use only when Keycloak is unavailable; disable afterwards.
#   k8s/locumview/guacamole/break-glass.sh status|enable|disable
# While enabled, the local login form is reached through the operator port-forward with SSO priority lowered:
#   kubectl -n locumview set env deploy/guacamole EXTENSION_PRIORITY='*, openid, locumview-branding'
# (revert with `kubectl apply -k k8s/locumview` when done).
set -euo pipefail
case "${1:-status}" in
  enable)  v=true ;;   # disabled = false
  disable) v=false ;;
  status)  v= ;;
  *) echo "usage: $0 status|enable|disable"; exit 1 ;;
esac
sql="SELECT e.name, u.disabled, u.password_date FROM guacamole_user u JOIN guacamole_entity e USING (entity_id) WHERE e.name = 'locumadmin';"
if [ -n "$v" ]; then
  sql="UPDATE guacamole_user u SET disabled = NOT $v FROM guacamole_entity e WHERE u.entity_id = e.entity_id AND e.name = 'locumadmin' AND e.type = 'USER'; $sql"
  echo "$(date -Is) break-glass $1 by $(whoami)@$(hostname)"
fi
kubectl -n locumview exec -i guacamole-db-0 -c postgres -- psql -v ON_ERROR_STOP=1 -U postgres -d guacamole -c "$sql"
