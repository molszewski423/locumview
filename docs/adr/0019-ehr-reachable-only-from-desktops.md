# ADR 0019: The EHR is reachable only from LocumView desktops, with one MFA sign-in

Status: Proposed (revised 2026-10-27 after the spike: the design works on the platform; nothing is built)
Date: 2026-10-26; revised 2026-10-27 (changelog #96, owner decision on renewal)

## Context

Phase 9 lite M3 put the clinical OpenEMR (`emr.corp.locumview.com`) and the clinical app
(`clinical.corp.locumview.com`) behind Keycloak with TOTP, through oauth2-proxy and a Traefik ForwardAuth middleware
(`k8s/clinical/sso.yaml`, changelog #89 and #90). It was the quickest way to keep the rest of the LAN away from
OpenEMR's login page.

The desktop test of M3 step 6 (lv-test17, image `sha256:8c94dcf4…`, 2026-10-26) passed, but showed what that costs a
clinician:

1. Keycloak with password and TOTP, to reach Guacamole and the desktop.
2. Keycloak with password and TOTP **again**, in the desktop's Chrome: it is a different browser from the one used
   for Guacamole, so it has no Keycloak session.
3. OpenEMR's own login (stock OpenEMR, ADR 0017 and the option 4 decision, cannot take its sign-in from Keycloak).
4. The SMART consent screen on each launch.

The DISA Chrome STIG setting `DefaultCookiesSetting` = 4 (session-only cookies, ADR 0016) means steps 2 and 3 come
back every time Chrome is closed. Two MFA prompts within a minute add friction and no assurance: the second one
proves the same person, on the same device, again.

The owner's model for the platform is the usual VDI one: strong sign-in with MFA once at the front door, then the
desktop is the trust boundary; the EHR keeps its own login, and the desktop limits where the browser can go (the
Chrome allowlist of changelog #91, verified on lv-test17).

## Decision

### 1. The desktop is the front door; MFA happens once

Keycloak with TOTP stays in front of Guacamole, unchanged. It is the only MFA. A clinician's day is: Keycloak with
TOTP, the desktop, then OpenEMR's login in the EHR window.

### 2. The EHR names answer only to LocumView desktops (mutual TLS)

`emr.` and `clinical.corp.locumview.com` require a client certificate at the TLS handshake. Traefik verifies it
against a CA that issues only to LocumView desktops; a client without one (a laptop on the LAN, a phone, a scanner)
is refused before any HTTP request reaches OpenEMR or the gateway.

- **A dedicated IdM sub-CA** (`ipa ca-add`, for example `locumview-desktop-clients`) with a CA ACL that lets only
  hosts in the `locumview-desktops` hostgroup (already set by OpenTofu) request from it, under a certificate profile
  for TLS client authentication with a **short validity** (days, not years).
- **A root renewal helper on each desktop** (a LocumView RPM with a systemd timer) requests and renews the
  certificate with the host's own IdM identity (the host keytab, `ipa cert-request` from the sub-CA), so no new
  credential is handed out. It makes a CSR with the TPM key, checks the issued certificate carries that key, stores
  it on the user's token and removes older ones. Certmonger was tried first and does not fit: it treats an empty
  token PIN as "no PIN" and then cannot save the certificate to the token (spike B3), while Chrome only stays silent
  with an empty PIN (spike Q2). Owner decision, 2026-10-27.
- **Traefik** gets a `TLSOption` with `clientAuth: RequireAndVerifyClientCert` and the sub-CA's certificate only,
  applied to the two clinical routers. These two hostnames are served by no other router, so the TLS option is not
  shared or overridden (Traefik answers 421 if SNI and Host map to different TLS options). Traefik 3.7.13 runs on
  the cluster, past the 3.7.3 fix for the client-certificate bypass with wildcard hosts (CVE-2026-48491); the
  clinical routers use exact hosts in any case.
- **Chrome presents the certificate without asking**, through the managed policy `AutoSelectCertificateForUrls`
  for the two names, filtered on the sub-CA as issuer.
- **oauth2-proxy, its Keycloak client `clinical-sso`, the `sso` middleware, its Secrets and network policies are
  removed**, and `login.locumview.com` leaves the EHR's Chrome allowlist (the desktop's Chrome then reaches only the
  two clinical names).

### 3. The device key cannot leave the desktop, and Chrome does not ask for a PIN

A certificate is only as good as its private key. If a user could copy the key to a laptop, the laptop would pass
for a desktop. The key is therefore created in the **desktop's TPM 2.0** (every desktop has one: OpenTofu's
`tpm-crb` vTPM, also used for disk unlock) through `tpm2-pkcs11` (RHEL 10 AppStream), and Chrome uses it through NSS
as a PKCS#11 token. The key never exists outside the TPM, so it cannot be exported, only used on that machine
(the token reports it `CKA_SENSITIVE`, `CKA_NEVER_EXTRACTABLE`; spike B2).

- **One token per desktop user**, in the user's home (`~/.tpm2_pkcs11`), with an **empty user PIN**: the key's
  protection is the TPM, and a PIN would make Chrome prompt at every start. Chrome finds the token with no
  registration step: the RPM registers tpm2-pkcs11 with p11-kit, and the user's NSS database loads p11-kit's proxy.
- **The certificate's subject is the host**, whichever user's token holds it: the certificate proves "this is a
  LocumView desktop", not who is signed in (section 4).
- **The root helper creates the token** (an ECDSA P-256 key generated in the TPM) the first time a user signs in to
  the desktop, and gives that user read and write access to the TPM resource manager (`/dev/tpmrm0`) for the session.
  Desktop users are not in `tss`. Every wrong authorization to the TPM raises its dictionary-attack counter, so the
  build checks that a user cannot lock out the objects the disk unlock depends on.

The software-key fallback considered earlier (a user with a shell could export the key) is not needed: the spike
showed the TPM path works with Chrome, IdM and Traefik.

### 4. Who may use the EHR

The Keycloak group check (`locumview-clinical`) in front of the EHR goes away. Access is decided by:

- **who can open a desktop:** Guacamole connection permissions, behind Keycloak and TOTP, and IdM HBAC on the
  desktop;
- **who has an OpenEMR account**, and its role in OpenEMR.

For the planned demo access this is simpler: the demo desktop reaches the EHR by being a desktop, and the demo user
signs in with the demo OpenEMR account; no oauth2-proxy group change is needed.

### 5. Revocation

Traefik does not check revocation lists for client certificates. A desktop is cut off by:

- **the short validity:** when OpenTofu destroys a desktop, its IdM host entry is removed, so the helper can no
  longer renew, and the last certificate expires within days. To be decided at build: the validity (the spike used 2
  days) and when the helper renews and alerts;
- **revoking a desktop's certificates in IdM** (`ipa cert-revoke`) does not stop Traefik, which reads no revocation
  list, but stops renewal. They are found by host: `ipa cert-find --hosts=<fqdn>` (filtering by sub-CA or issuer
  returned nothing in the spike);
- **immediately, if needed:** removing the sub-CA from the TLS option (all desktops) or re-issuing the sub-CA. A
  per-desktop immediate cut-off is not offered; if one is ever needed, the answer is a revocation-aware check in
  front of the gateway, decided then.

## Consequences

- One MFA per session instead of two; closing Chrome costs only the OpenEMR login.
- Fewer moving parts in the clinical namespace: no oauth2-proxy, no cross-namespace traffic to Keycloak, no cookie
  secret, no Keycloak client to keep in step.
- New moving parts: an IdM sub-CA and profile, a renewal helper on each desktop (our own code, with its timer,
  retries and an expiry alert), per-user TPM tokens, and a Traefik TLS option. OpenTofu's existing IdM host lifecycle
  covers issue and cut-off.
- The sub-CA's own lifetime must be set: IdM gives a sub-CA 20 years by default. The owner chooses a lifetime and a
  rotation runbook at build time.
- A browser on the owner's laptops (operator-laptop, suse-laptop) can no longer open the EHR directly. Testing and administration go
  through a desktop, or `kubectl port-forward` for maintenance.
- The `Secure` cookie gap in OpenEMR (open item from M3 step 4) stays open and is unaffected.
- The STIG session-only cookie setting stays as it is; no deviation is needed.

## Build plan (each step reviewed; access changes need the owner's approval)

1. ~~**Spike on lv-test17**~~ Done 2026-10-27 (changelog #96, `docs/plans/adr-0019-spike.md`); its throwaway pieces
   are undone before step 3's test.
2. IdM: the sub-CA, the profile and the CA ACL (owner run; a script in `scripts/clinical/`).
3. Image and provisioning: tpm2-pkcs11, the renewal helper and its timer, token creation and TPM access at a user's
   first sign-in, the Chrome policy (as a LocumView RPM). Built, scanned, tried on a `:testing` desktop.
4. Cluster: the Traefik TLS option on both routers, then oauth2-proxy and its pieces removed (an access change: the
   owner approves the cut-over).
5. Test from a desktop (the M3 step 6 checks again) and from a laptop on the LAN (refused at the handshake).

## Alternatives considered

- **Keep Keycloak in front, without TOTP for the `clinical-sso` client.** Removes the second MFA but not the second
  sign-in, and still leaves the EHR's login page one password away from the whole LAN.
- **Allow the desktops' IP addresses.** Traefik's service runs with `externalTrafficPolicy: Cluster`, so it does not
  reliably see the client's address; changing that affects every service on the cluster. Desktops share the LAN with
  other devices, so an address is weak evidence of anything.
- **Keycloak trusts the desktop's Kerberos ticket (SPNEGO).** Removes the second prompt, but the headless desktop
  session does not obviously hold a Kerberos ticket, and Keycloak stays in the EHR's path. It keeps per-user identity
  at the gateway, which mTLS does not; worth revisiting if the EHR ever needs it.
- **Keep EHR cookies across Chrome restarts** (`CookiesAllowedForUrls`). Fixes only the repeat after closing Chrome,
  at the price of a STIG deviation; the double MFA stays.

## Facts checked (2026-10-26)

- Traefik's TLS options apply at the handshake, keyed by host; different options for SNI and Host give 421
  (Traefik v3.7 TLS options reference). CVE-2026-48491 (client-certificate bypass with wildcard hosts, fixed in
  3.7.3). The cluster runs `rancher/mirrored-library-traefik:3.7.13`.
- `tpm2-pkcs11` 1.9.0 is packaged for EL 10 (AppStream).
- `AutoSelectCertificateForUrls` takes URL patterns with an issuer filter; Chrome does not merge the policy from
  several sources, so one managed file holds all entries.
- **Not confirmed yet** (the spike's job): Chrome on RHEL 10 using a tpm2-pkcs11 token through the user's NSS
  database, certmonger issuing into that token, and the policy working on Linux exactly as documented for Windows
  and macOS.

## Spike results (2026-10-27, changelog #96)

- **Key in the TPM:** an ECDSA P-256 key generated through tpm2-pkcs11, flagged `CKA_SENSITIVE`,
  `CKA_NEVER_EXTRACTABLE`; the software NSS database holds no key. Not yet shown: the token's files are useless on
  another vTPM.
- **Chrome:** with an empty token PIN, Chrome on RHEL 10 presents the certificate with no PIN prompt and no picker,
  through `AutoSelectCertificateForUrls` filtered on the issuer.
- **Traefik 3.7.13:** a `TLSOption` with `RequireAndVerifyClientCert` refuses a client with no certificate or with
  one from another CA at the handshake; SNI and Host pointing at different options gives 421 both ways.
- **IdM:** a sub-CA, a TLS-client profile derived from `caIPAserviceCert` (its key constraint must allow EC), a CA
  ACL for `locumview-desktops`; the host keytab is enough to request and renew.
- **Certmonger:** works with a PIN in a root-only file (issues, renews into the same TPM key, once the request names
  `-G EC -g 256` and the store is found at `/etc/tpm2_pkcs11`), but not with the empty PIN Chrome needs; hence the
  renewal helper.
- **End to end:** the helper issued and renewed into the user's token twice (new serial, same key), Traefik trusted
  only the sub-CA, and the desktop's Chrome reached the endpoint silently.

