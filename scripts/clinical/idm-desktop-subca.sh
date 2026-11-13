#!/usr/bin/env bash
# Owner run (operator-laptop), ADR 0019 build step 2 (docs/plans/adr-0019-build.md): the IdM sub-CA for LocumView
# desktop client certificates, a short-lived TLS-client profile for EC keys derived from caIPAserviceCert, and a CA
# ACL that lets only hosts in locumview-desktops use them. Derived from the spike's scripts/spike/idm-subca.sh.
# Needs an admin ticket on idm01 (`ssh -t <idm01> kinit admin`). Take a fresh IdM backup first (the runbook says how).
#   scripts/clinical/idm-desktop-subca.sh up       create each piece only if missing; the profile is updated in place
#   scripts/clinical/idm-desktop-subca.sh status   show the pieces, read-only
# There is deliberately no "down": removing a CA is a separate, reviewed step (changelog #98).
# The sub-CA's public certificate goes to k8s/clinical/desktop-client-ca.pem, for Traefik's TLS option (step 4).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
DOMAIN=corp.locumview.com
IDM=${IDM_HOST:-idm01.$DOMAIN}
SUBCA=locumview-desktop-clients
PROFILE=locumviewDesktopClient
VALIDITY_DAYS=3   # owner decision (docs/plans/adr-0019-build.md, decision 2)
OUT=k8s/clinical/desktop-client-ca.pem
ssh "$IDM" klist -s || { echo "no Kerberos ticket on $IDM: run ssh -t $IDM kinit admin" >&2; exit 1; }

status() {
  # shellcheck disable=SC2029
  ssh "$IDM" "ipa ca-show $SUBCA 2>&1 | sed -n 's/^ *\(Name\|Subject DN\|Issuer DN\|Description\): */  \1: /p'
              ipa certprofile-show $PROFILE 2>&1 | sed -n 's/^ *\(Profile ID\|Profile description\|Store issued certificates\): */  \1: /p'
              ipa caacl-show $SUBCA 2>&1 | sed -n 's/^ *\(ACL name\|Enabled\|CAs\|Profiles\|Host Groups\|Hosts\|Users\|Services\|User Groups\|Host category\|User category\|Service category\|CA category\|Profile category\): */  \1: /p'"
}

case "${1:-}" in
up)
  # shellcheck disable=SC2087  # expands here on purpose: names and the validity only
  ssh "$IDM" bash -s <<REMOTE
set -euo pipefail
t=\$(mktemp -d); trap 'rm -rf \$t' EXIT
ipa ca-show $SUBCA >/dev/null 2>&1 || ipa ca-add $SUBCA --subject="CN=LocumView desktop clients,O=${DOMAIN^^}" \
  --desc="ADR 0019: TLS client certificates for LocumView desktops" >/dev/null
echo "sub-CA $SUBCA present"
ipa certprofile-show caIPAserviceCert --out=\$t/base.cfg >/dev/null
python3 -I - \$t/base.cfg \$t/client.cfg $PROFILE $VALIDITY_DAYS <<'PY'
import re, sys
src, dst, pid, days = sys.argv[1:5]
lines = open(src).read().splitlines()
cls = {m.group(1): l.split("=", 1)[1] for l in lines if (m := re.match(r"(policyset\.\w+\.\d+)\.default\.class_id=", l))}
ccls = {m.group(1): l.split("=", 1)[1] for l in lines if (m := re.match(r"(policyset\.\w+\.\d+)\.constraint\.class_id=", l))}
validity = [k for k, v in cls.items() if v == "validityDefaultImpl"]
eku = [k for k, v in cls.items() if v == "extendedKeyUsageExtDefaultImpl"]
keyc = [k for k, v in ccls.items() if v == "keyConstraintImpl"]
assert len(validity) == 1 and len(eku) == 1 and len(keyc) == 1, (validity, eku, keyc)
rules = {
    r"profileId=": f"profileId={pid}",
    r"desc=": f"desc=ADR 0019: TLS client certificates for LocumView desktops, {days} days",
    r"name=": "name=LocumView desktop client",
    re.escape(validity[0]) + r"\.default\.params\.range=": f"{validity[0]}.default.params.range={days}",
    re.escape(validity[0]) + r"\.constraint\.params\.range=": f"{validity[0]}.constraint.params.range={days}",
    re.escape(eku[0]) + r"\.default\.params\.exKeyUsageOIDs=": f"{eku[0]}.default.params.exKeyUsageOIDs=1.3.6.1.5.5.7.3.2",
    re.escape(keyc[0]) + r"\.constraint\.params\.keyType=": f"{keyc[0]}.constraint.params.keyType=EC",
    re.escape(keyc[0]) + r"\.constraint\.params\.keyParameters=": f"{keyc[0]}.constraint.params.keyParameters=nistp256,nistp384",
}
out, hits = [], {r: 0 for r in rules}
for l in lines:
    for r, new in rules.items():
        if re.match(r, l):
            print(f"  - {l}\n  + {new}"); l = new; hits[r] += 1; break
    out.append(l)
bad = [r for r, n in hits.items() if n != 1]
assert not bad, f"each change must hit exactly one line: {bad}"
open(dst, "w").write("\n".join(out) + "\n")
PY
if ipa certprofile-show $PROFILE >/dev/null 2>&1; then
  ipa certprofile-mod $PROFILE --file=\$t/client.cfg >/dev/null
else
  ipa certprofile-import $PROFILE --file=\$t/client.cfg --store=TRUE \
    --desc="ADR 0019: TLS client, $VALIDITY_DAYS days" >/dev/null
fi
echo "profile $PROFILE present"
if ! ipa caacl-show $SUBCA >/dev/null 2>&1; then
  ipa caacl-add $SUBCA --desc="ADR 0019: LocumView desktops only" >/dev/null
  ipa caacl-add-ca $SUBCA --cas=$SUBCA >/dev/null
  ipa caacl-add-profile $SUBCA --certprofiles=$PROFILE >/dev/null
  ipa caacl-add-host $SUBCA --hostgroups=locumview-desktops >/dev/null
fi
REMOTE
  status
  # shellcheck disable=SC2029
  ssh "$IDM" "t=\$(mktemp); ipa ca-show $SUBCA --certificate-out=\$t >/dev/null; cat \$t; rm -f \$t" > "$OUT.tmp"
  openssl x509 -in "$OUT.tmp" -noout -subject -issuer -enddate
  mv "$OUT.tmp" "$OUT"
  echo "wrote $OUT (public certificate): commit it on the build branch"
  ;;
status) status ;;
*) echo "usage: $0 up | status" >&2; exit 2 ;;
esac
