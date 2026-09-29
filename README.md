# LocumView

Secure, reproducible Linux desktops for regulated environments, delivered anywhere through the browser, built to run agentic AI and research tooling without regulated data ever leaving the compliance boundary.

Status: Phase 1 in progress (hand-built reference desktop). No quick start or architecture diagram yet; those land at the end of Phase 3. See [docs/PLAN.md](docs/PLAN.md) for the full plan and [notes/phase1-changelog.md](notes/phase1-changelog.md) for the build log.

## About

LocumView is an open-source virtual desktop platform built on Red Hat Enterprise Linux 10. It provisions hardened GNOME and Sway desktops with Terraform and Ansible, then delivers them through a browser via Apache Guacamole, protected by Keycloak single sign-on and multi-factor authentication. No desktop is ever exposed directly to the internet, and every environment can be torn down and rebuilt identically from this repository. Desktops are hardened against DISA STIG profiles, scanned with OpenSCAP, and mapped to HIPAA technical safeguards, with the compliance evidence committed alongside the code.

Beyond the base desktop, LocumView is a platform for research and local LLM usage inside regulated environments. Desktops can be built out with agentic tooling and generative and agentic applications, for example clinical and research assistants, with local models so nothing regulated leaves the endpoint. The same base image, hardening, and delivery path stay constant; only the application layer changes. Initial user targets are clinical and life sciences, chosen for personal domain expertise; later phases apply the same pattern to other regulated domains (finance, legal, defense, and similar), since the tooling is customizable for any regulated workflow, not specific to healthcare.

## Vision

In healthcare, a locum clinician steps in wherever care is needed, ready to work on day one. LocumView applies that idea to infrastructure: a trusted, compliant workspace that appears wherever an authorized user signs in, and disappears cleanly when the work is done. The goal is to show that the capabilities of commercial VDI suites like VMware Horizon (originally VMware View) can be delivered with open, auditable, reproducible tooling, from a homelab on libvirt, to Kubernetes with KubeVirt, to AWS, and that the same hardened endpoint can safely host the agentic AI tooling regulated work increasingly needs.

## Why I built it

After two decades as a critical care and infectious disease pharmacist, I've worked inside the systems clinicians depend on every shift, including enterprise VDI. LocumView is where that clinical perspective meets platform engineering: building the kind of secure, dependable infrastructure I'd want at the bedside.

## How LocumView maps to VMware Horizon

| VMware Horizon | LocumView |
|---|---|
| Unified Access Gateway | Traefik + Tailscale / Cloudflare Tunnel |
| Connection Server | Apache Guacamole |
| Blast / HTML Access | RDP via guacd, delivered in the browser |
| Identity / MFA | Keycloak with MFA (WebAuthn) |
| Instant-clone pools | Terraform + Ansible desktop profiles |

Horizon is now owned by Omnissa after Broadcom divested VMware's end-user computing business. Horizon was originally named VMware View, which the LocumView name nods to.
