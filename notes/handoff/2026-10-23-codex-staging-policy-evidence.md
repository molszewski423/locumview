# Stage-only update service evidence

Agent: Codex. Date: 2026-10-23. Branch: codex/staging-policy-evidence, based on main d2fd2aa.

## Done

Runtime test on disposable desktop: actual update service stages a verified signed newer candidate without
changing boot ID, booted digest or rollback. Planned reboot activates exact staged candidate with original
policy image as rollback. Nothing staged afterward, no failed units, timer remains masked and inactive.
Owner supplied guarded-script results and privileged status; agent checked boot identity and health read-only.
Both candidate signatures, SPDX SBOMs and image scans verified independently against committed public key.
Evidence and limits: docs/evidence/update-policy/20261023/README.md. Roadmap and changelog #68 updated.

## Findings

Saved-plan apply requires the same testing override as plan. First attempt stopped at validation without
creating VM; owner retry succeeded. One-shot unit condition state is not durable after systemd unloads it;
local harness removed its ConditionResult assertion. Explicit deployment transitions establish staging proof.
Initial policy-image boot happened before the controlled test; cause was not independently attributed.

## Open

Required checks, signed commit and review/merge. Test desktop still exists and must not be deleted without
owner-approved reviewed destroy plan. Production rollout, any unmask and promotion remain separate decisions.
Timer expiry and deliberately failing provisioning condition were not independently exercised. No full
deployed-desktop STIG rescan for these candidates. Existing live demo and stable release unchanged by test.

## Next

Complete evidence review, then prepare an owner-run saved destroy plan restricted to the test desktop and
review it before applying. Preserve operator files and latest rollback tag. Private memory handoff has host
access details, exact boot IDs and owner-run script locations.
