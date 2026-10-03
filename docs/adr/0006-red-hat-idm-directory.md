# ADR 0006: Red Hat Identity Management as the directory

Status: Accepted
Date: 2026-10-03

## Context

Keycloak (ADR 0005) is the single sign-on and MFA front door, but it is not a Linux directory. Desktops still use local accounts: the reference desktop's user is a local `molszewski`, and the guest demo is a local `demo` (changelog #22). That means a person's web identity and their Linux identity are separate, sudo and host access are set per machine, and offboarding is manual on every desktop. Regulated customers expect one place to create, change and remove accounts, with host-based access rules and an audit trail. The owner chose Red Hat IdM over Microsoft Active Directory (2026-10-02).

## Decision

Run **Red Hat Identity Management (IdM, upstream FreeIPA)** as the directory for LocumView users, groups and Linux hosts.

- **Domain and realm:** DNS domain `corp.locumview.com`, Kerberos realm `CORP.LOCUMVIEW.COM`, first server `idm01.corp.locumview.com`. The domain is a subdomain of a domain the project owns (Red Hat guidance; no `.local` or `.lan`) and is never published publicly: only the home DNS forwards it, to IdM's integrated DNS.
- **Placement:** a dedicated RHEL 10 VM on **debianbox**, not on MikePC. Identity sits in a different failure domain from the desktop hypervisor, and MikePC's memory stays for desktops and the local AI workload. IdM is not containerized and not on k3s: it is a stateful system service with its own DNS, Kerberos and certificate authority, and Red Hat supports it on RHEL hosts.
- **Sizing:** 2 vCPU, 4 GiB RAM, 40 GiB disk (Red Hat's minimum for a small deployment). debianbox (Intel i3-4130T, 4 threads, 15 GiB RAM, about 8 GiB free) can carry it alongside its k3s worker role, with no headroom for a replica.
- **Integration:**
  - Keycloak federates users and groups from IdM over LDAPS (read-only service account). IdM becomes the source of truth for accounts; Keycloak keeps SSO, MFA, login policy and the login pages.
  - Desktops enrol with `ipa-client-install` (SSSD), so the Linux account is the same identity as the web login. Host-based access control (HBAC) and sudo rules come from IdM.
  - Microsoft AD is supported later through an IdM trust, if a customer brings AD (ADR 0009: integrate, don't bundle).
- **Provisioning:** kickstart and scripts in the repo (later Terraform + Ansible, using the `redhat.rhel_idm` collection), registration with an activation key (no account password in files), all secrets in SOPS (ADR 0003).

## Alternatives considered

- **Microsoft Active Directory (Windows Server):** the most common enterprise directory, but it adds Windows Server licensing and a Windows host to a Linux-first, RHEL-aligned project. Covered later by an IdM trust instead.
- **Samba AD DC on Linux:** AD-compatible without Windows, but Red Hat doesn't support it as a domain controller, and its Linux host integration (HBAC, sudo, certificates) is weaker than IdM's.
- **Keycloak alone, with local Linux accounts:** what runs today. No central Linux identity, sudo or host access policy; doesn't scale beyond a handful of desktops.
- **IdM on MikePC:** simplest networking (`br0` already exists), but it puts identity and desktops in one failure domain and competes with desktops and AI for memory.
- **OpenLDAP + MIT Kerberos by hand:** what IdM packages, minus the integration, policy tooling and support.

## Consequences

- debianbox needs host preparation first: libvirt/KVM (not installed today) and a LAN bridge like MikePC's `br0` (changelog #15), with the same rollback-safe switchover and the `bridge-nf-call-iptables` FORWARD rule, because debianbox is a k3s node.
- The home AdGuard (on debianbox) gets a conditional forward of `corp.locumview.com` to IdM's DNS. Nothing else on the home network changes.
- **Account migration risk:** the reference desktop's local `molszewski` (UID 1000) and IdM's `molszewski` can't share a name and UID. Enrolment needs a planned migration (backup or snapshot first, UID mapping or a renamed local account). The `demo` account is the first candidate to move to IdM.
- A single IdM server is a single point of failure for every login: with IdM down, Keycloak can't verify passwords for federated users (it validates against LDAP), and desktops can't resolve or authenticate IdM accounts beyond SSSD's offline cache. The break-glass paths (Keycloak's local admin, a local desktop admin) must stay outside IdM. A replica on another host and IdM backups (`ipa-backup`) are prerequisites before anyone depends on it.
- debianbox is a homelab deviation: an old desktop-class CPU, no ECC, a Debian hypervisor. The production reference is RHEL hosts.
- Not in the version-one critical path (ADR 0009): built when it doesn't delay version one, or immediately after it.
