#!/usr/bin/env bash
# Owner run on lv-test17 with sudo, ADR 0019 spike step A6 (docs/plans/adr-0019-spike.md): Chrome selects the TPM
# certificate for mtls-spike.corp.locumview.com without asking, and the URL allowlist lets the page open. Writes two
# managed policy files; Chrome does not merge one list policy from several files, so the allowlist is the image's
# file plus the spike URLs. The image's original is kept once in /root (*.spike-orig); undo: the spike's revert
# script (restores it and deletes the 90- file). ISSUER_CN selects the issuer Chrome picks the certificate by:
# the test CA (default) or "LocumView spike clients" for the IdM sub-CA (B3).
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "STOP: run with sudo"; exit 1; }
[ "$(hostname -s)" = lv-test17 ] || { echo "STOP: not lv-test17"; exit 1; }
POL=/etc/opt/chrome/policies/managed
ORIG=/root/50-locumview-ehr-sites.json.spike-orig
[ -f "$ORIG" ] || cp -p "$POL/50-locumview-ehr-sites.json" "$ORIG"
python3 -I - "$ORIG" "$POL" "${ISSUER_CN:-LocumView spike test CA}" <<'PY'
import json, sys
orig, pol, issuer_cn = sys.argv[1:4]
spike = ["https://mtls-spike.corp.locumview.com"]
sites = json.load(open(orig))
sites["URLAllowlist"] = [u for u in sites["URLAllowlist"] if "18443" not in u] + spike
json.dump(sites, open(f"{pol}/50-locumview-ehr-sites.json", "w"), indent=2)
issuer = {"ISSUER": {"CN": issuer_cn}}
auto = [json.dumps({"pattern": u, "filter": issuer}) for u in spike]
json.dump({"AutoSelectCertificateForUrls": auto}, open(f"{pol}/90-locumview-spike-mtls.json", "w"), indent=2)
PY
chmod 0644 "$POL"/50-locumview-ehr-sites.json "$POL"/90-locumview-spike-mtls.json
restorecon "$POL"/*.json
grep -h -e mtls-spike "$POL"/50-locumview-ehr-sites.json "$POL"/90-locumview-spike-mtls.json
echo "== done; close every Chrome window so it reloads the policies"
