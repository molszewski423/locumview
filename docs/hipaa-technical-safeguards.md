# HIPAA technical safeguards: how LocumView maps to 45 CFR 164.312

Version-one item 5 (ADR 0009). This maps each technical safeguard of the HIPAA Security Rule to what the LocumView reference deployment does today, with the evidence in this repository and the gaps stated plainly. Status as of 2026-10-20.

**What this is not.** HIPAA compliance belongs to an organization, not to software: it also needs the administrative and physical safeguards (164.308, 164.310), risk analysis, policies, training and business associate agreements. LocumView can make the technical safeguards easier to meet and to evidence; it cannot make anyone compliant. The public demo holds no PHI and must not be used with PHI.

R = required implementation specification, A = addressable (implement it, or document why an equivalent or nothing is reasonable).

| 164.312 | Specification | | What LocumView does | Evidence | Status |
|---|---|---|---|---|---|
| (a)(1) | **Access control** (standard) | | Access only through Keycloak SSO; desktops are never reachable from the internet; RDP and SSH accepted only from the cluster nodes; default-deny network policies around every access-layer component; Guacamole permissions by group. | ADR 0002, 0004, 0005; changelog #17 to #19, #30 | Met |
| (a)(2)(i) | Unique user identification | R | Every person has their own account in Red Hat IdM, federated read-only into Keycloak; desktop logins, sudo and Guacamole history are per user. Shared accounts are limited to the guest demo (no PHI, its own isolated desktop account) and documented break-glass accounts, disabled or owner-held. | ADR 0006; changelog #34 to #36, #44; [break-glass.md](break-glass.md) | Met (guest demo shared by design) |
| (a)(2)(ii) | Emergency access procedure | R | Break-glass accounts for each layer (Keycloak, Guacamole, the desktop, its boot loader, the IdM server and directory), each with how to use it and when; nightly encrypted, off-host IdM backups with a restore procedure. | [break-glass.md](break-glass.md); changelog #33, #35, #47 | Met |
| (a)(2)(iii) | Automatic logoff | A | Keycloak SSO sessions end after 30 minutes idle and 10 hours at most; Guacamole sessions after 30 minutes idle; the desktop blanks and locks after 10 minutes idle and users cannot change that (DISA STIG); shells and SSH sessions time out after 10 minutes. **Limits:** Guacamole keeps a session alive while a desktop connection is open, so an abandoned open connection ends only at the desktop lock; the guest demo session blanks but does not lock (guests know no Linux password). | changelog #18, #42, #47; [hardening/stig/README.md](../hardening/stig/README.md) | Met for staff; demo idle logout planned |
| (a)(2)(iv) | Encryption and decryption | A | Secrets in the repository are SOPS + age ciphertext; identity backups are encrypted before they leave the host. Desktops installed from the bootc image: disk encrypted with LUKS2, unlocked at boot by the desktop's vTPM (clevis, Secure Boot state), with a recovery passphrase kept in SOPS. The live demo runs on an image-built desktop since 2026-10-21 (changelog #61). **Gap:** the hand-built reference desktop (a fallback until it retires), the cluster nodes' disks and the databases are not encrypted at rest. | ADR 0003; changelog #16, #33, #53 | **Partial** |
| (b) | **Audit controls** | R | Keycloak keeps sign-in and admin events for 90 days; Guacamole keeps connection and login history (user, client address, times) for 90 days; the desktop runs auditd with the STIG rule set (privileged commands, permission and ownership changes, deletions, identity files, sudoers, kernel modules, logins and lockouts), immutable until reboot; AIDE checks file integrity weekly. **Limits:** logs stay on each system (no central collection yet); no session recording yet. | changelog #18, #41, #47; [STIG reports](evidence/stig/) | Partly met |
| (c)(1) | **Integrity** (standard) | | The platform protects its own integrity: SELinux enforcing, fapolicyd allows only RPM-installed software to run, packages must be GPG-signed, AIDE watches system files, configuration lives in git with signed commits and CI checks. LocumView stores no ePHI itself: clinical data stays in the systems that own it (ADR 0009), and copying data out of a session is blocked. | changelog #26, #31, #47, #48 | Met at platform level |
| (c)(2) | Mechanism to authenticate ePHI | A | Applies to the clinical systems that store ePHI, not to the desktop platform. LocumView's part is not adding a path for unauthorized change: copy-out blocked, clipboard cleared after 5 minutes, audit trail above. | changelog #26, #28 | Not applicable to the platform |
| (d) | **Person or entity authentication** | R | Keycloak requires password and TOTP for every account except the guest demo; brute-force lockout; IdM password policy and lockout; the desktop locks an account after three failed passwords until an administrator resets it; desktop RDP credentials are random per desktop and never typed by anyone. Next: WebAuthn / passkeys. | ADR 0005, 0006; changelog #18, #19, #34, #47 | Met (guest demo is password only, no PHI) |
| (e)(1) | **Transmission security** (standard) | | Every hop that crosses a network is encrypted. | changelog #21, #34, #49 | Met |
| (e)(2)(i) | Integrity controls | A | TLS, the tunnel, WireGuard and RDP over TLS all authenticate every packet, so changes in transit are detected. | changelog #49 | Met |
| (e)(2)(ii) | Encryption | A | Browser to Cloudflare: TLS. Cloudflare to the cluster: the outbound tunnel. Between cluster nodes: WireGuard. Keycloak to IdM: LDAPS. guacd to the desktop: RDP over TLS. Traffic between pods on the same node does not leave the host. The desktop does not run in FIPS mode (ADR 0012): HIPAA does not require it, and these protections do not depend on it. **Note:** Cloudflare terminates TLS at its edge, so it can see the traffic; an organization putting PHI through it needs a business associate agreement with Cloudflare, or its own ingress. | ADR 0004; changelog #49 | Met (see note) |

## Scanner evidence

`scap-security-guide` ships a HIPAA profile for RHEL 10, which checks system settings that support the safeguards above (it does not and cannot check the rest of this table). Results on the reference desktop, and on a desktop built from the bootc image:

| Scan | Pass | Fail | Report |
|---|---|---|---|
| 2026-10-17, before hardening | 38 | 121 | [docs/evidence/stig/20261017-baseline/](evidence/stig/20261017-baseline/) |
| 2026-10-19, after the DISA STIG tailoring (changelog #47) | 120 | 39 | [docs/evidence/stig/20261019-hipaa/](evidence/stig/20261019-hipaa/) |
| 2026-10-20, a desktop built from the bootc image from a clean clone (changelog #59) | 119 | 37 | [docs/evidence/stig/20261020-hipaa/](evidence/stig/20261020-hipaa/) |

Most of the remaining failures are rules the HIPAA profile has and the DISA STIG does not: more audit rules (time changes, `utmp`/`wtmp`/`btmp`, failed file creation and deletion, network configuration and SELinux policy changes) and a few settings (`sshd_disable_compression`, `sysctl_fs_suid_dumpable`, `sebool_selinuxuser_execstack`, `selinux_confinement_of_daemons`, `no_direct_root_logins`, removing the `telnet` client, `ensure_gpgcheck_repo_metadata`, `rpm_verify_permissions`). Remote logging (`rsyslog_remote_loghost`) is the same open item as in the STIG exceptions. These are open items, not exceptions: they have not been assessed one by one yet.

## Open items that would change this table

- Encryption at rest for the cluster nodes and databases, and retiring the hand-built reference desktop (the live demo moved to an encrypted, image-built desktop on 2026-10-21).
- Central log collection, and Guacamole session recording.
- Idle logout for the guest demo, and per-evaluator demo accounts with an expiry date.
- IdM password policy (IdM users currently follow IdM's defaults).
- WebAuthn / passkeys for staff.
- The rules the SSG HIPAA profile still fails (39 on the reference desktop; 37 on an image-built one, which has `/var/log/audit` on its own file system and passes `rpm_verify_permissions`): apply them through the tailoring or document each as an exception.
