# LocumView

An open-source virtual desktop platform for regulated environments, built in the open on Red Hat Enterprise Linux 10. Desktops are delivered through the browser behind single sign-on and MFA, and no desktop is ever exposed directly to the internet.

Website: [locumview.com](https://locumview.com) · Sign in: [login.locumview.com](https://login.locumview.com)

## Status

**Version one is not complete.** Its scope is locked by [ADR 0009](docs/adr/0009-v1-scope-integrate-dont-bundle.md); [ROADMAP.md](ROADMAP.md) has the live status of each item and what is planned after it.

**Live today**
- A RHEL 10 GNOME desktop reached at login.locumview.com: Keycloak SSO with TOTP enforced, then straight onto the desktop (no second login screen).
- Access layer on k3s: Apache Guacamole, guacd, Keycloak and their databases, with Pod Security `restricted` and default-deny network policies.
- Public access through an outbound-only Cloudflare Tunnel; RDP is reachable only from the cluster, never from the internet.
- Secrets in the repo only as SOPS + age ciphertext, enforced by pre-commit checks.
- An isolated guest demo account, LocumView branding, and a first-run tour.
- Organizational login through Red Hat IdM, with Keycloak as the only MFA authority.
- The reference desktop hardened to the DISA STIG with GUI profile: 417 OpenSCAP rules pass, and every rule not applied is documented ([hardening/stig/](hardening/stig/README.md)).
- Encryption on every network hop, including WireGuard between cluster nodes.
- CI that re-runs every check on each push.

**Not done yet (version one)**
- The desktop builds as a bootc image (`image/desktop/`) and installs and provisions itself from an ISO: LUKS on the vTPM, IdM, RDP (changelog #53). CI builds, signs and attests the image (changelog #57), and desktops accept only images signed with the project key (changelog #58). The destroy-and-rebuild proof from a clean clone passed (changelog #59); still open: the STIG scan of the rebuilt desktop ([ADR 0007](docs/adr/0007-desktop-containerization-bootc.md)). The running reference desktop is still the hand-built one, and the quick start below covers the access layer.
- No FIPS mode on the desktop: RDP sign-in to GNOME Remote Desktop needs NTLM, which FIPS mode disables ([ADR 0012](docs/adr/0012-fips-mode-and-remote-display.md)).
- Data at rest: desktops installed from the bootc image are encrypted (LUKS on the vTPM); the hand-built reference desktop, the cluster nodes and the databases are not yet (see the HIPAA mapping).

The full build history, with every command and its evidence, is in [notes/phase1-changelog.md](notes/phase1-changelog.md) and [docs/evidence/](docs/evidence/).

## How it fits together (today)

```
Browser ─HTTPS─▶ Cloudflare edge ─tunnel─▶ cloudflared (k3s)
   ├─ /realms/locumview, /resources ─▶ Keycloak (SSO, MFA, audit)
   └─ everything else ─▶ Guacamole ─▶ guacd ─RDP over TLS─▶ RHEL 10 desktop VM (libvirt)
```

The access layer runs as containers on k3s. The desktop runs as a VM: a GNOME session with audio and remote display behaves like a machine, not a process. From version one the desktop OS itself is built and shipped as a container image (RHEL image mode / bootc), and the hypervisor becomes a deploy-time choice ([ADR 0007](docs/adr/0007-desktop-containerization-bootc.md), [ADR 0009](docs/adr/0009-v1-scope-integrate-dont-bundle.md)).

## Quick start

**Try it.** The guest demo is at [login.locumview.com](https://login.locumview.com) (request access at [locumview.com/contact](https://locumview.com/contact); the guest password is rotated after each evaluation). It is a shared demo: never enter real patient data.

**Check the repository.** Every check CI runs is a pre-commit hook:

```
pre-commit install
pre-commit run --all-files     # ansible-lint, detect-secrets, SOPS check, gitleaks, kubeconform, tflint
```

The container-based hooks need `docker` (or podman with its `docker` shim).

**Run the access layer on your own k3s cluster.** You need k3s (the reference cluster uses `flannel-backend: wireguard-native`), `kubectl`, `sops` and `age`, and a RHEL 10 desktop reachable over RDP.

1. Create an age key and put its public key in `.sops.yaml`; the committed secrets are encrypted to the project's key and will not decrypt for you.
2. Create the six secrets in `k8s/locumview/secrets/` with your own values and encrypt them (`sops -e -i <file>`). Names and keys: `cloudflared` (`token`, only for public access), `guacamole-db` (`postgres-password`, `app-password`, `admin-password`), `keycloak` (`postgres-password`, `db-password`, `bootstrap-admin-password`), `demo-login` (`username`, `password`), and one per desktop connection (`hostname`, `port`, `rdp-username`, `rdp-password`). Generate passwords straight into the file; never type them.
3. Copy `k8s/locumview/site.env.example` to `k8s/locumview/site.env` and fill it in (desktop and IdM addresses, the node for the databases).
4. Apply: `sops -d` each secret into `kubectl apply -f -`, then `kubectl apply -k k8s/locumview`.
5. Configure Keycloak and Guacamole with the idempotent scripts, each documented in its header: `keycloak/configure-realm.sh`, `keycloak/create-user.sh`, `guacamole/upsert-desktop-connection.sh`, and `keycloak/configure-idm-federation.sh` if you use IdM.
6. Without a Cloudflare tunnel, reach Guacamole and Keycloak with `kubectl port-forward`.

**The desktop** is built today by the documented scripts in `packaging/` (desktop, remote access, IdM enrollment), in the order of [the build log](notes/phase1-changelog.md) entries #11 to #36, then hardened with `hardening/stig/apply-stig.sh` (the SSG Ansible playbook). Its replacement already works: the bootc image (`image/desktop/`) hardened at build time, installed and provisioned by OpenTofu (`terraform/`) with no manual steps (changelog #51 to #55). The live reference desktop moves to it once version-one item 1 is done.

## HIPAA technical safeguards

Each technical safeguard of 45 CFR 164.312 is mapped to the control that addresses it and the evidence in this repository in [docs/hipaa-technical-safeguards.md](docs/hipaa-technical-safeguards.md). In short: access control, emergency access, authentication and transmission security are met; audit controls are partly met (no central log collection or session recording yet); encryption at rest is partly met (desktops installed from the bootc image are encrypted; **the cluster nodes, the databases and the hand-built reference desktop are not yet**). HIPAA compliance itself belongs to the organization running the platform.

## Architecture decisions

| ADR | Decision |
|---|---|
| [0001](docs/adr/0001-rhel10.md) | RHEL 10 as the base distribution |
| [0002](docs/adr/0002-access-layer-on-k3s.md) | Access layer on k3s |
| [0003](docs/adr/0003-secrets-sops-age.md) | Secrets with SOPS and age |
| [0004](docs/adr/0004-public-access-cloudflare-tunnel.md) | Public access through a Cloudflare Tunnel |
| [0005](docs/adr/0005-keycloak-identity-provider.md) | Keycloak as the single identity provider |
| [0006](docs/adr/0006-red-hat-idm-directory.md) | Red Hat IdM as the directory (built) |
| [0007](docs/adr/0007-desktop-containerization-bootc.md) | Desktop OS as a bootc image; the session is a VM workload |
| [0008](docs/adr/0008-eu-regulatory-posture.md) | EU regulatory posture; clinical AI as a detachable module |
| [0009](docs/adr/0009-v1-scope-integrate-dont-bundle.md) | Version-one scope, integrate don't bundle, hypervisor at deploy time |
| [0010](docs/adr/0010-desktop-vm-sizing-memory.md) | Desktop VM sizing tiers and host memory overcommit (free page reporting, KSM) |
| [0011](docs/adr/0011-agentic-linus.md) | Argus (was "agentic Linus") for LocumView engineering: local model, read-only scoped access, changes only as PRs from a fork, code in a sandbox; staged toward a platform agent |
| [0012](docs/adr/0012-fips-mode-and-remote-display.md) | No FIPS mode on the desktop while GNOME Remote Desktop's RDP sign-in needs NTLM; revisited for sectors that require FIPS |
| [0013](docs/adr/0013-opentofu-for-infrastructure.md) | OpenTofu for the infrastructure around each desktop (VM, volumes, seed, IdM host entry), bootc for the operating system; state encrypted |
| [0014](docs/adr/0014-gnome-desktop.md) | GNOME on Wayland as the desktop, reached through GNOME Remote Desktop; organization-set layouts |
| [0015](docs/adr/0015-apache-guacamole-broker.md) | Apache Guacamole as the clientless browser broker in front of the desktops |
| [0016](docs/adr/0016-browser-baseline.md) | Browser baseline: Firefox ESR as the system browser, hardened Google Chrome for web EHRs; the browser is a swappable slot |

## Where it is going

Beyond the base desktop, LocumView is meant to host research tooling and local LLM applications inside regulated environments, so regulated data never leaves the boundary. The desktop, hardening and delivery path stay the same; only the application layer changes. Clinical and life sciences come first because of the author's domain expertise; the same pattern applies to other regulated domains.

LocumView **integrates rather than bundles**: it works with the identity provider, directory, file storage and clinical systems an organization already runs, through open standards. The homelab instances (Keycloak, IdM, Nextcloud, a synthetic FHIR server) demonstrate those integrations; they are not product components. Clinical decision support is a detachable module: outside version one, and outside the initial EU product, which needs medical-device certification for it ([ADR 0008](docs/adr/0008-eu-regulatory-posture.md)).

These are plans, listed with their status in [ROADMAP.md](ROADMAP.md).

## Vision

In healthcare, a locum clinician steps in wherever care is needed, ready to work on day one. LocumView applies that idea to infrastructure: a trusted, compliant workspace that appears wherever an authorized user signs in, and disappears cleanly when the work is done. The aim is to show that the capabilities of commercial VDI suites like VMware Horizon (originally VMware View) can be delivered with open, auditable, reproducible tooling.

## Why I built it

After two decades as a critical care and infectious disease pharmacist, I've worked inside the systems clinicians depend on every shift, including enterprise VDI. LocumView is where that clinical perspective meets platform engineering: building the kind of secure, dependable infrastructure I'd want at the bedside.

## How LocumView maps to VMware Horizon

| VMware Horizon | LocumView | Status |
|---|---|---|
| Unified Access Gateway | Cloudflare Tunnel (Tailscale for administration) | Live |
| Connection Server | Apache Guacamole | Live |
| Blast / HTML Access | RDP via guacd, in the browser | Live |
| Identity / MFA | Keycloak with TOTP; WebAuthn next | Live (TOTP) |
| Instant-clone pools | bootc desktop images, provisioned per hypervisor | Planned (version one: one desktop) |

Horizon is now owned by Omnissa after Broadcom divested VMware's end-user computing business. Horizon was originally named VMware View, which the LocumView name nods to.

## Repository layout

- `k8s/locumview/`: access layer manifests (kustomize), encrypted secrets, Keycloak realm and Guacamole scripts.
- `packaging/`: desktop setup, branding, remote access, the LocumView Tour and GNOME extensions.
- `hypervisor/`: host preparation and VM move scripts.
- `hardening/stig/`: the DISA STIG tailoring and the scripts that apply and scan it.
- `docs/adr/`: architecture decisions. `docs/evidence/`: compliance evidence and worklogs. `docs/user-guide/`: end-user help. `docs/hipaa-technical-safeguards.md`: the HIPAA mapping.
- `.gitea/workflows/`: CI.
- `terraform/`: OpenTofu (ADR 0013): the libvirt desktop module and the node1 root configuration.

## License

Copyright 2026 Michael Olszewski. Licensed under the [Apache License, Version 2.0](LICENSE); see [NOTICE](NOTICE). Every file in this repository is original to the project, including the generated wallpapers, logos and login background. The project website's text is not part of this repository and is not covered by this license.
