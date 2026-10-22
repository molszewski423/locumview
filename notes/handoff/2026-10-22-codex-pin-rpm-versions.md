# RPM version pinning

Agent: Codex. Date: 2026-10-22. Branch: codex/pin-rpm-versions, based on main 1fc85da.

## Built locally

Shared Git-based RPM version resolver and checked input list. RPM workflow builds the selected source;
image workflow passes its exact version-release into the Containerfile. All four packages are pinned and
checked after installation. Missing publication fails with an actionable error, without selecting newer RPMs.
Full history is required. The resolver uses first-parent history so a merge selects the combined input tree.
Builder pin, spec and archive are all read from that source. See changelog #67 and packaging/rpm/README.md.

## Verified

Nine local tests exercise real Git histories and execute the image install step with mocked host/package
commands, including unavailable publication and exact version requests. Workflow YAML parsing and Bash syntax
checks passed for sixteen run steps; build-rpms.sh passes Bash syntax checks. Full pre-commit result will be
recorded in the session handoff. No credentials, decryption, RPM publication, image build or desktop change.

## Open

Review and required checks, signed commit, owner approval before pushing to Gitea. After owner merge, let RPM
publication complete before retrying an image that starts too early. Both workflows must select the same source
and EVR. Verify two image builds of the same commit through their signed SBOMs: all four LocumView NEVRAs must
match the resolver. Stable is unchanged unless a later promotion is separately authorized.

## Next

Complete local checks and present the concrete diff. Keep the prior release evidence, latest rollback tag,
and any untracked operator files intact. Python 3.15 on operator-laptop still breaks ansible-lint; MikePC's
all-files checks worked for the prior merge, whose identical tree was signed on operator-laptop.
