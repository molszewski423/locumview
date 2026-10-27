#!/usr/bin/env bash
# Owner run (operator-laptop), ADR 0019 spike step B1 (docs/plans/adr-0019-spike.md): an IdM sub-CA for desktop client
# certificates, a 2-day TLS-client profile derived from caIPAserviceCert, and a CA ACL that lets only hosts in
# locumview-desktops use them. Needs an admin ticket on idm01 (`ssh -t <idm01> kinit admin`).
#   scripts/spike/idm-subca.sh up     create (each only if missing); writes the sub-CA certificate to /dev/shm
#   scripts/spike/idm-subca.sh down   CA ACL, profile, then the sub-CA (disabled, then deleted)
set -euo pipefail
DOMAIN=corp.locumview.com
IDM=${IDM_HOST:-idm01.$DOMAIN}
SUBCA=locumview-spike-clients
PROFILE=locumviewSpikeClient
ssh "$IDM" klist -s || { echo "no Kerberos ticket on $IDM: run ssh -t $IDM kinit admin" >&2; exit 1; }

case "${1:-}" in
up)
  # The profile: caIPAserviceCert with its ID, description, validity (2 days) and extended key usage (client
  # auth only) changed. Each change must hit exactly one line, or nothing is imported.
  # shellcheck disable=SC2087  # expands here on purpose: names only
  ssh "$IDM" bash -s <<REMOTE
set -euo pipefail
t=\$(mktemp -d); trap 'rm -rf \$t' EXIT
ipa ca-show $SUBCA >/dev/null 2>&1 || ipa ca-add $SUBCA --subject="CN=LocumView spike clients,O=${DOMAIN^^}" \
  --desc="ADR 0019 spike: desktop client certificates (throwaway)" >/dev/null
echo "sub-CA $SUBCA present"
if ! ipa certprofile-show $PROFILE >/dev/null 2>&1; then
  ipa certprofile-show caIPAserviceCert --out=\$t/base.cfg >/dev/null
  python3 -I - \$t/base.cfg \$t/client.cfg $PROFILE <<'PY'
import re, sys
src, dst, pid = sys.argv[1:4]
lines = open(src).read().splitlines()
cls = {m.group(1): l.split("=", 1)[1] for l in lines if (m := re.match(r"(policyset\.\w+\.\d+)\.default\.class_id=", l))}
validity = [k for k, v in cls.items() if v == "validityDefaultImpl"]
eku = [k for k, v in cls.items() if v == "extendedKeyUsageExtDefaultImpl"]
assert len(validity) == 1 and len(eku) == 1, (validity, eku)
rules = {
    r"profileId=": f"profileId={pid}",
    r"desc=": "desc=ADR 0019 spike: TLS client certificates for LocumView desktops, 2 days",
    r"name=": "name=LocumView spike client",
    re.escape(validity[0]) + r"\.default\.params\.range=": f"{validity[0]}.default.params.range=2",
    re.escape(validity[0]) + r"\.constraint\.params\.range=": f"{validity[0]}.constraint.params.range=2",
    re.escape(eku[0]) + r"\.default\.params\.exKeyUsageOIDs=": f"{eku[0]}.default.params.exKeyUsageOIDs=1.3.6.1.5.5.7.3.2",
}
out = []
hits = {r: 0 for r in rules}
for l in lines:
    for r, new in rules.items():
        if re.match(r, l):
            print(f"  - {l}\n  + {new}"); l = new; hits[r] += 1; break
    out.append(l)
bad = [r for r, n in hits.items() if n != 1]
assert not bad, f"each change must hit one line: {bad}"
open(dst, "w").write("\n".join(out) + "\n")
PY
  ipa certprofile-import $PROFILE --file=\$t/client.cfg --store=TRUE \
    --desc="ADR 0019 spike: TLS client, 2 days" >/dev/null
fi
echo "profile $PROFILE present"
if ! ipa caacl-show $SUBCA >/dev/null 2>&1; then
  ipa caacl-add $SUBCA --desc="ADR 0019 spike: desktops only" >/dev/null
  ipa caacl-add-ca $SUBCA --cas=$SUBCA >/dev/null
  ipa caacl-add-profile $SUBCA --certprofiles=$PROFILE >/dev/null
  ipa caacl-add-host $SUBCA --hostgroups=locumview-desktops >/dev/null
fi
ipa caacl-show $SUBCA | sed -n 's/^ *\(ACL name\|Enabled\|CAs\|Profiles\|Host Groups\|Hosts\|Users\|Services\|User Groups\|Host category\|User category\|Service category\|CA category\|Profile category\): */  \1: /p'
REMOTE
  # shellcheck disable=SC2029
  ssh "$IDM" "t=\$(mktemp); ipa ca-show $SUBCA --certificate-out=\$t >/dev/null; cat \$t; rm -f \$t" > /dev/shm/spike-subca.pem
  openssl x509 -in /dev/shm/spike-subca.pem -noout -subject -issuer -enddate
  echo "sub-CA certificate (public): /dev/shm/spike-subca.pem"
  ;;
down)
  # shellcheck disable=SC2029
  ssh "$IDM" "ipa caacl-show $SUBCA >/dev/null 2>&1 && ipa caacl-del $SUBCA
              ipa certprofile-show $PROFILE >/dev/null 2>&1 && ipa certprofile-del $PROFILE
              if ipa ca-show $SUBCA >/dev/null 2>&1; then ipa ca-disable $SUBCA; ipa ca-del $SUBCA; fi; true"
  echo "CA ACL, profile and sub-CA removed"
  ;;
*) echo "usage: $0 up | down" >&2; exit 2 ;;
esac
