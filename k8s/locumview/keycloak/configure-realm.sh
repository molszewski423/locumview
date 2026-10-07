#!/bin/bash
# Configure the "locumview" realm (ADR 0005). Idempotent: safe to re-run after edits.
# Runs inside the Keycloak pod, as the bootstrap admin whose credentials are already in its environment:
#   kubectl -n locumview exec -i deploy/keycloak -- bash -s < k8s/locumview/keycloak/configure-realm.sh
# Change GUAC_URL when Guacamole's public address changes (Cloudflare Tunnel, ADR 0004).
set -euo pipefail
GUAC_URL=https://login.locumview.com
R=locumview
k() { /opt/keycloak/bin/kcadm.sh "$@" --config /tmp/kcadm.config; }
k config credentials --server http://localhost:8080 --realm master \
  --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD"

# --- Realm and policy ---------------------------------------------------------------------------
k get "realms/$R" >/dev/null 2>&1 || k create realms -s realm="$R" -s enabled=true
k update "realms/$R" \
  -s displayName=LocumView -s 'displayNameHtml=<div class="kc-logo-text"><span>LocumView</span></div>' \
  -s loginTheme=locumview -s sslRequired=external \
  -s registrationAllowed=false -s resetPasswordAllowed=false -s rememberMe=false \
  -s loginWithEmailAllowed=true -s duplicateEmailsAllowed=false \
  -s bruteForceProtected=true -s failureFactor=5 -s permanentLockout=false \
  -s waitIncrementSeconds=60 -s maxFailureWaitSeconds=900 -s maxDeltaTimeSeconds=43200 \
  -s 'passwordPolicy=length(14) and notUsername and passwordHistory(5)' \
  -s otpPolicyType=totp -s otpPolicyAlgorithm=HmacSHA1 -s otpPolicyDigits=6 -s otpPolicyPeriod=30 \
  -s ssoSessionIdleTimeout=1800 -s ssoSessionMaxLifespan=36000 \
  -s accessTokenLifespan=300 -s accessTokenLifespanForImplicitFlow=300 \
  -s eventsEnabled=true -s eventsExpiration=7776000 \
  -s adminEventsEnabled=true -s adminEventsDetailsEnabled=true \
  -s 'attributes.adminEventsExpiration=7776000'
# Events (sign-ins, with IP) and admin events are deleted after 90 days (7776000 s), as the privacy policy states.
echo "realm $R: policy applied"

# master realm (Keycloak administration, break-glass admin kc-bootstrap): same brute-force protection (changelog #33).
k update realms/master -s bruteForceProtected=true -s failureFactor=5 -s permanentLockout=false \
  -s waitIncrementSeconds=60 -s maxFailureWaitSeconds=900 -s maxDeltaTimeSeconds=43200
echo "realm master: brute-force protection applied"

# --- Role and groups ----------------------------------------------------------------------------
k get "roles/mfa-exempt" -r "$R" >/dev/null 2>&1 || k create roles -r "$R" -s name=mfa-exempt \
  -s 'description=Skips TOTP in the locumview-browser flow. Granted only through group locumview-demo (ADR 0005).'
for g in locumview-admins locumview-users locumview-demo; do
  k get groups -r "$R" --fields name --format csv --noquotes | grep -qx "$g" || k create groups -r "$R" -s name="$g"
done
k add-roles -r "$R" --gname locumview-demo --rolename mfa-exempt
echo "role mfa-exempt, groups: ok"

# --- Browser flow: cookie | (password AND (TOTP unless mfa-exempt)) -------------------------------
F=locumview-browser
if ! k get authentication/flows -r "$R" --fields alias --format csv --noquotes | grep -qx "$F"; then
  k create authentication/flows -r "$R" -s alias="$F" -s providerId=basic-flow -s topLevel=true -s builtIn=false \
    -s 'description=Password plus TOTP for everyone except realm role mfa-exempt (ADR 0005)'
  k create "authentication/flows/$F/executions/execution" -r "$R" -s provider=auth-cookie
  k create "authentication/flows/$F/executions/flow" -r "$R" -s alias=locumview-forms -s type=basic-flow -s provider=registration-page-form
  k create authentication/flows/locumview-forms/executions/execution -r "$R" -s provider=auth-username-password-form
  k create authentication/flows/locumview-forms/executions/flow -r "$R" -s alias=locumview-mfa -s type=basic-flow -s provider=registration-page-form
  k create authentication/flows/locumview-mfa/executions/execution -r "$R" -s provider=conditional-user-role
  k create authentication/flows/locumview-mfa/executions/execution -r "$R" -s provider=auth-otp-form
fi
# Requirements and the condition's config are (re)applied every run.
k get "authentication/flows/$F/executions" -r "$R" --fields id,displayName --format csv --noquotes |
while IFS=, read -r id name; do
  case "$name" in
    Cookie|locumview-forms) req=ALTERNATIVE ;;
    locumview-mfa) req=CONDITIONAL ;;
    "Username Password Form"|"OTP Form"|"Condition - user role") req=REQUIRED ;;
    *) echo "unexpected execution: $name"; exit 1 ;;
  esac
  k update "authentication/flows/$F/executions" -r "$R" -b "{\"id\":\"$id\",\"requirement\":\"$req\"}"
  if [ "$name" = "Condition - user role" ]; then
    cfg=$(k get "authentication/flows/$F/executions" -r "$R" --format csv --noquotes --fields id,authenticationConfig | grep "^$id," | cut -d, -f2)
    body='{"alias":"not-mfa-exempt","config":{"condUserRole":"mfa-exempt","negate":"true"}}'
    if [ -z "$cfg" ]; then k create "authentication/executions/$id/config" -r "$R" -b "$body"
    else k update "authentication/config/$cfg" -r "$R" -b "{\"id\":\"$cfg\",${body#\{}"; fi
  fi
  echo "flow: $name -> $req"
done
k update "realms/$R" -s browserFlow="$F"

# --- Guacamole client (implicit flow only; Guacamole 1.6.0 limitation, ADR 0005) ----------------
CID=$(k get clients -r "$R" -q clientId=guacamole --fields id --format csv --noquotes)
[ -n "$CID" ] || { k create clients -r "$R" -s clientId=guacamole; CID=$(k get clients -r "$R" -q clientId=guacamole --fields id --format csv --noquotes); }
k update "clients/$CID" -r "$R" -s name=Guacamole -s protocol=openid-connect -s publicClient=true \
  -s standardFlowEnabled=false -s implicitFlowEnabled=true -s directAccessGrantsEnabled=false \
  -s serviceAccountsEnabled=false -s consentRequired=false -s frontchannelLogout=true \
  -s "redirectUris=[\"$GUAC_URL/\"]" -s "webOrigins=[\"$GUAC_URL\"]" \
  -s "attributes.\"post.logout.redirect.uris\"=$GUAC_URL/"
k get "clients/$CID/protocol-mappers/models" -r "$R" --fields name --format csv --noquotes | grep -qx groups ||
  k create "clients/$CID/protocol-mappers/models" -r "$R" -s name=groups -s protocol=openid-connect \
    -s protocolMapper=oidc-group-membership-mapper -s 'config."claim.name"=groups' -s 'config."full.path"=false' \
    -s 'config."id.token.claim"=true' -s 'config."access.token.claim"=false' -s 'config."userinfo.token.claim"=false'
echo "client guacamole: redirect $GUAC_URL/"
rm -f /tmp/kcadm.config
echo "CONFIGURE DONE"
