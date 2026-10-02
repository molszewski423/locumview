# ADR 0005: Keycloak as the single identity provider

Status: Accepted
Date: 2026-10-02

## Context

LocumView needs organizational logins with MFA in front of the desktops (Guacamole), and later for Nextcloud and the desktops themselves. Regulated customers expect one place to provision and deprovision accounts, enforce MFA, apply lockout and password policy, and audit logins. Mike also wants a demo guest login without MFA for showing the project (worklog 2026-10-02 12:40).

## Decision

Run **Keycloak** (26.8.0, upstream image pinned by digest) on k3s in the `locumview` namespace, with its own PostgreSQL. One realm, `locumview`, holds organizational accounts and groups. Every application is an OIDC client of that realm: Guacamole now, Nextcloud next, and desktop login (SSSD/IdM or GDM OIDC) later. Nextcloud is not a user directory.

Realm policy is set by a script in the repo (`k8s/locumview/keycloak/configure-realm.sh`), not by clicking in the console:
- **MFA for everyone.** A custom browser flow requires TOTP unless the user holds the realm role `mfa-exempt`. That role is granted only through the `locumview-demo` group.
- Brute-force protection; minimum password length 14, not the username, no reuse of the last 5; login and admin events stored for 90 days.
- Groups `locumview-admins`, `locumview-users` and `locumview-demo` reach Guacamole as a `groups` claim and map to Guacamole user groups that hold the permissions.

## Alternatives considered

- **Nextcloud as the directory** (its OIDC provider app): weaker MFA policy, audit and federation; unusual in regulated settings.
- **Red Hat IdM (FreeIPA)**: the right answer for Linux host identity (SSSD, sudo rules, Kerberos), and likely added later *behind* Keycloak as a user federation source. It isn't a web SSO and MFA front door by itself.
- **Authentik / Zitadel / Authelia**: capable, but Keycloak is the upstream of Red Hat build of Keycloak (the target employer's supported product) and the most common choice in regulated enterprises.
- **Guacamole's built-in TOTP extension**: MFA for Guacamole only, not for Nextcloud or later apps.

## Consequences

- **Guacamole 1.6.0's OpenID extension supports only the implicit flow** (`response_type=id_token`; it has no token-endpoint or client-secret settings). OAuth 2.1 discourages the implicit flow. Mitigations: the Guacamole client is public with only the implicit flow enabled, exact redirect URIs, an ID token with a nonce and no access token, and a short token validity. The upgrade path is an authorization-code-with-PKCE proxy (e.g. oauth2-proxy) feeding Guacamole's header authentication, or a later Guacamole release with code flow.
- The `mfa-exempt` role is a deliberate, auditable hole. It's granted only via the `locumview-demo` group, whose single desktop is isolated and holds no real data, and the account can be disabled between demos.
- Guacamole keeps its local `locumadmin` as break-glass. Once published to the internet, local login must be unreachable from outside (tunnel/route restriction) or removed.
- Hostnames: during LAN-only testing Keycloak's issuer is `http://127.0.0.1:8081` (operator port-forward). It changes to `https://login.locumview.com` with the Cloudflare Tunnel (ADR 0004), which means updating `KC_HOSTNAME` and Guacamole's endpoints and redirect URI together.
- Phase 3 can move realm configuration to Terraform's Keycloak provider. The script is the interim source of truth, and a realm export is kept as evidence.
