# RPM version pinning: two builds of one commit

Verified read-only on 2026-10-22. Image source and RPM source commit:
`5f07e84589f167cd51c333d7cf1170d8675eb00a` (signed merge of PR #5). Both builds are successful attempts of
image workflow run 125. Re-running the workflow preserves the run number; the image digests distinguish them.

| Build | Image manifest digest | Image scan timestamp (UTC) | Duration from workflow |
|---|---|---|---|
| First successful attempt | `sha256:f9b0b2a1c004b612860ac80317f035340e037cadf8beddefefb9582e1fe24b0e` | 2026-10-22T21:32:12Z | 29m05s |
| Repeat attempt | `sha256:a63dc8fbea587dcec0fdc18b5b8c7d2e5f57b8dc4b48f4088732e4d5db047f99` | 2026-10-22T22:06:05Z | 28m19s |

## Verification

For each immutable digest, `cosign verify` and `cosign verify-attestation` (types `spdxjson` and
`https://locumview.org/attestations/image-stig-scan/v1`) succeeded against the committed
`image/desktop/signing/cosign.pub`. Verification used `--insecure-ignore-tlog`, consistent with the project's
offline signing policy. No transparency-log verification is claimed. No signing secret or registry credential
was used by the verifier.

- Both image signatures identify the source commit above and CI run 125.
- Both verified SBOM subjects identify their corresponding immutable manifest digest.
- All four LocumView package names appear exactly once in each SBOM. Their version-release values match the
  resolver at the source commit and match each other, as shown below.
- Both signed scan predicates report `result: pass`, 361 pass, 26 fail, 14 error, 44 not applicable,
  7 not checked, and no unexpected failures. The 40 fail/error rules are the declared runtime-only rules.
  Content: scap-security-guide 0.1.82-2.el10_2; scanner: openscap-scanner 1.4.4-1.el10_2.

| Package | Version-release in both signed SBOMs |
|---|---|
| `locumview-branding` | `0.1.0-1.20261022210028git5f07e84589.el10` |
| `locumview-ehr-launcher` | `0.1.0-1.20261022210028git5f07e84589.el10` |
| `locumview-shell-extensions` | `0.1.0-1.20261022210028git5f07e84589.el10` |
| `locumview-tour` | `0.1.0-1.20261022210028git5f07e84589.el10` |

## Recheck

Run from a full checkout of the source commit. Substitute the operator's registry reference for `<registry>`
and one full digest from the table for `<digest>`:

```fish
python3 packaging/rpm/resolve-version.py 5f07e84589f167cd51c333d7cf1170d8675eb00a --check-inputs
cosign verify --key image/desktop/signing/cosign.pub --insecure-ignore-tlog <registry>/locumview-desktop@<digest>
cosign verify-attestation --key image/desktop/signing/cosign.pub --insecure-ignore-tlog --type spdxjson <registry>/locumview-desktop@<digest>
cosign verify-attestation --key image/desktop/signing/cosign.pub --insecure-ignore-tlog --type https://locumview.org/attestations/image-stig-scan/v1 <registry>/locumview-desktop@<digest>
```

Decode the verified SPDX statement payloads, confirm the subject digest, then select `predicate.packages`
entries for the four package names above and compare `versionInfo`. Read immutable digests, since re-running
the workflow moves the testing and commit tags.

## Scope

The RPM version-pinning acceptance check passes. The two image digests differ: this is not whole-image or
RPM-byte reproducibility. The builds also exercise successful installation of the pinned packages and the
image scan, but no deployed-desktop scan or update to these new images was performed. No promotion occurred
as part of this verification. The existing live demo and stable release were not changed.
