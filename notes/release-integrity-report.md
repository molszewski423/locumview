# Release integrity report (Milestone 1, Phase 4)

Read-only investigation, 2026-10-22, by Claude Code. Nothing was merged, built, promoted, tagged, switched or
rebooted. Role names: node1 (hypervisor and k3s node), node2 (k3s control plane and CI runner host), idm01;
`<registry>` is the Gitea container registry; `<lv-demo01-address>` is the live demo desktop's address.

Labels: **VERIFIED** (seen today, evidence given), **VERIFIED 2026-10-21** (observed in the previous session, not
re-checked today; see the pending owner runs), **ASSUMPTION** (inferred, not observed).

## Summary

1. Main is at d34d364; five `claude/*` branches are one signed commit ahead each, none behind, and merge cleanly in
   any order (no shared files). Checks passed on every branch head.
2. No image build has succeeded since e8e765d (2026-10-21): five failed at Red Hat's login during its SSO outage,
   two at the new scan gate on the scan's own 0777 output directory (fixed on `claude/image-scan-output-dir`).
3. In the registry, `:latest` = `sha256:137e69fa…` (signed, SBOM; no scan attestation); `:testing` and `:stable` do
   not exist. No existing digest can be promoted: `promote.yml` requires a scan attestation, which no image has yet.
4. lv-demo01 ran `137e69fa…`, the newest signed build, tracking `:latest` (as of 2026-10-21). Main has no
   image-content change since that build.
5. Two gaps before the sequence can finish: the clean-clone path is broken until `:stable` exists (new desktops
   would fail provisioning), and the image's automatic update timer is on, although provisioning says it stays off.
   No image has built since e8e765d, so RHEL updates released since 2026-10-21 are in no image yet.

## Findings

| # | Item | Evidence | Label |
|---|---|---|---|
| 1.1 | Branches, all based on d34d364, 1 ahead / 0 behind main | `git rev-list --left-right --count` per branch; heads: image-scan-output-dir 9825483, rpm-image-install 747d103, changelog-62-63 af47ca7, epic-connectors-watch f2e5d23, agents-md 2c0db05 | VERIFIED |
| 1.2 | Every branch commit signed (status G), the same SSH key as other agent commits | `git log --format='%G? %GK'` per branch | VERIFIED |
| 1.3 | Files: image-scan-output-dir `hardening/stig/scan-image.sh`; rpm-image-install `.gitea/workflows/image.yml`, `image/desktop/Containerfile`, `image/desktop/scripts/install-files.sh`, `packaging/install-desktop.sh`; changelog-62-63 `notes/phase1-changelog.md`, `notes/handoff/2026-10-22-claude-phase4-agent-context.md`; epic-connectors-watch `README.md`, `ROADMAP.md`, `docs/PLAN.md`, `docs/adr/0017-…md`; agents-md `.gitignore`, `AGENTS.md`, `CLAUDE.md` | `git diff --stat origin/main...<branch>` | VERIFIED |
| 1.4 | No file is touched by two branches; all five merge cleanly in sequence | `git merge-tree --write-tree` chained over the five branches: exit 0 each; overlap count 0 | VERIFIED |
| 1.5 | CI on branch heads: `checks` success on all five (tasks 272, 273, 276, 278, 279); `website-preview` skipped; image and RPM workflows run on main only | Gitea actions tasks API; `image.yml` and `rpms.yml` `branches: [main]` | VERIFIED |
| 1.6 | agents-md commit 2c0db05 was created with hooks skipped; the hooks were run on it afterwards and passed | session record 2026-10-22 | VERIFIED 2026-10-22 |
| 2.1 | `image.yml` (main and rpm-image-install) pushes `:$TAG` (12-char commit) and `:testing` only | `image.yml:95-96` on main, `:99-100` on the branch | VERIFIED |
| 2.2 | Nothing in any workflow on any branch pushes or names `:latest` | `git grep ':latest' <ref> -- .gitea/` on main and every `claude/*` branch: no match | VERIFIED |
| 2.3 | `promote.yml` (dispatch only) verifies signature, SBOM and scan attestations, then copies the manifest to `:stable` and prints the previous `:stable` | `promote.yml:12-13, 70-72, 100-102` | VERIFIED |
| 2.4 | `promote.yml` has never run | no `promote` task in the tasks API | VERIFIED |
| 2.5 | Last image builds: tasks 248, 251, 252, 257, 261 failed at the registry.redhat.io login (HTTP 503, Red Hat SSO outage); tasks 266 and 271 failed at the scan gate, `unexpected: ['dir_perms_world_writable_sticky_bits']`; last success task 237 (e8e765d) | job logs 250, 252, 259, 263, 268, 272 | VERIFIED |
| 2.6 | Last `rpms` run: task 270 (d34d364) success | tasks API | VERIFIED |
| 2.7 | Scan-gate failure cause: the scan's output directory, mode 0777, mounted into the scanned container, on ext4; reproduced (0777 fails, 0755 passes) | reproduction on node1 2026-10-22; fix 9825483 | VERIFIED 2026-10-22 |
| 3.1 | `:latest` and `:e8e765dfee3f` = `sha256:137e69fa630505997e3e3b911c5151f9cc4334c5f788e2bc725fd42668b08edc` | `registry-tag.py --digest` | VERIFIED |
| 3.2 | `:testing` and `:stable` do not exist | `registry-tag.py --digest` returns empty (HTTP 404) | VERIFIED |
| 3.3 | Other tags: `:2b999c13d9cc` = `sha256:da46c339…`, `:b3b0756e7452` = `sha256:06505483…`, `:050a5c7615ef` = `sha256:6c21612d…`, `:unsigned-test` = `sha256:b89c4aa8…`; plus 2026-10-20 commit tags and untagged manifests (45 package versions in all) | Gitea packages API; `registry-tag.py --digest` | VERIFIED |
| 3.4 | `137e69fa…`: signature valid (commit e8e765dfee3f, CI run 76), SBOM attestation valid, **no scan attestation** | `cosign verify` and `cosign verify-attestation` (spdxjson; image-stig-scan/v1) with `image/desktop/signing/cosign.pub` | VERIFIED |
| 3.5 | `da46c339…` (2b999c1, run 74): signature and SBOM valid, no scan attestation | as above | VERIFIED |
| 3.6 | Negative control: `:unsigned-test` fails all three checks | as above | VERIFIED |
| 3.7 | The `sha256-<digest>` package versions without `.sig`/`.att` suffix are cosign or OCI side artifacts, not desktop images | not inspected | ASSUMPTION |
| 4.1 | Repo references to `:stable`: `image.yml:15`, `promote.yml:1,9,10,100,102`, `image/desktop/README.md:46`, `hardening/stig/README.md:13`, `terraform/modules/libvirt-desktop/variables.tf:145`, `terraform/node1/site.auto.tfvars.example:8`; changelog | `git grep` on main | VERIFIED |
| 4.2 | No reference to `:latest` remains in workflows, terraform, image or docs on main (the changelog mentions it historically) | `git grep` on main and branches | VERIFIED |
| 4.3 | The git-ignored site values file on dev-laptop-2: key `update_image` ends in `:stable` (count 1), none in `:latest` | `grep -c` on the key line, value not printed | VERIFIED |
| 4.4 | Provisioning passes `UPDATE_IMAGE` into the seed and runs `bootc switch --enforce-container-sigpolicy "$UPDATE_IMAGE"` under `set -euo pipefail` | `seed.sh:14`; `provision:12, 226-259` | VERIFIED |
| 4.5 | **The clean-clone path is broken until `:stable` exists**: a desktop created today would switch to `:stable` at provisioning step 9b, which fails while the tag is absent, and `set -e` stops the script | 4.3 + 4.4 + 3.2 | ASSUMPTION (not run) |
| 4.6 | `claude/rpm-image-install` changes nothing that provisioning executes: no difference to main in `usr/libexec/locumview/`, the provisioning unit, `packaging/remote-access/`, `image/desktop/install/` or `seed.sh`. The one RPM-owned file provisioning uses, the guest's `locumview-tour-on-connect.service` (enabled by `demo-user-root.sh`), keeps its path and content. **No ISO rebuild is needed for it** | `git diff --stat origin/main origin/claude/rpm-image-install -- <those paths>`: empty; RPM contents byte-compared with the image on 2026-10-21 | VERIFIED |
| 4.7 | The installer ISO on node1 (built 2026-10-21 10:43 from `da46c339…`, commit 2b999c1) differs from main on provisioning paths only in `dns-v4-only` (the #61 exit fix): a desktop installed from it shows that unit failed on its first boots, until its switch to `:stable` takes effect | `git diff --stat 2b999c1 origin/main -- <provisioning paths>`; ISO timestamp | VERIFIED |
| 4.8 | No image has built since e8e765d (2026-10-21 15:27 UTC), so RHEL updates released since then are in no image | 2.5 | VERIFIED (no build); whether security errata were released since is ASSUMPTION |
| 5.1 | Running VMs on node1: idm01, locumview-ref-dev (hand-built, not a bootc system), lv-demo01. No other image-built desktop exists | `virsh list --all` | VERIFIED |
| 5.2 | lv-demo01 booted `sha256:137e69fa…` from `<registry>/…/locumview-desktop:latest` (signature policy enforced), nothing staged | `bootc status` on lv-demo01, 2026-10-21 after its automatic update | VERIFIED 2026-10-21; re-check pending owner run |
| 5.3 | lv-demo01 is current: no newer signed build exists, and main has no image-content change since e8e765d (only `registry-tag.py` and `packaging/extensions/COPYING`, neither installed) | `git diff --stat e8e765d origin/main` over the Containerfile's sources | VERIFIED |
| 5.5 | The update unit in the image: `bootc-fetch-apply-updates.timer` (OnBootSec 1h, then every 8h with up to 2h random delay) starting `bootc-fetch-apply-updates.service`, `ExecStart=/usr/bin/bootc upgrade --apply --quiet` (applies and reboots). Enabled by the vendor symlink `/usr/lib/systemd/system/default.target.wants/bootc-fetch-apply-updates.timer`, so `systemctl disable` cannot remove it; `systemctl mask` (a link in `/etc`, which persists on bootc) can | `podman run` of `137e69fa…`: unit files and `.wants` links listed | VERIFIED |
| 5.4 | **The automatic update timer is on**: lv-demo01 updated to `137e69fa…` and rebooted itself on 2026-10-21 through `bootc-fetch-apply-updates`; provisioning's comment says the timer stays off, and nothing in the repo disables it | `provision:224-225`; `git grep` for the timer: none; lv-demo01 journal and timers, 2026-10-21 | VERIFIED 2026-10-21 (behavior); VERIFIED (repo) |
| 6.1 | Local rollback, `bootc rollback`: exercised on the first bootc test VM (changelog #52) | `notes/phase1-changelog.md:697` | VERIFIED (repo record) |
| 6.2 | Upgrade with the previous image kept as rollback: exercised on lv-test10 (changelog #58) | `notes/phase1-changelog.md:787` | VERIFIED (repo record) |
| 6.3 | Fleet rollback: run `promote.yml` with the previous digest, which `promote.yml` prints | `promote.yml:9-10, 102` | VERIFIED (as written) |
| 6.4 | On `bootc upgrade` with `:stable` pointing at an older digest, bootc stages that digest, because it compares digests, not ages; the timer would then apply it and reboot | no repo evidence | ASSUMPTION |
| 6.5 | Access to an image-built desktop without any desktop credential: the owner's IdM account over SSH from a k3s node, with the public key served by IdM; sudo through the owner's IdM sudo rule (`locumview-admins`), which asks for the owner's password. The agent on node1 holds a key registered to the owner's IdM account, so it can run unprivileged checks; anything under sudo is an owner run | key-based IdM login and sudo shown on the reference desktop (changelog #47 era, 2026-10-17); on an image-built desktop not yet tried | ASSUMPTION for the test desktop (checked in step 5) |
| 6.6 | Plan count: one desktop in this root is exactly **10 resources**: 8 unconditional (`random_password.enroll`, `freeipa_host.desktop`, `freeipa_host_hostgroup_membership.desktop`, `libvirt_volume.disk`, `libvirt_volume.seed`, `terraform_data.seed`, `libvirt_domain.desktop`, `terraform_data.provisioned`) plus `terraform_data.rhsm` (count 1 because `rhsm_sops_file` defaults to `rhsm.sops.yaml`, present) and `terraform_data.guacamole` (count 1 because `guacamole_kubeconfig` is set in the site values). Matches lv-demo01's apply (10 added, 2026-10-21) and the clean-clone destroys (10 removed, changelog #59) | `terraform/modules/libvirt-desktop/main.tf:13-236`, counts at `:110` and `:236`; `terraform/node1/variables.tf` default; site value key set (count 1, value not printed); lv-demo01 apply log | VERIFIED |
| 7.1 | cosign flags `--use-signing-config=false --tlog-upload=false` in `image.yml:107,131,141`: no deprecation warning in the last successful build log (job 239), and cosign 3.1.3's help still shows `--tlog-upload=false` | job 239 log; `cosign sign --help` | VERIFIED; **not blocking** |

## Proposed execution sequence

Each step names who runs it, the approval gate, the success check and how to undo it. Agent steps that change
anything run only after the owner's go for that step. **The agent never decrypts a desktop credential:** every step
that needs root on a desktop, and every OpenTofu run (OpenTofu decrypts the desktop's SOPS file to build its seed),
is an owner run (Fish commands below); the agent checks results read-only, over SSH as the owner's IdM account from
node1 without sudo (6.5), and through the registry and CI APIs. The tests run on a disposable test desktop; lv-demo01
is switched last.

**Digests are the evidence, not tags.** At every gate marked **[E]**, the record holds, before and after the step: the
`:stable` digest from the registry (`registry-tag.py --digest`), and from the desktop's `bootc status` (P-status) the
booted, staged and rollback digests with each one's tracked image reference. The record goes into the evidence
table below and, at the end, into the changelog.

**Hard stops.** Any failed signature, SBOM attestation, scan attestation, digest comparison or desktop-access check
halts the sequence before the next merge or promotion. Nothing proceeds on a partial result; the owner decides how to
continue, and the failure is recorded as a finding.

0. **Stop automatic updates on lv-demo01, before any promotion.** Owner, P0, with its pre-checks and post-checks.
   Check: before, `bootc-fetch-apply-updates.service` is not active and `bootc status` is recorded; after, the timer
   is `masked` and inactive, and the staged deployment is unchanged. Reversal (P0-reverse) is a separate owner
   decision, not a routine undo. **Temporary containment:** the mask is per desktop; every desktop created before the
   image-level update policy (the next item after this milestone) inherits the auto-apply timer and needs the same
   mask. (lv-demo01 follows `:latest`, which nothing moves any more, so this guards the later switch rather than
   today.)
1. **Merge `claude/image-scan-output-dir`.** Owner, in Gitea (fast-forward). Gate: owner review. Check: main contains
   9825483; an image build starts by itself (path `hardening/**`). Undo: revert 9825483.
2. **Build A.** Automatic. Check (agent, read-only): the `build` task succeeds; `:testing` resolves to a new digest
   DA; `cosign verify` and both `verify-attestation` checks pass on DA; the scan summary reports no unexpected
   failures. Undo: none needed (no desktop follows `:testing`).
3. **Merge the documentation branches** (`claude/epic-connectors-watch`, `claude/agents-md`,
   `claude/changelog-62-63`) whenever convenient. Owner. They touch no image paths and start no image build.
   Undo: revert.
4. **[E] Promote A to `:stable`.** Owner runs `promote` (Actions, Run workflow) with digest DA, or the agent
   dispatches it on the owner's go (no credential involved). Check (agent): the log shows all three verifications and
   "previous :stable was none"; `:stable` before = none, after = DA. This also restores the clean-clone path (4.5).
   **One-way:** the first promotion has no previous digest to return to. If A proves bad, stop all new provisioning
   and investigate; never delete `:stable` as a rollback (desktops following it would fail to update, and new
   desktops would fail to provision).
5. **Create a disposable test desktop following `:stable`.** Owner, P4 on dev-laptop-2: its secrets, an entry in
   `terraform/node1/desktops.auto.tfvars` (for example `lv-test15`, default size, owner connection only), then
   `./tofu.sh plan -out` to a file; the owner reviews that **only `module.desktop["lv-test15"]` resources are added and
   nothing else changes or is destroyed**, that the summary is exactly `Plan: 10 to add, 0 to change, 0 to destroy.`
   (finding 6.6), and reads the whole plan output; any other count is a hard stop. Then the owner applies that saved plan as a user service under `systemd-inhibit`
   (changelog #61). No `-auto-approve`. Installed from the existing ISO (4.7). Check: the apply completes and
   provisioning finishes; owner's P-status shows the booted image is the ISO's (2b999c1's) and DA **staged**,
   tracking `:stable`; agent confirms the key login works as the owner's IdM account (6.5). Undo: step 15.
6. **Stop automatic updates on the test desktop, before its switch reboot.** Owner, P6 (P0's checks, on the test
   desktop). Check: `masked`, inactive, the staged DA unchanged. Undo: destroyed in step 15.
7. **[E] Finish the switch: one reboot.** Owner, P5. Check: P-status shows booted DA tracking `:stable`, nothing
   staged, rollback the ISO's image; agent confirms `systemctl is-failed locumview-dns-v4-only.service` is **not**
   `failed`, no failed units, and the timer still `masked`.
8. **Merge `claude/rpm-image-install`; build B.** Owner merges; the build is automatic. Check (agent, read-only): as
   step 2, plus: the build log shows the four `locumview-*` packages installed with both signature checks and `rpm -V`
   clean; the **NEVRAs of the four packages taken from B's verified SBOM attestation** (A8) are recorded, and each is
   checked to carry the LocumView RPM signature (key ID `0f02a990167ea18e`), both in the image (`rpm -q` with the
   signature tag, in a container of DB) and as published in the RPM registry (`rpm -K` against the committed public
   key). Undo: revert 747d103. No ISO rebuild is needed (4.6).
9. **[E] Promote B to `:stable`.** As step 4 with digest DB. Check (agent): the log prints "previous :stable was DA";
   `:stable` before = DA, after = DB. Undo: promote DA (which is step 13).
10. **[E] Upgrade test.** Owner, P7 on the test desktop: `sudo bootc upgrade`, planned reboot. Check: before, booted DA;
    after, booted DB tracking `:stable`, rollback DA, nothing staged; agent confirms no failed units.
11. **Full deployed-desktop STIG scan of DB** on the test desktop. Owner, P8 (`hardening/stig/scan-stig.sh` from node1;
    it asks for sudo once). Check (agent, from the fetched results): the image profile result matches #59 (405 pass,
    0 fail) or every difference is explained; results kept as evidence in `docs/evidence/stig/`. This is also where the
    rules the image scan leaves to installed desktops (Q5) are judged for this release. Undo: none (read-only).
12. **[E] Local rollback test.** Owner, P9: `sudo bootc rollback`, reboot. Check: booted DA, rollback DB. Then P9 again.
    Check: booted DB, rollback DA. **If the second rollback does not return to DB, stop before step 13.**
13. **[E] Fleet rollback test (observed, not assumed).** Owner runs `promote` with digest DA; agent checks `:stable`
    before = DB, after = DA. Owner, P10 on the test desktop: `sudo bootc upgrade --check`, `sudo bootc upgrade`, planned
    reboot. Check: the test desktop stages and boots DA tracking `:stable` (confirms or refutes 6.4). **If bootc does not
    follow `:stable` back to DA,** record it as a finding and, on the owner's approval, use the fallback (P10-fallback):
    `bootc switch --enforce-container-sigpolicy` to `…@DA` (the pinned older digest), planned reboot, verify booted DA;
    then `bootc switch` back to `:stable` and verify, after step 14, booted DB tracking `:stable`.
14. **[E] Re-promote B and upgrade forward.** Owner runs `promote` with digest DB. Check (agent): the log prints
    "previous :stable was DA"; `:stable` before = DA, after = **DB**. Owner, P10 again on the test desktop. Check:
    booted DB tracking `:stable`, rollback DA. This leaves `:stable` = DB for step 16. Undo: none needed (the restore).
15. **Destroy the test desktop.** Owner, P11 on dev-laptop-2: remove its entry, `./tofu.sh plan -out` to a file, review
    that **only `module.desktop["lv-test15"]` resources are destroyed and nothing else changes**, that the summary is
   exactly `Plan: 0 to add, 0 to change, 10 to destroy.` (finding 6.6), and reads the whole plan output; any other count is
   a hard stop. Then apply that saved plan;
    remove its secrets file. No `-auto-approve`. Check (agent): no IdM host or DNS record, Red Hat registration,
    Guacamole connection or volume of it left. Undo: none needed.
16. **[E] Switch lv-demo01 to `:stable`, one reboot.** Owner, P3. Gate: owner; no guest session open (Guacamole
    history). Check: before, booted `137e69fa…` tracking `:latest`; `:stable` = DB (step 14's digest); after, booted
    **DB** tracking `:stable`, rollback `137e69fa…` tracking `:latest`, nothing staged; no failed units; the guest session
    reachable through guacd; the timer still `masked`. Undo: `sudo bootc rollback` and reboot (back to `137e69fa…`).
17. **Re-run the reference check from 4.1 to 4.3** (agent, read-only): no `:latest` in the repo or site values, and
    lv-demo01 tracks `:stable` (step 16's P-status).
18. **Keep `:latest` until lv-demo01's rollback entry tracks `:stable` (recommended).** After step 16, lv-demo01's
    rollback entry still tracks `:latest`; deleting the tag would leave its rollback image unreachable by tag, although
    the deployment itself stays on disk. So `:latest` is removed only after lv-demo01's next upgrade to a later `:stable`
    digest makes the rollback entry a `:stable` one (likely after this milestone). Then, with step 17 clean: agent on
    the owner's explicit go, `DELETE /api/v1/packages/mike/container/locumview-desktop/latest` (Gitea API). Check:
    `:latest` returns 404; `:e8e765dfee3f` still resolves to `137e69fa…`. Undo:
    `registry-tag.py <registry>/…@sha256:137e69fa… latest`. (The alternative, removing it now and documenting the gap, is
    not recommended.)
19. **Record it.** Agent, on a branch: changelog entry with the evidence table, ROADMAP Phase 4 status, the STIG
    evidence from step 11, the B package NEVRAs from step 8, handoff note.

### Evidence table (filled in during execution)

One row per **[E]** gate and desktop. Digests in full; image references as `bootc status` prints them.

| Step | Desktop | `:stable` before / after | Booted before → after (ref, digest) | Staged before → after | Rollback before → after |
|---|---|---|---|---|---|
| 4 | (none) | none / DA | | | |
| 7 | test desktop | DA / DA | ISO image → DA (`:stable`) | DA → none | none → ISO image |
| 9 | (none) | DA / DB | | | |
| 10 | test desktop | DB / DB | DA → DB | none → none | ISO image → DA |
| 12 | test desktop | DB / DB | DB → DA → DB | none | DA → DB → DA |
| 13 | test desktop | DB / DA | DB → **observed** | observed | observed |
| 14 | test desktop | DA / DB | DA → DB | | |
| 16 | lv-demo01 | DB / DB | `137e69fa…` (`:latest`) → DB (`:stable`) | none → none | → `137e69fa…` (`:latest`) |

The expected values are pre-filled; the observed ones replace them, and any difference is a hard stop, except in
step 13: its outcome is recorded as observed, and if the test desktop does not boot DA, that routes to the
P10-fallback decision (step 13), not to a hard stop.

### A8: B's LocumView packages from the SBOM (agent, read-only)

```fish
set -x DOCKER_CONFIG (mktemp -d); ln -s $XDG_RUNTIME_DIR/containers/auth.json $DOCKER_CONFIG/config.json
cosign verify-attestation --key image/desktop/signing/cosign.pub --insecure-ignore-tlog --type spdxjson <registry>/mike/locumview-desktop@<DB> | python3 -c 'import base64,json,sys; [print(p["name"], p.get("versionInfo","")) for l in sys.stdin for p in json.loads(base64.b64decode(json.loads(l)["payload"]))["predicate"]["packages"] if p["name"].startswith("locumview-")]'
podman run --rm --network none <registry>/mike/locumview-desktop@<DB> rpm -q --qf '%{NEVRA} %{RSAHEADER:pgpsig}\n' locumview-shell-extensions locumview-branding locumview-tour locumview-ehr-launcher
rm -rf $DOCKER_CONFIG; set -e DOCKER_CONFIG
```

The registry copies are then checked with `rpm -K` against `packaging/rpm/signing/RPM-GPG-KEY-locumview` in the pinned
CentOS Stream 10 container (as `packaging/rpm/publish-rpms.sh` does).

## Pending owner runs

Desktops accept SSH only from the k3s nodes, so desktop commands run from node1. The owner logs in with the owner's
IdM account (key served by IdM) and types the owner's password for sudo; no desktop credential is decrypted.
`<owner>` is the owner's IdM user. OpenTofu runs on dev-laptop-2, which holds the age key.

```fish
# P-status (every [E] gate, before and after): booted, staged and rollback, each with its image reference and digest
ssh -t <owner>@<desktop-address> 'sudo bootc status'

# P0 (step 0) on lv-demo01. Pre-checks: no update running now, and the current deployments
ssh -t <owner>@<lv-demo01-address> 'systemctl is-active bootc-fetch-apply-updates.service; sudo bootc status'
#   expect: "inactive"; record booted, staged (expect none) and rollback. If the service is active, wait and re-check.
# then mask, and post-checks: masked, the timer inactive, the staged deployment unchanged
ssh -t <owner>@<lv-demo01-address> 'sudo systemctl mask --now bootc-fetch-apply-updates.timer; systemctl is-enabled bootc-fetch-apply-updates.timer; systemctl is-active bootc-fetch-apply-updates.timer; sudo bootc status'
#   expect: "masked", "inactive", and the same staged entry as before

# P0-reverse: a separate owner decision (re-enables automatic apply-and-reboot), not a routine undo
ssh -t <owner>@<lv-demo01-address> 'sudo systemctl unmask bootc-fetch-apply-updates.timer && sudo systemctl start bootc-fetch-apply-updates.timer'

# P1: lv-demo01 now: deployments, tracked image, and the update timer (findings 5.2, 5.4)
ssh -t <owner>@<lv-demo01-address> 'sudo bootc status; systemctl is-enabled bootc-fetch-apply-updates.timer; systemctl list-timers bootc-fetch-apply-updates.timer --no-pager'

# P2: what the update service did recently
ssh -t <owner>@<lv-demo01-address> 'sudo journalctl -u bootc-fetch-apply-updates.service --since -2d --no-pager | tail -20'

# P3 (step 16): switch lv-demo01 to :stable, then reboot (P-status before and after)
ssh -t <owner>@<lv-demo01-address> 'sudo bootc switch --enforce-container-sigpolicy <registry>/mike/locumview-desktop:stable && sudo bootc status && sudo systemctl reboot'

# P4 (step 5), on dev-laptop-2: secrets, the entry, a saved plan to review, then apply exactly that plan
cd ~/Projects/locumview/terraform/node1
./secrets.sh desktop lv-test15
#   add to desktops.auto.tfvars:   "lv-test15" = { user = "<owner>" }
./tofu.sh init -input=false
./tofu.sh plan -input=false -no-color -out=lv-test15.tfplan | tee lv-test15-plan.txt
grep -E '^  # ' lv-test15-plan.txt | grep -v 'module.desktop\["lv-test15"\]'
#   expect: no output (only the test desktop's resources)
grep -E '^Plan:' lv-test15-plan.txt
#   expect exactly: "Plan: 10 to add, 0 to change, 0 to destroy." Any other count is a hard stop.
#   Then the owner reads the whole plan output (lv-test15-plan.txt) before applying.
#   (a "# data.…" line for a data source read is fine; any other resource outside lv-test15 is a hard stop)
systemd-run --user --unit=lv-test15-apply --collect -p WorkingDirectory=(pwd) -E PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin -p StandardOutput=file:$HOME/lv-test15-apply.log -p StandardError=inherit systemd-inhibit --what=sleep:idle:handle-lid-switch --who=tofu --why=apply ./tofu.sh apply -input=false -no-color lv-test15.tfplan
tail -f ~/lv-test15-apply.log
rm lv-test15.tfplan lv-test15-plan.txt

# P6 (step 6), from node1: P0's pre-checks, mask and post-checks, on the test desktop, before its switch reboot
ssh -t <owner>@<test-desktop-address> 'systemctl is-active bootc-fetch-apply-updates.service; sudo bootc status'
ssh -t <owner>@<test-desktop-address> 'sudo systemctl mask --now bootc-fetch-apply-updates.timer; systemctl is-enabled bootc-fetch-apply-updates.timer; systemctl is-active bootc-fetch-apply-updates.timer; sudo bootc status'

# P5 (step 7): the switch reboot
ssh -t <owner>@<test-desktop-address> 'sudo systemctl reboot'

# P7 (step 10): upgrade test
ssh -t <owner>@<test-desktop-address> 'sudo bootc upgrade && sudo bootc status && sudo systemctl reboot'

# P8 (step 11), from node1 in the repository: full STIG scan (asks for sudo once)
hardening/stig/scan-stig.sh <owner>@<test-desktop-address>

# P9 (step 12): local rollback test (run twice: to DA, then back to DB)
ssh -t <owner>@<test-desktop-address> 'sudo bootc rollback && sudo bootc status && sudo systemctl reboot'

# P10 (steps 13 and 14): after a promotion, take whatever :stable points at
ssh -t <owner>@<test-desktop-address> 'sudo bootc upgrade --check; sudo bootc upgrade && sudo bootc status && sudo systemctl reboot'

# P10-fallback (step 13, only if bootc does not follow :stable back, and on the owner's approval)
ssh -t <owner>@<test-desktop-address> 'sudo bootc switch --enforce-container-sigpolicy <registry>/mike/locumview-desktop@<DA> && sudo bootc status && sudo systemctl reboot'
#   verify booted DA; after step 14's promotion, switch back and verify booted DB tracking :stable:
ssh -t <owner>@<test-desktop-address> 'sudo bootc switch --enforce-container-sigpolicy <registry>/mike/locumview-desktop:stable && sudo bootc status && sudo systemctl reboot'

# P11 (step 15), on dev-laptop-2: remove the "lv-test15" entry from desktops.auto.tfvars, then a reviewed plan
./tofu.sh plan -input=false -no-color -out=lv-test15-destroy.tfplan | tee lv-test15-destroy-plan.txt
grep -E '^  # ' lv-test15-destroy-plan.txt | grep -v 'module.desktop\["lv-test15"\]'
#   expect: no output
grep -E '^Plan:' lv-test15-destroy-plan.txt
#   expect exactly: "Plan: 0 to add, 0 to change, 10 to destroy." Any other count is a hard stop.
#   Then the owner reads the whole plan output before applying.
#   (a "# data.…" line for a data source read is fine; any other resource outside lv-test15 is a hard stop)
systemd-run --user --unit=lv-test15-destroy --collect -p WorkingDirectory=(pwd) -E PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin -p StandardOutput=file:$HOME/lv-test15-destroy.log -p StandardError=inherit systemd-inhibit --what=sleep:idle:handle-lid-switch --who=tofu --why=destroy ./tofu.sh apply -input=false -no-color lv-test15-destroy.tfplan
rm lv-test15-destroy.tfplan lv-test15-destroy-plan.txt desktops/lv-test15.sops.yaml
```

The agent's read-only checks on a desktop, as the owner's IdM account from node1, never use sudo: for example
`systemctl --failed`, `systemctl is-failed locumview-dns-v4-only.service`,
`systemctl is-enabled bootc-fetch-apply-updates.timer`.

## Risks and open questions

- **Q1, canary (decided by the owner):** the upgrade and both rollback tests run on a disposable test desktop
  following `:stable`, created after the first promotion and destroyed afterwards; lv-demo01 is switched last.
- **Q2, the update timer (decided for this milestone):** masked on lv-demo01 before any promotion (step 0, temporary) and on
  the test desktop after provisioning and before its switch reboot (step 6). The image-level update policy is the next item after this milestone. Provisioning's comment says the timer stays off; the image enables it (5.4, 5.5).
- **Q3, provisioning before the first promotion:** until step 4, an OpenTofu-created desktop fails at provisioning
  step 9b (4.5). Create no desktops before step 4.
- **Q5, scan coverage (decided):** the full deployed-desktop STIG scan runs on the test desktop for the release that
  goes to lv-demo01 (step 11).
- **Risk: the fix for the gate is verified locally only**, on ext4 on node1; the first CI confirmation is step 2.
- **Risk: RHEL updates are waiting.** No image has built since e8e765d (4.8); build A is the first to carry RHEL
  updates released since 2026-10-21, which is also why A's digest will differ from `137e69fa…` although main has
  no LocumView content change (5.3).
- **Risk: the test desktop's first boots** run the ISO's image (2b999c1), whose `dns-v4-only` reports failed after
  succeeding (4.7), until the switch reboot in step 7. Expected, not a test failure; step 7's check requires it cleared.
- **Risk: an unknown Red Hat registration** named `localhost.localdomain` checks in daily (probably the reference
  desktop); unrelated to this milestone, and it ends when the reference desktop retires.

## Open items after this milestone (not in the sequence)

- **Update policy in the image (the next item after this milestone):** replace the vendor timer's `bootc upgrade --apply` (download, apply and reboot at a
  random time) with staged updates applied at the next planned reboot, and make provisioning's comment true. Until
  then, masking is per-desktop containment: every desktop created before the policy inherits the auto-apply timer and
  must be masked by hand.
- **Phase 4, RPM versions pinned to the build commit (was Q4):** after `claude/rpm-image-install`, an image build
  installs whatever is newest in the RPM registry; pin the image to the NVRs built from the same commit, so an image
  is reproducible from its commit alone.
- **cosign flags** (7.1): not blocking.
