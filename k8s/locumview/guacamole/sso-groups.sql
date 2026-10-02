-- Guacamole user groups matching the Keycloak groups in the OIDC "groups" claim (ADR 0005). Idempotent.
-- Apply: kubectl -n locumview exec -i guacamole-db-0 -c postgres -- psql -v ON_ERROR_STOP=1 -U postgres -d guacamole < k8s/locumview/guacamole/sso-groups.sql
-- Permissions live on the groups, so SSO users need no per-user grants (accounts are auto-created for audit history).
BEGIN;

INSERT INTO guacamole_entity (name, type)
SELECT g, 'USER_GROUP' FROM (VALUES ('locumview-admins'), ('locumview-users'), ('locumview-demo')) v(g)
ON CONFLICT (type, name) DO NOTHING;

INSERT INTO guacamole_user_group (entity_id)
SELECT entity_id FROM guacamole_entity
WHERE type = 'USER_GROUP' AND name IN ('locumview-admins', 'locumview-users', 'locumview-demo')
ON CONFLICT (entity_id) DO NOTHING;

-- Admins: full Guacamole administration.
INSERT INTO guacamole_system_permission (entity_id, permission)
SELECT e.entity_id, p::guacamole_system_permission_type
FROM guacamole_entity e,
     (VALUES ('ADMINISTER'), ('CREATE_CONNECTION'), ('CREATE_CONNECTION_GROUP'),
             ('CREATE_SHARING_PROFILE'), ('CREATE_USER'), ('CREATE_USER_GROUP')) v(p)
WHERE e.type = 'USER_GROUP' AND e.name = 'locumview-admins'
ON CONFLICT DO NOTHING;

-- Users: the reference desktop. (locumview-demo gets only its own demo desktop, added with that VM.)
INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT e.entity_id, c.connection_id, 'READ'
FROM guacamole_entity e, guacamole_connection c
WHERE e.type = 'USER_GROUP' AND e.name IN ('locumview-users', 'locumview-admins')
  AND c.connection_name = 'locumview-ref-dev'
ON CONFLICT DO NOTHING;

COMMIT;

SELECT e.name AS user_group,
       (SELECT string_agg(permission::text, ',' ORDER BY permission) FROM guacamole_system_permission s WHERE s.entity_id = e.entity_id) AS system,
       (SELECT string_agg(c.connection_name, ',') FROM guacamole_connection_permission cp JOIN guacamole_connection c USING (connection_id) WHERE cp.entity_id = e.entity_id) AS connections
FROM guacamole_entity e WHERE e.type = 'USER_GROUP' ORDER BY 1;
