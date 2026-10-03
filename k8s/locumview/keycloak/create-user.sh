#!/bin/bash
# Create (or reset) a locumview realm user with a temporary password. Runs inside the Keycloak pod.
# The caller prepends USERNAME, FIRST, LAST, USER_GROUPS (space-separated) and TMP_PASSWORD (empty = keep) on stdin;
# optional EMAIL, PERMANENT_PASSWORD=1 (shared demo password, not forced to change) and NO_SELF_SERVICE=1
# (removes default-roles-locumview, so no account console: a guest can't change the password or add MFA). E.g.:
#   { printf 'USERNAME=%q\nFIRST=%q\nLAST=%q\nGROUPS=%q\nTMP_PASSWORD=%q\n' ...; cat create-user.sh; } |
#     kubectl -n locumview exec -i deploy/keycloak -- bash -s
# The temporary password never appears in arguments or output. First login forces a new password
# (realm policy) and TOTP enrolment (locumview-browser flow) unless the user is in locumview-demo.
set -euo pipefail
R=locumview
k() { /opt/keycloak/bin/kcadm.sh "$@" --config /tmp/kcadm.config; }
k config credentials --server http://localhost:8080 --realm master \
  --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null 2>&1
UID_=$(k get users -r "$R" -q exact=true -q username="$USERNAME" --fields id --format csv --noquotes)
if [ -z "$UID_" ]; then
  k create users -r "$R" -s username="$USERNAME" -s enabled=true -s firstName="$FIRST" -s lastName="$LAST" \
    -s email="${EMAIL:-}" -s emailVerified="$([ -n "${EMAIL:-}" ] && echo true || echo false)"
  UID_=$(k get users -r "$R" -q exact=true -q username="$USERNAME" --fields id --format csv --noquotes)
fi
if [ -n "${TMP_PASSWORD:-}" ]; then   # empty = keep the current password (e.g. only fixing groups)
  umask 077; body=$(mktemp)
  temp=true; [ "${PERMANENT_PASSWORD:-}" = 1 ] && temp=false
  printf '{"type":"password","temporary":%s,"value":"%s"}' "$temp" "$TMP_PASSWORD" > "$body"
  k update "users/$UID_/reset-password" -r "$R" -f "$body"; rm -f "$body"
fi
for g in $USER_GROUPS; do
  GID=$(k get groups -r "$R" --fields id,name --format csv --noquotes | grep ",$g$" | cut -d, -f1)
  [ -n "$GID" ] || { echo "no such group: $g"; exit 1; }
  k update "users/$UID_/groups/$GID" -r "$R" -s realm="$R" -s userId="$UID_" -s groupId="$GID" -n
done
if [ "${NO_SELF_SERVICE:-}" = 1 ]; then
  k remove-roles -r "$R" --uusername "$USERNAME" --rolename "default-roles-$R" 2>/dev/null || true
fi
echo "user $USERNAME: ${TMP_PASSWORD:+password set ($([ "${PERMANENT_PASSWORD:-}" = 1 ] && echo permanent || echo temporary)); }groups: $(k get "users/$UID_/groups" -r "$R" --fields name --format csv --noquotes | tr '\n' ' ')"
rm -f /tmp/kcadm.config
