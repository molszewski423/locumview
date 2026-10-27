# Plan: the ADR 0019 spike (mutual TLS from a desktop, TPM-backed key)

Status: **In progress**: part of track A ran on 2026-10-26 before this plan was written (changelog #96): Q1 partly
shown, Q2 found a PIN prompt, the empty-PIN check is next; Q3 and Q4 not started. Written 2026-10-26. Decision under test: ADR 0019 (Proposed). Canary desktop: lv-test17, running
the `:stable` image (`sha256:8c94dcf4…`, promoted 2026-10-26).

## 1. What the spike must answer

ADR 0019 rests on four things nobody has seen work on this platform yet. The spike answers each with a yes or no and
the evidence, nothing more:

| # | Question | Why it matters |
|---|---|---|
| Q1 | Can a desktop make a key **inside its vTPM** through `tpm2-pkcs11`, and is it impossible to export? | The whole design is "the key cannot leave the desktop". |
| Q2 | Does **Chrome on RHEL 10** see that key through the user's NSS database, and present it **without asking** when `AutoSelectCertificateForUrls` matches? | A prompt, or a PIN dialog, would bring back the friction ADR 0019 removes. |
| Q3 | Does **Traefik 3.7** refuse a client with no certificate (or the wrong CA) at the handshake, and let the desktop through? | This is the boundary; it has to be tested, not assumed. |
| Q4 | Can **certmonger** request and renew the certificate from an **IdM sub-CA** into that TPM key, using only the host's own IdM identity? | Without it, every desktop needs a hand-made certificate. |

Q1 to Q3 are tried with a throwaway test CA first (track A), so nothing in IdM changes until the client side is proven.
Q4 (track B) touches IdM and runs only if track A passes.

## 2. Ground rules

- **Nothing in the clinical namespace changes.** `emr.` and `clinical.` keep oauth2-proxy and Keycloak throughout. The
  spike uses its own name, `mtls-spike.corp.locumview.com`, in its own namespace, `mtls-spike`.
- **Root steps on lv-test17 and IdM steps are owner runs**: scripts in `scripts/spike/`, read before they are run, each
  with its undo. The agent prepares, checks results read-only and records them.
- **Every change has an undo**, listed in section 6. The spike ends with all of them done, whatever the outcome.
- **Results go in the changelog either way.** A "no" is a result; ADR 0019's fallback (a software key, recorded as a
  known weakness) comes back to the owner and is never chosen silently.
- Time box: two working sessions. If it runs past that, stop and report what is known.

## 3. Facts to check first (read-only, no changes)

On lv-test17, as the desktop user and with `sudo -l`-free commands where possible:

1. The vTPM is present and usable: `/dev/tpmrm0` exists, its group and mode, `tpm2_getcap properties-fixed` (tpm2-tools
   is in the image).
2. Packages: `tpm2-pkcs11` is **not** in the image (checked in `image/desktop/Containerfile`); `nss-tools` (`modutil`,
   `certutil`) and `certmonger` come with `ipa-client`, to be confirmed with `rpm -q`. (2026-10-27: confirmed; also
   `pkcs11-provider`, `opensc`, `gnutls-utils`. The desktop user is not in `tss`, so `/dev/tpmrm0` needs a grant.)
3. **fapolicyd** mode and rules (the STIG content installs it): a library added outside the image may be denied when
   Chrome loads it. This decides how step A1 adds the package.
4. Chrome's version, `chrome://policy` showing the managed `URLAllowlist` (the spike name has to be allowed too), and
   which NSS database Chrome uses (`~/.pki/nssdb`, sql format).
5. SELinux denials so far (`ausearch -m avc -ts today`), as a baseline before anything is added.

## 4. Track A: client key, Chrome and Traefik (no IdM changes)

**A0. Test CA (operator-laptop, no secrets leave it).** An openssl CA, `LocumView mTLS spike CA (throwaway)`, valid
7 days, in a private tmpfs directory. Its key never leaves operator-laptop and is deleted at the end.

**A1. Add `tpm2-pkcs11` to lv-test17, without changing the image (owner run).** `bootc usroverlay`, then
`dnf install tpm2-pkcs11 tpm2-pkcs11-tools`. The overlay is transient: a reboot drops it, which is itself the undo.
If fapolicyd denies the library: `fapolicyd-cli --update` so it trusts the overlay's RPM database, recorded as a
finding. If that is not enough, stop track A and bring back the choice (a spike image built for lv-test17 only,
never pushed to `:testing`), rather than loosen fapolicyd.

**A2. Token and key (Q1).** As the desktop user: a `tpm2-pkcs11` store, one token (`locumview-spike`), an
**ECDSA P-256 key generated in the TPM** (`tpm2_ptool addkey`, or `p11tool --generate-privkey` through the module).
Proof it cannot leave:
- `p11tool --export` or `pkcs11-tool --read-object --type privkey` fail;
- the store on disk holds only TPM-wrapped blobs (`tpm2_ptool listobjects`), useless on another machine: copied to
  a second VM with a vTPM, they do not load.

**A3. Certificate.** A CSR from the TPM key (`openssl req` with the PKCS#11 provider, or `p11tool`); the test CA signs
it on operator-laptop (client auth only, 2 days); the certificate goes back into the token. Only the CSR and the
certificate cross; both are public.

**A4. Chrome sees the token (Q2, part 1).** No registration needed: the RPM registers the module with p11-kit and the
user's NSS database loads `p11-kit-proxy` (#96). Check with `certutil -L -d sql:$HOME/.pki/nssdb -h <token>`;
`chrome://settings/certificates` is blocked by the image's `URLBlocklist`. **Watch for a PIN prompt:** the token is created with an empty
user PIN on purpose, because the key's protection is the TPM, not a PIN. If Chrome still asks, that is the main
finding of the spike.

**A5. Throwaway mTLS endpoint (Q3; agent prepares, owner approves the apply).**
- IdM: an A record for `mtls-spike` pointing at Traefik, and a server certificate for the name, made the way
  `scripts/clinical/make-tls-secrets.sh` makes them (owner run).
- Cluster: namespace `mtls-spike`; `traefik/whoami` (pinned by digest); a `TLSOption` with
  `clientAuth: {secretNames: [spike-ca], clientAuthType: RequireAndVerifyClientCert}`; an `IngressRoute` for the exact
  host with that option, and Traefik's `passTLSClientCert` middleware so the page shows the certificate's subject.
  Manifests in `k8s/mtls-spike/`, deleted with the namespace at the end.

**A6. Chrome policy on lv-test17 (owner run).** One extra managed file:
`AutoSelectCertificateForUrls` = `{"pattern":"https://mtls-spike.corp.locumview.com","filter":{"ISSUER":{"CN":"LocumView mTLS spike CA (throwaway)"}}}`,
plus the spike URL in `URLAllowlist`. Chrome does not merge a policy from several files, so the allowlist change is a
copy of the image's file with one line added, removed afterwards.

**A7. The checks.**

| Check | From | Expected |
|---|---|---|
| Open `https://mtls-spike…` in the desktop's Chrome | lv-test17 | whoami page, no certificate prompt, no PIN prompt; subject shown is the TPM certificate's |
| `curl https://mtls-spike…` with no client certificate | operator-laptop | refused at the handshake (TLS alert), no HTTP response |
| Same with a certificate from a different CA | operator-laptop | refused at the handshake |
| SNI `mtls-spike…` with Host `emr.corp…` | operator-laptop | 421, as the ADR expects; `emr.` itself unchanged (still Keycloak) |
| Reboot lv-test17, redo A1 and A4 only (no new key) | lv-test17 | the same key works: it survives a reboot and a TPM reset is not needed |
| Close and reopen Chrome | lv-test17 | still no prompt (session-only cookies do not matter to TLS) |

## 5. Track B: certmonger and an IdM sub-CA (only if track A passes)

**B1. IdM (owner run, on idm01).** `ipa ca-add locumview-spike-clients` (a sub-CA, removable), a certificate profile
for TLS client auth with a 2-day validity, and a CA ACL letting only hosts in `locumview-desktops` use them. This is
the same shape ADR 0019's build plan step 2 will use, with spike names.

**B2. certmonger on lv-test17 (owner run).** A root-owned NSS database with the `tpm2` module and a machine-level
token (not the user's), then `ipa-getcert request -X locumview-spike-clients -T <profile>` with the key in that token,
using the host's keytab. Check `ipa-getcert list` reaches `MONITORING`, then `ipa-getcert resubmit` renews it with the
**same key**.

**B3. Chrome uses the machine token (Q4 end to end).** The user's NSS database gets the same module, pointed at the
machine store (read-only for the user); the A6 policy filters on the sub-CA's issuer; the A7 checks again with the
TLS option trusting the sub-CA instead of the test CA. Open question to settle here: whether the user can **use**
the machine token's key without being able to read the store, or whether the store has to be per-user (then
certmonger requests per user, and the ADR needs a change).

## 6. Undo (all of it, whatever the result)

| Change | Undo |
|---|---|
| `tpm2-pkcs11` in the usroverlay | reboot lv-test17 |
| User token and NSS module (A2, A4) | `modutil -delete tpm2`; remove `~/.tpm2_pkcs11`; the TPM keys are useless without their blobs |
| Extra Chrome policy file (A6) | delete it; `chrome://policy` shows the image's file only |
| Namespace `mtls-spike`, its Secrets and TLSOption | `kubectl delete namespace mtls-spike` |
| IdM: A record, host, HTTP service and server certificate for `mtls-spike` | `ipa cert-revoke`, `ipa service-del`, `ipa host-del`, `ipa dnsrecord-del` |
| IdM sub-CA, profile, CA ACL (B1) | `ipa caacl-del`, `ipa certprofile-del`, `ipa ca-disable` then `ipa ca-del` |
| certmonger request, machine token (B2) | `ipa-getcert stop-tracking`; remove the token and the root NSS database |
| Test CA (A0) | delete the tmpfs directory on operator-laptop |
| lv-test17 itself | destroyed by OpenTofu after the spike (owner run), as planned; `owner/lv-test17` merged or dropped |

## 7. Outcome and next step

The spike ends with a changelog entry: each of Q1 to Q4 answered, with the commands and outputs that show it, and
every undo done. Then one of:

- **All yes:** ADR 0019 goes to Accepted (with what the spike changed), and its build plan starts at step 2.
- **Q2 fails on a PIN prompt or no silent selection:** the owner chooses between a software key (ADR fallback, known
  weakness) and another way to present the key; the ADR is revised before anything is built.
- **Q1 or Q3 fails:** ADR 0019 is revised or withdrawn; oauth2-proxy stays, and the double-MFA problem goes back to the
  alternatives in the ADR.
