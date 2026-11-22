# The frozen evaluation build (Phase 9 lite M6 exit)

Status: Planned (2026-11-21, changelog #209). Owner review of this plan pending.

M6 ends with "a frozen, versioned evaluation build: rules, model and version, prompts, knowledge base, scenario set
and app all pinned, with one identifier and a manifest of hashes. Its outputs on every case are exported as the data
the Review app shows" (`phase9-lite-and-review-workspace.md`, M6). This plan says what is pinned, how the identifier
is made, what the export holds, and how a build is checked. The Review app (M7) and the evaluation rounds (M8) read
what this produces; nothing here changes the live demo.

## 1. What a build pins

One file, `clinical/eval/builds/<id>/manifest.json`, records:

| Item | Recorded as |
|---|---|
| Source | the git commit the build was made from (must be on main, clean tree) |
| Images | agent, gateway (with the app) and OpenEMR, by digest, equal to `k8s/clinical/kustomization.yaml` at that commit; each verified (signature and SBOM attestation) by `scripts/clinical/verify-images.sh` |
| Rules and knowledge base | `antimicrobials.json` version and sha256 |
| Citations | `citations.json` sha256 |
| Model | name, Ollama digest, options (temperature, seed, token limit), from `clinical/agent/model.json` |
| Prompt | file name and sha256 |
| Scenario set | each case's id, version, kind, owner review status (all `approved`) and sha256; the FHIR fixture's sha256 |
| Export | sha256 of every exported file (section 3) |

**Identifier:** `eval-<YYYYMMDD>-<n>` for people (for example `eval-20261122-1`), plus the manifest's own sha256 for
machines. Every exported file names both. A later build after any change, even a single prompt word, gets a new
identifier; a build is never edited.

## 2. How it is made

`clinical/eval/freeze.py`, run by the agent on MikePC (it needs the pinned model on the local GPU):

1. Refuses unless the tree is clean, on main, every case is approved, and the image digests equal the kustomization's.
2. Runs **the pinned agent image itself** (podman, by digest), not the working tree, on each case's recorded FHIR
   read-back, so the findings are those of the artifact that is deployed. The agent's own model check refuses a model
   whose digest differs.
3. Asks for explanations once, at the pinned options, and **stores the text**. A build never regenerates an
   explanation: what reviewers read is exactly what was frozen. Withheld explanations (the guard) are recorded as
   withheld, with the reason.
4. Compares each case's findings with its `expected_findings`. The build is refused unless all match (the same check CI
   runs); a mismatch is a bug to fix first, not something to freeze.
5. Writes the export and the manifest, then hashes them.

A cross-check, not part of the build: the same rules on the live cluster's read-back of each chart give the same
findings (as the app shows them), recorded in the changelog entry.

## 3. What the export holds

Two sets, so reviewers never see the answer key:

- **`review/<case>.json`, what a reviewer sees (in the build's randomized order per reviewer, M7):** the patient as
  the chart shows it (age, sex, problems, home medications, orders with dates and routes, vitals, labs, cultures and
  susceptibilities, a timeline), the module, and either the finding (summary, evidence, citations, explanation) or
  "no finding" for that module. No case kind, no expected findings, no reference answer, no case title that gives the
  answer away (a neutral label such as "Case 07").
- **`key/<case>.json`, owner only:** case id and version, kind (finding, negative control, ambiguous), expected
  findings, reference answer, rationale, citations, and whether the build's findings matched. The analysis (plan
  section 4.3) joins reviewers' answers to this.

Plus `summary.md`: counts by module and kind, matches (all must match), explanations written and withheld, and the
time each took, for the changelog and for Phase 8 lite.

## 4. How it is checked

- `freeze.py --verify <id>`: recomputes every hash from the files at the recorded commit and the export; runs in CI
  for every build directory, so a build that drifts from its manifest fails the checks.
- The owner reads the candidate build's `review/` files (the explanations especially) before it is declared frozen.
  Freezing is the owner's decision, recorded in the changelog; until then it is a candidate.
- After freezing: a git tag `eval-<date>-<n>` on the build's commit. Tags reach the public mirrors, so the owner
  creates and pushes it.

## 5. Scope of the first build

All 32 approved cases (15 with a finding, 13 negative controls, 4 ambiguous) across the four modules: stewardship,
IV to PO, ADE monitoring and opioid stewardship. Rules not yet built (suspected HIT, renal dosing, daptomycin with CK,
linezolid with an SSRI, daptomycin for pneumonia, dose-based opioid rules) go into a later build.

## 6. Owner decisions

1. **Scope:** all 32 cases and four modules in the first build (recommended), or the 26 antimicrobial cases only, since
   round 1's reviewers are stewardship pharmacists.
2. **Reviewer view:** hide case kind, expected findings and reference answer from reviewers (recommended), or show the
   reference answer after a reviewer submits each case.
3. **Explanations:** generate once and freeze the text (recommended), or regenerate at review time (not reproducible).
4. **Tag:** the owner pushes `eval-<date>-<n>` after freezing (recommended), or no tag (the manifest alone).

## 7. Steps after approval

1. `freeze.py` with `--verify`, tests and the CI check (one PR).
2. A candidate build `eval-<date>-1` (one PR with the build directory); the owner reads it.
3. The owner freezes it (changelog), tags it; ROADMAP.md marks M6 and Phase 9 lite Done. Phase 8 lite (the demo
   video) is next.
