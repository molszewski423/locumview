"""Where load.py writes: the local spike (clinical/spike/run.sh, rootless podman) or the clinical namespace
(k8s/clinical, kubectl). Both are reached the same way, so a load on the spike tests the cluster path too:

- SQL runs inside the database container, with that container's own root password.
- OpenEMR's API is called from inside the OpenEMR container (api.php below), with the administrator credentials in
  that container's environment (OE_USER, OE_PASS).

No credential reaches the machine running the loader, and nothing is printed but API responses. For the length of a
load, a loader API client is registered and enabled and the password grant is on; afterwards the client is deleted,
the grant is restored to its previous value and the helper directory (with the client secret) is removed.
"""
from contextlib import contextmanager
import json
import shlex
import subprocess

CLIENT = "LocumView Scenario Loader"
DIR = "/tmp/lv-loader"
DB_SQL = ["sh", "-c", 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot --batch openemr']
CONTAINERS = {
    "spike": (["podman", "exec", "-i", "openemr-spike-db"], ["podman", "exec", "-i", "openemr-spike-openemr"]),
    "cluster": (["kubectl", "exec", "-i", "-n", "clinical", "mariadb-0", "-c", "mariadb", "--"],
                ["kubectl", "exec", "-i", "-n", "clinical", "deploy/openemr", "-c", "openemr", "--"]),
}
API_PHP = r"""<?php
// LocumView scenario loader (clinical/scenarios/targets.py): OpenEMR API calls from inside the OpenEMR container.
// The administrator's credentials come from this container's environment and never leave it; the loader's client
// secret stays in this directory (mode 0700) until the load ends and the directory is removed.
//   api.php register <client name> <scopes>     register the loader's client
//   api.php call <method> <path>                one API call (path under /apis/default/), request body on stdin
$base = 'http://localhost';
function http($method, $url, $body, $headers) {
    $c = curl_init($url);
    curl_setopt_array($c, [CURLOPT_CUSTOMREQUEST => $method, CURLOPT_RETURNTRANSFER => true,
                           CURLOPT_HTTPHEADER => $headers, CURLOPT_TIMEOUT => 60]);
    if ($body !== null && $body !== '') {
        curl_setopt($c, CURLOPT_POSTFIELDS, $body);
    }
    $out = curl_exec($c);
    if ($out === false) {
        fwrite(STDERR, 'request failed: ' . curl_error($c) . "\n");
        exit(1);
    }
    return [curl_getinfo($c, CURLINFO_RESPONSE_CODE), $out];
}
$mode = $argv[1] ?? '';
if ($mode === 'register') {
    [$status, $out] = http('POST', "$base/oauth2/default/registration", json_encode([
        'application_type' => 'private', 'client_name' => $argv[2], 'redirect_uris' => ["$base/"],
        'token_endpoint_auth_method' => 'client_secret_post', 'scope' => $argv[3]]), ['Content-Type: application/json']);
    $client = json_decode($out, true);
    if ($status !== 200 || empty($client['client_id'])) {
        fwrite(STDERR, "registration failed: HTTP $status\n");
        exit(1);
    }
    umask(077);
    file_put_contents(__DIR__ . '/client.json', json_encode(['client_id' => $client['client_id'],
        'client_secret' => $client['client_secret'], 'scope' => $argv[3]]));
    exit(0);
}
if ($mode === 'call') {
    $client = json_decode(file_get_contents(__DIR__ . '/client.json'), true);
    [$status, $out] = http('POST', "$base/oauth2/default/token", http_build_query([
        'grant_type' => 'password', 'user_role' => 'users', 'username' => getenv('OE_USER'),
        'password' => getenv('OE_PASS'), 'scope' => $client['scope'], 'client_id' => $client['client_id'],
        'client_secret' => $client['client_secret']]), ['Content-Type: application/x-www-form-urlencoded']);
    if ($status !== 200) {
        fwrite(STDERR, "token request failed: HTTP $status: " . substr($out, 0, 300) . "\n");
        exit(1);
    }
    $token = json_decode($out, true)['access_token'];
    $type = str_starts_with($argv[3], 'fhir/') ? 'application/fhir+json' : 'application/json';
    [$status, $out] = http(strtoupper($argv[2]), "$base/apis/default/{$argv[3]}", stream_get_contents(STDIN),
                           ["Authorization: Bearer $token", "Content-Type: $type", "Accept: $type"]);
    echo json_encode(['status' => $status, 'body' => $out]), "\n";
    exit(0);
}
fwrite(STDERR, "usage: api.php register <name> <scopes> | call <method> <path>\n");
exit(1);
"""


def quote(value):
    return "'" + str(value).replace("\\", "\\\\").replace("'", "''") + "'"


class Target:
    def __init__(self, name):
        self.name = name
        self.db, self.emr = CONTAINERS[name]

    def sql(self, statement):
        """Run SQL in the database container; returns the result rows (tab-separated, header removed)."""
        out = subprocess.run(self.db + DB_SQL, input=statement, text=True, capture_output=True, check=True).stdout
        rows = [line.split("\t") for line in out.splitlines()]
        return rows[1:] if rows else []

    def install(self, name, source):
        """Put a file into the helper directory in the OpenEMR container, owned by the web server user."""
        path = f"{DIR}/{name}"
        script = (f"install -d -o apache -m 0700 {DIR} && cat > {path} && chown apache {path} && chmod 0600 {path}")
        subprocess.run(self.emr + ["sh", "-c", script], input=source, text=True, check=True)
        return path

    def php(self, path, *args, stdin=""):
        """Run a PHP file as the web server user (as OpenEMR itself runs), keeping the container's environment."""
        command = "exec php " + " ".join(shlex.quote(a) for a in (path, *args))
        return subprocess.run(self.emr + ["su", "-s", "/bin/sh", "apache", "-c", command], input=stdin, text=True,
                              capture_output=True)

    def api(self, method, path, body=None):
        """Authorized call; path starts with 'fhir/' or 'api/'. Returns (status, parsed JSON or raw text)."""
        done = self.php(f"{DIR}/api.php", "call", method, path, stdin="" if body is None else json.dumps(body))
        if done.returncode:
            raise SystemExit(f"{method} {path}: {done.stderr.strip()[-400:]}")
        reply = json.loads(done.stdout.strip().splitlines()[-1])
        try:
            return reply["status"], json.loads(reply["body"])
        except ValueError:
            return reply["status"], reply["body"]

    @contextmanager
    def session(self, scopes):
        """A loader API client and the password grant, for the length of one load."""
        off = [name for name, value in self.sql(
            "SELECT gl_name, gl_value FROM globals WHERE gl_name IN ('rest_api', 'rest_fhir_api');") if value != "1"]
        if off:
            raise SystemExit(f"OpenEMR's API is off ({', '.join(off)}); on the cluster, run "
                             "scripts/clinical/register-gateway.sh first")
        grant = self.sql("SELECT gl_value FROM globals WHERE gl_name = 'oauth_password_grant';")
        previous = grant[0][0] if grant else "0"
        self.install("api.php", API_PHP)
        try:
            self.sql(f"DELETE FROM oauth_clients WHERE client_name = {quote(CLIENT)};\n"
                     "UPDATE globals SET gl_value = '1' WHERE gl_name = 'oauth_password_grant';")
            done = self.php(f"{DIR}/api.php", "register", CLIENT, scopes)
            if done.returncode:
                raise SystemExit(f"loader client: {done.stderr.strip()[-400:]}")
            # As an administrator approving the client (Administration > System > API Clients).
            self.sql(f"UPDATE oauth_clients SET is_enabled = 1 WHERE client_name = {quote(CLIENT)};")
            yield self
        finally:
            self.sql(f"DELETE FROM oauth_clients WHERE client_name = {quote(CLIENT)};\n"
                     f"UPDATE globals SET gl_value = {quote(previous)} WHERE gl_name = 'oauth_password_grant';")
            subprocess.run(self.emr + ["rm", "-rf", DIR], check=True)
