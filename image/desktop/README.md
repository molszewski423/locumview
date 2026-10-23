# LocumView desktop image (bootc)

Version-one item 1 (ADR 0007, ADR 0009): the desktop built as a RHEL 10 image-mode (bootc) container image from a Containerfile, and provisioned from a clean clone with zero manual steps. **Status: builds, boots (UEFI Secure Boot, vTPM, the STIG's separate file systems), updates in place with `bootc upgrade`, installs and provisions itself from an ISO with no manual steps on the VM (changelog #53), and accepts only updates signed with the project key (changelog #58).** No FIPS mode (ADR 0012). This directory replaces, step by step, the scripts the hand-built reference desktop was made with (build log #11 to #36, then `hardening/stig/apply-stig.sh`).

## What goes where

| Today (scripts on a running VM) | In the image | At provisioning, per desktop |
|---|---|---|
| Workstation environment and the 5 add-on groups (`docs/evidence/phase1/baseline`) | Containerfile step 1 | |
| `packaging/install-desktop.sh`: extensions (RPM, pinned downloads, our three), Papirus, logo, wallpapers, GDM logo, LocumView Tour, dconf defaults, keymap, layout (mac, locked), clipboard policy | Step 2: the same script with `LV_IMAGE_BUILD=1`, installing under `/usr` | |
| Logo and hidden GNOME Tour via `/usr/local/share` in `XDG_DATA_DIRS` | `/usr/share/locumview/override` first in `XDG_DATA_DIRS` (`/usr/lib/environment.d/50-locumview.conf`) | |
| Flatpaks (Extensions, ONLYOFFICE) installed by the script | `locumview-flatpaks.service`, first boot | Installed on first boot |
| Headless session restart drop-in (`user-mode-root.sh`) | `/usr/lib/systemd/system/gnome-headless-session@.service.d/` | |
| DISA STIG through Ansible, VM profile | Step 4: `oscap-im` with the image profile `xccdf_org.locumview_profile_stig_gui_image`; step 5 for what it cannot do at build time (`/etc/skel` modes, chrony `server` lines); `/var/log/faillock` from tmpfiles.d so it gets its SELinux label | |
| FIPS mode | **Not enabled** (ADR 0012): GNOME Remote Desktop's RDP sign-in needs NTLM, which FIPS mode disables | |
| Separate `/tmp`, `/var`, `/var/log`, `/var/log/audit`, `/var/tmp` | | Installer disk layout |
| Disk encryption: none (HIPAA gap) | | LUKS bound to the vTPM at install |
| firewalld zone for the k3s nodes, demo egress fence (`user-mode-root.sh`, `demo-user-root.sh`) | | Rendered from site values |
| Hostname, IdM enrollment (one-time password), `lvadmin` password, GRUB password | | Provisioning, from SOPS |
| Per-user headless session and RDP credentials and TLS certificate (`user-mode-user.sh`); the demo user | | Provisioning, from SOPS |

Why `/usr` and not `/usr/local`: in a bootc system `/usr/local` is a link into `/var`, and `/var` is written once at installation and never updated by image upgrades. Anything that must change with the image lives in `/usr` (read-only at run time) or `/etc` (merged on upgrade).

## Building

The base image and the RHEL repositories need Red Hat credentials:

- `podman login registry.redhat.io` with a registry service account (https://access.redhat.com/terms-based-registry/).
- On a host that is not a subscribed RHEL system, an activation key as a build secret. `scripts/rhsm.sh` registers the build container for the package steps only and unregisters it again; the key is never written to a layer.

The four LocumView RPMs must already be published at the exact version selected from the image commit. See
[RPM version selection](../../packaging/rpm/README.md#pinning-rpms-to-an-image-commit). Supply the registry's public
CA as a build secret as well as the owner's Red Hat registration secret. Run from a clean committed checkout.

```fish
set -l rpm_evr (python3 packaging/rpm/resolve-version.py | python3 -c 'import json,sys; print(json.load(sys.stdin)["evr"])')
podman build --network host --secret id=rhsm,src=<owner-provided-rhsm-file> \
  --secret id=lanca,src=<registry-ca-file> --build-arg LOCUMVIEW_RPM_EVR=$rpm_evr \
  -f image/desktop/Containerfile -t <registry>/locumview/desktop:dev .
```

## Registry and signing

CI builds the image on every change to `image/`, `packaging/` or `hardening/` (`.gitea/workflows/image.yml`), on a dedicated runner on node2: a host-mode act_runner as an unprivileged user with rootless podman, registered to this repository only. It first scans the image against the image STIG profile, inside the image (`hardening/stig/scan-image.sh`): a failure the image alone can judge stops the build, and the rules only an installed desktop can judge (kernel parameters, boot arguments, partitions, services) are listed in `hardening/stig/image-scan-runtime-only.txt`. It then pushes `git.lan/mike/locumview-desktop:<commit>` and `:testing`, signs the pushed digest with cosign, generates an SPDX SBOM with syft (packages and their relationships; the per-file listing is left out, since it would exceed the 128 MiB attestation size cosign reads back) and attaches it and the scan summary as signed attestations, then verifies all three. Signing is offline: no public transparency log, so nothing about the image leaves the site. Verify with the committed public key:

```
cosign verify --key image/desktop/signing/cosign.pub --insecure-ignore-tlog git.lan/mike/locumview-desktop@<digest>
cosign verify-attestation --key image/desktop/signing/cosign.pub --insecure-ignore-tlog --type spdxjson git.lan/mike/locumview-desktop@<digest>
cosign verify-attestation --key image/desktop/signing/cosign.pub --insecure-ignore-tlog --type https://locumview.org/attestations/image-stig-scan/v1 git.lan/mike/locumview-desktop@<digest>
```

**Promotion.** Desktops follow `:stable`, which only the promote workflow (`.gitea/workflows/promote.yml`, run by hand) moves: it verifies the signature, the SBOM and a passing scan on the digest, then points `:stable` at the same manifest, byte for byte (`scripts/registry-tag.py`), and prints the previous `:stable` digest for a rollback. A build reaches desktops only after someone has tried `:testing` and promoted it.

The private key and its password are Actions secrets, with a SOPS backup in `signing/cosign.sops.yaml`.

## Default apps

Each default app is a slot: the image fills it with LocumView's default, and a deployment can fill it with the customer's standard instead (ADR 0016 for the browsers).

| Slot | Default | Source | Swappable for |
|---|---|---|---|
| System browser | Firefox ESR, with enterprise policies following the DISA Firefox STIG (hardening/browser/) | Red Hat's Flatpak remote (registered desktops); Mozilla's Firefox from Flathub otherwise | |
| EHR browser | Google Chrome in app mode (the "EHR" launcher, pinned first in the dock): DISA Chrome STIG policies, only the EHR's sites allowed (ADR 0016, hardening/browser/) | Google's RPM repository, in the image, checked against Google's pinned key | Microsoft Edge, EPEL Chromium, or the customer's standard browser |
| Office | ONLYOFFICE | Flathub, first boot | The customer's office suite |
| Files, calculator | GNOME Files, Calculator | RHEL (AppStream) | |
| Extensions manager | GNOME Extensions | Flathub, first boot | |

## Installing and provisioning

`install/build-installer-iso.sh` (root) turns the image into an installer ISO: Anaconda with `install/kickstart.ks`, which lays out the STIG's separate file systems on LVM inside LUKS2 and binds the LUKS volume to the TPM (clevis, PCR 7), so the desktop unlocks at boot with no prompt. The kickstart holds a random one-time LUKS passphrase made for each ISO build, so the ISO is kept private (mode 0600) and first-boot provisioning removes that key slot.

`hypervisor/new-desktop.sh <name>` (node1, group libvirt) installs a desktop from that ISO with a NoCloud seed disk attached and waits for first boot to finish. The per-desktop values come on its stdin, one `KEY=VALUE` per line, normally straight from SOPS:

| Key | What it is |
|---|---|
| `LV_FQDN` | Host name in the IdM domain (cloud-init sets it from the seed's meta-data) |
| `IDM_DOMAIN`, `IDM_REALM`, `IDM_SERVER` | The IdM domain, realm and server |
| `IDM_OTP` | One-time enrollment password from `ipa host-add <fqdn> --random` (not kept in SOPS) |
| `LVADMIN_PASSWORD` | Break-glass local administrator `lvadmin` |
| `GRUB_PASSWORD` | GRUB superuser `lvgrub` |
| `LUKS_RECOVERY_PASSPHRASE` | The disk's recovery passphrase, used if the TPM cannot unlock it |
| `K3S_NODE_CIDRS`, `DNS_IP` | Sources allowed to reach RDP, SSH and Cockpit (the k3s nodes); the DNS server the demo fence allows |
| `DESKTOP_USER`, `DESKTOP_RDP_USER`, `DESKTOP_RDP_PASSWORD` | The desktop's IdM user and the RDP credentials guacd uses for that user's session (port 3390) |
| `DEMO_RDP_USER`, `DEMO_RDP_PASSWORD` | Optional: the demo (guest) session on 3391, with the egress fence |
| `TIMEZONE` | The desktop's time zone (IANA name; the site value, default `America/New_York`) |
| `UPDATE_IMAGE`, `REGISTRY_CA_B64`, `REGISTRY_PULL_USER`, `REGISTRY_PULL_TOKEN` | Optional: track the signed image in the registry for updates (the image, the registry's CA in base64, a read-only pull token) |
| `RHSM_ORG`, `RHSM_ACTIVATION_KEY` | Optional: register the desktop with Red Hat under its host name (support, compliance, Red Hat's Flatpak remote) |

On the desktop, `locumview-provision.service` (`/usr/libexec/locumview/provision`) reads that file straight from the read-only seed (cloud-init only reads the hostname, so no secret is copied to `/var/lib/cloud`) and, once:

1. Checks the hostname and sets the time zone (the image ships none, and the kickstart's `timezone` does not reach an image-mode install).
2. Sets the vTPM's dictionary-attack limits (32 failures, each expiring after 5 minutes; also set by the kickstart), adds the recovery passphrase to LUKS and removes every key slot except the TPM's and the recovery one. The TPM default (3 failures, about 17 minutes each) counts every unclean shutdown as a failure: three forced stops locked a test desktop's TPM, and it asked for the disk passphrase at boot.
3. Creates `lvadmin` (in `wheel`).
4. Sets the GRUB password with superuser `lvgrub`. bootc boots from bootupd's static `/boot/grub2/grub.cfg`, whose users block names `root`; the name is changed in place.
5. Ignores DNS servers from IPv6 router advertisements (changelog #15).
5b. Registers with Red Hat if the seed has an activation key. `locumview-flatpaks.service` runs after provisioning: registered desktops get Red Hat's Firefox ESR through the image's preinstall declaration (`redhat-flatpak-preinstall-firefox`, as the RHEL installer does on a conventional install); others get Mozilla's Firefox from Flathub.
6. Joins IdM with the one-time password, then selects `custom/hardening` again (with `with-faillock`, `without-nullok`, `with-sudo`, `with-mkhomedir`), because `ipa-client-install` switches to the stock `sssd` profile.
6b. Puts back the STIG settings that enrollment and first boot change: `GSSAPIAuthentication no` in `ipa-client-install`'s sshd drop-in, `offline_credentials_expiration = 1` in the `sssd.conf` it rewrites, and the SSH host keys (created at first boot) as `root:root` 0600 (changelog #59).
7. Opens RDP, SSH and Cockpit to the k3s nodes only (`locumview-gateways` zone).
8. Starts the user's always-on headless session with user-mode GNOME Remote Desktop and its RDP credentials.
9. Optionally sets up the demo user.
10. Builds the AIDE database, last, after every other change (about 13 minutes on a test VM). The image's own database is in `/var`, which an installation does not carry over (changelog #59). After an image update, AIDE reports the new `/usr` until `aide --update`.

With `UPDATE_IMAGE`, provisioning also makes the desktop track that image and accept only images from its repository signed with the key in `/usr/share/locumview/signing/cosign.pub` (a `sigstoreSigned` rule in `/etc/containers/policy.json`, sigstore attachments in `registries.d`, `bootc switch --enforce-container-sigpolicy`). The policy's default becomes `reject`, which bootc requires before it enforces signatures: Red Hat's registries keep their own signature rules, images already on the machine stay usable, and pulls from any other registry are refused on a desktop. CI signs in cosign's classic format (`.sig` tags), the one RHEL's container tools read. The switch takes effect at the next reboot.

### Background updates stage only

The image ships a vendor service drop-in at
`/usr/lib/systemd/system/bootc-fetch-apply-updates.service.d/20-locumview-stage-only.conf`. It resets the inherited
`ExecStart` and uses `/usr/bin/bootc upgrade`, without `--apply`. The vendor timer keeps its schedule, but its
job only downloads and stages an update. It does not initiate a reboot. The drop-in waits for the first-boot
provisioning service and requires its success marker before an automatic update can start.

On the tested bootc 1.16.4, a staged update becomes the booted image at the next reboot. This includes an
unexpected reboot: the policy prevents the update job from requesting a reboot, not other causes of reboot.
The operator inspects `bootc status` and schedules the restart. `--download-only` is deliberately not used,
because it requires a separate apply action before a reboot can activate the downloaded image. Upstream:
[bootc upgrade](https://bootc.dev/bootc/man/bootc-upgrade.8.html).

Existing local masks in `/etc/systemd/system` remain in force. In particular, the live demo's containment mask
is not removed by this image change. No fleet-wide unmask or restart is part of building or promoting an image.
Other local service overrides can take precedence too; inspect the effective unit before enabling staging.
An operator may also leave the timer masked and run `bootc upgrade` manually in a maintenance window.

After building this change, verify it on a disposable desktop before enabling the timer anywhere else:

- The booted image contains the drop-in; the effective service has one `ExecStart`, `bootc upgrade`, with no
  `--apply`, and preserves the vendor's `/run/ostree-booted` condition.
- First-boot provisioning completes before automatic staging. No timer override removes its conditions.
- With a separately approved newer signed candidate, start the update service as an owner run. Confirm the
  newer digest is staged while boot ID, booted digest and session uptime stay unchanged. A successful service
  invocation alone, with no newer image, does not prove staging behavior.
- Perform an operator-approved reboot and verify that exact staged digest boots, rollback exists and no units
  failed. Check the timer mask and effective service again. A live-demo mask stays until a separate owner decision.

The controlled service staging and planned-reboot checks passed on a disposable desktop on 2026-10-23:
[evidence](../../docs/evidence/update-policy/20261023/README.md). The timer remained masked and the service was
started explicitly; timer expiry and deliberate failure of the provisioning guard were not separately tested.
Current desktops adopt this policy only after booting an image containing it; their existing masks remain.

Every step is safe to repeat; the service runs on each boot until it succeeds. When it succeeds it ejects the seed, which is the script's signal to detach and wipe it. On failure the seed stays attached: `journalctl -u locumview-provision` on the desktop.

## Open (in order)

1. ~~First build; pin the base image by digest.~~ Done (changelog #51). Left: clear the `bootc container lint` warnings (content in `/var` from the package and authselect steps).
2. ~~Boot it on libvirt and compare it with the hand-built desktop.~~ Done (changelog #52): booted from a bootc-image-builder qcow2 with Secure Boot and a vTPM; FIPS, SELinux, services, branding, layout lock, Flatpaks on first boot, 0 SELinux or fapolicyd denials; updated in place with `bootc switch` and `bootc upgrade`; STIG 402 pass / 4 fail (GRUB password, test account). Not yet looked at: the GNOME session itself over RDP through Guacamole.
3. ~~Check FIPS with RDP sign-in.~~ Done: fails, so no FIPS mode (ADR 0012).

Findings for the provisioning layout: `/var/tmp` needs more than 2 GiB (bootc unpacks local image archives there); the libvirt NAT network needed a host firewall rule on node1 for DHCP and DNS.
4. ~~Provisioning code.~~ Done (changelog #53): installer ISO, first-boot provisioning, `hypervisor/new-desktop.sh`. Left: SOPS file per desktop and the Guacamole connection upsert in the operator script; system-mode RDP on 3389 for the GDM sign-in; GNOME Remote Desktop's credential store (key file, it cannot use the vTPM).
5. ~~Registry (Gitea's container registry), signing (cosign) and an SBOM (syft); CI builds the image.~~ Done (changelog #57, #58): CI builds, signs and attests the image; desktops accept only images signed with the project key.
6. ~~Proof: destroy the desktop, rebuild it from a clean clone, rerun the STIG and HIPAA scans.~~ Done (changelog #59): rebuilt from a clean clone and destroyed with nothing left behind; image STIG profile 405 pass / 0 fail, HIPAA 119 / 37 (docs/evidence/stig/20261020-image, 20261020-hipaa). Version-one item 1 is done.
