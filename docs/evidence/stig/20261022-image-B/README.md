# STIG scan of image B on a deployed desktop (2026-10-22)

Release sequence step 11 (`notes/release-integrity-report.md`), changelog #66. The desktop is `lv-test15`, built by
OpenTofu from the signed image A and upgraded in place to image B
(`sha256:50c14768c9440fd03e737c67d74e99cc736ce31fc961639640115f12b6800f5d`) through `:stable`. Scanned with
`hardening/stig/scan-stig.sh` at 14:30 EDT, during the boot of B. Scanner and content: `versions.txt`
(openscap-scanner 1.4.4-1.el10_2, scap-security-guide 0.1.82-2.el10_2).

Files: `results.txt` (oscap's rule-by-rule output), `report.html.gz` (the HTML report; the desktop's addresses and MAC
address replaced with placeholders in square brackets), `versions.txt`.

## Result

| Profile | Pass | Fail | Not applicable | Not checked | Rules |
|---|---|---|---|---|---|
| `xccdf_org.locumview_profile_stig_gui` (this run) | 405 | 1 | 35 | 7 | 448 |
| `xccdf_org.locumview_profile_stig_gui_image` (#59, `../20261020-image/`) | 405 | 0 | 40 | 7 | 452 |

The one failure is `firewalld_sshd_port_enabled`, the documented exception for image-built desktops
(`hardening/stig/README.md`): SSH is open only to the k3s nodes, in the `locumview-gateways` zone, and the check
passes only when SSH is open to every source in the default zone.

## Why the two numbers differ

They come from two profiles in the same tailoring file (`hardening/stig/locumview-stig-gui-tailoring.xml`):

- `stig_gui` is the reference desktop's profile. `scan-stig.sh` always uses it.
- `stig_gui_image` extends it for desktops built from the image: it turns the five separate-partition rules back on
  and deselects `firewalld_sshd_port_enabled` (the exception). #59 was scanned with this profile.

So this run includes the exception rule (fail) and leaves out the five partition rules, while #59 did the opposite.
On the 447 rules both profiles share, **every result is identical** (405 pass, 35 not applicable, 7 not checked;
compared rule by rule). The five partition rules were not applicable in #59. Recorded consistently:

- **Image profile, the release gate:** 405 pass / 0 fail in #59. Image B's results equal #59's on every shared rule;
  its only other result is the exception, which the image profile deselects.
- **Desktop profile, as `scan-stig.sh` runs it:** 405 pass / 1 fail, the one being the documented exception.

Follow-up (planned): `scan-stig.sh` takes the profile as an argument, defaulting to the image profile for image-built
desktops, so later scans report on the gate's profile directly.
