# Runbooks

Routine operator procedures. Emergency access is in [break-glass.md](break-glass.md). Commands are bash, run from the
repo root on the owner's machine (it holds the SOPS age key); `kubectl` needs a cluster context.

## Rotate the shared demo password

The guest demo is one shared Keycloak account, `demo` (password only, no MFA, no self-service; changelog #22). The
privacy policy commits to rotating its password **after each evaluation**. Per-evaluator accounts with an expiry date
are on the backlog for when real evaluators exist.

1. **Check nobody is mid-session.** Signing out Keycloak sessions does not close an open desktop connection
   (Guacamole never expires a session that has one), so look first:
   `kubectl -n locumview exec guacamole-db-0 -c postgres -- psql -U postgres -d guacamole -Atc "select username, start_date from guacamole_connection_history where end_date is null"`
   If `demo` is listed, wait, or end it from Guacamole's admin view (Settings, Active Sessions).
2. **Generate the new password straight into SOPS**, never displayed: word-word-number, at least 14 characters
   (realm policy), not derived from the product name.
   ```bash
   pw=$(printf '%s-%s-%s' $(grep -E '^[a-z]{5,8}$' /usr/share/dict/words | shuf -n2 --random-source=/dev/urandom) $(shuf -i 10-99 -n1 --random-source=/dev/urandom))
   sops set k8s/locumview/secrets/demo-login.sops.yaml '["stringData"]["password"]' "\"$pw\""; unset pw
   ```
3. **Set it in Keycloak** (permanent, group and no-self-service kept), then **sign out every demo session**:
   ```bash
   x() { sops -d --extract "[\"stringData\"][\"$1\"]" k8s/locumview/secrets/demo-login.sops.yaml; }
   { printf 'USERNAME=demo\nFIRST=Demo\nLAST=Guest\nEMAIL=demo@locumview.com\nUSER_GROUPS=locumview-demo\nPERMANENT_PASSWORD=1\nNO_SELF_SERVICE=1\nTMP_PASSWORD=%q\n' "$(x password)"
     cat k8s/locumview/keycloak/create-user.sh; } | kubectl -n locumview exec -i deploy/keycloak -- bash -s
   kubectl -n locumview exec deploy/keycloak -- bash -c 'k() { /opt/keycloak/bin/kcadm.sh "$@" --config /tmp/k.cfg; }
     k config credentials --server http://localhost:8080 --realm master --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null
     id=$(k get users -r locumview -q exact=true -q username=demo --fields id --format csv --noquotes)
     k create "users/$id/logout" -r locumview && k get "users/$id/credentials" -r locumview --fields type,createdDate; rm -f /tmp/k.cfg'
   ```
   The credential's `createdDate` should be now.
4. **Apply the Secret** so the cluster copy matches git: `sops -d k8s/locumview/secrets/demo-login.sops.yaml | kubectl apply -f -`.
   Commit the re-encrypted file.
5. **Hand over** the new password to the next evaluator out of band, without displaying it, e.g.
   `sops -d --extract '["stringData"]["password"]' k8s/locumview/secrets/demo-login.sops.yaml | wl-copy -o`.
6. **Record** the rotation (date, reason) in the changelog or the day's worklog.
