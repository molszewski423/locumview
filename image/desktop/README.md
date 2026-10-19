# LocumView desktop image (bootc)

Version-one item 1 (ADR 0007, ADR 0009): the desktop built as a RHEL 10 image-mode (bootc) container image from a Containerfile, and provisioned from a clean clone with zero manual steps. **Status: builds (first image 2026-10-19), not booted yet.** This directory replaces, step by step, the scripts the hand-built reference desktop was made with (build log #11 to #36, then `hardening/stig/apply-stig.sh`).

## What goes where

| Today (scripts on a running VM) | In the image | At provisioning, per desktop |
|---|---|---|
| Workstation environment and the 5 add-on groups (`docs/evidence/phase1/baseline`) | Containerfile step 1 | |
| `packaging/install-desktop.sh`: extensions (RPM, pinned downloads, our three), Papirus, logo, wallpapers, GDM logo, LocumView Tour, dconf defaults, keymap, layout (mac, locked), clipboard policy | Step 2: the same script with `LV_IMAGE_BUILD=1`, installing under `/usr` | |
| Logo and hidden GNOME Tour via `/usr/local/share` in `XDG_DATA_DIRS` | `/usr/share/locumview/override` first in `XDG_DATA_DIRS` (`/usr/lib/environment.d/50-locumview.conf`) | |
| Flatpaks (Extensions, ONLYOFFICE) installed by the script | `locumview-flatpaks.service`, first boot | Installed on first boot |
| Headless session restart drop-in (`user-mode-root.sh`) | `/usr/lib/systemd/system/gnome-headless-session@.service.d/` | |
| DISA STIG through Ansible, VM profile | Step 4: `oscap-im` with the image profile `xccdf_org.locumview_profile_stig_gui_image` | |
| FIPS: not possible after install | `fips=1` in `/usr/lib/bootc/kargs.d/`, FIPS crypto policy from the image profile | |
| Separate `/tmp`, `/var`, `/var/log`, `/var/log/audit`, `/var/tmp` | | Installer disk layout |
| Disk encryption: none (HIPAA gap) | | LUKS bound to the vTPM at install |
| firewalld zone for the k3s nodes, demo egress fence (`user-mode-root.sh`, `demo-user-root.sh`) | | Rendered from site values |
| Hostname, IdM enrollment (one-time password), `lvadmin` password, GRUB password | | Provisioning, from SOPS |
| Per-user headless session and RDP credentials and TLS certificate (`user-mode-user.sh`); the demo user | | Provisioning, from SOPS |

Why `/usr` and not `/usr/local`: in a bootc system `/usr/local` is a link into `/var`, and `/var` is written once at installation and never updated by image upgrades. Anything that must change with the image lives in `/usr` (read-only at run time) or `/etc` (merged on upgrade).

## Building

The base image and the RHEL repositories need Red Hat credentials:

- `podman login registry.redhat.io` with a registry service account (https://access.redhat.com/terms-based-registry/).
- On a host that is not a subscribed RHEL system, an activation key as a build secret. `build/rhsm.sh` registers the build container for the package steps only and unregisters it again; the key is never written to a layer.

```
podman build --secret id=rhsm,src=$HOME/.config/locumview/rhsm.env \
  -f image/desktop/Containerfile -t <registry>/locumview/desktop:dev .
```

## Open (in order)

1. ~~First build; pin the base image by digest.~~ Done 2026-10-19 (changelog #51). Left: clear the `bootc container lint` warnings (content in `/var` from the package and authselect steps).
2. Boot it on libvirt (bootc-image-builder or Anaconda with `ostreecontainer`) and compare it with the hand-built desktop: packages, branding, extensions, the layout lock, Flatpaks on first boot.
3. Check `oscap-im` results inside the image, and FIPS with RDP sign-in through Guacamole (NLA uses NTLM, which FIPS does not allow).
4. Provisioning code: disk layout with the separate file systems and LUKS on the vTPM; firewall and demo fence from site values; IdM enrollment, RDP credentials and break-glass passwords from SOPS. Check that `ipa-client-install` keeps the STIG's authselect profile (`custom/hardening` with `with-sudo`) instead of selecting `sssd` again.
5. Registry (Gitea's container registry), signing (cosign) and an SBOM (syft); CI builds the image.
6. Proof: destroy the desktop, rebuild it from a clean clone, rerun the STIG and HIPAA scans.
