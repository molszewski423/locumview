# ADR 0003: Secrets with SOPS and age

Status: Accepted
Date: 2026-10-02

## Context

Phase 0 requires that nothing sensitive is ever stored in plain text. Phase 2 introduces the first real secrets: database passwords for Guacamole and Keycloak, Keycloak's admin bootstrap credentials, and the OIDC client secret shared between Keycloak and Guacamole. They must be committed in a form that a reviewer can rebuild from, without being readable in the repo. The pre-commit hooks (detect-secrets, gitleaks) block plain-text secrets at commit time.

## Decision

Encrypt Kubernetes Secret manifests in the repo with **SOPS** using **age** keys. Only the `data`/`stringData` values are encrypted (`encrypted_regex: ^(data|stringData)$`), so a reviewer can still read the rest of each manifest. `.sops.yaml` at the repo root lists the age recipients. Private keys are never committed: each operator keeps theirs at `~/.config/sops/age/keys.txt` (mode 600), with an offline backup. Secrets are decrypted only when applied (`sops -d file | kubectl apply -f -`), and later by a GitOps controller holding its own age key.

Ansible Vault stays the plan for Phase 3's Ansible-only secrets (host and guest configuration), where it is the native tool.

## Alternatives considered

- **Ansible Vault for everything.** Encrypts whole files, so the encrypted manifests can't be reviewed, and it fits Kubernetes workflows poorly.
- **Sealed Secrets.** Encrypts against a key held inside the cluster, so the secrets can't be decrypted and re-applied to a rebuilt cluster without exporting that key. That cuts against "rebuild from the repo."
- **External Secrets with Vault/OpenBao or a cloud KMS.** The right answer at enterprise scale, and a documented upgrade path. Too much infrastructure for version one.
- **PGP keys with SOPS.** Works, but age is simpler, and SOPS now recommends it.

## Consequences

- Losing every age private key means losing the secrets. The keys need an offline backup, and rotation means re-encrypting with `sops updatekeys`.
- Adding an operator or a CI or GitOps decryptor means adding its age public key to `.sops.yaml` and running `sops updatekeys`.
- Plain-text secrets must never touch disk inside the repo. Generated values are piped straight into `sops --encrypt`.
