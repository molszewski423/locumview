# Break-glass access

Ways back in when the normal path (Keycloak SSO + TOTP, and from changelog #32 on, IdM) is down or broken. Every account here works without IdM. Credentials are named by location only; none are in this file. Created 2026-10-05 (changelog #33). Review it whenever an account or host changes, and test each path at least once a quarter.

| Layer | Account | Defined in | Credential lives in | State | How to use |
|---|---|---|---|---|---|
| Keycloak administration (`master` realm) | `kc-bootstrap` | Keycloak bootstrap environment | Secret `keycloak`, key `bootstrap-admin-password` (`k8s/locumview/secrets/keycloak.sops.yaml`) | Enabled. Local. Brute-force protection (5 failures, temporary lockout). Admin console only through the operator port-forward, never through the tunnel (ADR 0004). | Port-forward Keycloak from a cluster node, sign in to the admin console. Or `kubectl -n locumview exec deploy/keycloak -- /opt/keycloak/bin/kcadm.sh ...` with the bootstrap credentials from the pod environment. |
| Keycloak `locumview` realm | `lv-breakglass` | Local Keycloak user (not federated) | Password: owner's machine (`breakglass.env`, 0600) and `debianbox:~/backups/idm01/breakglass.env.age`; TOTP: authenticator entry "LocumView BREAK-GLASS" | Enabled, group `locumview-admins` (Guacamole admin) | Sign in at login.locumview.com. Works when IdM is down, because local users don't depend on the LDAP provider. The owner's everyday account `molszewski` is an IdM user since 2026-10-05 (#35). |
| Guacamole | `locumadmin` | Guacamole database (replaces the default `guacadmin`) | Secret `guacamole-db` (`guacamole-db.sops.yaml`) | **Disabled** by default | `k8s/locumview/guacamole/break-glass.sh enable`, lower SSO priority through the operator port-forward (see the script header), then `disable` and `kubectl apply -k k8s/locumview` afterwards. Use only when Keycloak is unavailable. |
| Reference desktop `locumview-ref-dev` | `lvadmin` (local, `wheel`) | Local account, created by `packaging/idm/refdev-enroll.sh` | Owner's machine (`breakglass.env`, `LVADMIN_PASSWORD`; rotated 2026-10-05 13:19, #36) | Enabled | GNOME login screen through Guacamole, or SSH from a k3s node. Works when IdM is unreachable. The retired personal `molszewski-legacy` (UID 1000, still `wheel`) is to be locked once its data is confirmed migrated. |
| IdM server `idm01` | `mike` (local, not an IdM user; becomes generic `lvadmin` at the next rebuild) | cloud-init (`hypervisor/idm01/user-data.template`) | SSH keys only: devsuse, MikePC, DevThinkPad; passwordless sudo | Enabled | `ssh mike@192.168.4.47` from one of those machines. |
| IdM directory | Directory Manager (`cn=Directory Manager`) | IdM / 389-ds | `idm-secrets.env` on the owner's machine (0600); age-encrypted copy beside the backup on debianbox | For restore and emergency LDAP repair only | `ipa-restore` asks for it; `ldapmodify -D "cn=Directory Manager" -W`. |
| Hypervisors and cluster | `mike` on mikepc, debianbox | Local accounts | SSH keys; sudo | Enabled | `virsh -c qemu:///system` on mikepc for the VMs (console: `virsh console idm01`); `kubectl` on mikepc. |

## IdM backup and restore

- **Backups:** `ipa-backup` (full, offline: IdM stops for about 20 seconds) on idm01, written to `/var/lib/ipa/backup/ipa-full-<UTC timestamp>/`. Off-host copy, encrypted to the project age key (`.sops.yaml` recipient; private key on DevThinkPad with an offline backup): `debianbox:~/backups/idm01/idm01-<backup>.tar.age`, plus `idm-secrets.env.age` (the passwords a restore needs). First backup: `ipa-full-2026-10-05-04-56-04`, verified by decrypting on DevThinkPad.
- **Make a backup and copy it off-host** (from the owner's machine):
  `ssh mike@192.168.4.47 sudo ipa-backup`, then
  `ssh mike@192.168.4.47 "sudo tar -C /var/lib/ipa/backup -cf - <backup>" | age -r <recipient> | ssh mikepc "ssh debianbox 'umask 077; cat > ~/backups/idm01/idm01-<backup>.tar.age'"`
- **Restore** onto a rebuilt idm01 (same hostname and address, created with `hypervisor/idm01/`, `ipa-server` packages installed, `ipa-server-install` **not** run): decrypt on DevThinkPad (`age -d -i ~/.config/sops/age/keys.txt < file | tar -xf -`), copy the directory to `/var/lib/ipa/backup/` on idm01, run `sudo ipa-restore /var/lib/ipa/backup/<backup>` and give the Directory Manager password.
- **Scheduled (since 2026-10-05, #35):** `idm01-backup.timer` on debianbox runs nightly at 03:30 (up to 5 min random delay, catches up after downtime). It pulls through `idmbackup@idm01`, whose key can only run `/usr/local/sbin/idm-backup-stream` (full `ipa-backup`, tar to stdout, keep the newest 3 on idm01), encrypts with age on arrival and keeps the newest 14 as `debianbox:~/backups/idm01/idm01-full-<UTC>.tar.age`. Check: `systemctl list-timers idm01-backup.timer` and `journalctl -u idm01-backup.service` on debianbox; `journalctl -t idm-backup` on idm01. No alerting on failure yet.
- **Open:** the replica on debianbox (ADR 0006); failure alerting for the backup timer.

## Rules

- People have one personal account each, in IdM (`uid` = first initial + last name, `mail` = `<uid>@locumview.com`). Break-glass accounts are generic and role-named, never personal.
- Break-glass accounts never come from IdM and never depend on it.
- Use one only when the normal path is broken; record the use in the changelog (what, when, why) and disable or re-secure it afterwards.
- When a break-glass credential is used or exposed, rotate it.
