#!/usr/bin/env bash
# Шаг 2: клиентские сертификаты и kubeconfig (нужен запущенный minikube).
set -euo pipefail

export MSYS2_ARG_CONV_EXCL='*'
export PATH="${HOME}/bin:/c/Program Files/Docker/Docker/resources/bin:${PATH}"

BASE="$(cd "$(dirname "$0")" && pwd)"
DIR="$BASE/users"

if [[ -e "$DIR" && ! -d "$DIR" ]]; then
  echo "Ошибка: $DIR — это файл. Удалите: rm $DIR" >&2
  exit 1
fi
mkdir -p "$DIR"
cd "$DIR"

# CA minikube (kubectl config view иногда отдаёт пустой CA в Git Bash)
if [[ -s "${HOME}/.minikube/ca.crt" ]]; then
  cp "${HOME}/.minikube/ca.crt" ca.crt
else
  kubectl config view --raw --flatten --minify \
    -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d >ca.crt
fi
[[ -s ca.crt ]] || { echo "Ошибка: нет CA. Запустите: minikube start" >&2; exit 1; }

SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CLUSTER=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')

for pair in \
  "ivan.security:propdev-security" \
  "maria.viewer:propdev-viewers" \
  "alex.platform:propdev-platform"
do
  user="${pair%%:*}"
  group="${pair##*:}"
  echo ">>> $user ($group)"

  openssl genrsa -out "${user}.key" 2048

  cat >"${user}.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
[dn]
CN = ${user}
O = ${group}
EOF
  openssl req -new -key "${user}.key" -out "${user}.csr" -config "${user}.cnf"

  kubectl delete csr "$user" --ignore-not-found >/dev/null 2>&1 || true
  REQ=$(base64 <"${user}.csr" | tr -d '\n')
  cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: $user
spec:
  request: $REQ
  signerName: kubernetes.io/kube-apiserver-client
  usages: [client auth]
EOF

  kubectl certificate approve "$user"
  kubectl get csr "$user" -o jsonpath='{.status.certificate}' | base64 -d >"${user}.crt"

  # относительные пути: Windows-kubectl не читает /c/Users/...
  kubectl config set-cluster "$CLUSTER" --server="$SERVER" \
    --certificate-authority=ca.crt --embed-certs=true --kubeconfig="${user}.kubeconfig"
  kubectl config set-credentials "$user" \
    --client-certificate="${user}.crt" --client-key="${user}.key" \
    --embed-certs=true --kubeconfig="${user}.kubeconfig"
  kubectl config set-context "${user}@${CLUSTER}" --cluster="$CLUSTER" \
    --user="$user" --kubeconfig="${user}.kubeconfig"
  kubectl config use-context "${user}@${CLUSTER}" --kubeconfig="${user}.kubeconfig"
done

echo "Готово: $DIR/*.kubeconfig"
