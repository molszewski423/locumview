# LocumView: agent instructions

Read the global agent instructions first: `~/.claude/CLAUDE.md` (Claude Code) or `~/.codex/AGENTS.md` (Codex),
both linked to `context/global/AGENTS.md` in the private claude-memory repo. They cover conventions, approvals and
the session protocol (branches `<agent>/<topic>`, signed commits with an `Agent:` trailer, handoff notes). This file
adds what is specific to this repository; where it is stricter, it wins.

## What this is

LocumView, an open-source VDI platform on RHEL 10: a hardened GNOME desktop built as a bootc image, delivered in the
browser through Guacamole and Keycloak, with infrastructure in OpenTofu and the access layer on k3s. Start with
`README.md`, `ROADMAP.md` (the status of record), `docs/PLAN.md` and `docs/adr/`.

## Rules for this repository

- **Public.** Gitea mirrors this repo to GitHub and GitLab: everything pushed is published. Role names only
  (node1, node2, suse-laptop, operator-laptop); no real IPs, hostnames beyond those already public, or credential
  locations. Site values live in the git-ignored `site.env` files and `terraform/node1/site.auto.tfvars`.
- **Status** comes from `ROADMAP.md`. Use Done, Built, In progress, Planned, and never "compliant".
- **Changelog:** every change of substance gets an entry in `notes/phase1-changelog.md` (numbered, with what was
  done, what was found, and how it was verified). It is also this project's handoff record.
- **Secrets:** SOPS + age only (`.sops.yaml`; ADR 0003). The pre-commit hooks check that SOPS files are encrypted
  and scan for secrets; never bypass them with `--no-verify`.
- **Images and packages:** desktops follow `:stable`, which only `.gitea/workflows/promote.yml` moves. RPMs are
  built, signed and published by `.gitea/workflows/rpms.yml` (`packaging/rpm/README.md`).
- **Infrastructure:** OpenTofu runs from operator-laptop (`terraform/node1`, `./tofu.sh`); run long applies so a dropped
  session or sleep cannot interrupt them (changelog #61).
- **Website copy** lives in the separate locumview-website repo; production deploys only on the owner's go.

## Checks

```fish
pre-commit run --all-files
```
