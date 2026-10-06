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

## Update 2026-10-04: MFA for IdM users

- **Keycloak is the only MFA authority.** Federated IdM users sign in through the existing `locumview-browser` flow: Keycloak checks the password against IdM over LDAPS, then requires the second factor itself. OTP credentials live in Keycloak, not IdM. New IdM users get Keycloak's `CONFIGURE_TOTP` required action and enrol on first sign-in. The `mfa-exempt` role keeps working through the `locumview-demo` group, which can now come from IdM.
- **IdM users stay on user auth type `password`.** IdM's native OTP (`ipa otptoken-add`, auth type `otp`) stays off for anyone who signs in through Keycloak: with it on, IdM expects the password and the OTP concatenated on every LDAP bind, which breaks Keycloak's password check, and users would enrol two authenticators.
- **Linux-side logins** (sudo, screen unlock, SSH) use the IdM password. Acceptable because desktops are reached only through Guacamole after Keycloak MFA, and SSH and RDP are firewalled to the k3s nodes (changelog #19, #30). Later experiments, not part of the first build: IdM passkeys (FIDO2) for sudo and SSH, enabled alongside `password` so the LDAP bind still works; IdM external IdP authentication delegated to Keycloak, which creates a circular dependency while Keycloak validates passwords against IdM.
- **Acceptance test for the federation step:** create a test user in IdM, sign in at login.locumview.com, confirm Keycloak forces TOTP enrolment, then reaches Guacamole with the expected groups.
- **Timing:** the owner started the build on 2026-10-04, ahead of version one. It stays outside ADR 0009's scope; version one does not depend on it.

## Update 2026-10-05: first server on MikePC, replica on debianbox

- **Change:** `idm01` runs on **MikePC** (libvirt, LAN bridge `br0`, 192.168.4.47), not on debianbox. Owner decision, 2026-10-05.
- **Why:** the failure-domain argument above doesn't hold yet. Keycloak, Guacamole, guacd and the reference desktop all run on MikePC, so if MikePC is down LocumView is down wherever IdM lives. MikePC already has `br0`, libvirt and storage pools (changelog #15); debianbox would need a bridge switchover that interrupts the home DNS (AdGuard) and the k3s agent. MikePC's CPU (Ryzen 7 7800X3D) is also far faster than debianbox's (i3-4130T).
- **Failure separation comes from the replica:** the IdM replica, already a prerequisite before anyone depends on IdM, goes on debianbox once its bridge is done at a quiet time. A primary on MikePC plus a replica on debianbox separates identity from the desktop host better than one server on debianbox.
- **Cost:** MikePC memory. About 11 GiB was available on 2026-10-05 with the reference VM (6 GiB) and Ollama running; `idm01` gets a fixed 4 GiB. No further desktop VMs on MikePC until VM memory limits are decided (PLAN.md, pending decisions); decided in ADR 0010.
- **Unchanged:** domain `corp.locumview.com`, realm `CORP.LOCUMVIEW.COM`, sizing (2 vCPU, 4 GiB, 40 GiB), Keycloak federation over LDAPS, MFA in Keycloak only (update of 2026-10-04).
- **Provisioning detail:** the base image is a RHEL 10.2 qcow2 built with Red Hat Image Builder (package mode, no packages, register later; SHA-256 `b5a806e00f4338c7f2f1bc678e0e7bb8d9c303094ab9c70c23f2611470a2f8e7`), configured on first boot by cloud-init (hostname, static address, admin SSH keys, activation-key registration) instead of a kickstart.

## Update 2026-10-05: accounts and naming

Standard practice for an organisation with its own domain and services (desktops now; mail and Nextcloud later). Owner decision, 2026-10-05.

- **People:** one account per person, in IdM. Login (`uid`) is first initial + last name, lower case (`molszewski`); collisions get a middle initial or a number. Email (`mail`) is `<uid>@locumview.com` and is what people type at sign-in (Keycloak accepts email or username). The Kerberos principal follows automatically (`molszewski@CORP.LOCUMVIEW.COM`). The same account and the same MFA reach every service through Keycloak SSO. Rights come from IdM groups mapped to applications (`locumview-admins`, `locumview-users`, `locumview-demo`), never from per-application accounts.
- **Break-glass:** a few generic, role-named emergency accounts outside IdM (`lv-breakglass` in Keycloak, `lvadmin` on desktops and servers, Guacamole's `locumadmin`, Keycloak's `kc-bootstrap`). Credentials sealed (age/SOPS), used only when the normal path fails, every use logged. See `docs/break-glass.md`.
- **Services:** applications authenticate as IdM system accounts (for example Keycloak's read-only LDAP bind), which can't log in interactively.
- **Transition:** the existing local `molszewski` accounts predate the directory. In Keycloak, a local `lv-breakglass` admin is created before federation; once the IdM `molszewski` signs in (TOTP enrolled again on the federated account), the local Keycloak `molszewski` is removed, because Keycloak won't import an LDAP user whose name matches a local user. Desktops get `lvadmin` in the bootc image (version-one item 1) and no personal local accounts; the current reference desktop keeps its local `molszewski` until it is rebuilt from that image, and only test users and `demo` are enrolled on it before then, so no account is migrated by hand. This supersedes the account-migration plan in Consequences.

## Update 2026-10-05: organizational login on the reference desktop

- The reference desktop is enrolled in IdM now, ahead of the bootc image, at the owner's request (changelog #36). The planned migration of the local `molszewski` (Consequences, and the accounts-and-naming update) was done by renaming it to `molszewski-legacy` and copying selected data into the IdM account's home; a generic local `lvadmin` is the desktop's break-glass.
- **Login path:** Keycloak (IdM password + TOTP) to Guacamole, then the desktop's GNOME login screen through GNOME Remote Desktop in system mode, where the user signs in with their IdM account and gets a session of their own. The lock screen, sudo and SSH authenticate against IdM through SSSD. Guacamole's RDP credentials only reach the login screen. The IdM password is entered twice; removing the second prompt needs smartcards or passkeys, not stored passwords.
- **Policy:** host group `locumview-desktops`; HBAC rule `locumview-desktop-login` (locumview-users, locumview-admins); sudo rule `locumview-admins-desktops`; IdM's `allow_all` disabled; default shell `/bin/bash`. Script: `hypervisor/idm01/desktop-policy.sh`.
- The bootc image (version-one item 1) carries the same: enrolment at provisioning, `lvadmin`, no personal local accounts, GRD system mode.

