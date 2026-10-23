# STIG scanner profile selection

Agent: Codex. Date: 2026-10-23. Branch: codex/stig-scan-profile, from main c9d506d.

## Built

scan-stig.sh adds --profile auto/image/reference and the two full tailoring IDs, preserving positional target
and output arguments. Auto detects /run/ostree-booted over read-only SSH. Invalid profiles stop before remote
operations; failed detection does not fall back. Selected ID and scanner exit saved in fetched evidence.
New scan-stig-remote.sh bundles the sudo sequence for owner review/run; private remote temp directory.
Failed-rule exit 2 and scanner errors propagate after fetching reports instead of being hidden. No remediation.

## Verified

Seven local tests mock transport and scanner commands. Both auto modes, overrides/full IDs, failed detection,
invalid input/path, quoted output directory, results retrieval and remote-helper exit handling pass.
Both Bash scripts pass syntax checks. Required all-files checks to be completed before signed commit.

## Open

Owner live scan with this wrapper is pending. Do not replace or relabel historical evidence; record actual
profile and compare rule sets. No desktop root command, scan, secrets operation or remediation run by agent.
Review/CI and signed merge follow the shared owner-terminal workflow. This hardening-path change may trigger
an image build after merge; image promotion remains a separate owner decision.
