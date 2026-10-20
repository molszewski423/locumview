#!/usr/bin/env bash
# One-time IdM setup for OpenTofu (ADR 0013). Run on a machine that can SSH to the IdM server and encrypt to the
# project's SOPS key; asks for the IdM admin password once (kinit on the server, ticket destroyed at the end).
#   terraform/node1/idm-account.sh <ssh-user>@<idm-server>
# Creates user svc-opentofu (no login anywhere: no HBAC rule includes it) in role "LocumView desktop
# provisioning" with only the Host Administrators, Host Group Administrators and DNS Administrators privileges,
# with a random password that goes straight into idm.sops.yaml and to the server on stdin (never printed, never
# in plain text on disk). Also turns on dynamic DNS updates for the zone, so desktops register themselves, and
# sets its negative-caching time to 60 seconds.
set -euo pipefail
cd "$(dirname "$0")"
IDM=${1:?usage: idm-account.sh <ssh-user>@<idm-server>}
ZONE=${IDM_ZONE:-corp.locumview.com}
U=svc-opentofu ROLE="LocumView desktop provisioning"
[ ! -e idm.sops.yaml ] || { echo "idm.sops.yaml exists; delete it first to replace the account's password"; exit 1; }
pw=''; while [ "${#pw}" -lt 32 ]; do pw+=$(head -c 64 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9'); done; pw=${pw:0:32}

echo "== kinit admin on the IdM server =="
ssh -t "$IDM" kinit admin
trap 'ssh "$IDM" kdestroy -A >/dev/null 2>&1 || true' EXIT
# Run one command on the server: every argument is quoted for the remote shell (printf %q), so descriptions and
# names with spaces or parentheses arrive intact.
# shellcheck disable=SC2029 # expanded here on purpose: cmd is already quoted for the remote shell
r() { local cmd; cmd=$(printf '%q ' "$@"); ssh "$IDM" "$cmd"; }

echo "== account =="
if r ipa user-show "$U" >/dev/null 2>&1; then
  echo "$U exists: setting a new password"
  printf '%s\n%s\n' "$pw" "$pw" | r ipa passwd "$U" >/dev/null
else
  printf '%s\n%s\n' "$pw" "$pw" | r ipa user-add "$U" --first=OpenTofu --last=Provisioning --shell=/sbin/nologin \
    --title="OpenTofu desktop provisioning (ADR 0013), no login" --password >/dev/null
fi
# An administrator-set password is expired at once in IdM; this one is rotated by rerunning this script instead.
r ipa user-mod "$U" --password-expiration=20991231235959Z >/dev/null
printf 'ipa_password: %s\n' "$pw" | sops --encrypt --filename-override terraform/node1/idm.sops.yaml \
  --input-type yaml --output-type yaml /dev/stdin > idm.sops.yaml.tmp && mv idm.sops.yaml.tmp idm.sops.yaml
unset pw

echo "== role =="
r ipa role-show "$ROLE" >/dev/null 2>&1 || r ipa role-add "$ROLE" --desc="Hosts, host groups and their DNS records (OpenTofu, ADR 0013)" >/dev/null
r ipa role-add-privilege "$ROLE" --privileges="Host Administrators" --privileges="Host Group Administrators" --privileges="DNS Administrators" >/dev/null 2>&1 || true
r ipa role-add-member "$ROLE" --users="$U" >/dev/null 2>&1 || true
r ipa role-show "$ROLE" | grep -E 'Role name|Privileges|Member users'

echo "== dynamic DNS updates for $ZONE =="
r ipa dnszone-mod "$ZONE" --dynamic-update=TRUE >/dev/null 2>&1 || true
# Negative-caching time (SOA minimum) 60 s instead of 3600: a desktop's name is looked up (NXDOMAIN) just before
# it registers itself, and resolvers in front of IdM would otherwise keep that answer for an hour (lv-test04).
r ipa dnszone-mod "$ZONE" --setattr=idnssoaminimum=60 >/dev/null 2>&1 || true
r ipa dnszone-show "$ZONE" --all | grep -i -E 'Dynamic update|SOA minimum'

echo "== leftover test host =="
r ipa host-del lv-test01.corp.locumview.com --updatedns >/dev/null 2>&1 && echo "lv-test01 removed" || echo "lv-test01: not there"
echo "== IDM ACCOUNT DONE: idm.sops.yaml written =="
