#!/bin/bash
# Create or update a Guacamole VNC connection for a Catalyst desktop. Operator machine.
#   printf '%s' "$password" | k8s/locumview/guacamole/upsert-vnc-connection.sh <connection-name> <host> <grantee>...
# The desktop's WayVNC password comes on stdin and never appears in arguments or output. The username is the fixed one
# the desktop's role writes. Permissions: READ for each grantee (others are revoked); a grantee is a Guacamole user
# group, or user:<name> for one user. VNC_PORT (default 5900) sets the port: 15902 with host vnc-tunnel is the
# tunnel to the owner's Catalyst desktop (changelog #170).
# See changelog #105 for what this login does and does not protect, and #106 for `cursor`.
set -euo pipefail
NAME=${1:?connection name}; HOST=${2:?desktop address or name}; shift 2
[ $# -ge 1 ] || { echo "give at least one grantee"; exit 1; }
PORT=${VNC_PORT:-5900}
[[ $PORT =~ ^[0-9]{1,5}$ ]] || { echo "bad VNC_PORT: $PORT"; exit 1; }
IFS= read -r PASSWORD || [ -n "$PASSWORD" ] || { echo "give the VNC password on stdin"; exit 1; }
q() { printf "%s" "$1" | sed "s/'/''/g"; }   # SQL literal escaping for \set values
# Grantees as (type, name) pairs for SQL: user groups by default, user:<name> for a single user.
grantees=""
for g in "$@"; do
  if [[ $g == user:* ]]; then grantees="$grantees('USER','$(q "${g#user:}")'),"
  else grantees="$grantees('USER_GROUP','$(q "$g")'),"; fi
done
grantees=${grantees%,}
{
  printf "\\\\set name '%s'\n\\\\set host '%s'\n\\\\set port '%s'\n\\\\set password '%s'\n" "$(q "$NAME")" "$(q "$HOST")" "$PORT" "$(q "$PASSWORD")"
  cat <<SQL
BEGIN;
INSERT INTO guacamole_connection (connection_name, protocol)
SELECT :'name', 'vnc' WHERE NOT EXISTS (SELECT 1 FROM guacamole_connection WHERE connection_name = :'name' AND parent_id IS NULL);
UPDATE guacamole_connection SET protocol = 'vnc' WHERE connection_name = :'name' AND parent_id IS NULL;
DELETE FROM guacamole_connection_parameter WHERE connection_id = (SELECT connection_id FROM guacamole_connection WHERE connection_name = :'name' AND parent_id IS NULL);
INSERT INTO guacamole_connection_parameter (connection_id, parameter_name, parameter_value)
SELECT c.connection_id, p.n, p.v FROM guacamole_connection c,
  (VALUES ('hostname', :'host'), ('port', :'port'), ('color-depth', '24'), ('disable-copy', 'true'), ('cursor', 'local'),
          ('username', 'vdi'), ('password', :'password')) p(n, v)
WHERE c.connection_name = :'name' AND c.parent_id IS NULL;
DELETE FROM guacamole_connection_permission cp USING guacamole_connection c, guacamole_entity e
WHERE cp.connection_id = c.connection_id AND cp.entity_id = e.entity_id AND c.connection_name = :'name'
  AND (e.type::text, e.name) NOT IN ($grantees);
INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT e.entity_id, c.connection_id, 'READ' FROM guacamole_entity e, guacamole_connection c
WHERE (e.type::text, e.name) IN ($grantees) AND c.connection_name = :'name' AND c.parent_id IS NULL
ON CONFLICT DO NOTHING;
COMMIT;
SELECT c.connection_name, c.protocol,
       (SELECT string_agg(parameter_name || '=' || CASE parameter_name WHEN 'password' THEN '(set)' ELSE parameter_value END, ' ' ORDER BY parameter_name) FROM guacamole_connection_parameter p WHERE p.connection_id = c.connection_id) AS parameters,
       (SELECT string_agg(lower(e.type::text) || ':' || e.name, ',') FROM guacamole_connection_permission cp JOIN guacamole_entity e USING (entity_id) WHERE cp.connection_id = c.connection_id) AS grantees
FROM guacamole_connection c WHERE c.connection_name = :'name';
SQL
} | kubectl -n locumview exec -i guacamole-db-0 -c postgres -- psql -v ON_ERROR_STOP=1 -v VERBOSITY=terse -q -U postgres -d guacamole
