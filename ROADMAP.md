# LocumView roadmap

Status as of 2026-10-21. Labels: **Done** (built and verified), **Open** (version-one work not finished), **In progress** (work has started outside version one, not finished or shipped), **Planned** (after version one, or alongside it only if it doesn't delay it), **Parked** (deliberately not pursued for now). The build log ([notes/phase1-changelog.md](notes/phase1-changelog.md)) and [docs/PLAN.md](docs/PLAN.md) hold the detail.

## Version one (scope locked by ADR 0009)

**Version one is complete: all five items Done, 2026-10-20** (changelog #59). The list below is locked; changing it needs a new ADR.

| # | Requirement | Status | Notes |
|---|---|---|---|
| 1 | One RHEL 10 desktop built as a bootc image from a Containerfile and provisioned on the reference hypervisor (libvirt) from a clean clone, with zero manual steps | **Done** | 2026-10-20 (changelog #51 to #59).  The image builds, boots and updates in place (changelog #51, #52); no FIPS mode (ADR 0012). Desktops install from an ISO with LUKS bound to the vTPM and provision themselves on first boot: IdM, RDP, break-glass, firewall (changelog #53). OpenTofu creates and destroys a desktop with its IdM host entry, Guacamole connection and Red Hat registration (changelog #54 to #56, ADR 0013). CI builds, signs (cosign) and attests (SBOM) the image, and the installer is built from the signed image (changelog #57). Desktops track the registry and accept only images signed with the project key, proven on a desktop provisioned with no manual steps (changelog #58). The destroy-and-rebuild proof from a clean clone passed on 2026-10-20 (changelog #59): a fresh clone plus the site values file, `tofu apply` to a provisioned desktop in 8 minutes, checked, then `tofu destroy` with nothing left behind. The final STIG scan, of a third desktop built from a clean clone and installed from an ISO with the provisioning fixes the first rescan led to: the image STIG profile passes 405 rules with 0 failures, and the HIPAA profile fails 37 rules, 2 fewer than the reference desktop; reports in docs/evidence/stig/20261020-image and 20261020-hipaa. ADR 0007. |
| 2 | Reached in a browser through Guacamole, Keycloak SSO with enforced MFA, no exposed RDP | **Done** | Live at login.locumview.com since 2026-10-02 (changelog #17 to #21). |
| 3 | DISA STIG profile applied, OpenSCAP report committed, exceptions documented | **Done** | 2026-10-19 on the reference desktop: DISA STIG with GUI, tailored; 417 pass, 0 open failures; reports in docs/evidence/stig, exceptions in hardening/stig/README.md (changelog #47). The bootc image applies the same profile at build time and has the separate file systems (changelog #51 to #53); FIPS mode is an exception (ADR 0012). |
| 4 | Encryption in transit everywhere | **Done** | 2026-10-19: every hop that crosses a network is encrypted. Browser to Cloudflare (TLS), the tunnel, pod traffic between cluster nodes (k3s WireGuard backend, changelog #49), Keycloak to IdM (LDAPS), and RDP to the desktop (TLS). Traffic between pods on the same node does not leave the host. |
| 5 | README with architecture diagram, quick start, HIPAA technical-safeguard mapping, honest status | **Done** | 2026-10-19 (changelog #50): quick start for the checks and the access layer; HIPAA mapping in docs/hipaa-technical-safeguards.md, with its gaps stated (encryption at rest partly met since #53). The desktop part of the quick start points to image/desktop/README.md (item 1 done 2026-10-20). |

### Version-one housekeeping (small, not scope items)

- Remaining ADRs written: Terraform vs OpenTofu (0013), GNOME (0014), Guacamole (0015). **Done**
- CI that re-runs the pre-commit checks on every push. **Done**
- Scoped kubeconfig for operators; admin GDM connection credentials into SOPS; Tomcat error page; cluster-wide egress policies. **Open**
- Backup procedure for desktop VMs on node1. **Open**
- Encryption at rest for desktop disks and cluster nodes. Desktops installed from the bootc image: LUKS bound to the vTPM (changelog #53). The hand-built reference desktop (until it is replaced) and the cluster nodes: **Open**
- The rules the SSG HIPAA profile still fails: 39 on the reference desktop, 37 on desktops built from the bootc image (2026-10-20, which pass partition_for_var_log_audit and rpm_verify_permissions): applied through the tailoring or documented. **Open**

## Planned after version one

Order after version one: move the live demo to an image-built desktop (done 2026-10-21); Phase 4 (packaging and supply chain); Phase 9 lite (clinical AI demo, ADR 0017); Phase 8 lite (demo video and first write-ups); Phase 7 (AWS, alongside SAA-C03). Phase 5 (SUSE) keeps running in parallel. The phases are described in [docs/PLAN.md](docs/PLAN.md).

| Area | Item | Status | Reference |
|---|---|---|---|
| Identity | Red Hat IdM directory (`corp.locumview.com`, first server on node1), Keycloak federation, organizational login on desktops; Keycloak stays the MFA authority | **Built** 2026-10-05, ahead of version one by owner decision (#32 to #36): idm01, read-only federation, owner's account in IdM, reference desktop enrolled (GNOME login, lock screen, sudo via IdM), nightly encrypted backups. Open: replica on node2, password policy, backup alerting | ADR 0006 |
| Identity | WebAuthn / passkeys; MFA for the demo login | Planned | ADR 0005 |
| Access | Guacamole session recording; edge rate limiting | Planned | |
| Access | Per-evaluator demo accounts with an expiry date (disabled at expiry, deleted later) | Planned | When real evaluators exist; until then the shared guest password is rotated after each evaluation (docs/runbooks.md) |
| Access | Close abandoned demo connections: idle logout or screen lock on the demo desktop | Planned | Guacamole keeps a session alive while a desktop connection is open, and the demo desktop has no screen lock (#42) |
| Access | Clipboard DLP: copy-out blocked, 5-minute clipboard clear in sessions | Built; lock-screen fix in #28, live clipboard tests pending | changelog #26, #28 |
| Desktop | Browser baseline (ADR 0016): Google Chrome for web EHRs in the image, managed policies following the DISA Chrome STIG, a default EHR launcher, Firefox ESR policies following the DISA Firefox STIG; an audit of Chrome's outbound traffic, published | **Built** 2026-10-20 (changelog #60): with the EHR launcher open for 15 minutes no DNS query or HTTPS connection left the desktop (docs/evidence/browser/). Open: a 24-hour capture (Safe Browsing), egress rules on the desktop firewall | ADR 0016 |
| Desktop | Image signing (cosign), SBOMs (syft), registry and build pipeline | **Built** (changelog #57); desktops accept only signed images (changelog #58) | ADR 0007 |
| Desktop | Organization-set desktop layout (Mac, Windows or GNOME style), locked centrally | Built; Mac style and lock verified, Windows/GNOME not exercised | changelog #25, #28 |
| Desktop | The live demo (login.locumview.com) on an image-built desktop, replacing the hand-built reference desktop | Done (2026-10-21) | Changelog #61; the reference desktop stays as a fallback for about a week, then retires |
| Desktop | Separate, resettable demo desktop | Planned | First KubeVirt workload |
| Hypervisors | Proxmox VE (practical production target) | Planned | ADR 0007, 0009 |
| Hypervisors | A dedicated desktop network (own subnet or VLAN); guacd's RDP egress narrowed from the LAN to it | Planned | With Proxmox (Phase 6); today guacd may reach RDP ports on the LAN (changelog #55) |
| Hypervisors | Host configuration as an Ansible role (bridge, nftables, libvirt, k3s prerequisites; node1, node2, then Proxmox hosts), replacing the shell scripts in hypervisor/ | Planned | With Proxmox (Phase 6); the desktop itself stays an image (ADR 0007) |
| Hypervisors | KubeVirt / OpenShift Virtualization (scoped learning piece) | Planned | ADR 0007, 0009 |
| Hypervisors | Public or sovereign cloud (AWS alongside SAA-C03) | Planned | ADR 0009 |
| Integrations | Nextcloud (files) via Keycloak OIDC, as a reference integration | Planned | ADR 0009 |
| Integrations | Synthetic FHIR server, Matrix messaging | Planned | ADR 0009 |
| Clinical AI | Detachable clinical AI module (US only, FDA CDS design principles): one web app in the hardened Chrome, launched from the desktop and as a SMART on FHIR app from the EHR; deterministic rules flag, a local model explains; Antimicrobial Stewardship, IV to PO and ADE Monitoring queues. First, Phase 9 lite: a clinical AI demo on OpenEMR with synthetic patients, showing a stewardship and an IV to PO finding; then the full Phase 9. Watch item: Epic Connectors (announced 2026-10-21) as a possible read-only delivery path for stewardship findings; revisit when Epic publishes developer documentation | Planned | ADR 0008, 0017 |
| Distributions | SUSE / openSUSE build from the same definitions | **In progress, not shipped** | Infrastructure work has begun and runs largely in parallel with the RHEL build; not supported or shipped yet |
| Distributions | Debian build from the same definitions | Planned | |

## Parked

- **FIPS mode on desktops:** GNOME Remote Desktop's RDP sign-in uses NTLM, which FIPS mode disables (tested 2026-10-19). Revisited when LocumView targets sectors that require FIPS 140 validated cryptography in FIPS mode (federal and defense health, FedRAMP), or when the remote display stack gains a FIPS-compatible sign-in. ADR 0012.
- **Clinical decision support in the EU:** requires MDR certification (Rule 11, Class IIa or higher; ISO 13485 QMS; notified body). Parked until there is a company with the capital and QMS to pursue it. In the EU, AI is limited to productivity verbs (draft, summarize, organize, retrieve). ADR 0008.

## Done so far (highlights)

- Hand-built RHEL 10.2 reference desktop: UEFI + Secure Boot, vTPM, headless GNOME Remote Desktop, branding (changelog #1 to #13).
- Strict LAN RDP validation, including GNOME's double redirection (changelog #14).
- VM moved to node1 on a LAN bridge (changelog #15).
- SOPS + age secrets with a pre-commit guard (changelog #16).
- Guacamole, Keycloak (TOTP), straight-to-desktop sessions, RDP firewalled to the cluster (changelog #17 to #19).
- Branding, public access through the tunnel, guest demo, LocumView Tour, layout switch, marketing site and email (changelog #20 to #23).
- DISA STIG with GUI applied to the reference desktop through a tailoring file reusable in the bootc build; 164 to 417 passing rules (changelog #47).
- CI on every push, with the website preview following this roadmap (changelog #48).
- Pod traffic between cluster nodes encrypted with WireGuard, closing the last unencrypted network hop (changelog #49).
- README quick start and a HIPAA technical-safeguard mapping with its evidence (changelog #50).
- The desktop as a bootc image: builds, boots with Secure Boot and the STIG's separate file systems, updates in place; FIPS mode tested and set aside (changelog #51, #52, ADR 0012).
- Desktops install from an ISO with LUKS on the vTPM and provision themselves on first boot (IdM, RDP, break-glass), with no manual steps on the VM (changelog #53).
- OpenTofu creates a desktop with its IdM host entry and removes all of it again; state encrypted (changelog #54, ADR 0013).
- CI builds, signs and attests the desktop image on a dedicated runner; the installer is built only from the signed image (changelog #57).
- Desktops accept only signed updates: the signature policy rejects unsigned images and other registries; a desktop installed by OpenTofu moved to the signed CI build on first boot and booted it (changelog #58).
- Browser baseline: Chrome for the EHR and Firefox ESR, both locked down to the DISA STIG settings; Chrome measured silent for 15 minutes (changelog #60, ADR 0016).
- Version one complete, 2026-10-20: a desktop built from a clean clone with zero manual steps, destroyed with nothing left behind, and rebuilt; its STIG scan passes 405 rules with 0 failures (changelog #59).
