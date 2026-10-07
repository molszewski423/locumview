# LocumView

An open-source virtual desktop platform for regulated environments, built in the open on Red Hat Enterprise Linux 10. Desktops are delivered through the browser behind single sign-on and MFA, and no desktop is ever exposed directly to the internet.

Website: [locumview.com](https://locumview.com) · Sign in: [login.locumview.com](https://login.locumview.com)

## Status

**Version one is not complete.** Its scope is locked by [ADR 0009](docs/adr/0009-v1-scope-integrate-dont-bundle.md); see [ROADMAP.md](ROADMAP.md) for what is in it and what is planned after it.

**Live today**
- A RHEL 10 GNOME desktop reached at login.locumview.com: Keycloak SSO with TOTP enforced, then straight onto the desktop (no second login screen).
- Access layer on k3s: Apache Guacamole, guacd, Keycloak and their databases, with Pod Security `restricted` and default-deny network policies.
- Public access through an outbound-only Cloudflare Tunnel; RDP is reachable only from the cluster, never from the internet.
- Secrets in the repo only as SOPS + age ciphertext, enforced by pre-commit checks.
- An isolated guest demo account, LocumView branding, and a first-run tour.

**Not done yet (version one)**
- The desktop is still built by documented scripts, not yet as a bootc image from code ([ADR 0007](docs/adr/0007-desktop-containerization-bootc.md)).
- DISA STIG hardening and the OpenSCAP report are not applied yet.
- Pod-to-pod traffic between cluster nodes is not yet encrypted.
- No quick start or final architecture diagram yet.

The full build history, with every command and its evidence, is in [notes/phase1-changelog.md](notes/phase1-changelog.md) and [docs/evidence/](docs/evidence/).

## How it fits together (today)

```
Browser ─HTTPS─▶ Cloudflare edge ─tunnel─▶ cloudflared (k3s)
   ├─ /realms/locumview, /resources ─▶ Keycloak (SSO, MFA, audit)
   └─ everything else ─▶ Guacamole ─▶ guacd ─RDP over TLS─▶ RHEL 10 desktop VM (libvirt)
```

The access layer runs as containers on k3s. The desktop runs as a VM: a GNOME session with audio and remote display behaves like a machine, not a process. From version one the desktop OS itself is built and shipped as a container image (RHEL image mode / bootc), and the hypervisor becomes a deploy-time choice ([ADR 0007](docs/adr/0007-desktop-containerization-bootc.md), [ADR 0009](docs/adr/0009-v1-scope-integrate-dont-bundle.md)).

## Architecture decisions

| ADR | Decision |
|---|---|
| [0001](docs/adr/0001-rhel10.md) | RHEL 10 as the base distribution |
| [0002](docs/adr/0002-access-layer-on-k3s.md) | Access layer on k3s |
| [0003](docs/adr/0003-secrets-sops-age.md) | Secrets with SOPS and age |
| [0004](docs/adr/0004-public-access-cloudflare-tunnel.md) | Public access through a Cloudflare Tunnel |
| [0005](docs/adr/0005-keycloak-identity-provider.md) | Keycloak as the single identity provider |
| [0006](docs/adr/0006-red-hat-idm-directory.md) | Red Hat IdM as the directory (planned) |
| [0007](docs/adr/0007-desktop-containerization-bootc.md) | Desktop OS as a bootc image; the session is a VM workload |
| [0008](docs/adr/0008-eu-regulatory-posture.md) | EU regulatory posture; clinical AI as a detachable module |
| [0009](docs/adr/0009-v1-scope-integrate-dont-bundle.md) | Version-one scope, integrate don't bundle, hypervisor at deploy time |
| [0010](docs/adr/0010-desktop-vm-sizing-memory.md) | Desktop VM sizing tiers and host memory overcommit (free page reporting, KSM) |
| [0011](docs/adr/0011-agentic-linus.md) | Agentic Linus for LocumView engineering: local model, read-only scoped access, changes only as PRs from a fork |

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
- `docs/adr/`: architecture decisions. `docs/evidence/`: compliance evidence and worklogs. `docs/user-guide/`: end-user help.
- `terraform/`, `ansible/`: provisioning (version one work, not populated yet).

## License

Copyright 2026 Michael Olszewski. Licensed under the [Apache License, Version 2.0](LICENSE); see [NOTICE](NOTICE). Every file in this repository is original to the project, including the generated wallpapers, logos and login background. The project website's text is not part of this repository and is not covered by this license.
