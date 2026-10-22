# Release closeout verification

Agent: Codex. Date: 2026-10-22. Branch: codex/release-closeout.

## Done

Continued Claude's interrupted verification after the owner's demo switch and test destruction.
Updated changelog #66 on top of claude/changelog-66-promotions, preserving its evidence and roadmap changes.
No deployment, promotion, deletion, secret decryption or OpenTofu run performed by Codex.

## Verified

- Demo: zero failed units; update timer masked/inactive; update service inactive; four image B RPMs installed.
  Owner and guest GNOME remote-desktop processes belong to their headless service cgroups. Both ports are
  reachable from guacd. Deployment origin files include stable and latest, consistent with the owner's switch
  and Claude's post-reboot observation. Privileged bootc status was not available to Codex.
- Test destruction: owner output and saved log show exactly ten resources destroyed, no changes or additions.
  No test libvirt domain or volumes, no resolving host address, no Guacamole connection. Operator configuration
  equals main. Apply log records Red Hat registration removal and IdM host resource destruction; independent
  credentialed queries were not performed.

## Open

- Owner supplied fresh privileged bootc status: B booted from stable, nothing staged, rollback latest at
  sha256:137e69fa630505997e3e3b911c5151f9cc4334c5f788e2bc725fd42668b08edc. This gate is Done.
- Owner decision on local encrypted test-secret and saved-plan cleanup. Files remain; never delete silently.
- Fresh browser sign-in not tested. Fleet rollback test intentionally skipped by owner, not verified.
- Review and signed merge of the combined #66 branch. Prior Claude-specific one-time merge authorizations
  are not assumed to authorize new Codex pushes, merges, mirror sync or branch deletion.
- Production website deploy still needs its own owner go. Keep latest while rollback references it.

## Next

Complete required checks, sign the evidence update, and present the combined diff for merge approval.
RPM version pinning and the scan profile argument remain Planned.
