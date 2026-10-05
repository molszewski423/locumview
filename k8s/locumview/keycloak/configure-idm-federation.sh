#!/bin/bash
# Keycloak user federation from Red Hat IdM (ADR 0006, changelog #34). Idempotent: safe to re-run after edits.
# Runs inside the Keycloak pod as the bootstrap admin. The caller prepends BIND_PASSWORD (IdM system account
# uid=keycloak,cn=sysaccounts,cn=etc,...; created with `ipa sysaccount-add keycloak`) on stdin, e.g.:
#   { printf 'BIND_PASSWORD=%q\n' "$KC_LDAP_BIND_PASSWORD"; cat configure-idm-federation.sh; } |
#     kubectl -n locumview exec -i deploy/keycloak -- bash -s
# The bind password never appears in arguments or output. Prerequisites: the IdM CA in Keycloak's truststore
# (keycloak/idm-ca.pem, KC_TRUSTSTORE_PATHS) and the NetworkPolicy egress to 192.168.4.47:636.
#
# Read-only: IdM is the source of truth; Keycloak never writes to it. Only members of the three locumview-*
# IdM groups are visible to Keycloak. Their IdM groups map onto the existing Keycloak groups of the same name,
# which carry the Guacamole permissions. MFA stays in Keycloak (ADR 0006 update 2026-10-04): OTP credentials of
# federated users are stored in Keycloak, and the locumview-browser flow enrols them on first sign-in.
set -euo pipefail
: "${BIND_PASSWORD:?prepend BIND_PASSWORD=... on stdin}"
R=locumview
NAME=idm
BASE=dc=corp,dc=locumview,dc=com
URL=ldaps://idm01.corp.locumview.com:636
k() { /opt/keycloak/bin/kcadm.sh "$@" --config /tmp/kcadm.config; }
k config credentials --server http://localhost:8080 --realm master \
  --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null 2>&1

FILTER="(|(memberOf=cn=locumview-admins,cn=groups,cn=accounts,$BASE)(memberOf=cn=locumview-users,cn=groups,cn=accounts,$BASE)(memberOf=cn=locumview-demo,cn=groups,cn=accounts,$BASE))"
settings=(
  -s 'config.vendor=["rhds"]' -s 'config.enabled=["true"]' -s 'config.priority=["0"]'
  -s "config.connectionUrl=[\"$URL\"]" -s 'config.useTruststoreSpi=["always"]' -s 'config.startTls=["false"]'
  -s 'config.connectionTimeout=["5000"]' -s 'config.readTimeout=["10000"]'
  -s 'config.authType=["simple"]' -s "config.bindDn=[\"uid=keycloak,cn=sysaccounts,cn=etc,$BASE\"]"
  -s "config.bindCredential=[\"$BIND_PASSWORD\"]"
  -s 'config.editMode=["READ_ONLY"]' -s 'config.importEnabled=["true"]' -s 'config.syncRegistrations=["false"]'
  -s "config.usersDn=[\"cn=users,cn=accounts,$BASE\"]" -s 'config.searchScope=["1"]' -s 'config.pagination=["true"]'
  -s 'config.usernameLDAPAttribute=["uid"]' -s 'config.rdnLDAPAttribute=["uid"]' -s 'config.uuidLDAPAttribute=["ipaUniqueID"]'
  -s 'config.userObjectClasses=["inetOrgPerson, organizationalPerson"]' -s "config.customUserSearchFilter=[\"$FILTER\"]"
  -s 'config.trustEmail=["true"]' -s 'config.validatePasswordPolicy=["false"]'
  -s 'config.fullSyncPeriod=["-1"]' -s 'config.changedSyncPeriod=["3600"]' -s 'config.batchSizeForSync=["200"]'
  -s 'config.cachePolicy=["DEFAULT"]'
  -s 'config.allowKerberosAuthentication=["false"]' -s 'config.useKerberosForPasswordAuthentication=["false"]'
)

# --- LDAP provider -------------------------------------------------------------------------------
PID=$(k get components -r "$R" -q name="$NAME" --fields id --format csv --noquotes)
if [ -z "$PID" ]; then
  RID=$(k get "realms/$R" --fields id --format csv --noquotes)
  PID=$(k create components -r "$R" -s name="$NAME" -s providerId=ldap \
    -s providerType=org.keycloak.storage.UserStorageProvider -s parentId="$RID" "${settings[@]}" -i)
  echo "provider $NAME: created"
else
  k update "components/$PID" -r "$R" "${settings[@]}"
  echo "provider $NAME: updated"
fi

# --- Mappers -------------------------------------------------------------------------------------
# The rhds defaults map "first name" to cn (the full name); IdM keeps the given name in givenName.
MID=$(k get components -r "$R" -q parent="$PID" -q name="first name" --fields id --format csv --noquotes)
[ -n "$MID" ] && k update "components/$MID" -r "$R" -s 'config."ldap.attribute"=["givenName"]'

group_settings=(
  -s "config.\"groups.dn\"=[\"cn=groups,cn=accounts,$BASE\"]" -s 'config."group.name.ldap.attribute"=["cn"]'
  -s 'config."group.object.classes"=["groupOfNames"]' -s 'config."preserve.group.inheritance"=["false"]'
  -s 'config."ignore.missing.groups"=["true"]' -s 'config."membership.ldap.attribute"=["member"]'
  -s 'config."membership.attribute.type"=["DN"]' -s 'config."membership.user.ldap.attribute"=["uid"]'
  -s 'config."groups.ldap.filter"=["(|(cn=locumview-admins)(cn=locumview-users)(cn=locumview-demo))"]'
  -s 'config.mode=["READ_ONLY"]' -s 'config."user.roles.retrieve.strategy"=["LOAD_GROUPS_BY_MEMBER_ATTRIBUTE"]'
  -s 'config."memberof.ldap.attribute"=["memberOf"]' -s 'config."groups.path"=["/"]'
  -s 'config."drop.non.existing.groups.during.sync"=["false"]'
)
GID=$(k get components -r "$R" -q parent="$PID" -q name=locumview-groups --fields id --format csv --noquotes)
if [ -z "$GID" ]; then
  k create components -r "$R" -s name=locumview-groups -s providerId=group-ldap-mapper \
    -s providerType=org.keycloak.storage.ldap.mappers.LDAPStorageMapper -s parentId="$PID" "${group_settings[@]}" >/dev/null
  echo "mapper locumview-groups: created"
else
  k update "components/$GID" -r "$R" "${group_settings[@]}"
  echo "mapper locumview-groups: updated"
fi

# --- Checks --------------------------------------------------------------------------------------
for a in testConnection testAuthentication; do
  k create testLDAPConnection -r "$R" -s action="$a" -s componentId="$PID" -s connectionUrl="$URL" \
    -s bindDn="uid=keycloak,cn=sysaccounts,cn=etc,$BASE" -s bindCredential='**********' \
    -s useTruststoreSpi=always -s authType=simple -s startTls=false >/dev/null && echo "$a: OK"
done
rm -f /tmp/kcadm.config
echo "FEDERATION DONE"
