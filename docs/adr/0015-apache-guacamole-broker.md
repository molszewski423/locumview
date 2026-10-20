# ADR 0015: Apache Guacamole as the browser access broker

Status: Accepted (recorded 2026-10-20; the decision dates from Phase 2, changelog #17 to #21)
Date: 2026-10-20

## Context

Version one requires that the desktop is reached in a browser through SSO with enforced MFA, with no RDP exposed (ROADMAP item 2). ADR 0002 decided where the access layer runs (k3s); it did not record why Guacamole is the broker. This records it.

## Decision

**Apache Guacamole** (the web application) with **guacd** (the protocol proxy), on k3s:

- **Clientless.** HTML5 in any modern browser: nothing to install on clinical endpoints or thin clients.
- **Speaks RDP to the existing desktops.** guacd's FreeRDP connects to GNOME Remote Desktop (ADR 0014), including its two server redirections (changelog #14, #17), so the desktop needs no extra agent and RDP stays on the private network, reachable only from the cluster nodes (changelog #19).
- **Identity through Keycloak.** The OpenID Connect extension makes Keycloak the only identity provider and the only MFA authority (ADR 0005); Guacamole's own logins are for break-glass only.
- **Audit and data controls.** Connection history (who, which desktop, when, from where) in its database, session recording available, and per-connection controls such as blocking copy-out from the desktop (changelog #26).
- **Apache License 2.0**, an Apache Software Foundation project, self-hosted, and connections can be managed as data (SQL), which the OpenTofu module uses (ADR 0013).

## Alternatives considered

- **Kasm Workspaces.** Streams containerized or VM desktops with its own protocol; the community edition is limited and the full product is commercial. It replaces the remote display stack rather than fronting GNOME Remote Desktop.
- **Teleport.** Strong identity-aware access, but its desktop access targets Windows RDP; Linux desktops are out of scope.
- **noVNC or a plain RDP web client.** A viewer, not a broker: no SSO, no connection management, no audit trail.
- **Citrix, Omnissa Horizon.** The incumbents LocumView is meant to offer an open alternative to (the build log's Horizon mapping); proprietary and licensed per seat.

## Consequences

- Guacamole sends the remote display to the browser as images over a WebSocket: more bandwidth and some latency compared with a native RDP client, acceptable for clinical and office work, not for video-heavy or GPU work.
- Device redirection is limited (file transfer and audio, no general USB), which fits the data-protection posture but rules out some peripherals; Windows-first peripherals are already outside scope (build log, honest scope).
- The extensions are pinned and upgraded with Guacamole itself; the OIDC extension is part of the identity path and is tested on every upgrade.
