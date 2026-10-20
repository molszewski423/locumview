#!/usr/bin/env bash
# Red Hat subscription registrations, through the subscription management API (the developer subscription counts
# registered systems, so test desktops must not leave theirs behind). The API's offline token is decrypted from a
# SOPS file here, at run time, so it never enters OpenTofu's state.
#   rhsm-systems.sh list                  every registered system: name, last check-in
#   rhsm-systems.sh remove <system-name>  delete every registration with exactly this name (none: no-op)
# Environment: RHSM_SOPS_FILE (with key rhsm_offline_token).
set -euo pipefail
: "${RHSM_SOPS_FILE:?}"
RHSM_OFFLINE_TOKEN=$(sops -d --extract '["rhsm_offline_token"]' "$RHSM_SOPS_FILE")
export RHSM_OFFLINE_TOKEN
exec python3 -I - "$@" <<'PY'
import json, os, sys, time, urllib.error, urllib.parse, urllib.request
api = "https://api.access.redhat.com/management/v1"
def call(r):
    # Red Hat's API answers 502 now and then (seen 2026-10-20); retry server errors and network failures with
    # backoff, so one bad moment does not fail a destroy and leave a registration behind.
    for wait in (5, 15, 45, None):
        try:
            with urllib.request.urlopen(r, timeout=60) as resp:
                return resp.read()
        except urllib.error.HTTPError as e:
            if e.code < 500 or wait is None:
                raise
        except urllib.error.URLError:
            if wait is None:
                raise
        print(f"Red Hat API not answering, retrying in {wait} s", file=sys.stderr)
        time.sleep(wait)
tok = json.loads(call(urllib.request.Request(
    "https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token",
    data=urllib.parse.urlencode({"grant_type": "refresh_token", "client_id": "rhsm-api",
                                 "refresh_token": os.environ.pop("RHSM_OFFLINE_TOKEN")}).encode())))["access_token"]
def req(method, path):
    body = call(urllib.request.Request(api + path, method=method, headers={"Authorization": "Bearer " + tok, "Accept": "application/json"}))
    return json.loads(body) if body else None
systems, offset = [], 0
while True:
    page = req("GET", f"/systems?limit=100&offset={offset}")
    systems += page.get("body", [])
    if len(page.get("body", [])) < 100:
        break
    offset += 100
cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
if cmd == "list":
    for s in sorted(systems, key=lambda s: s.get("name", "")):
        print(f'{s.get("name")}\t{s.get("lastCheckin", "")}')
    print(f"{len(systems)} registered")
elif cmd == "remove" and len(sys.argv) == 3:
    gone = [s for s in systems if s.get("name") == sys.argv[2]]
    for s in gone:
        req("DELETE", f'/systems/{s["uuid"]}')
    print(f"removed {len(gone)} registration(s) named {sys.argv[2]}")
else:
    sys.exit("usage: rhsm-systems.sh list | remove <system-name>")
PY
