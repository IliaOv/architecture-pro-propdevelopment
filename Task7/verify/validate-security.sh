#!/usr/bin/env bash
# Проверка состояния Pod Security Admission и OPA Gatekeeper.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK7_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
NS="audit-zone"
ERRORS=0

log_ok() { echo "[OK] $*"; }
log_fail() { echo "[FAIL] $*" >&2; ERRORS=$((ERRORS + 1)); }

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl не найден" >&2
  exit 1
fi

echo "==> Pod Security labels на namespace ${NS}"
if kubectl get namespace "${NS}" >/dev/null 2>&1; then
  ENFORCE="$(kubectl get namespace "${NS}" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}')"
  if [[ "${ENFORCE}" == "restricted" ]]; then
    log_ok "enforce=restricted"
  else
    log_fail "ожидался enforce=restricted, получено: ${ENFORCE:-<пусто>}"
  fi
else
  log_fail "namespace ${NS} не найден — примените 01-create-namespace.yaml"
fi

echo "==> Gatekeeper"
if kubectl get deployment -n gatekeeper-system gatekeeper-controller-manager >/dev/null 2>&1; then
  READY="$(kubectl get deployment -n gatekeeper-system gatekeeper-controller-manager -o jsonpath='{.status.readyReplicas}')"
  if [[ "${READY:-0}" -ge 1 ]]; then
    log_ok "gatekeeper-controller-manager готов (${READY} replica)"
  else
    log_fail "Gatekeeper deployment не готов"
  fi
else
  log_fail "Gatekeeper не установлен (namespace gatekeeper-system)"
  echo "  Установка: kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/v3.14.0/deploy/gatekeeper.yaml"
fi

echo "==> ConstraintTemplates"
for ct in k8sdenyprivileged k8sdenyhostpath k8srequiresecuritycontext; do
  if kubectl get constrainttemplate "${ct}" >/dev/null 2>&1; then
    log_ok "ConstraintTemplate ${ct}"
  else
    log_fail "ConstraintTemplate ${ct} отсутствует"
  fi
done

echo "==> Constraints"
check_constraint() {
  local kind="$1" name="$2"
  if kubectl get "${kind}" "${name}" >/dev/null 2>&1; then
    log_ok "Constraint ${name} (${kind})"
  else
    log_fail "Constraint ${name} отсутствует — примените gatekeeper/constraints/"
  fi
}
check_constraint k8sdenyprivileged deny-privileged-containers
check_constraint k8sdenyhostpath deny-hostpath-volumes
check_constraint k8srequiresecuritycontext require-nonroot-readonly-rootfs

echo "==> Статус ограничений"
kubectl get constraints 2>/dev/null || true

echo "==> Dry-run небезопасных манифестов (ожидается отказ)"
for manifest in "${TASK7_DIR}"/insecure-manifests/*.yaml; do
  name="$(basename "${manifest}")"
  if kubectl apply -f "${manifest}" --dry-run=server >/dev/null 2>&1; then
    log_fail "${name}: dry-run=server прошёл (должен быть отказ)"
  else
    log_ok "${name}: отклонён при dry-run=server"
  fi
done

echo ""
if [[ "${ERRORS}" -gt 0 ]]; then
  echo "Обнаружено ошибок: ${ERRORS}" >&2
  exit 1
fi
echo "Валидация безопасности пройдена."
