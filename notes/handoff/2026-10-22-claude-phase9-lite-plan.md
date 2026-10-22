# Handoff: Phase 9 lite and Clinical Review Workspace plan (planning only)

Agent: Claude Code. Date: 2026-10-22. Branch: `claude/phase9-lite-plan`. Changelog #65.

## Done

- ADR 0017 dated update (scenario library, the spike, frozen evaluation build as exit criterion).
- ADR 0018, Clinical Review Workspace (new).
- `docs/plans/phase9-lite-and-review-workspace.md`, `docs/policy/synthetic-data-and-independence.md`.
- ROADMAP.md sequencing and three Clinical AI rows; docs/PLAN.md reconciled (scenario library in Phase 9 lite, Review
  Workspace after Phase 8 lite as the first slice of the full Phase 9); legal questions 5 and 6; changelog #65.

## Verified, and how

- Preconditions: `claude/epic-connectors-watch` (c9c5350) and `claude/changelog-62-63` (0c55a6b) merged before
  branching from main at aca7d81.
- OpenEMR capabilities: read from OpenEMR's FHIR and API documentation on its main branch, 2026-10-22; not tested
  against a running OpenEMR (that is M1).
- node1 memory: read-only `virsh dominfo`, qemu RSS, `/proc/meminfo`, KSM counters, kubelet reservations and
  `kubectl describe node`, 2026-10-22.
- `pre-commit run --all-files` passed.

## Open

- Owner: decides node1's `system-reserved` correction after the reference desktop retires (owner run).
- Owner decisions listed in the plan, section 9.
- Nothing in the website was changed; the disclosure text and privacy changes are drafts in the plan.

## Next step

After Phase 4: milestone M1, the OpenEMR microbiology spike.
