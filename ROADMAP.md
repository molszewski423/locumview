# LocumView roadmap

Status as of 2026-10-05. Labels: **Done** (built and verified), **Open** (version-one work not finished), **Planned** (after version one, or alongside it only if it doesn't delay it), **Parked** (deliberately not pursued for now). The build log ([notes/phase1-changelog.md](notes/phase1-changelog.md)) and [docs/PLAN.md](docs/PLAN.md) hold the detail.

## Version one (scope locked by ADR 0009)

Version one is complete when all five items are Done. Nothing else is required for it, and changing this list needs a new ADR.

| # | Requirement | Status | Notes |
|---|---|---|---|
| 1 | One RHEL 10 desktop built as a bootc image from a Containerfile and provisioned on the reference hypervisor (libvirt) from a clean clone, with zero manual steps | **Open** | Today the desktop is built by documented scripts (changelog #11 to #23). Needs the Containerfile, a registry, signing, and provisioning code. ADR 0007. |
| 2 | Reached in a browser through Guacamole, Keycloak SSO with enforced MFA, no exposed RDP | **Done** | Live at login.locumview.com since 2026-10-02 (changelog #17 to #21). |
| 3 | DISA STIG profile applied, OpenSCAP report committed, exceptions documented | **Open** | Not started. |
| 4 | Encryption in transit everywhere | **Open** | Browser to Cloudflare, the tunnel, and RDP are encrypted; the in-cluster hop between nodes is not (planned fix: k3s WireGuard backend). |
| 5 | README with architecture diagram, quick start, HIPAA technical-safeguard mapping, honest status | **Open** | Status section and current-state diagram done; quick start and HIPAA mapping not yet. |

### Version-one housekeeping (small, not scope items)

- Remaining ADRs: GNOME + Sway, Guacamole, Terraform vs OpenTofu. **Open**
- CI that re-runs the pre-commit checks on every push. **Open**
- Scoped kubeconfig for operators; admin GDM connection credentials into SOPS; Tomcat error page; cluster-wide egress policies. **Open**
- Backup procedure for desktop VMs on MikePC. **Open**

## Planned after version one

| Area | Item | Status | Reference |
|---|---|---|---|
| Identity | Red Hat IdM directory (`corp.locumview.com`, first server on MikePC), Keycloak federation, organizational login on desktops; Keycloak stays the MFA authority | **Built** 2026-10-05, ahead of version one by owner decision (#32 to #36): idm01, read-only federation, owner's account in IdM, reference desktop enrolled (GNOME login, lock screen, sudo via IdM), nightly encrypted backups. Open: replica on debianbox, password policy, backup alerting | ADR 0006 |
| Identity | WebAuthn / passkeys; MFA for the demo login | Planned | ADR 0005 |
| Access | Guacamole session recording; edge rate limiting | Planned | |
| Access | Clipboard DLP: copy-out blocked, 5-minute clipboard clear in sessions | Built; lock-screen fix in #28, live clipboard tests pending | changelog #26, #28 |
| Desktop | Image signing (cosign), SBOMs (syft), registry and build pipeline | Planned (part of version-one item 1 where needed) | ADR 0007 |
| Desktop | Organization-set desktop layout (Mac, Windows or GNOME style), locked centrally | Built; Mac style and lock verified, Windows/GNOME not exercised | changelog #25, #28 |
| Desktop | Sway kiosk profile | Planned | |
| Desktop | Separate, resettable demo desktop | Planned | First KubeVirt workload |
| Hypervisors | Proxmox VE (practical production target) | Planned | ADR 0007, 0009 |
| Hypervisors | KubeVirt / OpenShift Virtualization (scoped learning piece) | Planned | ADR 0007, 0009 |
| Hypervisors | Public or sovereign cloud (AWS alongside SAA-C03) | Planned | ADR 0009 |
| Integrations | Nextcloud (files) via Keycloak OIDC, as a reference integration | Planned | ADR 0009 |
| Integrations | Synthetic FHIR server, Matrix messaging | Planned | ADR 0009 |
| Clinical AI | Detachable clinical AI module (US first, FDA CDS design principles), antimicrobial stewardship as the lead agent | Planned | ADR 0008 |
| Distributions | SUSE / openSUSE and Debian builds from the same definitions | Planned | |

## Parked

- **Clinical decision support in the EU:** requires MDR certification (Rule 11, Class IIa or higher; ISO 13485 QMS; notified body). Parked until there is a company with the capital and QMS to pursue it. In the EU, AI is limited to productivity verbs (draft, summarize, organize, retrieve). ADR 0008.

## Done so far (highlights)

- Hand-built RHEL 10.2 reference desktop: UEFI + Secure Boot, vTPM, headless GNOME Remote Desktop, branding (changelog #1 to #13).
- Strict LAN RDP validation, including GNOME's double redirection (changelog #14).
- VM moved to MikePC on a LAN bridge (changelog #15).
- SOPS + age secrets with a pre-commit guard (changelog #16).
- Guacamole, Keycloak (TOTP), straight-to-desktop sessions, RDP firewalled to the cluster (changelog #17 to #19).
- Branding, public access through the tunnel, guest demo, LocumView Tour, layout switch, marketing site and email (changelog #20 to #23).
