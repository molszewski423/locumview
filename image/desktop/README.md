# LocumView desktop image (bootc)

Version-one item 1 (ADR 0007, ADR 0009): the desktop built as a RHEL 10 image-mode (bootc) container image from a Containerfile, and provisioned from a clean clone with zero manual steps. **Status: builds, boots (UEFI Secure Boot, vTPM, the STIG's separate file systems) and updates in place with `bootc upgrade`; provisioning code not written yet.** No FIPS mode (ADR 0012). This directory replaces, step by step, the scripts the hand-built reference desktop was made with (build log #11 to #36, then `hardening/stig/apply-stig.sh`).

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

```
podman build --secret id=rhsm,src=$HOME/.config/locumview/rhsm.env \
  -f image/desktop/Containerfile -t <registry>/locumview/desktop:dev .
```

## Open (in order)

1. ~~First build; pin the base image by digest.~~ Done (changelog #51). Left: clear the `bootc container lint` warnings (content in `/var` from the package and authselect steps).
2. ~~Boot it on libvirt and compare it with the hand-built desktop.~~ Done (changelog #52): booted from a bootc-image-builder qcow2 with Secure Boot and a vTPM; FIPS, SELinux, services, branding, layout lock, Flatpaks on first boot, 0 SELinux or fapolicyd denials; updated in place with `bootc switch` and `bootc upgrade`; STIG 402 pass / 4 fail (GRUB password, test account). Not yet looked at: the GNOME session itself over RDP through Guacamole.
3. ~~Check FIPS with RDP sign-in.~~ Done: fails, so no FIPS mode (ADR 0012).

Findings for the provisioning layout: `/var/tmp` needs more than 2 GiB (bootc unpacks local image archives there); the libvirt NAT network needed a host firewall rule on node1 for DHCP and DNS.
4. Provisioning code: disk layout with the separate file systems and LUKS on the vTPM; firewall and demo fence from site values; IdM enrollment, RDP credentials and break-glass passwords from SOPS. Check that `ipa-client-install` keeps the STIG's authselect profile (`custom/hardening` with `with-sudo`) instead of selecting `sssd` again.
5. Registry (Gitea's container registry), signing (cosign) and an SBOM (syft); CI builds the image.
6. Proof: destroy the desktop, rebuild it from a clean clone, rerun the STIG and HIPAA scans.
