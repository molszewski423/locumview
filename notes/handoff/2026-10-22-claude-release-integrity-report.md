# Handoff: release integrity report (Milestone 1, read-only)

Agent: Claude Code. Date: 2026-10-22. Branch: `claude/release-integrity-report`. No changelog entry: nothing in the
platform was changed.

## Done

- Read-only investigation of the pending branches, CI, registry tags and signatures, `:latest` and `:stable`
  references, lv-demo01's state and the rollback paths. Report: `notes/release-integrity-report.md`.

## Verified, and how

- Branches: five, each one signed commit on d34d364; they merge cleanly in sequence (`git merge-tree`); checks
  passed on every head.
- CI: `image.yml` pushes `:<commit>` and `:testing` only; nothing pushes `:latest`; `promote.yml` never ran; the last
  seven image builds failed (Red Hat SSO outage, then the scan gate's 0777 directory).
- Registry: `:latest` = `137e69fa…` (signature and SBOM valid, no scan attestation); `:testing` and `:stable` absent;
  the unsigned test image fails every check.
- References: no `:latest` left on main; the site values follow `:stable` (key `update_image`, checked by count).
- Image: the update unit is `bootc-fetch-apply-updates.timer`, vendor-enabled under `/usr`
  (so it needs `systemctl mask`)
- Provisioning: `claude/rpm-image-install` changes nothing provisioning executes (no ISO rebuild).

## Open

- Owner runs P1 and P2 (lv-demo01 `bootc status`, update timer) to refresh findings 5.2 and 5.4.
- Decided by the owner and written into the sequence: tests on a disposable test desktop following `:stable`, lv-demo01
  switched last (Q1); the update timer masked on lv-demo01 before any promotion and on the test desktop (Q2); the
  full deployed-desktop STIG scan on the test desktop (Q5). Still open: Q3 (no new desktops before the first
  promotion). After this milestone: the image-level update policy and RPM NVRs pinned to the build commit.
- Revised with the owner: B is re-promoted after the fleet rollback test so lv-demo01 lands on B (step 13, checked in
  step 15); the agent never decrypts a desktop credential, so desktop root steps and OpenTofu runs are owner runs
  (P0 to P11), and the agent checks read-only through the owner's IdM account without sudo.
- Step 12 (fleet rollback) is to be observed, not assumed (finding 6.4 stays ASSUMPTION until then). If `bootc upgrade`
  does not follow `:stable` back to the older digest, record that as a finding, and use
  `sudo bootc switch --enforce-container-sigpolicy <registry>/mike/locumview-desktop@<older digest>` as the fleet
  rollback fallback (then switch back to `:stable` once it points at a good digest again).
- The 2026-10-22 handoff note `2026-10-22-claude-phase4-agent-context.md` is on `claude/changelog-62-63`, not on main.

## Next step

Owner runs P0 (mask the update timer on lv-demo01), then step 1: merge `claude/image-scan-output-dir`.
