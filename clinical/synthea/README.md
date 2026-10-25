# Synthea background patients

The demo EHR's other patients, so the clinical app opens onto a realistic patient list rather than only the
scenario cases (plan M2: "Synthea supplies background patients only").

```fish
clinical/synthea/generate.sh        # regenerate background.json (needs podman; downloads Synthea once)
```

- **Synthea v4.0.0**, the tagged release, downloaded once to `~/.cache/locumview-synthea` and checked against the
  SHA-256 GitHub publishes for the release asset before it runs. It runs in a digest-pinned Eclipse Temurin 21 JRE
  container with no network.
- **Reproducible:** fixed seed, clinician seed and reference date (20261025), 20 living patients aged 25 to 90.
  Two generations give a byte-identical `background.json`.
- **What is kept** (`convert.py`): demographics, active problems that SNOMED CT classes as disorders, and active
  allergies (allergens only, with their SNOMED CT or RxNorm code). No encounters, medications, labs or cultures, so a
  background patient can never produce a finding: together they are a population-wide negative control.
- **Loaded** by `clinical/scenarios/load.py` with the cases (patient numbers `SYN-001` to `SYN-020`; skipped when
  already present). Synthea's names carry numbers (`Jamal145 Grant908`), which keeps them visibly synthetic.

Through FHIR, allergies come back coded. Problems come back as text only: OpenEMR 8.4.1's FHIR problem-list query
reads the stored code (`SNOMED-CT:59621000`) without parsing it, a defect to offer upstream with the M1 fixes.
