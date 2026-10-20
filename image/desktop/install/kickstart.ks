# LocumView desktop installation (Anaconda, payload: the LocumView bootc image embedded in the installer ISO by
# bootc-image-builder, which adds the ostreecontainer command itself). Fully unattended; no per-desktop values:
# those come at first boot through cloud-init (image/desktop/provision/).
#
# Disk: one LUKS2 volume holding LVM, so everything but /boot and /boot/efi is encrypted (HIPAA 164.312(a)(2)(iv)),
# with the separate file systems the DISA STIG asks for (partition_for_*; /tmp is a tmpfs). /var/tmp is 8 GiB:
# bootc unpacks local image archives there (changelog #52). /home is /var/home on bootc systems.
#
# @LUKS_INSTALL_PASSPHRASE@ is replaced by build-installer-iso.sh with a random value for each ISO and not kept.
# %post binds the volume to the vTPM (clevis, PCR 7 = Secure Boot state), so it unlocks without a prompt; first
# boot adds the desktop's recovery passphrase from SOPS and removes this one.
text
# A text install would otherwise set the installed system's default target to multi-user (no GDM, no headless
# sessions); found on lv-test01.
xconfig --startxonboot
lang en_US.UTF-8
keyboard us
timezone America/New_York --utc
network --bootproto=dhcp --activate
rootpw --lock
zerombr
clearpart --all --initlabel --disklabel=gpt
reqpart --add-boot
part pv.01 --size=1 --grow --encrypted --luks-version=luks2 --passphrase=@LUKS_INSTALL_PASSPHRASE@
volgroup lv pv.01
logvol /              --vgname=lv --name=root   --size=20480 --fstype=xfs
logvol /var           --vgname=lv --name=var    --size=10240 --fstype=xfs
logvol /var/log       --vgname=lv --name=log    --size=4096  --fstype=xfs
logvol /var/log/audit --vgname=lv --name=audit  --size=4096  --fstype=xfs
logvol /var/tmp       --vgname=lv --name=vartmp --size=8192  --fstype=xfs
reboot

# No --log: Anaconda then shows this section's output in its error dialog if it fails.
# blkid, not lsblk: lsblk needs the udev database, which the installer's chroot lacks.
# clevis takes its options only before the pin: "-k -" placed after "tpm2 CFG" is ignored, and clevis then
# prompts and fails on end of input (found 2026-10-19).
%post --erroronfail
set -euo pipefail
dev=$(blkid -t TYPE=crypto_LUKS -o device | head -n 1)
[ -n "$dev" ] || { echo "no LUKS device found"; exit 1; }
# vTPM dictionary-attack limits: the default (3 failures, 1000 s each to expire) counts every unclean shutdown
# as a failure, so three forced stops lock the TPM and the disk asks for a passphrase (lv-test01).
tpm2_dictionarylockout --clear-lockout
tpm2_dictionarylockout --setup-parameters --max-tries=32 --recovery-time=300 --lockout-recovery-time=300
printf '%s' '@LUKS_INSTALL_PASSPHRASE@' | clevis luks bind -y -k - -d "$dev" tpm2 '{"pcr_ids":"7"}'
clevis luks list -d "$dev"
%end
