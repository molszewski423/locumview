# ADR 0009: Version-one scope lockdown, integrate don't bundle, hypervisor as a deploy-time parameter

Status: Accepted
Date: 2026-10-03

## Context

By 2026-10-03 the access layer is live (changelog #17 to #23), and the list of good ideas keeps growing: Nextcloud, Red Hat IdM, Matrix, clinical AI agents, FHIR, KubeVirt, AWS, SUSE and Debian builds, WebAuthn, session recording. Each is worth doing, and together they would postpone version one indefinitely. A website review the same day found the project had been described as further along than it is (changelog #23), which shows the cost of scope that isn't written down. Healthcare and life-sciences organizations also already run most of these services (a directory, an IdP, file sharing, messaging, an EHR), so a VDI platform that ships its own copy of each competes with what customers have instead of fitting into it.

## Decision

### 1. Version one is locked to this list

Version one is complete when all of these are true, and nothing else is required for it:

1. **Desktop from code:** one RHEL 10 desktop built as a bootc image from a Containerfile (ADR 0007) and provisioned on the reference hypervisor from a clean clone with zero manual steps.
2. **Access:** reached in a browser through Guacamole with Keycloak SSO and enforced MFA, no exposed RDP (live since changelog #21).
3. **Hardening evidence:** DISA STIG profile applied, OpenSCAP report committed to `docs/evidence/`, documented exceptions.
4. **Encryption in transit everywhere:** including the in-cluster hop between nodes (open item from changelog #21).
5. **Documentation:** README with an architecture diagram, a working quick start, the HIPAA technical-safeguard mapping, and an honest status section.

Anything not on this list is **planned**, and is described as planned everywhere (README, ROADMAP, website). New ideas go to the roadmap, not into version one. Changing this list needs a new ADR that supersedes this one.

### 2. Integrate, don't bundle

LocumView's product is the governed desktop and its delivery path. For surrounding services it **integrates with what the customer already runs** through open standards, rather than shipping its own copy:

| Need | Integration point | Homelab reference instance |
|---|---|---|
| Identity / MFA | Keycloak as broker: OIDC/SAML to an existing IdP | Keycloak (ADR 0005) |
| Directory | LDAP/Kerberos; IdM, or AD through an IdM trust | Red Hat IdM (ADR 0006) |
| Files | WebDAV/SMB mounts in the desktop | Nextcloud (planned) |
| Clinical data | FHIR R4 / SMART on FHIR | Synthetic FHIR server (planned) |
| Messaging | Standards-based clients in the desktop | Matrix (planned) |
| Clinical AI | Optional, detachable module (ADR 0008) | Local models (planned) |

The homelab instances exist to **demonstrate and test** the integrations. They are reference deployments, not product components, and none of them is a version-one requirement.

### 3. The hypervisor is a deploy-time parameter

The desktop artifact (the bootc image, ADR 0007) doesn't depend on where the VM runs. The hypervisor is chosen at deploy time through a provisioning module per target, with the same image, the same hardening and the same access path:

- **libvirt/KVM:** the reference target, and the only one validated for version one.
- **Proxmox VE:** the practical production target (planned).
- **KubeVirt / OpenShift Virtualization:** a scoped learning piece (planned), with the demo desktop as its first workload; not required to call the architecture container-based (ADR 0007).
- **Public or sovereign cloud:** planned.

Nothing in the desktop or the access layer may assume a specific hypervisor (no libvirt-only guest settings in the image; host specifics live in the provisioning module).

## Alternatives considered

- **An open-ended roadmap with no lock:** maximal flexibility; in practice version one never ships and the status keeps being overstated.
- **Bundling a full suite** (own directory, file share, messaging and AI in every deployment): attractive in a demo, but it duplicates services hospitals already run and multiplies what has to be hardened, patched and audited.
- **Picking one hypervisor permanently:** simpler, but it locks deployments to one platform and conflicts with the deploy-anywhere and sovereignty goals.

## Consequences

- Phase plan, README, ROADMAP and website must label every item as version one, live, next or planned, consistently.
- Nextcloud, IdM, Matrix, FHIR, clinical AI, KubeVirt, cloud targets, WebAuthn and session recording are planned work after (or alongside, if they don't delay) version one.
- Each integration needs a documented interface (protocol, configuration, test) so a customer's own service can replace the homelab reference instance.
- Provisioning code is split per hypervisor target, and the desktop image is tested on at least the reference target in CI once CI exists.
- Clinical decision support is outside version one and, in the EU, outside the initial product altogether (ADR 0008).
