#!/usr/bin/env bash
# Print a kubeconfig for the scoped locumview-operator account (k8s/locumview/operator.yaml) on stdout. Run where
# kubectl has cluster-admin; send it straight to the operator machine, never to a file in the repository:
#   ./operator-kubeconfig.sh | ssh <operator> 'umask 077; mkdir -p ~/.kube; cat > ~/.kube/locumview-operator.yaml'
set -euo pipefail
server=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
ca=$(kubectl -n locumview get secret locumview-operator-token -o jsonpath='{.data.ca\.crt}')
token=$(kubectl -n locumview get secret locumview-operator-token -o jsonpath='{.data.token}' | base64 -d)
[ -n "$token" ] || { echo "no token in locumview-operator-token yet" >&2; exit 1; }
cat <<KC
apiVersion: v1
kind: Config
clusters:
  - name: locumview
    cluster:
      server: $server
      certificate-authority-data: $ca
users:
  - name: locumview-operator
    user:
      token: $token
contexts:
  - name: locumview-operator
    context:
      cluster: locumview
      user: locumview-operator
      namespace: locumview
current-context: locumview-operator
KC
