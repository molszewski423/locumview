# LocumView Plan

Owner: Michael Olszewski. Status: Phase 1 in progress.

LocumView is an open-source virtual desktop platform built on RHEL 10. It provisions hardened GNOME and Sway desktops with Terraform and Ansible, delivers them through the browser via Apache Guacamole behind Keycloak SSO and MFA, and never exposes a desktop directly to the internet. Every environment must be rebuildable identically from the repository. It is a portfolio project aimed at solutions architecture and platform engineering roles, with Red Hat as a target employer.

Core test for every phase: can a reviewer clone the repo and rebuild it with no manual steps? "I configured a thing" is IT administration; "it rebuilds from code" is engineering.

Name: nods to locum tenens clinicians and VMware View (now Horizon, owned by Omnissa).

## 1. Progress log

| Date | Step | Notes |
|---|---|---|
| 2026-09-28 | Red Hat Developer account created | Personal account type, company "Individual". Developer Subscription for Individuals (16 systems, self-supported). |
| 2026-09-28 | Downloaded RHEL 10.2 x86_64 DVD ISO | Full offline BaseOS and AppStream repos. Verified with sha256sum. |
| 2026-09-28 | Created VM locumview-ref-dev in virt-manager | Connection qemu:///system (not user session). 4 vCPU, 8192 MiB RAM, 40 GiB thin-provisioned qcow2 in /var/lib/libvirt/images, network default (NAT). |
| 2026-09-28 | Installed RHEL 10.2 | Base environment: Workstation. Add-on groups: Smart Card Support, Container Management, Development Tools. Root disabled. Admin user mike (wheel). Hostname locumview-ref-dev. KDUMP disabled. No disk encryption (would block headless boot). |
| 2026-09-28 | Registered during install | Role: RHEL Workstation, SLA: Self-Support, Usage: Development/Test, Insights enabled. subscription-manager status shows Registered (Simple Content Access, no attach needed). |
| 2026-09-28 | sudo dnf upgrade -y | Already up to date. |
| 2026-09-28 | QEMU guest agent | Package already installed by the Workstation environment; service enabled. Host was missing the virtio channel org.qemu.guest_agent.0; needs adding on the host (virt-manager Add Hardware > Channel, or virsh edit). Verify with sudo virsh domifaddr locumview-ref-dev --source agent. |
| 2026-09-29 08:50 | Fixed Gitea SSH access | Gitea (hosted on a separate k3s cluster, control plane MikePC) had three bugs blocking git-over-ssh from any external host: SSH port was ClusterIP-only, the container's real sshd ignored the Gitea-side port setting, and INSTALL_LOCK=false was resetting the instance to the install wizard on every pod restart. All fixed in the homelab-infra repo's k8s/gitea.yaml, not this repo. Full writeup in [notes/phase1-changelog.md](../notes/phase1-changelog.md). |
| 2026-09-29 09:08 | First commit to this repo | Phase 0 layout, this plan, CLAUDE.md, phase1-changelog.md, Phase 1 evidence. Signed with the VM's per-machine SSH key. |

## 2. Open items (Phase 1)

- [ ] Add guest agent channel on host and verify
- [ ] Confirm VM firmware (UEFI) and CPU mode (host-passthrough); if not set at creation, note it for Terraform (known: it was created with SeaBIOS by mistake, see changelog)
- [ ] Record baseline: cat /etc/redhat-release, uname -r, dnf group list --installed
- [ ] Snapshot: clean-install-registered
- [ ] Optional: install Security Tools group and run a baseline OpenSCAP scan ("before" evidence)
- [ ] Validate GNOME Remote Desktop headless RDP (the highest-risk item in the whole project)
- [ ] Snapshot after RDP works
- [x] Start the Git repo (Phase 0) and move this log into it

## 3. Notes to carry into automation

- Host-side settings belong in Terraform: guest agent channel (qemu_agent), UEFI firmware, host-passthrough CPU (RHEL 10 requires x86-64-v3), memory, vCPU, disk, network.
- Guest-side settings belong in Ansible: package groups, GNOME config, users, hardening, RDP.
- Registration in automation: use an activation key plus org ID from console.redhat.com, never the account password.
- Accounts: mike is a named admin account (good for audit traceability). Add a separate ansible service account with SSH key and scoped sudo. End users are separate, non-admin, and eventually come from Keycloak or Red Hat IdM.
- Base images: the DVD ISO is for the hand-built reference; Phase 3 uses the RHEL KVM guest qcow2 image (cloud-init ready) from the developer portal Images page.
- KubeVirt note: k3s/KubeVirt does not use the host's qemu:///system. What carries to Kubernetes is the Ansible, applied to a RHEL guest image imported via CDI.
- VM sizing: 4 vCPU / 8 GB mirrors a realistic knowledge-worker VDI; a task worker is about 2 vCPU / 4 GB. Memory is allocated on demand but tends to grow to its full allocation, so size realistically.

## 4. Architecture decisions

| Area | Decision | Why |
|---|---|---|
| OS | RHEL 10 via Developer Subscription for Individuals | Dominant enterprise Linux in regulated healthcare; STIG/CIS baselines, FIPS crypto, 10-year lifecycle; target employer's product. See [ADR 0001](adr/0001-rhel10.md). |
| Desktop | GNOME default via GNOME Remote Desktop headless RDP (RHEL 10 is Wayland-only). Sway (EPEL) as minimal/kiosk profile via wayvnc. | Supported, native RDP path. |
| Windows-familiar layout | GNOME Classic (Red Hat-shipped Window List, Applications and Places extensions) as a "Familiar" profile, not Dash to Panel | Vendor-supported, survives GNOME updates, easy to lock with dconf. Dash to Panel only as a documented optional extra via ADR. |
| Broker | Apache Guacamole (guacd translates RDP to browser) | Apache 2.0, native RDP, Keycloak OIDC/SAML, session recording for audit evidence. Traefik is a reverse proxy, not a substitute. |
| Path | Browser > Traefik (TLS) > Guacamole > guacd > RDP > RHEL desktop | RDP never exposed. |
| Identity | Keycloak SSO with MFA via OIDC (end state). Guacamole TOTP extension acceptable in early Phase 2. Never both at once. | Centralized identity for all future services. |
| MFA upgrades | WebAuthn / passkeys / YubiKey, Keycloak brute-force lockout, CrowdSec on login endpoints | Phishing-resistant; analogous to clinical badge-tap. |
| Critical default | Change or delete Guacamole's guacadmin/guacadmin via Ansible before any exposure | Default credentials. |
| Exposure | Tailscale first, optionally Cloudflare Tunnel | Nothing listening publicly. |
| Tool split | Terraform = infrastructure; Ansible = everything inside the guest; Terraform outputs feed Ansible dynamic inventory | Clean handoff. |
| Hardening | scap-security-guide Ansible (DISA STIG / CIS), OpenSCAP reports committed to docs/evidence/, mapped to HIPAA safeguards | Compliance as code with evidence. |
| Packaging | Signed RPMs built with mock, served from own dnf repo or COPR. Stretch: RHEL image mode (bootc). | "Signed RPM from my repo, installed by Ansible" is engineering. |
| Platform ladder | libvirt (homelab) > KubeVirt on k3s > AWS EC2; desktop and Ansible layers stay constant | Shows portability; KubeVirt tells the OpenShift Virtualization story. |

### Broker alternatives considered

- **Kasm Workspaces**: polished, but limited free tier and less open. Good "future work" comparison write-up.
- **OpenUDS**: true broker with pools, but small community and Proxmox/OpenStack oriented.
- **noVNC**: viewer only, no brokering or auth.
- **VMware Horizon / Citrix**: trial licenses only, not reproducible.

### How LocumView maps to VMware Horizon

See [README.md](../README.md) for the Horizon comparison table.

## 5. Phases

**Phase 0, Foundations:**
- [x] Developer subscription active
- [x] Repo layout: terraform/, ansible/roles/, packaging/, docs/adr/, docs/evidence/, notes/
- [x] Pre-commit: ansible-lint, detect-secrets, gitleaks (podman, pinned by digest), tflint (podman, pinned by digest, no-ops until terraform/ has content). `terraform fmt`/`tofu fmt` deferred until the Terraform vs OpenTofu ADR lands. See [notes/phase1-changelog.md](../notes/phase1-changelog.md).
  - Local hooks are bypassable with `git commit --no-verify`; they are convenience, not enforcement. The same checks must also run in CI (Gitea Actions) once it exists.
- [ ] Secrets via Ansible Vault or SOPS. Nothing sensitive in plain text, ever
- [x] First ADR: [0001, RHEL 10 as base distribution](adr/0001-rhel10.md)
- [ ] Remaining ADRs: why GNOME + Sway, why Guacamole, Terraform vs OpenTofu

Done when: repo exists, lints run on commit, ADRs written.

**Phase 1, Hand-built reference desktop** (current, being done out of order before Phase 0 finished):
- [x] RHEL 10.2 installed and registered (locumview-ref-dev)
- [x] Guest agent working, baseline recorded, snapshot taken
- [ ] GNOME Remote Desktop headless RDP working from another machine on the LAN, with no one logged in at the console
- [ ] GNOME customization by command, including a Familiar (GNOME Classic) profile
- [ ] Sway kiosk profile explored
- [ ] Every change logged as a command

Done when: you can RDP into a headless session, and the notes log fully describes how to reproduce the desktop. See [notes/phase1-changelog.md](../notes/phase1-changelog.md).

**Phase 2, Access layer:** Guacamole + guacd (decide hosting: Podman/Quadlet vs k3s); Keycloak SSO + MFA (TOTP first, then WebAuthn); remove default guacadmin; Tailscale, optionally Cloudflare Tunnel; session policies and session recording. Done when a user reaches the desktop in a browser through SSO + MFA with no exposed RDP.

**Phase 3, Automation and hardening (end of version one):** Terraform libvirt VM from RHEL KVM guest qcow2 (UEFI, host-passthrough, guest agent channel, cloud-init, activation key registration); Ansible roles base, hardening, gnome_desktop, sway_kiosk, devtools, remote_access; STIG profile applied, OpenSCAP report committed to docs/evidence/; HIPAA safeguard mapping; bake-vs-fry ADR. Done when terraform destroy then apply rebuilds the desktop with zero manual steps.

### Minimum shippable version (version one)

Version one is interview-ready when all are true:

- One RHEL 10 desktop provisioned by Terraform and configured by Ansible, rebuildable from a clean clone.
- Reached through Guacamole in a browser, Keycloak MFA in front, no exposed RDP.
- STIG-hardened with a committed OpenSCAP report.
- README with architecture diagram, working quick start, and HIPAA mapping.

Everything below is optional until version one ships.

**Phase 4, Custom packaging:** mock-built signed RPMs, own dnf repo or COPR. Stretch: RHEL image mode (bootc).

**Phase 5, Cross-distro Ansible (last, skippable):** branch on ansible_os_family, test with Molecule on Fedora/Debian/Arch. Least aligned with Red Hat targeting; deprioritized.

**Phase 6, Kubernetes:** KubeVirt + CDI on k3s, import RHEL guest image, apply same Ansible; Argo CD GitOps; Prometheus/Grafana. Set VM memory limits first (MikePC's 32 GB is shared with the AI stack).

**Phase 7, AWS:** budget alarm first; VPC with private subnets; S3 remote state; no public IPs; IAM roles; destroy after every session. Check Red Hat Cloud Access before using RHEL AMIs (pay-as-you-go RHEL adds hourly cost); otherwise record an ADR.

**Phase 8, Portfolio polish:** README, diagram, HIPAA mapping, 3 to 5 minute demo video, per-phase write-ups.

Sequencing: Phases 0 to 3 in order, then Phase 8 lite, then Phase 7 alongside AWS SAA-C03 study, then Phases 4 and 6, then Phase 5 last or never.

## 6. Follow-on ideas

Secure pharmacovigilance analyst workstation (ties to PV AI Workbench), OpenShift Virtualization port, Dev Spaces vs VDI tradeoff write-up, Red Hat IdM, self-healing compliance with Event-Driven Ansible, GPU desktop via VFIO passthrough, backup and DR with Velero, encrypted disks with automatic unlock (Clevis/Tang), smart card / badge login, Kasm comparison.

Longer-term direction (not version one scope): positioned for clinical and life sciences, with an agentic AI angle using local models (for example RHEL Lightspeed MCP) so no regulated data leaves the boundary. Build architecturally general for any regulated environment.

## 7. Product positioning and thesis

Reference material for Phase 8 portfolio write-ups and interview framing.

**Positioning:** LocumView delivers secure, compliant, reproducible Linux desktops for clinical, research, and technical workloads that are web-based or Linux-native: analysts, data science, pharmacovigilance, developers, and browser-based EHR access. It is not a drop-in replacement for a nurse's primary native EHR station.

**Honest scope boundary:** native Epic (Hyperspace, and Hyperdrive, a managed Chromium-based client) and older Meditech (MAGIC, Client/Server) clients are Windows-first. Browser-based front ends (Epic web access, Meditech Expanse, most modern hospital web apps) run fine on a Linux desktop.

**The browser is becoming the workstation** (idea to explore, not vendor roadmap knowledge): EHR presentation is moving to web technology. Meditech's strategic platform Expanse is browser-based, and Epic has adopted a web engine under the hood while still shipping a controlled client. If this continues, a hardened, centrally managed browser endpoint becomes more valuable, which is what LocumView provides.

**Handling Windows-dependent applications:** there is no regulated, clinical-grade compatibility layer. Wine, CrossOver, and Proton are not supported by EHR vendors, and running patient-care software in an unsupported configuration is a compliance and patient-safety risk. Decision hierarchy, most defensible first:

1. Web-based and Linux-native applications.
2. Application publishing: the Windows app runs on a supported Windows host and is delivered to the Linux desktop.
3. Open-source replacements for general productivity.
4. Compatibility layers only for low-risk internal tools, never clinical systems.

Principle: put each workload on the platform that properly supports it, and deliver them all to one hardened Linux endpoint.

**Cost model, consolidation not elimination:** Windows is demoted from a per-seat desktop to a shared, right-sized application service. Endpoint OS licensing goes away (community Linux, or Red Hat when a support contract is wanted). Published apps are concurrent: size the Windows session-host pool to simultaneous users of legacy apps, not headcount. As clinical software goes web-native, the Windows farm keeps shrinking. Caveats: Windows Server and per-user delivery licensing still cost money and need careful sizing; the publishing tier is real engineering; if most staff need a heavy native Windows app all day, savings shrink. Savings scale with how much of the workload is web or Linux-native.

**Security and vendor-independence thesis:** a browser-focused, immutable, STIG-hardened Linux endpoint with no local install rights and phishing-resistant MFA has a far smaller attack surface than a general-purpose Windows desktop, and sidesteps much of the Windows-targeted ransomware landscape. The vendor angle is optionality, not an anti-Microsoft stance. Counterpoints to volunteer in interviews: retraining and change management, the remaining native-app gap, and peripherals (badge readers, label printers, scanners, dictation) with Windows-first drivers. These scope the thesis; they do not kill it.

One-line thesis: as clinical computing moves to the browser, LocumView lets healthcare organizations reduce licensing dependence and shrink their attack surface by standardizing on hardened, reproducible Linux endpoints, adopted workload by workload.

## 8. Pending decisions

- Guacamole hosting: Podman/Quadlet vs k3s
- Verify Red Hat Cloud Access before the AWS rung
- Set VM memory limits on MikePC before KubeVirt
