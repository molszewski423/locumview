#!/usr/bin/env bash
# Owner run (operator-laptop): create or update OpenEMR's shared demo login (changelog #178).
#   scripts/clinical/openemr-demo-user.sh            create the SOPS file if it is missing, then set the user from it
#   scripts/clinical/openemr-demo-user.sh --rotate   generate a new password first (after each evaluation)
#
# The user is `demo`, shown as Guest Pharmacist: not an administrator, access group Physicians (the clinical app's
# reads need its patients/med rights, changelog #119), provider type pharmacist, the facility the administrator uses.
# The password is word-word-number with capitals (Maple-Harbor-47), which meets OpenEMR's secure_password rule (a
# lowercase letter, an uppercase letter, a number and a special character) and is easy to share. It is generated
# straight into k8s/clinical/secrets/openemr-demo.sops.yaml and reaches the OpenEMR pod on stdin; it is never shown,
# never in an argument and never in a file in plain text. No workload reads the SOPS file; it is the record to share
# from. After a rotation, save a new baseline (k8s/clinical/reset.yaml), or the nightly reset brings the old one back.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
out=k8s/clinical/secrets/openemr-demo.sops.yaml
rotate=0
case "${1:-}" in
  --rotate) rotate=1 ;;
  "") ;;
  *) echo "usage: $0 [--rotate]" >&2; exit 2 ;;
esac

if [[ ! -e "$out" || $rotate == 1 ]]; then
  [[ -r /usr/share/dict/words ]] || { echo "needs a word list at /usr/share/dict/words (package: words)" >&2; exit 1; }
  umask 077
  python3 -I -c '
import re, secrets
words = sorted({w.strip() for w in open("/usr/share/dict/words") if re.fullmatch(r"[a-z]{5,8}", w.strip())})
pw = "-".join(secrets.choice(words).capitalize() for _ in range(2)) + "-" + str(secrets.randbelow(90) + 10)
print("apiVersion: v1\nkind: Secret\nmetadata:\n  name: openemr-demo\n  namespace: clinical\n  annotations:\n"
      "    locumview.org/purpose: Shareable password of the OpenEMR demo user (non-admin). Not used by any workload.\n"
      "type: Opaque\nstringData:\n  username: demo\n  password: \"" + pw + "\"")
' | sops encrypt --filename-override "$out" --input-type yaml --output-type yaml /dev/stdin > "$out.tmp"
  grep -q 'ENC\[' "$out.tmp" || { echo "encryption check failed" >&2; rm -f "$out.tmp"; exit 1; }
  mv "$out.tmp" "$out"
  echo "wrote $out (encrypted; the password is never shown). Commit it."
fi

read -r -d '' PHP <<'EOF' || true
<?php
// Creates or updates OpenEMR's demo user with OpenEMR's own hashing and access control (changelog #178). The password
// arrives on stdin; nothing here prints it.
$_GET['site'] = 'default';
$ignoreAuth = true;
require_once '/var/www/localhost/htdocs/openemr/interface/globals.php';

use OpenEMR\Common\Acl\AclExtended;
use OpenEMR\Common\Auth\AuthHash;
use OpenEMR\Common\Uuid\UuidRegistry;

$pw = rtrim((string) stream_get_contents(STDIN), "\r\n");
foreach (['/[a-z]/', '/[A-Z]/', '/\d/', '/[\W_]/'] as $rule) {
    if (!preg_match($rule, $pw)) {
        fwrite(STDERR, "the password does not meet OpenEMR's secure_password rule\n");
        exit(1);
    }
}
if (strlen($pw) < 9) {
    fwrite(STDERR, "the password is shorter than OpenEMR's minimum\n");
    exit(1);
}
$hash = (new AuthHash())->passwordHash($pw);
$pw = '';
if (empty($hash)) {
    fwrite(STDERR, "OpenEMR could not hash the password\n");
    exit(1);
}

$user = sqlQuery("SELECT id FROM users WHERE username = 'demo'");
if (empty($user)) {
    $admin = sqlQuery("SELECT facility, facility_id FROM users WHERE username = 'admin'");
    $id = sqlInsert(
        "INSERT INTO users (uuid, username, password, fname, lname, authorized, active, facility, facility_id," .
        " billing_facility, billing_facility_id, physician_type, calendar, see_auth, main_menu_role," .
        " patient_menu_role, portal_user, cal_ui, info)" .
        " VALUES (?, 'demo', 'NoLongerUsed', 'Guest', 'Pharmacist', 0, 1, ?, ?, ?, ?, 'pharmacist', 0, 1," .
        " 'standard', 'standard', 0, 1, 'Shared demo login (LocumView changelog #178); reset nightly')",
        [UuidRegistry::getRegistryForTable('users')->createUuid(), $admin['facility'], $admin['facility_id'],
         $admin['facility'], $admin['facility_id']]
    );
    privStatement(
        "INSERT INTO users_secure (id, username, password, last_update_password) VALUES (?, 'demo', ?, NOW())",
        [$id, $hash]
    );
    sqlStatement("INSERT INTO `groups` SET name = 'Default', user = 'demo'");
    if (!AclExtended::setUserAro(['Physicians'], 'demo', 'Guest', '', 'Pharmacist')) {
        fwrite(STDERR, "the user was created but its access group could not be set\n");
        exit(1);
    }
    echo "created the demo user\n";
} else {
    // A reset of the password history too: the demo password is shared, and history only blocks a rotation.
    privStatement(
        "UPDATE users_secure SET password = ?, last_update_password = NOW(), password_history1 = NULL, " .
        "password_history2 = NULL, password_history3 = NULL, password_history4 = NULL, login_fail_counter = 0 " .
        "WHERE username = 'demo'",
        [$hash]
    );
    sqlStatement("UPDATE users SET active = 1 WHERE username = 'demo'");
    echo "updated the demo user's password\n";
}

$groups = AclExtended::aclGetGroupTitles('demo');
if ($groups !== ['Physicians']) {
    fwrite(STDERR, "unexpected access groups for demo: " . json_encode($groups) . "\n");
    exit(1);
}
echo "demo: access group Physicians only, not an administrator\n";
EOF

helper=/tmp/lv-demo-user.php
kubectl -n clinical wait --for=condition=Available deployment/openemr --timeout=60s >/dev/null
printf '%s\n' "$PHP" | kubectl -n clinical exec -i deploy/openemr -c openemr -- \
  sh -c "cat > $helper && chown apache $helper && chmod 0600 $helper"
trap 'kubectl -n clinical exec deploy/openemr -c openemr -- rm -f "$helper" >/dev/null 2>&1 || true' EXIT
sops -d --extract '["stringData"]["password"]' "$out" |
  kubectl -n clinical exec -i deploy/openemr -c openemr -- su -s /bin/sh apache -c "exec php $helper"
