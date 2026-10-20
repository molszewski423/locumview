# ADR 0014: GNOME as the desktop, delivered through GNOME Remote Desktop

Status: Accepted (recorded 2026-10-20; the decision dates from the reference desktop, changelog #1 to #14)
Date: 2026-10-20

## Context

LocumView delivers a full Linux desktop to clinicians and analysts through a browser. The desktop environment decides what Red Hat supports, which hardening baseline applies, how the session is reached remotely, and how familiar the desktop feels to staff coming from Windows or macOS. The choice was made on the hand-built reference desktop and carried into the bootc image (ADR 0007) without an ADR; this records it.

## Decision

GNOME, the desktop RHEL 10 ships and supports, running on Wayland, with remote access through **GNOME Remote Desktop** over RDP:

- **Supported on RHEL.** RHEL 10's Workstation environment is GNOME; it is the only desktop covered by the subscription and the 10-year lifecycle (ADR 0001).
- **Hardening baseline.** The DISA STIG with GUI profile for RHEL 10 is written for GNOME: screen lock, banners, removable media, automount and session settings are dconf rules OpenSCAP checks (changelog #47).
- **Native remote display.** GNOME Remote Desktop is RHEL's supported RDP server for Wayland sessions: a headless, always-on session per user (user mode, port 3390) and the GDM login screen for administrators (system mode, 3389). It needs no X11 and no third-party server (changelog #14, #19).
- **Familiar layouts, set centrally.** Supported extensions (dash-to-dock, dash-to-panel) give the organization a Windows-style, Mac-style or standard GNOME layout, locked in dconf so it is the same for everyone (changelog #25).

## Alternatives considered

- **KDE Plasma.** Polished and Windows-like out of the box, but not shipped or supported in RHEL 10 (EPEL or Fedora only) and not covered by the STIG profile.
- **Xfce or MATE with xrdp.** Lighter, and xrdp is a mature RDP server, but both are EPEL only, depend on X11 (RHEL 10 ships no X11 server, only Xwayland), and fall outside the STIG profile and Red Hat support (also ADR 0012 on xrdp).
- **A kiosk session (a single browser or app).** Enough for EHR-in-a-browser alone, but the workspace is meant to carry office, data and AI tools side by side.

## Consequences

- RDP sign-in to GNOME Remote Desktop uses NTLM, which rules out FIPS mode on the desktop for now (ADR 0012).
- GNOME Remote Desktop serves one graphical session per user; denser desktops (several users per VM) are an ADR 0010 question.
- GNOME's per-release changes (extensions, settings) are absorbed in the image build, where they are tested before any desktop gets them.
- Distribution ports (SUSE, Debian) keep GNOME, so the layouts, dconf policy and remote display stay the same across them.
