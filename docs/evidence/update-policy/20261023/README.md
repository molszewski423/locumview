# Stage-only image update service: deployed-desktop test

Verified 2026-10-23 on a disposable desktop. Source commit:
`d2fd2aa70125152e5e32b01e6fafaab80adbed53`, signed merge of PR #7. Both candidates were built from this
commit in separate successful attempts of image workflow run 131. Their image manifests differ.

| Candidate | Immutable image digest | Role |
|---|---|---|
| T1 | `sha256:d2146e1200b13a7150484cba67b73d340bed1cc722088517907d9578a00d54b9` | Initially booted policy image |
| T2 | `sha256:2f4e9448d39e22fd7730cacfc8bbd3ee0dc7483af82e8be015c50019400dbe72` | Update staged by the service, then booted by planned restart |

## Build verification

For both immutable digests, the agent independently verified the image signature, SPDX SBOM attestation and
image-STIG-scan attestation using the committed `image/desktop/signing/cosign.pub`. The offline policy uses
`--insecure-ignore-tlog`; no transparency-log verification is claimed. Signature annotations identify the source
commit above and run 131; each verified SBOM subject identifies its corresponding manifest digest. All four
LocumView packages have version-release `0.1.0-1.20261023000253gitd2fd2aa701.el10`. Both signed scans report
361 pass, 26 fail, 14 error, 44 not applicable, 7 not checked, and no unexpected failures. The 40 fail/error
rules are declared runtime-only checks. Neither image was promoted to stable for this test.

## Effective service

On T1 and after booting T2, effective `ExecStart` is `/usr/bin/bootc upgrade`, with no `--apply` and no
`ExecStartPost`. The image-owned drop-in resets the inherited command. The vendor `/run/ostree-booted`
condition remains; the drop-in adds ordering after provisioning and its success-marker condition. Bootc is
1.16.4. The actual service was tested, not a direct substitute invocation of `bootc upgrade`.

## Observed transitions

| Point | Booted | Staged | Rollback | Boot identity | Update timer |
|---|---|---|---|---|---|
| Before service start | T1, testing | None | Installer | Baseline | Masked, inactive |
| After service start | T1, testing | T2, testing | Same installer | Unchanged | Masked, inactive |
| After owner-planned restart | T2, testing | None | T1, testing | New | Masked, inactive |

The owner ran a guarded script that checked the initial digests, absence of staging, effective command,
completed provisioning, inactive service and timer mask before starting `bootc-fetch-apply-updates.service`.
Agent read-only checks confirmed the boot ID and boot start time stayed unchanged after service execution.
The owner then supplied privileged `bootc status`: exact T2 staged, T1 still booted, installer rollback retained.

The first harness stopped before printing PASS because its post-checks included transient service state.
After a completed one-shot unit is unloaded, a later query can load a fresh unit with default condition state;
`ConditionResult` was observed as `no` with no condition timestamp or execution metadata. It is not durable
proof of whether the earlier invocation ran. That assertion was removed from the local harness. The staged
deployment transition, unchanged boot identity and explicit owner output establish the relevant behavior.

The owner ran a second guarded script that verified T1 booted, exact T2 staged and timer still masked before
requesting a reboot. After reconnection, the owner verification script printed PASS: exact T2 booted from
testing, T1 as rollback, no staged deployment, new boot ID, timer masked/inactive and zero failed units.
Independent read-only checks confirmed the new boot identity, effective command, mask and absence of failures.

## Scope and remaining operations

The service successfully stages a newer signed image without requesting a reboot; an operator-planned restart
activates that exact image. A future unexpected reboot would also activate an already staged deployment under
this bootc behavior. Automatic timer expiry and deliberate failure of the provisioning condition were not
separately exercised: the timer was held masked for the controlled test. No live-demo change or fleet unmask
occurred. This is not a full deployed-desktop STIG rescan of these candidates, nor byte reproducibility proof.
Disposable-desktop destruction and production rollout require separate owner review and approval.
