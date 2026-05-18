#!/usr/bin/env bash
# Шаг 3: привязка групп пользователей к ролям
set -euo pipefail
export PATH="${HOME}/bin:/c/Program Files/Docker/Docker/resources/bin:${PATH}"

DIR="$(cd "$(dirname "$0")" && pwd)/users"

kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: propdev-security-binding
subjects:
  - kind: Group
    name: propdev-security
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: propdev-security-admin
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: propdev-viewers-binding
subjects:
  - kind: Group
    name: propdev-viewers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: propdev-cluster-viewer
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: propdev-platform-binding
subjects:
  - kind: Group
    name: propdev-platform
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: propdev-platform-engineer
  apiGroup: rbac.authorization.k8s.io
EOF

echo "Проверка прав:"
if [[ ! -s "$DIR/ca.crt" ]]; then
  echo "Пересоздайте пользователей: ./create-users.sh (ca.crt пустой)" >&2
  exit 1
fi
cd "$DIR"
kubectl --kubeconfig=ivan.security.kubeconfig auth can-i list secrets --all-namespaces
kubectl --kubeconfig=maria.viewer.kubeconfig auth can-i list pods --all-namespaces
kubectl --kubeconfig=alex.platform.kubeconfig auth can-i create deployments -n propdev-sales

echo "Готово: группы привязаны к ClusterRole"
