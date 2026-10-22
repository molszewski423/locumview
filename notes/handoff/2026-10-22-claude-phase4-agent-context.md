# Handoff: Phase 4 start, Epic watch item, shared agent context

Agent: Claude Code. Date: 2026-10-22. Changelog #62 and #63.

## Done

- Image promotion pipeline: per-image STIG scan and its attestation, `:testing`, the promote workflow, desktops on
  `:stable` (b807f0c).
- LocumView RPMs: spec, build, sign, publish, CI workflow, repository file (580910c to d34d364). First packages in
  the registry.
- ADR 0017 "Future considerations" (Epic Connectors) and the Phase 9 watch lines (branch `claude/epic-connectors-watch`,
  here and in the website).
- AGENTS.md in every repository (branch `claude/agents-md` in each), the global AGENTS.md and Codex setup notes
  (branch `claude/agent-context` in the memory repository).

## Verified, and how

- Image scan: 361 pass, none unexpected, on the 2026-10-21 image; the 0777 fault reproduced on ext4 and the fix
  passes there.
- Registry tag copy: a throwaway tag pointed at a digest byte for byte, then deleted.
- RPMs: byte comparison against the image (75 files), install refused without the key, `rpm -V` clean, install
  from the registry with both signature checks.
- RPM CI: run on db0bb43 built, signed and published.

## Open

- Owner merges the `claude/*` branches (locumview: `image-scan-output-dir`, `epic-connectors-watch`, `agents-md`,
  `changelog-62-63`; website: `epic-connectors-watch`, `agents-md`; memory repository: `agent-context`, `agents-md`;
  every other repository: `agents-md`).
- After the scan fix is merged: rebuild the image, promote it, switch the live demo desktop to `:stable`, delete the
  stale `:latest` tag.
- After the memory repository merge: link the global AGENTS.md into each tool's global location on both machines.
- The image installing the RPMs (prepared and rehearsed, not committed; to go on `claude/rpm-image-install`).
- A Red Hat registration named `localhost.localdomain` that checks in daily: identify it.

## Next step

Rebuild the image once `claude/image-scan-output-dir` is merged.
