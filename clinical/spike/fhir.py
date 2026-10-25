#!/usr/bin/env python3
"""Phase 9 lite M1 spike: an OAuth2 client for the disposable OpenEMR started by run.sh.

    fhir.py register             register a confidential API client (run.sh enables it), save it in the run state
    fhir.py get <path>           GET <path> from the FHIR API (for example 'Patient' or 'Observation?patient=<id>')
    fhir.py api <method> <path>  call the standard REST API, request body as JSON on stdin

Credentials are the per-run values in $XDG_RUNTIME_DIR; nothing is printed except API responses. TLS verification
is off because the instance uses the image's self-signed certificate on 127.0.0.1.
"""
import base64
import json
import os
from pathlib import Path
import ssl
import sys
import urllib.parse
import urllib.request

BASE = "https://127.0.0.1:18443"
STATE = Path(os.environ["XDG_RUNTIME_DIR"]) / "locumview-openemr-spike"
# Every scope below is one the instance lists in scopes_supported (/oauth2/default/.well-known/openid-configuration).
SCOPES = ("openid offline_access api:oemr api:fhir user/patient.crus user/encounter.crus user/medical_problem.cruds "
          "user/medication.cruds user/allergy.cruds user/prescription.crds user/Patient.read user/Patient.write "
          "user/Encounter.read user/Observation.read user/DiagnosticReport.read user/Specimen.rs "
          "user/ServiceRequest.rs user/MedicationRequest.read user/Condition.read user/Practitioner.read "
          "user/Organization.read")
TLS = ssl.create_default_context()
TLS.check_hostname = False
TLS.verify_mode = ssl.CERT_NONE


def request(method, url, body=None, headers=None):
    req = urllib.request.Request(url, data=body, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(req, context=TLS, timeout=60) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def admin_password():
    for line in (STATE / "secret.yaml").read_text().splitlines():
        if line.strip().startswith("admin:"):
            return base64.b64decode(line.split(":", 1)[1].strip()).decode()
    raise SystemExit("no admin password in the run state; start the instance with run.sh up")


def register():
    body = {"application_type": "private", "client_name": "locumview-m1-spike", "redirect_uris": [f"{BASE}/"],
            "token_endpoint_auth_method": "client_secret_post", "scope": SCOPES}
    status, data = request("POST", f"{BASE}/oauth2/default/registration", json.dumps(body).encode(),
                           {"Content-Type": "application/json"})
    if status != 200:
        raise SystemExit(f"registration failed: HTTP {status}: {data[:300]!r}")
    client = json.loads(data)
    (STATE / "client.json").write_text(json.dumps({k: client[k] for k in ("client_id", "client_secret")}))
    os.chmod(STATE / "client.json", 0o600)
    print(client["client_id"])


def token():
    client = json.loads((STATE / "client.json").read_text())
    form = {"grant_type": "password", "user_role": "users", "username": "spike-admin", "password": admin_password(),
            "scope": SCOPES, **client}
    status, data = request("POST", f"{BASE}/oauth2/default/token", urllib.parse.urlencode(form).encode(),
                           {"Content-Type": "application/x-www-form-urlencoded"})
    if status != 200:
        raise SystemExit(f"token request failed: HTTP {status}: {data[:300]!r}")
    return json.loads(data)["access_token"]


def call(method, path, body=None):
    """Authorized call; path starts with 'fhir/' or 'api/'. Returns (status, parsed JSON or raw text)."""
    content_type = "application/fhir+json" if path.startswith("fhir/") else "application/json"
    status, data = request(method, f"{BASE}/apis/default/{path}",
                           None if body is None else json.dumps(body).encode(),
                           {"Authorization": f"Bearer {token()}", "Content-Type": content_type,
                            "Accept": content_type})
    try:
        return status, json.loads(data)
    except ValueError:
        return status, data.decode(errors="replace")


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "register":
        register()
    elif command == "get" and len(sys.argv) == 3:
        status, data = request("GET", f"{BASE}/apis/default/fhir/{sys.argv[2]}",
                               headers={"Authorization": f"Bearer {token()}", "Accept": "application/fhir+json"})
        print(data.decode())
        return 0 if status == 200 else 1
    elif command == "api" and len(sys.argv) == 4:
        body = sys.stdin.read().encode() or None
        status, data = request(sys.argv[2].upper(), f"{BASE}/apis/default/api/{sys.argv[3]}", body,
                               {"Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
        print(data.decode())
        return 0 if status in (200, 201) else 1
    else:
        print(__doc__, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
