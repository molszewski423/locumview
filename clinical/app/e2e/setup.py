#!/usr/bin/env python3
"""Prepare the local end-to-end test (clinical/app/e2e.sh): register the gateway with the local OpenEMR as a
confidential SMART client, enable it, and write the gateway's and the browser test's settings.

    setup.py <patient number>     for example LV-bsi-enterobacter-ampc-01

Everything goes to the run's tmpfs state directory with mode 0600: the client secret, gateway.env and e2e.env (which
holds the local OpenEMR administrator's per-run password for the browser test). Nothing secret is printed.
"""
import base64
import json
import os
from pathlib import Path
import ssl
import subprocess
import sys
import urllib.request

HERE = Path(__file__).resolve().parent
RUN = HERE.parent.parent / "spike" / "run.sh"
STATE = Path(os.environ["XDG_RUNTIME_DIR"]) / "locumview-openemr-spike"
EMR = "https://127.0.0.1:18443"
GATEWAY = "https://127.0.0.1:8443"
NAME = "LocumView Clinical (gateway)"
sys.path.insert(0, str(HERE.parent / "server"))
from scopes import SCOPES  # noqa: E402  (the scopes the gateway requests are the ones it registers)


def private(name: str, content: str) -> None:
    fd = os.open(STATE / name, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.write(fd, content.encode())
    os.close(fd)


def sql(statement: str) -> str:
    return subprocess.run([str(RUN), "sql"], input=statement, text=True, capture_output=True, check=True).stdout


def main() -> None:
    number = sys.argv[1]
    tls = ssl.create_default_context()
    tls.check_hostname, tls.verify_mode = False, ssl.CERT_NONE  # the local instance's self-signed certificate
    body = {"application_type": "private", "client_name": NAME, "token_endpoint_auth_method": "client_secret_post",
            "redirect_uris": [f"{GATEWAY}/callback"], "initiate_login_uri": f"{GATEWAY}/launch", "scope": SCOPES}
    request = urllib.request.Request(f"{EMR}/oauth2/default/registration", data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
    client = json.loads(urllib.request.urlopen(request, context=tls).read())
    # The local stand-in for an administrator approving the client (Administration > System > API Clients).
    sql(f"UPDATE oauth_clients SET is_enabled = 1 WHERE client_id = '{client['client_id']}';")
    private("client-secret", client["client_secret"])
    private("gateway.env", "".join(f"{k}={v}\n" for k, v in {
        "EHR_FHIR_BASE": f"{EMR}/apis/default/fhir", "CLIENT_ID": client["client_id"],
        "CLIENT_SECRET_FILE": "/run/gateway/client-secret", "PUBLIC_URL": GATEWAY, "STATIC_DIR": "/dist",
        "EHR_TLS_VERIFY": "false", "FRAME_ANCESTORS": EMR}.items()))
    password = next(base64.b64decode(line.split(":", 1)[1].strip()).decode()
                    for line in (STATE / "secret.yaml").read_text().splitlines() if line.strip().startswith("admin:"))
    pid = sql(f"SELECT pid FROM patient_data WHERE pubpid = '{number}';").splitlines()[-1]
    case = json.loads((HERE.parent.parent / "scenarios" / "cases" / f"{number.removeprefix('LV-')}.json").read_text())
    organism = next((c["organism"]["text"] for c in case.get("cultures", []) if "organism" in c), "")
    private("e2e.env", "".join(f"{k}={v}\n" for k, v in {
        "OE_USER": "spike-admin", "OE_PASS": password, "PID": pid, "APP_NAME": NAME, "APP_URL": f"{GATEWAY}/",
        "EXPECT_NAME": f"{case['patient']['given']} {case['patient']['family']}", "EXPECT_ORGANISM": organism}.items()))
    print(f"registered '{NAME}' and wrote the test settings for {number}")


if __name__ == "__main__":
    main()
