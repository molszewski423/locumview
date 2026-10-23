# Background update policy

Agent: Codex. Date: 2026-10-22. Branch: codex/staged-image-updates, from main db544ca.

## Prepared

Follow-up explicitly named in the release-integrity report: background updates stage for a planned reboot.
The new image drop-in resets the inherited bootc upgrade --apply command to bootc upgrade, waits for
locumview-provision.service, and requires /var/lib/locumview/provisioned. It retains the vendor timer schedule
and the vendor /run/ostree-booted condition. Existing /etc timer masks are never unmasked by the image.
Provisioning comment, image README, changelog #68 and roadmap updated. Source only; no desktop mutations.

## Checked

Read-only desktop inspection: vendor service ExecStart=/usr/bin/bootc upgrade --apply --quiet, bootc 1.16.4.
Help confirms upgrade stages for next reboot and --apply requests a reboot. Upstream documentation agrees:
https://bootc.dev/bootc/man/bootc-upgrade.8.html. Offline systemd-analyze verify accepted the actual new drop-in
with a fixture of the inspected vendor unit and minimal targets. No claim of runtime behavior from this check.

## Open

Required pre-commit checks and signed commit, then push review branch under standing authorization.
New image build and disposable-desktop acceptance: inspect effective unit, stage a newer signed candidate via
the service without changing boot ID/booted digest, planned reboot, confirm exact staged digest and rollback.
No-update invocations do not establish successful staging. Runtime checks and every root operation are owner
runs. Timer unmasking, image promotion and live-demo changes need separate approval; existing containment stays.
An unexpected reboot still activates an already staged update. Download-only mode is intentionally not used.

## Next

Finish checks and present source changes. Status remains In progress until built and exercised on a desktop.
RPM source coverage includes these image files, so merging also triggers a new pinned RPM publication; let it
finish before retrying an image build that finds the required version unavailable.
