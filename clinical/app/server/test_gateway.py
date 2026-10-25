"""The gateway's security properties, against a fake EHR (httpx MockTransport): launch only from the configured EHR,
PKCE and state, tokens never sent to the browser, reads pinned to the launched patient, GET only."""
import base64
import hashlib
import json
import unittest
from urllib.parse import parse_qs, urlsplit

import httpx
from fastapi.testclient import TestClient

from gateway import COOKIE, Settings, create_app

EHR = "https://ehr.example.org/apis/default/fhir"
APP = "https://clinical.example.org"
TOKEN = "access-token-from-the-ehr"


class FakeEhr:
    def __init__(self):
        self.token_requests, self.searches = [], []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if url == f"{EHR}/.well-known/smart-configuration":
            return httpx.Response(200, json={"authorization_endpoint": "https://ehr.example.org/oauth2/default/authorize",
                                             "token_endpoint": "https://ehr.example.org/oauth2/default/token"})
        if url == "https://ehr.example.org/oauth2/default/token":
            form = parse_qs(request.content.decode())
            self.token_requests.append(form)
            return httpx.Response(200, json={"access_token": TOKEN, "token_type": "Bearer", "expires_in": 3600,
                                             "patient": "patient-1", "scope": "launch user/Observation.read"})
        if request.headers.get("Authorization") != f"Bearer {TOKEN}":
            return httpx.Response(401)
        self.searches.append(request.url)
        if request.url.path.endswith("/Patient/patient-1"):
            return httpx.Response(200, json={"resourceType": "Patient", "id": "patient-1"})
        if "page=2" in url:
            return httpx.Response(200, json={"resourceType": "Bundle", "entry": [{"resource": {"id": "obs-2"}}]})
        if request.url.path.endswith("/Observation"):
            return httpx.Response(200, json={"resourceType": "Bundle", "entry": [{"resource": {"id": "obs-1"}}],
                                             "link": [{"relation": "next", "url": f"{EHR}/Observation?page=2"}]})
        return httpx.Response(200, json={"resourceType": "Bundle", "entry": []})


class GatewayTests(unittest.TestCase):
    def setUp(self):
        self.ehr = FakeEhr()
        settings = Settings(ehr_fhir_base=EHR, client_id="app", client_secret="s3cret", public_url=APP,
                            frame_ancestors="https://ehr.example.org")
        self.client = TestClient(create_app(settings, httpx.MockTransport(self.ehr)), base_url=APP,
                                 follow_redirects=False)

    def launch(self):
        r = self.client.get("/launch", params={"iss": EHR, "launch": "launch-1"})
        self.assertEqual(r.status_code, 302)
        return parse_qs(urlsplit(r.headers["location"]).query)

    def signed_in(self):
        q = self.launch()
        r = self.client.get("/callback", params={"code": "code-1", "state": q["state"][0]})
        self.assertEqual(r.status_code, 302)
        return r

    def test_launch_only_from_the_configured_ehr(self):
        r = self.client.get("/launch", params={"iss": "https://attacker.example/fhir", "launch": "x"})
        self.assertEqual(r.status_code, 400)
        self.assertEqual(self.ehr.searches, [])

    def test_launch_uses_pkce_s256_and_state(self):
        q = self.launch()
        self.assertEqual(q["code_challenge_method"], ["S256"])
        self.assertEqual(q["aud"], [EHR])
        self.assertEqual(q["launch"], ["launch-1"])
        self.assertGreaterEqual(len(q["state"][0]), 40)

    def test_callback_sends_the_verifier_that_matches_the_challenge(self):
        q = self.launch()
        self.client.get("/callback", params={"code": "code-1", "state": q["state"][0]})
        verifier = self.ehr.token_requests[0]["code_verifier"][0]
        challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
        self.assertEqual(challenge, q["code_challenge"][0])
        self.assertEqual(self.ehr.token_requests[0]["client_secret"], ["s3cret"])

    def test_unknown_or_reused_state_is_refused(self):
        self.assertEqual(self.client.get("/callback", params={"code": "c", "state": "forged"}).status_code, 400)
        q = self.launch()
        self.client.get("/callback", params={"code": "c", "state": q["state"][0]})
        self.assertEqual(self.client.get("/callback", params={"code": "c", "state": q["state"][0]}).status_code, 400)

    def test_the_browser_gets_a_hardened_cookie_and_never_the_token(self):
        r = self.signed_in()
        cookie = r.headers["set-cookie"].lower()
        for attribute in ("httponly", "secure", "samesite=lax"):
            self.assertIn(attribute, cookie)
        self.assertNotIn(TOKEN, json.dumps(dict(r.headers)) + r.text)
        context = self.client.get("/api/context")
        self.assertEqual(context.json(), {"patient": "patient-1", "scope": "launch user/Observation.read"})
        self.assertNotIn(TOKEN, context.text)

    def test_no_session_no_data(self):
        self.assertEqual(self.client.get("/api/fhir/Observation").status_code, 401)
        self.assertEqual(self.ehr.searches, [])

    def test_searches_are_pinned_to_the_launched_patient(self):
        self.signed_in()
        r = self.client.get("/api/fhir/Observation", params={"patient": "someone-else", "subject": "x", "category": "laboratory"})
        self.assertEqual(r.status_code, 200)
        first = self.ehr.searches[0]
        self.assertEqual(first.params.get("patient"), "patient-1")
        self.assertNotIn("subject", first.params)
        self.assertEqual(first.params.get("category"), "laboratory")

    def test_pages_are_followed_and_flattened(self):
        self.signed_in()
        r = self.client.get("/api/fhir/Observation").json()
        self.assertEqual([e["resource"]["id"] for e in r["entry"]], ["obs-1", "obs-2"])

    def test_only_allowed_types_and_only_get(self):
        self.signed_in()
        self.assertEqual(self.client.get("/api/fhir/Practitioner").status_code, 404)
        self.assertEqual(self.client.post("/api/fhir/Observation", json={}).status_code, 405)
        self.assertEqual(self.client.get("/api/fhir/Patient").json()["id"], "patient-1")

    def test_security_headers(self):
        r = self.client.get("/api/context")
        self.assertIn("frame-ancestors https://ehr.example.org", r.headers["content-security-policy"])
        self.assertEqual(r.headers["cache-control"], "no-store")
        self.assertEqual(r.headers["x-content-type-options"], "nosniff")


if __name__ == "__main__":
    unittest.main()
