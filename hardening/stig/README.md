# DISA STIG hardening

Version-one item 3 (ADR 0009): the DISA STIG profile applied to the LocumView desktop, an OpenSCAP report committed, and every exception written down. This directory holds the tailoring and the two scripts that apply and check it. The same tailoring file is meant for `oscap-im` in the bootc image build (ADR 0007), so the hardening is written once.

| File | What it is |
|---|---|
| `locumview-stig-gui-tailoring.xml` | XCCDF tailoring of `xccdf_org.ssgproject.content_profile_stig_gui` (DISA STIG with GUI for RHEL 10, scap-security-guide 0.1.82). Profile ID `xccdf_org.locumview_profile_stig_gui`. |
| `apply-stig.sh` | Generates the Ansible remediation from the tailoring on the target (so it matches the installed SSG), then runs `pre-authselect.yml` and that playbook from the operator's machine. Asks for the target's sudo password once. |
| `pre-authselect.yml` | Works around an SSG authselect problem that removes sudo for directory users (below). |
| `scan-stig.sh` | Read-only scan against the tailoring; fetches the HTML report, ARF results and pass/fail list. |

`stig_gui` is used rather than `stig`: the plain profile is for servers without a graphical target and would flag GNOME itself.

## Running it

```
hardening/stig/apply-stig.sh <user>@<ref-dev-ip>     # about 25 minutes, idempotent apart from a few SSG tasks that always report "changed"
hardening/stig/scan-stig.sh  <user>@<ref-dev-ip>     # about 5 minutes
```

The user needs sudo on the target (an IdM administrator works). Take a snapshot first. A reboot is needed afterwards for the kernel arguments, the immutable audit rules and the `/home` mount options. Run logs and scan output are written to the current directory and are git-ignored because they contain addresses.

Four STIG items are not automated by SSG and were done by hand on the reference desktop (changelog #47): the GRUB superuser name (`lvgrub`, in `/etc/grub.d/01_users`) and its password (`grub2-setpassword`; normal boots stay unattended), `pam_wheel.so use_uid` in `/etc/pam.d/su`, chrony `server` lines instead of `pool`, and re-setting local passwords so they are stored as SHA-512 (RHEL 10 defaults to yescrypt). In the bootc image these become part of the Containerfile.

## Tailoring: what is not applied, and why

| Rules | Decision | Reason |
|---|---|---|
| `sysctl_crypto_fips_enabled`, `configure_crypto_policy`, the four `harden_sshd_{ciphers,macs}_{openssh,opensshserver}_conf_crypto_policy` rules | **Deferred to the bootc image** | RHEL 10 can only enable FIPS mode at install time. The four SSH rules check for the FIPS-only cipher and MAC lists, which come with the FIPS policy. `var_system_crypto_policy` is set to `DEFAULT` until then, because `crypto_policy_not_overridden` re-applies whatever that variable says. Risk to test with FIPS: RDP sign-in (NLA) uses NTLM, which FIPS does not allow. |
| `partition_for_tmp`, `partition_for_var`, `partition_for_var_log`, `partition_for_var_log_audit`, `partition_for_var_tmp` | **Deferred to the bootc image** | Needs a new disk layout; the image's layout will provide them. |
| `sssd_enable_smartcards`, `sssd_enable_certmap`, `sssd_certificate_verification`, `dconf_gnome_lock_screen_on_smartcard_removal` | **Exception** | Multi-factor authentication is Keycloak TOTP at the access layer (ADR 0005). No smartcard reaches a desktop over RDP. |
| `rsyslog_remote_loghost`, `rsyslog_remote_access_monitoring` | **Exception, open item** | No central log server yet. Logs stay local (auditd, journald). |
| `network_configure_name_resolution` | **Exception, open item** | One resolver, the network's DNS server, which also holds the internal names. A second resolver comes with the IdM replica on node2. |
| `selinux_context_elevation_for_sudo` | **Deferred** | Confined administrators (`sysadm_r`) need IdM SELinux user maps; planned with the IdM password-policy work. |
| `no_files_unowned_by_user`, `file_permissions_ungroupowned` | **False positive** | The OVAL check reads only `/etc/passwd` and `/etc/group`, so every file owned by an IdM user counts as unowned. Checked instead with `find / -xdev \( -nouser -o -nogroup \)`, which resolves owners through NSS (SSSD): no results on 2026-10-19. |

### Values changed

- `var_accounts_authorized_local_users_regex`: the default list lacks `gnome-remote-desktop` and other accounts present on the image. That rule has no automated fix in SSG 0.1.82, but the check would fail and a hand fix following it would remove the RDP service account. The list here is every system account on the image plus `lvadmin` (local break-glass) and `demo`.
- Login banner: "Authorized users only. All activity may be monitored and reported." instead of the U.S. Government consent text. SSG 0.1.82 has two variables per banner: `*_banner_text` is the regex the check uses, `*_banner_contents` is the text the remediation writes. Both pairs are set.

## SSG problem: authselect and sudo

Several SSG 0.1.82 remediations create the authselect profile `custom/hardening` and run `authselect select custom/hardening` **without the current features**, then try to restore the features with sudo. Dropping `with-sudo` removes SSSD from `sudoers` in `nsswitch.conf`, so an IdM administrator loses sudo at that point, the restore step fails, and the run stops halfway ("is not in the sudoers file"). `pre-authselect.yml` selects `custom/hardening` itself with the same features (`with-sudo`, `with-mkhomedir` and the rest) before the SSG playbook runs, and the SSG tasks then skip their own `select`. Found 2026-10-17; the reference desktop was reverted to its `pre-stig` snapshot and the run repeated with the fix.

## What users and administrators notice

- Login screen and SSH show the banner; GDM has no user list (type the user name); restart and shutdown are not offered at the login screen.
- The screen blanks and locks after 10 minutes idle, and users cannot change that. **Exception, not visible to the scanner:** the guest demo account keeps its own user-level `org.gnome.desktop.lockdown disable-lock-screen=true` (changelog #22; guests know no Linux password), which the STIG settings do not lock, so its session blanks but never locks. The scan checks only the system dconf database. Idle logout for the demo is still the open ROADMAP item.
- `sudo` asks for the password every time.
- **Three wrong passwords within 15 minutes lock the account on that desktop until an administrator unlocks it** (pam_faillock, `unlock_time=0`, as the STIG requires). This applies to IdM users too, at the login screen, the lock screen and sudo. Unlock: `faillock --user <name> --reset` as root, from another administrator's session, `lvadmin`, or the VM console (`virsh console`). IdM has its own, separate lockout.
- New local passwords: 15 or more characters, all four character classes, no more than 4 characters of one class in a row, 60-day maximum age. IdM passwords follow the IdM password policy (open item).
- `/home` is `noexec`, and **fapolicyd** allows only files that RPM installed to run or to be loaded by interpreters. Installed Flatpaks and the GNOME extensions work. `pip install --user`, scripts in a home directory and similar developer tools do not. The reference desktop is no longer a development machine; development happens on the dev laptops (ADR 0009).
- New packages and services: AIDE (check weekly, Sunday 04:05, mailed to root), auditd with the STIG rule set, fapolicyd, USBGuard (policy generated from the devices present at install), postfix for local mail to root. Removed: tuned, gssproxy (and nfs-utils, which depends on it), unbound (and `ipa-client-encrypted-dns`, unused).
- Kernel arguments: `audit=1 audit_backlog_limit=8192 init_on_free=1 page_poison=1 pti=on vsyscall=none`.

## Results

| Scan | Profile | Pass | Fail | Evidence |
|---|---|---|---|---|
| Baseline, 2026-10-17, before any change | `stig_gui` (untailored) | 164 | 271 | `docs/evidence/stig/20261017-baseline/` |
| Baseline, 2026-10-17 | `hipaa` | 38 | 121 | same directory |
| After remediation, 2026-10-19 | LocumView tailoring (before the two false-positive rules were deselected) | 417 | 2 | `docs/evidence/stig/20261019-tailored/` |

The two remaining failures are the false positives above; with the current tailoring the result is 0 failures. Committed reports have the desktop's addresses replaced by placeholders. The full ARF result files (about 60 MB each) are not committed.
