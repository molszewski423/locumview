# Live verification of automatic image-profile selection

The owner ran the revised scanner from signed source merge
`e7079eb543488205593d3802cdadd6af919d713a` on the image-built demo desktop on 2026-10-23. No explicit profile
argument was supplied: the read-only bootc marker check selected `xccdf_org.locumview_profile_stig_gui_image`.
OpenSCAP and the wrapper returned 0. No remediation or reboot was requested.

| ARF result | Count |
|---|---|
| Pass | 405 |
| Fail | 0 |
| Not applicable | 40 |
| Not checked | 7 |
| Not selected | 621 |

The agent independently parsed the structured ARF and checked that its profile matches `profile.txt` and that
`oscap-exit-code.txt` records 0. Scanner: openscap-scanner 1.4.4-1.el10_2; content: scap-security-guide
0.1.82-2.el10_2. The selected profile includes the image partition checks and excludes the documented SSH-zone
exception. Counts are consistent with the earlier image-profile result (#59); they should not be compared to
reference-profile totals without considering the different selected rules (#66).

`summary.json` contains only selected verification metadata and SHA-256 hashes of the privately retained raw
artifacts. The raw HTML and ARF contain internal desktop facts and are not published. Their hashes identify
the exact files used for verification; this summary is not a replacement for those raw reports, nor a signed
scan attestation. This was a deployed-desktop scan, separate from the per-image CI scan attestations.

## Limits

This verifies the revised wrapper's live automatic selection and successful evidence retrieval on an
image-built desktop. Explicit profile overrides and failed-rule/error propagation were tested locally with
mocked transports and scanners, not by deliberately failing the live desktop. The desktop image digest was
not freshly re-read as part of this scan, so no new digest-bound desktop attestation is claimed. No production
update, timer unmask or image promotion occurred. The already-failed file-indexing service noted before the
scan was not changed; the scan result is not a claim that every system service was healthy.
