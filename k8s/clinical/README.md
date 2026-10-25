# clinical namespace: OpenEMR, the clinical app and its gateway (Phase 9 lite M3)

OpenEMR 8.4.1 with LocumView's fix (`clinical/images/openemr/`), MariaDB, and the clinical app with its SMART gateway
(`clinical/images/gateway/`), on node2. Design and evidence: `clinical/app/README.md`,
`docs/evidence/clinical/20261025-m3-local-launch/`.

- **Network:** default deny. Traefik reaches OpenEMR (80) and the gateway (8080); the gateway reaches OpenEMR; OpenEMR
  reaches MariaDB; DNS. No pod has internet egress.
- **Pod security:** baseline enforced, restricted warned. MariaDB (as mysql, no capabilities) and the gateway (non-root,
  read-only root filesystem, no capabilities, no service account token) meet restricted; OpenEMR's upstream
  entrypoint starts as root, drops NET_RAW only.
- **Images:** built, signed and SBOM-attested by `.gitea/workflows/clinical-images.yml`; deployed by digest
  (`kustomization.yaml`, `images`).
- **Names:** `emr.corp.locumview.com` (OpenEMR) and `clinical.corp.locumview.com` (the app), IdM DNS and certificates,
  M3 step 3. Until then, checks use `kubectl port-forward`.

## Deploying (owner runs on operator-laptop, in order)

1. `cp k8s/clinical/site.env.example k8s/clinical/site.env` and set `CLINICAL_NODE` (node2's node name).
2. Create the database secret (database and administrator credentials) with `scripts/clinical/make-db-secret.sh`, commit the encrypted file, then
   create the namespace and apply the Secret into it: `kubectl apply -f k8s/clinical/namespace.yaml`, then
   `sops -d k8s/clinical/secrets/clinical-db.sops.yaml | kubectl apply -f -`.
3. `scripts/clinical/verify-images.sh` (needs cosign) verifies the signature and SBOM attestation of every image
   pinned in `kustomization.yaml`; only when it reports all verified, `kubectl apply -k k8s/clinical`.
   The gateway waits for its Secret (step 5); OpenEMR installs itself on first start (a few minutes).
4. When `kubectl -n clinical get pods` shows OpenEMR ready: `scripts/clinical/register-gateway.sh` configures OpenEMR's
   API and public address and registers the gateway; it writes `clinical-gateway.sops.yaml`. Commit it.
5. `sops -d k8s/clinical/secrets/clinical-gateway.sops.yaml | kubectl apply -f -`, then
   `kubectl -n clinical rollout restart deployment/gateway`.

6. `scripts/clinical/load-scenarios.sh` loads the scenario library and the Synthea background patients (M3 step 2b).
   It decrypts nothing: SQL runs inside the MariaDB pod and API calls inside the OpenEMR pod, each with its own
   credentials (`clinical/scenarios/targets.py`). Running it again skips what is already loaded.

Nothing in these steps displays a password or the client secret.
