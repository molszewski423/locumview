# Phase 4 closeout and live-scan evidence

Agent: Codex. Date: 2026-10-24. Branch: codex/phase4-closeout, from main e7079eb.

## Prepared

Recorded owner live scan and independently parsed ARF: image profile, 405 pass / 0 fail, scanner/wrapper exit
0. Summary includes versions, recorded scan timestamps and raw-artifact hashes, with no private host facts.
Raw HTML/ARF remain private and were not copied into the repository. Scanner source e7079eb; target image
digest was not freshly read during the scan, so no new digest-bound desktop attestation is claimed.

PLAN/ROADMAP close the verified core release milestone with explicit Planned packaging/maintenance follow-ups:
COPR, optional mock integration, Fedora/EPEL dependency packaging when needed, SBOM resource optimization,
cosign flag maintenance. Current implementation uses a pinned rpmbuild container and Gitea. Owner review of
this branch records that scope decision. Production rollout remains separate; no promotion or timer unmask.

## Verified

Gitea API: main checks 137 and image 138 succeeded at e7079eb. API authentication used Git's own credential
store in memory; no credential printed, persisted or decrypted. Latest website preview runs 130/131 failed.
Found generator-incompatible status formatting in roadmap housekeeping and stage-only row; corrected both.
The actual website generator, supplied the local roadmap in memory and writing only to a temporary output,
accepts the proposed document and its privacy checks. Remote preview verification after merge remains open.

## Next

Required checks and signed commit, review branch push, HTTPS PR link. Owner creates PR ("pulled"), performs
separate-worktree signed merge/checks, then main push after output review. Verify main CI and website preview.
No need to provision another desktop or promote an image for this documentation closeout. Phase 9 lite starts
with the OpenEMR microbiology/FHIR feasibility spike, before UI work. Remaining scope limits are in #70.
