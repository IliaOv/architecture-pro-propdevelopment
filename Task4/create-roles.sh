#!/usr/bin/env bash
# Шаг 1: namespace и RBAC-роли (см. Шаблон_проектная_работа_5спринт.md)
set -euo pipefail
export PATH="${HOME}/bin:/c/Program Files/Docker/Docker/resources/bin:${PATH}"

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: propdev-sales
---
apiVersion: v1
kind: Namespace
metadata:
  name: propdev-hcs
---
apiVersion: v1
kind: Namespace
metadata:
  name: propdev-finance
---
apiVersion: v1
kind: Namespace
metadata:
  name: propdev-data
---
# propdev-security-admin — просмотр secrets и аудит
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: propdev-security-admin
rules:
  - apiGroups: [""]
    resources: ["secrets", "pods", "pods/log", "events", "namespaces", "services", "configmaps", "nodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps", "networking.k8s.io", "rbac.authorization.k8s.io"]
    resources: ["deployments", "statefulsets", "ingresses", "roles", "rolebindings", "clusterroles", "clusterrolebindings"]
    verbs: ["get", "list", "watch"]
---
# propdev-cluster-viewer — только чтение, без secrets
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: propdev-cluster-viewer
rules:
  - apiGroups: ["", "apps", "batch", "networking.k8s.io"]
    resources: ["pods", "services", "configmaps", "events", "namespaces", "deployments", "ingresses", "jobs"]
    verbs: ["get", "list", "watch"]
---
# propdev-platform-engineer — управление нагрузками во всех NS
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: propdev-platform-engineer
rules:
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["", "apps", "networking.k8s.io", "batch"]
    resources: ["pods", "services", "configmaps", "deployments", "ingresses", "jobs"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
EOF

# propdev-domain-operator / propdev-domain-viewer — в каждом домене
for ns in propdev-sales propdev-hcs propdev-finance propdev-data; do
  kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: propdev-domain-operator
  namespace: $ns
rules:
  - apiGroups: ["", "apps", "networking.k8s.io"]
    resources: ["pods", "services", "configmaps", "deployments", "ingresses"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: propdev-domain-viewer
  namespace: $ns
rules:
  - apiGroups: ["", "apps", "networking.k8s.io"]
    resources: ["pods", "services", "configmaps", "deployments", "ingresses"]
    verbs: ["get", "list", "watch"]
EOF
done

echo "Готово: namespace и роли propdev-*"
kubectl get clusterrole | grep propdev || true
