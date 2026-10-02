#!/bin/bash
# Phase 1 baseline capture, rebuilt locumview-ref-dev (2026-10-01). Same commands as the original baseline/.
set -uo pipefail
OUT=/home/molszewski/Projects/locumview/docs/evidence/phase1/baseline-rebuild-20261001
U=molszewski
install -d -o $U -g $U "$OUT"; cd "$OUT"
update-crypto-policies --show                         > crypto-policy.txt
systemctl get-default                                 > default-target.txt
dnf history list 2>&1                                 > dnf-history.txt
systemctl list-unit-files --state=enabled             > enabled-units.txt
firewall-cmd --list-all-zones                         > firewalld.txt
sudo -u $U dnf group list --installed 2>&1            > groups.txt
rpm -qa --qf "%{NAME}\n" | sort -u                    > packages.txt
rpm -Va 2>&1                                          > rpm-verify.txt
getenforce                                            > selinux.txt
{ cat /etc/redhat-release; uname -r; echo "secureboot: $(mokutil --sb-state)";
  echo "tpm: $(ls /dev/tpm0 /dev/tpmrm0 | tr "\n" " ")"; echo "firmware: $([ -d /sys/firmware/efi ] && echo UEFI || echo BIOS)";
  echo "cpu: $(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2-)"; } > system.txt
chown $U:$U *; ls -la
