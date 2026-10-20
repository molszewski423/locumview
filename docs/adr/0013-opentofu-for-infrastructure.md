# ADR 0013: OpenTofu for infrastructure; bootc for the operating system

Status: Accepted
Date: 2026-10-20

## Context

The original plan (docs/PLAN.md, Phase 3) split the work as "Terraform outside, Ansible inside": Terraform creates the VM, Ansible configures the guest. ADR 0007 then moved the guest to RHEL image mode: the desktop is a bootc image built from a Containerfile, hardened at build time, and per-desktop values are applied by first-boot provisioning (changelog #51 to #53). Ansible roles for the desktop are no longer needed.

What remained by hand or by script is everything around the image: the VM itself (q35, UEFI with Secure Boot, SMM, a vTPM, disks, the LAN bridge), the seed disk with the desktop's values, the IdM host entry with its one-time enrollment password (run by the owner with `ipa host-add` for every test desktop), and cleaning all of it up again. `hypervisor/new-desktop.sh` covered the VM and seed; nothing covered the IdM entry or teardown. Version-one item 1 asks for a destroy and rebuild with zero manual steps.

"Terraform vs OpenTofu" was an open ADR (ROADMAP housekeeping). The seed and the IdM host carry secrets: the break-glass, GRUB and RDP passwords, the LUKS recovery passphrase and the enrollment password. Any infrastructure-as-code tool records what it creates in its state, so the state holds them too.

## Decision

- **The split is "OpenTofu outside, bootc inside."** The image defines what runs in the desktop; OpenTofu defines the infrastructure around it and the records each desktop needs elsewhere. Per-desktop values travel on the seed disk, never in the image.
- **OpenTofu, not HashiCorp Terraform.** Same HCL language, workflow and providers, so the configuration reads as Terraform to anyone who knows it. Chosen for:
  - **State encryption built in** (`encryption` block, enforced for state and plan files), so the secrets in the state are never stored in plain text. Terraform has no equivalent without an encrypting remote backend.
  - **An open-source license** (MPL 2.0, Linux Foundation), consistent with the rest of the stack; Terraform has been under the Business Source License since 2023.
- **What the module (`terraform/modules/libvirt-desktop`) owns:** the IdM host entry and its host group membership (FreeIPA provider), a random one-time enrollment password, the desktop disk and seed volumes, the seed contents, the VM, and the wait for first boot to finish (the desktop ejects its seed when provisioning succeeds; the seed volume is then wiped). `tofu destroy` removes all of it, the IdM entry included.
- **Secrets** stay in SOPS (ADR 0003): one file per desktop, read with the `sops` provider in the root configuration (`terraform/node1`). The state passphrase is in SOPS too. OpenTofu therefore runs on an operator machine that holds the age key, against node1's libvirt over SSH.
- **Providers pinned exactly** in the root configuration, and `.terraform.lock.hcl` committed. Two providers (libvirt, FreeIPA) are not signed in the OpenTofu registry; their hashes were checked against the checksums published with each GitHub release before the lock file was committed.

## Alternatives considered

- **HashiCorp Terraform.** Equivalent for the VM and the providers; rejected for the lack of native state encryption and the license. The configuration stays Terraform-compatible apart from the `encryption` block.
- **Keep the shell script.** Works (changelog #53) but has no teardown, no drift detection, and leaves the IdM entry manual.
- **Ansible for the VM and IdM.** Possible (community.libvirt, freeipa.ansible_freeipa), but Ansible has no state, so "destroy" and drift detection would be hand-written.
- **cloud-init's own seed (`libvirt_cloudinit_disk`).** It carries only cloud-init's files; putting the secrets in user-data would leave copies in `/var/lib/cloud` on the desktop. The module builds the seed itself.

## Consequences

- The platform ladder of ADR 0009 keeps its shape: bootc-image-builder turns the same image into a qcow2 or an AMI, and only the OpenTofu module changes per target (libvirt now; Proxmox and AWS later).
- Losing the state passphrase means losing the state, not the desktops: they keep running, and resources can be imported again.
- The FreeIPA provider currently signs in as an IdM administrator, typed in at each run. A dedicated IdM account limited to host and host group administration is a follow-up.
- Provider quirks found on the first run are recorded in the module: disks referenced by path (AppArmor on Debian hosts), the seed volume's reported format ignored, enrollment-time changes to the IdM host ignored.
