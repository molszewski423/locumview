# ADR 0019 build plan: one MFA sign-in to the EHR

Written 2026-11-12. Decision: [ADR 0019](../adr/0019-ehr-reachable-only-from-desktops.md). The spike is done and
fully undone (changelog #96, #98). M3 closes when this build passes its tests (owner decision, 2026-10-27).
Status: In progress. Step 2 Done (changelog #144); step 3 built and tried on lv-test17 (changelog #151): certificate works, Remote Desktop credentials fix open.

## Why now

Every EHR session asks for Keycloak and TOTP twice: once before Guacamole, then again in the desktop's Chrome
(oauth2-proxy in front of OpenEMR). After changelog #142, OpenEMR's own sign-in is the only other prompt, and the
SMART launch no longer adds one. This build removes the second Keycloak prompt.

## Owner decisions (approved 2026-11-12, as recommended)

1. **Accept ADR 0019** (status Proposed to Accepted). The spike confirmed the design; nothing in it changed since.
2. **Client certificate validity. Recommendation: 3 days**, with the helper trying to renew every 6 hours and at
   boot once less than 2 days remain, and an alert when less than 1 day remains. A destroyed desktop loses EHR access
   within 3 days at most (Traefik reads no revocation list; ADR 0019 section 5). A desktop shut off for longer
   renews at its next boot, before anyone opens Chrome, because the host keytab stays valid. The spike used 2 days.
3. **Sub-CA lifetime. Recommendation: accept IdM's fixed lifetime and keep a rotation runbook.** `ipa ca-add` takes no
   validity option; upstream sources describe the lightweight sub-CA as getting Dogtag's CA default (20 years in
   practice; the spike's sub-CA had it), which cannot be overridden per CA without unsupported profile edits. The
   key never leaves IdM's CA; the runbook covers replacing the sub-CA (add the new one to Traefik's TLS option next
   to the old, let desktops renew from it, then drop the old). Confirmed at step 2: the sub-CA ends 2046-10-05, the end of IdM's own CA, about 20 years.
4. **The icon (owner direction, 2026-11-12):** the EHR launcher shows the EHR's own icon, set per site; the
   reference desktops use OpenEMR's, taken at build time from the pinned OpenEMR release (not committed), after
   reading OpenEMR's brand page; a neutral EHR icon is the fallback. It ships in the same desktop image as step 3.

## Steps (each reviewed; access changes need the owner's approval)

| Step | What | Who |
|---|---|---|
| 2 | IdM: sub-CA `locumview-desktop-clients`, profile `locumviewDesktopClient`, CA ACL for `locumview-desktops`: `scripts/clinical/idm-desktop-subca.sh up` (no destructive mode). Fresh IdM backup first. The sub-CA's public certificate is committed as `k8s/clinical/desktop-client-ca.pem`. | owner run; agent checks with `status` |
| 3 | Desktop image: a LocumView RPM with tpm2-pkcs11, the renewal helper and its timer, token creation and TPM access at a user's first sign-in, the Chrome policy `AutoSelectCertificateForUrls` (issuer filter) in the one managed policy file, and the launcher icon. Built, scanned, tried on a `:testing` desktop. | agent builds; owner applies the test desktop |
| 4 | Cluster: Traefik `TLSOption` (`RequireAndVerifyClientCert`, the sub-CA only) on the `emr.` and `clinical.` routers; then oauth2-proxy, its Keycloak client, the `sso` middleware, its Secrets and network policies removed, and `login.locumview.com` out of the EHR's Chrome allowlist. | owner approves the cut-over |
| 5 | Tests: the M3 step 6 checks from a desktop (one Keycloak prompt, OpenEMR sign-in, SMART launch with findings); a laptop on the LAN refused at the handshake; a renewal observed; a reboot check. | owner and agent |

Then the ADR's status moves to Built, M3 closes, and `:stable` is promoted only with the owner's approval.

## Safety rules carried from the spike

- Nothing destructive acts on a search result (changelog #98): every revoke or delete names one object, re-read
  before acting. No script here revokes or deletes anything.
- A fresh IdM backup before any IdM change: `sudo systemctl start idm01-backup.service` on the backup host.
- The TPM's dictionary-attack counter: the build checks that a desktop user cannot lock out the disk-unlock objects.
