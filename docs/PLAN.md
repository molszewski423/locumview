# LocumView Plan

## 1. Project summary

LocumView is an open-source VDI platform built on RHEL 10, and a portfolio project for solutions architecture and platform engineering roles, with Red Hat as a target employer. It provisions hardened GNOME and Sway desktops with Terraform and Ansible, delivers them through the browser via Apache Guacamole behind Keycloak SSO and MFA, and never exposes a desktop directly to the internet. Every environment must be rebuildable identically from the repository.

Core test for every phase: can a reviewer clone the repo and rebuild it with no manual steps? "I configured a thing" is IT administration; "it rebuilds from code" is engineering.

Owner: Michael Olszewski. Name nods to locum tenens clinicians and VMware View (now Horizon, owned by Omnissa).

## 2. Architecture decisions

- OS: RHEL 10 via Red Hat Developer Subscription for Individuals. Enterprise standard in regulated healthcare; STIG/CIS baselines, FIPS crypto, 10-year lifecycle.
- Desktop: GNOME default via GNOME Remote Desktop headless RDP (RHEL 10 is Wayland only). Sway (EPEL) as minimal/kiosk profile via wayvnc. GNOME Classic as a "Familiar" profile (Red Hat shipped extensions, locked with dconf), not Dash to Panel.
- Broker: Apache Guacamole (guacd translates RDP to browser). Session recording for audit evidence.
- Path: Browser > Traefik (TLS) > Guacamole > guacd > RDP > RHEL desktop. RDP never exposed.
- Identity: Keycloak SSO with MFA via OIDC (end state). Guacamole TOTP acceptable early in Phase 2, never both at once. Upgrades: WebAuthn/passkeys, Keycloak brute-force lockout, CrowdSec.
- Critical default: change or delete Guacamole's guacadmin/guacadmin via Ansible before any exposure.
- Exposure: Tailscale first, optionally Cloudflare Tunnel. Nothing listening publicly.
- Tool split: Terraform = infrastructure (host side); Ansible = everything inside the guest; Terraform outputs feed Ansible dynamic inventory. Prefer RHEL System Roles where one exists.
- Hardening: scap-security-guide Ansible (DISA STIG / CIS), OpenSCAP reports in docs/evidence/, mapped to HIPAA safeguards.
- Packaging: signed RPMs built with mock (EPEL, so prefer COPR which runs mock server side), own dnf repo or COPR. Stretch: RHEL image mode (bootc).
- Platform ladder: libvirt (homelab) > KubeVirt on k3s > AWS EC2. Desktop and Ansible layers stay constant.
- Broker alternatives considered: Kasm (limited free tier), OpenUDS (small community), noVNC (viewer only), Horizon/Citrix (not reproducible).

## 3. Phases

**Phase 0, Foundations:**
- [x] Red Hat Developer Subscription active
- [ ] Repo layout: terraform/, ansible/roles/, packaging/, docs/adr/, docs/evidence/, notes/
- [ ] Pre-commit: ansible-lint, terraform fmt, tflint, secret scanning
- [ ] Secrets via Ansible Vault or SOPS. Nothing sensitive in plain text, ever
- [ ] ADRs: why RHEL 10, why GNOME + Sway, why Guacamole (plus proposed: Terraform BSL 1.1 vs OpenTofu MPL 2.0)

Done when: repo exists, lints run on commit, three ADRs written.

**Phase 1, Hand-built reference desktop** (in progress, being done out of order before Phase 0):
- [x] RHEL 10.2 installed and registered
- [x] Guest agent working, baseline recorded, snapshots taken
- [ ] GNOME Remote Desktop headless RDP working with no one logged in at the console
- [ ] GNOME customization by command (gsettings/dconf), including a Familiar (GNOME Classic) profile
- [ ] Sway kiosk profile explored
- [ ] Every change logged as a command

Done when: headless RDP works and the notes log fully describes how to reproduce the desktop. See [notes/phase1-changelog.md](../notes/phase1-changelog.md) for findings so far.

**Phase 2, Access layer:** Guacamole + guacd (hosting pending: Podman/Quadlet vs k3s); Keycloak SSO + MFA (TOTP, then WebAuthn); remove default guacadmin; Tailscale, optionally Cloudflare Tunnel; session policies and recording. Done when a user reaches the desktop in a browser through SSO + MFA with no exposed RDP.

**Phase 3, Automation and hardening:** Terraform libvirt VM from the RHEL KVM guest qcow2 (UEFI + Secure Boot, host-passthrough, guest agent channel, vTPM, cloud-init, activation key registration); Ansible roles base, hardening, gnome_desktop, sway_kiosk, devtools, remote_access; STIG applied with committed OpenSCAP report; HIPAA mapping; bake-vs-fry ADR. Done when terraform destroy then apply rebuilds the desktop with zero manual steps.

**Version one (interview ready)** = all true: one RHEL 10 desktop provisioned by Terraform and configured by Ansible from a clean clone; reached through Guacamole with Keycloak MFA and no exposed RDP; STIG hardened with committed OpenSCAP report; README with diagram, quick start, and HIPAA mapping.

**Optional after version one:** Phase 4 custom packaging; Phase 5 cross-distro Ansible (last or never); Phase 6 KubeVirt + CDI on k3s, Argo CD, Prometheus/Grafana (set memory limits first; MikePC's 32 GB is shared with an AI stack); Phase 7 AWS (budget alarm first, private subnets, S3 state, no public IPs, destroy after sessions, check Red Hat Cloud Access); Phase 8 portfolio polish (README, diagram, demo video, write-ups).

Sequencing: Phases 0 to 3 in order, then Phase 8 lite, then Phase 7, then 4 and 6, then 5.

Longer-term direction (not version one scope): positioned for clinical and life sciences, with an agentic AI angle using local models (for example RHEL Lightspeed MCP) so no regulated data leaves the boundary. Build architecturally general for any regulated environment.

Pending decisions: Guacamole hosting (Podman/Quadlet vs k3s); verify Red Hat Cloud Access before AWS; VM memory limits on MikePC before KubeVirt.
