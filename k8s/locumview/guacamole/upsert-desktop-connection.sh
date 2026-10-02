#!/bin/bash
# Create or update a Guacamole RDP connection from a desktop's SOPS secret (changelog #19). Operator machine.
#   k8s/locumview/guacamole/upsert-desktop-connection.sh <connection-name> <secret.sops.yaml> <user-group>...
# The secret is decrypted in memory and sent to psql on stdin as \set lines: credentials never appear in
# arguments, files or output. Permissions: READ for each listed Guacamole user group (others are revoked).
set -euo pipefail
NAME=${1:?connection name}; SECRET=${2:?secret file}; shift 2
[ $# -ge 1 ] || { echo "give at least one user group"; exit 1; }
x() { sops -d --extract "[\"stringData\"][\"$1\"]" "$SECRET"; }
q() { printf "%s" "$1" | sed "s/'/''/g"; }   # SQL literal escaping for \set values
groups_sql=$(printf "'%s'," "$@"); groups_sql=${groups_sql%,}
{
  printf "\\\\set name '%s'\n\\\\set host '%s'\n\\\\set port '%s'\n" "$(q "$NAME")" "$(q "$(x hostname)")" "$(q "$(x port)")"
  printf "\\\\set rdpuser '%s'\n\\\\set rdppass '%s'\n" "$(q "$(x rdp-username)")" "$(q "$(x rdp-password)")"
  cat <<SQL
BEGIN;
INSERT INTO guacamole_connection (connection_name, protocol)
SELECT :'name', 'rdp' WHERE NOT EXISTS (SELECT 1 FROM guacamole_connection WHERE connection_name = :'name' AND parent_id IS NULL);
DELETE FROM guacamole_connection_parameter WHERE connection_id = (SELECT connection_id FROM guacamole_connection WHERE connection_name = :'name' AND parent_id IS NULL);
INSERT INTO guacamole_connection_parameter (connection_id, parameter_name, parameter_value)
SELECT c.connection_id, p.n, p.v FROM guacamole_connection c,
  (VALUES ('hostname', :'host'), ('port', :'port'), ('username', :'rdpuser'), ('password', :'rdppass'),
          ('security', 'nla'), ('ignore-cert', 'true'), ('resize-method', 'display-update'),
          ('enable-font-smoothing', 'true'), ('enable-wallpaper', 'true'), ('enable-theming', 'true')) p(n, v)
WHERE c.connection_name = :'name' AND c.parent_id IS NULL;
DELETE FROM guacamole_connection_permission cp USING guacamole_connection c, guacamole_entity e
WHERE cp.connection_id = c.connection_id AND cp.entity_id = e.entity_id AND c.connection_name = :'name'
  AND e.type = 'USER_GROUP' AND e.name NOT IN ($groups_sql);
INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT e.entity_id, c.connection_id, 'READ' FROM guacamole_entity e, guacamole_connection c
WHERE e.type = 'USER_GROUP' AND e.name IN ($groups_sql) AND c.connection_name = :'name' AND c.parent_id IS NULL
ON CONFLICT DO NOTHING;
COMMIT;
SELECT c.connection_name, (SELECT string_agg(parameter_name || CASE WHEN parameter_name = 'password' THEN '=***' ELSE '=' || parameter_value END, ' ' ORDER BY parameter_name) FROM guacamole_connection_parameter p WHERE p.connection_id = c.connection_id AND parameter_name <> 'username') AS params,
       (SELECT string_agg(e.name, ',') FROM guacamole_connection_permission cp JOIN guacamole_entity e USING (entity_id) WHERE cp.connection_id = c.connection_id) AS granted_to
FROM guacamole_connection c WHERE c.connection_name = :'name';
SQL
} | kubectl -n locumview exec -i guacamole-db-0 -c postgres -- psql -v ON_ERROR_STOP=1 -q -U postgres -d guacamole
