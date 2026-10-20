# Infrastructure with OpenTofu

ADR 0013: OpenTofu creates and removes the infrastructure around each desktop; the desktop itself is the bootc image in `image/desktop/` (ADR 0007).

- `modules/libvirt-desktop/`: one desktop on libvirt. IdM host entry with a one-time enrollment password and host group membership; desktop disk and seed volumes; the seed (built by `scripts/seed.sh`, never through cloud-init's user-data); the VM (q35, UEFI with Secure Boot, SMM, vTPM, LAN bridge, installer ISO); and a wait until first-boot provisioning ejects the seed, after which the seed volume is wiped (`scripts/wait-provisioned.sh`).
- `node1/`: the root configuration for the reference hypervisor. Desktops are listed in `desktops.auto.tfvars`; their secrets are in `desktops/<name>.sops.yaml`; site values are in `site.auto.tfvars` (git-ignored, see the example file). State and plan files are encrypted (OpenTofu state encryption, enforced).

## Requirements

On the operator machine: OpenTofu 1.10 or later, `sops` with the age key (ADR 0003), `virsh` and `xorriso`, SSH access to node1 as a user in group libvirt, and the IdM CA certificate. On node1: the installer ISO (`image/desktop/install/build-installer-iso.sh`) and the storage pool.

## Use

```
cd terraform/node1
cp site.auto.tfvars.example site.auto.tfvars      # fill in
./secrets.sh state                                # once: the state passphrase, into SOPS
./secrets.sh desktop <name>                       # per desktop: break-glass, GRUB, LUKS recovery, RDP
#   add  <name> = { user = "<idm user>" }  to desktops.auto.tfvars
./tofu.sh init
./tofu.sh apply                                   # asks for the IdM password; ~6 minutes per desktop
./tofu.sh destroy                                 # removes the VMs, their volumes and IdM host entries
```

`tofu.sh` decrypts the state passphrase from SOPS and asks for the IdM password; neither is written to disk. `secrets.sh` pipes generated values straight into `sops --encrypt`, so it works with the public key alone.

## Notes

- Disks are attached by file path, not as pool volumes: on hosts that confine guests with AppArmor (Debian), libvirt's profile helper only adds file paths, and a pool volume fails at start with "Permission denied".
- The libvirt provider does not remove a domain whose first start failed; it stays defined in libvirt but not in the state. Undefine it (`virsh undefine <name> --nvram --tpm`) before applying again.
- The libvirt and FreeIPA providers are not signed in the OpenTofu registry. Their hashes in `node1/.terraform.lock.hcl` were checked against the checksums published with each GitHub release.
- Verified on node1 (changelog #54): install and provisioning in 5.5 minutes, a second plan with no changes, and a destroy that removed every resource.
