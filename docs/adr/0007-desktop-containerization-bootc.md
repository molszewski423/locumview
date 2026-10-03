# ADR 0007: Desktop containerization via bootc; interactive session as a VM workload

Status: Accepted
Date: 2026-10-03

## Context

A reviewer asked why LocumView is not "container-based." The question is fair, because the access layer (Guacamole, guacd, Keycloak, Postgres, cloudflared) already runs as containers on k3s, while the desktop itself runs as a libvirt VM on MikePC.

Two different things are easy to conflate here:

1. **How the desktop OS is built, versioned and shipped.** This benefits from container tooling: reproducible builds, registries, signing, rollback.
2. **How the interactive desktop session runs.** A full GNOME session with a compositor, audio, GPU access, systemd, a user login and remote display (GNOME Remote Desktop over RDP) behaves like a machine, not a process. Running it as a pod means fighting the container model at every layer (privileged mode, device access, init system, session lifecycle).

The earlier informal answer ("libvirt will move to KubeVirt") described a hosting migration, not a containerization strategy, and did not address the question.

## Decision

- The desktop OS is containerized at **build and delivery time** using RHEL image mode (**bootc**). The desktop is defined in a Containerfile and built into a versioned, signed OCI image stored in a registry. Updates are image swaps; rollback is a reboot into the previous image.
- The interactive session runs as a **VM booted from that image**. Today that VM runs on libvirt. The target hypervisor is a deploy-time parameter (see ADR 0009): libvirt now, Proxmox as the practical production target, KubeVirt / OpenShift Virtualization as a scoped learning piece.
- Supporting services (broker, identity, databases, AI plumbing) remain normal containers on k3s.

In one sentence: **the OS is a container image; the desktop session is a VM, because a GPU and audio desktop is a VM workload, not a pod.**

## Consequences

**Positive**
- Every desktop is built from one auditable definition, which supports the GxP/CSV-style reproducibility story and per-release SBOMs (syft) and signatures (cosign).
- Atomic updates and rollback protect the core OS from drift and user error.
- One image definition boots on libvirt, Proxmox and KubeVirt, so the hypervisor choice does not fork the desktop build.
- Matches how Red Hat positions image mode, which is directly relevant to the target employer.

**Negative / costs**
- Requires a container registry and an image build and signing pipeline (CI work not yet done).
- Desktop changes now go through an image rebuild rather than ad-hoc package installs; iteration happens on a mutable dev desktop first, then is encoded in the Containerfile.
- Per-user state (home directories, settings) must live outside the image and be designed deliberately.

**Neutral**
- KubeVirt remains possible but is not required to claim a container-based architecture.
