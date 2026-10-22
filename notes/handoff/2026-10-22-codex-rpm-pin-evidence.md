# RPM pinning CI evidence

Agent: Codex. Date: 2026-10-22. Branch: codex/rpm-pin-evidence, based on main 5f07e84.

## Done

Independently verified both successful build attempts of image workflow run 125 at immutable digests.
Both signatures bind commit 5f07e84589f167cd51c333d7cf1170d8675eb00a. Both signed SPDX SBOM subjects match
their image digests and contain exactly the four expected LocumView versions. Both signed scan predicates
pass with 361 rules passed and nothing unexpected. Evidence: docs/evidence/rpm-pinning/20261022/README.md.
Updated roadmap and changelog #67 to reflect the verified acceptance check.

## Scope and open work

No promotion or desktop change. Image manifests differ; byte reproducibility is not established.
No full deployed-desktop scan for these images. SBOM generation takes about eleven minutes on the current
runner with active swap; optimization is a separate task. No runner configuration changed.
Complete required checks and signed commit, push review branch under standing authorization, owner reviews
and merges. Private cross-repository session handoff contains operational context.
