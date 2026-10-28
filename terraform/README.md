# Infrastructure with OpenTofu

ADR 0013: OpenTofu creates and removes the infrastructure around each desktop; the desktop itself is the bootc image in `image/desktop/` (ADR 0007).

- `modules/libvirt-desktop/`: one desktop on libvirt. IdM host entry with a one-time enrollment password and host group membership; desktop disk and seed volumes; the seed (built by `scripts/seed.sh`, never through cloud-init's user-data); the VM (q35, UEFI with Secure Boot, SMM, vTPM, LAN bridge, installer ISO); and a wait until first-boot provisioning ejects the seed, after which the seed volume is wiped (`scripts/wait-provisioned.sh`).
- `node3/`: the same for node3, operator-laptop kept running as a second hypervisor (changelog #99). Same module and the same IdM, RHSM and registry secrets (symlinks to `node1/`), its own state and desktop list; OpenTofu runs on node3 itself (`libvirt_uri = "qemu:///system"`). Host prep: `hypervisor/node3-host.sh`.
- `node1/`: the root configuration for the reference hypervisor. Desktops are listed in `desktops.auto.tfvars`; their secrets are in `desktops/<name>.sops.yaml`; site values are in `site.auto.tfvars` (git-ignored, see the example file). State and plan files are encrypted (OpenTofu state encryption, enforced).

## Requirements

On the operator machine: OpenTofu 1.10 or later, `sops` with the age key (ADR 0003), `virsh`, `xorriso` and `kubectl`, SSH access to node1 as a user in group libvirt, and the IdM CA certificate (`k8s/locumview/keycloak/idm-ca.pem`). On node1: the installer ISO (`image/desktop/install/build-installer-iso.sh`) and the storage pool.

One-time setup:
- `node1/idm-account.sh <ssh-user>@<idm-server>` (asks for the IdM admin password once): IdM account `svc-opentofu` with hosts, host groups and DNS privileges only, its password into `idm.sops.yaml`; dynamic DNS updates and a 60-second negative-caching time for the zone.
- `node1/rhsm-secrets.sh` (once): the Red Hat organization, activation key and subscription API offline token into `rhsm.sops.yaml`. Desktops then register under their host name, and `modules/libvirt-desktop/scripts/rhsm-systems.sh` removes the registration before a desktop is created and after it is destroyed, so test desktops do not use up a subscription that counts systems (`rhsm-systems.sh list` shows what is registered).
- `node1/operator-kubeconfig.sh | ssh <operator> 'umask 077; cat > ~/.kube/locumview-operator.yaml'` (where kubectl has cluster-admin): a kubeconfig for `locumview-operator`, which can only exec into the Guacamole database pod (`k8s/locumview/operator.yaml`). Set its path as `guacamole_kubeconfig`.

## Use

```
cd terraform/node1
cp site.auto.tfvars.example site.auto.tfvars      # fill in
./secrets.sh state                                # once: the state passphrase, into SOPS
./secrets.sh desktop <name>                       # per desktop: break-glass, GRUB, LUKS recovery, RDP
#   add  <name> = { user = "<idm user>" }  to desktops.auto.tfvars
./tofu.sh init
./tofu.sh apply                                   # nothing to type; ~6 minutes per desktop
./tofu.sh destroy                                 # removes the VMs, their volumes and IdM host entries
```

`tofu.sh` decrypts the state passphrase and the IdM account's password from SOPS; neither is written to disk. Each desktop gets a Guacamole connection by host name (the desktop registers itself in IdM DNS at enrollment), granted to the user groups in `guacamole_groups` (default `locumview-admins`) and labelled `guacamole_name` (default: the desktop's name); destroy removes it and keeps the session history. `secrets.sh` pipes generated values straight into `sops --encrypt`, so it works with the public key alone.

## Notes

- Disks are attached by file path, not as pool volumes: on hosts that confine guests with AppArmor (Debian), libvirt's profile helper only adds file paths, and a pool volume fails at start with "Permission denied".
- The libvirt provider does not remove a domain whose first start failed; it stays defined in libvirt but not in the state. Undefine it (`virsh undefine <name> --nvram --tpm`) before applying again.
- The libvirt and FreeIPA providers are not signed in the OpenTofu registry. Their hashes in `node1/.terraform.lock.hcl` were checked against the checksums published with each GitHub release.
- Verified on node1 (changelog #54) and from the operator machine with SOPS (changelog #55): install and provisioning in 5.5 minutes, a second plan with no changes, and a destroy that removed every resource.
