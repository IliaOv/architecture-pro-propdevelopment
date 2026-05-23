#!/usr/bin/env bash
# Проверка: небезопасные поды отклоняются, безопасные — принимаются.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK7_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
NS="audit-zone"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl не найден" >&2
  exit 1
fi

echo "==> Namespace и Pod Security"
kubectl apply -f "${TASK7_DIR}/01-create-namespace.yaml"

echo "==> Gatekeeper: шаблоны и ограничения"
kubectl apply -f "${TASK7_DIR}/gatekeeper/constraint-templates/"
sleep 5
kubectl apply -f "${TASK7_DIR}/gatekeeper/constraints/"

FAILED_INSECURE=0
PASSED_INSECURE=0

echo "==> Небезопасные манифесты (ожидается отказ)"
for manifest in "${TASK7_DIR}"/insecure-manifests/*.yaml; do
  name="$(basename "${manifest}")"
  echo "--- ${name}"
  if kubectl apply -f "${manifest}" --dry-run=server 2>/dev/null; then
    echo "ОШИБКА: ${name} прошёл dry-run=server, ожидался отказ" >&2
    PASSED_INSECURE=$((PASSED_INSECURE + 1))
  else
    echo "OK: ${name} отклонён"
    FAILED_INSECURE=$((FAILED_INSECURE + 1))
  fi
done

SECURE_OK=0
SECURE_FAIL=0

echo "==> Безопасные манифесты (ожидается успех)"
for manifest in "${TASK7_DIR}"/secure-manifests/*.yaml; do
  name="$(basename "${manifest}")"
  echo "--- ${name}"
  if kubectl apply -f "${manifest}"; then
    echo "OK: ${name} принят"
    SECURE_OK=$((SECURE_OK + 1))
  else
    echo "ОШИБКА: ${name} отклонён" >&2
    SECURE_FAIL=$((SECURE_FAIL + 1))
  fi
done

echo ""
echo "Итог:"
echo "  Небезопасные отклонены: ${FAILED_INSECURE}/3 (приняты ошибочно: ${PASSED_INSECURE})"
echo "  Безопасные приняты:     ${SECURE_OK}/3 (отклонены ошибочно: ${SECURE_FAIL})"

if [[ "${PASSED_INSECURE}" -gt 0 || "${SECURE_FAIL}" -gt 0 ]]; then
  exit 1
fi

echo "Проверка admission пройдена."
