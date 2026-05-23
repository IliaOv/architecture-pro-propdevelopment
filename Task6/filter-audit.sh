#!/usr/bin/env bash

set -euo pipefail

INPUT="${1:-audit.log}"
OUTPUT="${2:-audit-extract.json}"

if [[ ! -f "${INPUT}" ]]; then
  echo "Файл не найден: ${INPUT}" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Требуется jq" >&2
  exit 1
fi

TMP="$(mktemp)"
trap 'rm -f "${TMP}"' EXIT

# 1. Доступ к secrets (get / list)
jq -c 'select(
  .objectRef.resource == "secrets"
  and (.verb == "get" or .verb == "list")
)' "${INPUT}" >> "${TMP}" 2>/dev/null || true

# 2. kubectl exec в поды (subresource exec, verb create)
jq -c 'select(
  .verb == "create"
  and .objectRef.subresource == "exec"
)' "${INPUT}" >> "${TMP}" 2>/dev/null || true

# 3. Привилегированные поды
jq -c 'select(
  .objectRef.resource == "pods"
  and .verb == "create"
  and (.requestObject.spec.containers[]?.securityContext.privileged == true)
)' "${INPUT}" >> "${TMP}" 2>/dev/null || true

# 4. RoleBinding / ClusterRoleBinding с cluster-admin
jq -c 'select(
  (.objectRef.resource == "rolebindings" or .objectRef.resource == "clusterrolebindings")
  and (.verb == "create" or .verb == "update" or .verb == "patch")
  and (.requestObject.roleRef.name == "cluster-admin"
       or .responseObject.roleRef.name == "cluster-admin")
)' "${INPUT}" >> "${TMP}" 2>/dev/null || true

# 5. Удаление / изменение audit-policy (по URI или имени объекта)
grep -i 'audit-policy' "${INPUT}" | jq -c '.' >> "${TMP}" 2>/dev/null || true

# Дополнительный фильтр: impersonation (--as) при чувствительных операциях.
# Может дублировать события из пунктов 1 и 2; дубликаты удаляются по auditID.
jq -c 'select(
  ((.impersonatedUser.username // "") | startswith("system:serviceaccount:"))
  and (.objectRef.resource == "secrets" or .objectRef.subresource == "exec")
)' "${INPUT}" >> "${TMP}" 2>/dev/null || true

if [[ ! -s "${TMP}" ]]; then
  echo '[]' > "${OUTPUT}"
  echo "Подозрительных событий не найдено. Записан пустой ${OUTPUT}" >&2
  exit 0
fi

# Дедупликация по auditID + сортировка по времени → JSON-массив
jq -s 'unique_by(.auditID) | sort_by(.stageTimestamp // .requestReceivedTimestamp // "")' \
   "${TMP}" > "${OUTPUT}"

COUNT="$(jq 'length' "${OUTPUT}")"
echo "Извлечено событий: ${COUNT} → ${OUTPUT}"