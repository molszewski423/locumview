# ADR 0012: No FIPS mode on the desktop while GNOME Remote Desktop needs NTLM

Status: Accepted
Date: 2026-10-19

## Context

The DISA STIG for RHEL 10 requires FIPS mode (`sysctl_crypto_fips_enabled`, CAT I). On the hand-built reference desktop it was deferred to the bootc image, because RHEL 10 can enable FIPS mode only at installation or boot (changelog #47). The first bootc image (changelog #51) turned it on: `fips=1`, the FIPS crypto policy, and the four SSH rules that depend on it.

Booted on libvirt (changelog #52), the image ran in FIPS mode as intended, and RDP sign-in to GNOME Remote Desktop failed. FreeRDP 3 against the image, `/sec:nla +auth-only`, with valid credentials:

```
gnome-remote-desktop-daemon: [com.winpr.crypto.hash] winpr_Digest_Init_Internal: Failed to initialize digest md4
gnome-remote-desktop-daemon: [com.winpr.sspi.NTLM] ntlm_fetch_ntlm_v2_hash: Error: Could not find user in SAM database
gnome-remote-desktop-daemon: [com.freerdp.core.auth] credssp_auth_authenticate: AcceptSecurityContext failed with SEC_E_NO_CREDENTIALS
```

and with `/sec:tls`: `server supports only NLA Security`. GNOME Remote Desktop 49 accepts only NLA (CredSSP), its NLA authenticates only with NTLM against its own credential store, and NTLM is built on MD4, which FIPS mode disables. Guacamole's guacd (FreeRDP 2.11) is on the client side of the same exchange. There is no configuration that keeps both.

The same test showed a second FIPS effect: the SSH server accepts only ECDSA keys (`PubkeyAcceptedAlgorithms` lists ecdsa-sha2-nistp256/384/521), so the Ed25519 administrator keys used everywhere in this project, including the ones stored in IdM, would not work.

## Decision

The desktop image does not enable FIPS mode. `sysctl_crypto_fips_enabled`, `configure_crypto_policy` (crypto policy DEFAULT) and the four FIPS SSH cipher and MAC rules stay documented exceptions in the image profile, as on the hand-built desktop. Every other STIG setting applies, including the separate file systems.

FIPS mode is revisited when LocumView targets a sector that requires FIPS 140 validated cryptography in FIPS mode (federal and defense health systems, FedRAMP, some state agencies), or earlier if one of these changes:

- GNOME Remote Desktop gains an RDP sign-in that does not use NTLM (for example Kerberos through CredSSP), or a supported way to accept TLS without NLA.
- Guacamole supports a remote display protocol whose authentication is FIPS-compatible and that RHEL supports on the desktop side.

## Why this is acceptable for the current target

HIPAA does not require FIPS mode. The Security Rule requires appropriate encryption; FIPS mode on the desktop comes from the DISA STIG, a Department of Defense baseline. Without FIPS mode:

- Every network hop is still encrypted with TLS 1.2 or 1.3 (or WireGuard between cluster nodes, LDAPS to IdM), and the DEFAULT crypto policy still excludes weak protocols and ciphers.
- The NTLM exchange runs inside the TLS connection between guacd and the desktop, and checks a random per-desktop RDP credential that no person types. People authenticate at Keycloak, with MFA.
- Disk encryption (LUKS, AES-XTS), planned at provisioning, works the same with or without FIPS mode.

## Alternatives considered

- **Re-enable MD4 for the GNOME Remote Desktop process only.** Rejected: it uses a non-approved algorithm for authentication on a system that claims FIPS mode, which is the thing a FIPS assessment checks.
- **xrdp instead of GNOME Remote Desktop.** Not in RHEL's supported repositories (EPEL only), and it changes the session model the access layer is built on.
- **VNC.** VNC authentication is not FIPS-compatible either, and Guacamole's RDP path is what the access layer is built and tested on.

## Consequences

- The DISA STIG report for the image shows these six rules as exceptions, with this ADR as the reason. A buyer who requires FIPS mode is told so, not surprised later.
- When FIPS mode comes back, administrator SSH keys must be ECDSA (or RSA) rather than Ed25519, including the keys stored in IdM.
- The HIPAA mapping states that transmission security relies on strong TLS and WireGuard, not on FIPS mode.
