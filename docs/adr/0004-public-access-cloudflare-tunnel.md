# ADR 0004: Public access through a Cloudflare Tunnel

Status: Accepted
Date: 2026-10-02

## Context

LocumView must be reachable from the internet at Mike's domain, locumview.com (DNS on Cloudflare), without exposing desktops or RDP, and without inbound ports on the home router. The apex `locumview.com` is reserved for the marketing site (built separately, hosted on Vercel). The VDI needs a user-facing entry point and an identity-provider hostname.

## Decision

- **Hostname:** one, `login.locumview.com`, split by path: `/realms/locumview/*` and `/resources/*` → Keycloak (sign-in, MFA; also the issuer for Nextcloud and other apps later); everything else → Guacamole (the desktop portal). The two apps share no paths. One origin means one address for users and no cross-site cookie issues. The apex stays with the marketing site. (First planned as `desktop.` + `login.`; changed at Mike's request before any route was published.)
- **Transport:** a dedicated, remotely managed Cloudflare Tunnel named `locumview` (separate from the RingCatch tunnel, so the projects are isolated), with its connector `cloudflared` running as a Deployment in the `locumview` namespace. Outbound-only: cloudflared dials Cloudflare's edge; nothing listens on the router. TLS terminates at Cloudflare's edge; edge-to-connector traffic is inside the tunnel; connector-to-service traffic is cluster-internal HTTP, confined by NetworkPolicies.
- **Exposure rules:** only `login.locumview.com` is routed. Keycloak receives only the `locumview` realm and its static resources; the master realm, the admin console (`/admin`, `/realms/master`) and health/metrics never reach Keycloak from the internet (those paths go to Guacamole, which doesn't serve them); administration uses the operator port-forward (`KC_HOSTNAME_ADMIN`). Guacamole sends users straight to SSO (`EXTENSION_PRIORITY=openid, ...`), and its local break-glass account is disabled by default (enabling it is a documented, audited cluster-admin action).
- **Audit:** Guacamole trusts `X-Forwarded-For` only from in-cluster proxies (Tomcat RemoteIpValve), so its logs show the real client IP. Keycloak uses `KC_PROXY_HEADERS=xforwarded`.
- Nothing is routed until Guacamole is behind Keycloak with MFA enforced (done, #18).

## Alternatives considered

- **Port forwarding on the router + Traefik + Let's Encrypt:** exposes the home IP and an inbound port, and depends on the ISP router. Rejected.
- **Tailscale Funnel:** simple, but tied to tailnet hostnames; custom domains and fine-grained path rules are limited. Tailscale stays for admin access.
- **Cloudflare Access in front of everything:** a second IdP layer that duplicates Keycloak MFA for users. It may be added later for the admin paths or as a device-posture gate.
- **A VPS reverse proxy (WireGuard back home):** more infrastructure to run and patch for no gain at this scale.

## Consequences

- Cloudflare sees TLS-terminated traffic (it's a man-in-the-middle by design). Acceptable for the homelab and the demo; a regulated production deployment would use its own edge (or Cloudflare with a BAA where applicable) and document it.
- The tunnel token is a credential (anyone holding it can run the connector). It lives only in SOPS (`k8s/locumview/secrets/cloudflared.sops.yaml`); rotate it in the dashboard if it's exposed.
- Routes for a remotely managed tunnel live in Cloudflare, not in the repo. The intended route table is recorded in the worklog, and a later step can manage it through the Cloudflare API from code.
