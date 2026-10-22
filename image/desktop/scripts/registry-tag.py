#!/usr/bin/env python3
"""Point a tag at an existing manifest, byte for byte, so the digest cannot change (changelog #62).

    registry-tag.py <registry>/<repository>@sha256:<digest> <tag>
    registry-tag.py --digest <registry>/<repository>:<tag>     prints the digest the tag points at (empty: none)

Reads the manifest by digest and puts the same bytes under the tag through the registry API (a podman re-push may
re-encode layers and produce a different digest). Credentials: REGISTRY_USER and REGISTRY_TOKEN from the
environment; the Docker token flow is used when the registry asks for it. Prints the tag's digest afterwards, read
back from the registry.
"""
import base64, hashlib, json, os, re, sys, urllib.error, urllib.request

ACCEPT = ", ".join([
    "application/vnd.oci.image.index.v1+json", "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
    "application/vnd.docker.distribution.manifest.v2+json",
])


def main():
    lookup = sys.argv[1] == "--digest"
    if lookup:
        m = re.fullmatch(r"([^/]+)/(.+):([A-Za-z0-9_][A-Za-z0-9_.-]{0,127})", sys.argv[2])
    else:
        m = re.fullmatch(r"([^/]+)/(.+)@(sha256:[0-9a-f]{64})", sys.argv[1])
        tag = sys.argv[2]
    if not m or (not lookup and not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}", tag)):
        sys.exit(__doc__)
    registry, repo, digest = m.groups()
    basic = "Basic " + base64.b64encode(f"{os.environ['REGISTRY_USER']}:{os.environ['REGISTRY_TOKEN']}".encode()).decode()
    auth = {"value": basic}

    def call(method, path, body=None, headers=None, missing_ok=False):
        url = f"https://{registry}/v2/{repo}/{path}"
        for attempt in (1, 2):
            req = urllib.request.Request(url, data=body, method=method,
                                         headers={"Authorization": auth["value"], **(headers or {})})
            try:
                with urllib.request.urlopen(req, timeout=60) as r:
                    return r.read(), r.headers
            except urllib.error.HTTPError as e:
                challenge = e.headers.get("WWW-Authenticate", "")
                if e.code == 404 and missing_ok:
                    return None, {}
                if e.code != 401 or attempt == 2 or not challenge.startswith("Bearer "):
                    raise SystemExit(f"{method} {url}: HTTP {e.code} {e.read()[:200]!r}")
                params = dict(re.findall(r'(\w+)="([^"]*)"', challenge))
                q = "&".join(f"{k}={params[k]}" for k in ("service", "scope") if k in params)
                treq = urllib.request.Request(f"{params['realm']}?{q}", headers={"Authorization": basic})
                with urllib.request.urlopen(treq, timeout=60) as r:
                    t = json.load(r)
                auth["value"] = "Bearer " + (t.get("token") or t["access_token"])

    if lookup:   # here "digest" is the tag
        _, h = call("HEAD", f"manifests/{digest}", headers={"Accept": ACCEPT}, missing_ok=True)
        print(h.get("Docker-Content-Digest", ""))
        return
    body, headers = call("GET", f"manifests/{digest}", headers={"Accept": ACCEPT})
    got = "sha256:" + hashlib.sha256(body).hexdigest()
    if got != digest:
        sys.exit(f"registry returned a manifest with digest {got}, not {digest}")
    ctype = json.loads(body).get("mediaType") or headers.get("Content-Type")
    call("PUT", f"manifests/{tag}", body=body, headers={"Content-Type": ctype})
    _, h = call("HEAD", f"manifests/{tag}", headers={"Accept": ACCEPT})
    now = h.get("Docker-Content-Digest")
    if now != digest:
        sys.exit(f"{tag} now resolves to {now}, expected {digest}")
    print(f"{registry}/{repo}:{tag} -> {digest}")


if __name__ == "__main__":
    main()
