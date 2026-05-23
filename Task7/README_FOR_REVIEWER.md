# Задание 7 — Аудит и соответствие политике безопасности контейнеров

## Цель

Продемонстрировать работу **Pod Security Admission** (уровень `restricted`) и **OPA Gatekeeper** на namespace `audit-zone`: небезопасные поды отклоняются, исправленные — проходят.

## Структура

| Путь | Назначение |
|------|------------|
| `01-create-namespace.yaml` | Namespace `audit-zone` с метками Pod Security `restricted` |
| `insecure-manifests/` | Три пода с нарушениями (privileged, hostPath, UID 0) |
| `secure-manifests/` | Исправленные манифесты |
| `gatekeeper/` | ConstraintTemplate + Constraint |
| `audit-policy.yaml` | Политика аудита API для `audit-zone` и Gatekeeper |
| `verify/` | Скрипты проверки |

## Предварительные требования

- Kubernetes 1.25+ (встроенный Pod Security Admission)
- `kubectl` с доступом к кластеру
- Установленный [OPA Gatekeeper](https://open-policy-agent.github.io/gatekeeper/website/docs/install/) (например v3.14):

```bash
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/v3.14.0/deploy/gatekeeper.yaml
kubectl wait --for=condition=Available deployment/gatekeeper-controller-manager -n gatekeeper-system --timeout=120s
```

## Порядок применения

```bash
cd Task7

# 1. Namespace с Pod Security restricted
kubectl apply -f 01-create-namespace.yaml

# 2. Gatekeeper: шаблоны, затем ограничения
kubectl apply -f gatekeeper/constraint-templates/
sleep 5   # дождаться CRD от ConstraintTemplate
kubectl apply -f gatekeeper/constraints/

# 3. Проверка отказов (ожидается ошибка для каждого)
kubectl apply -f insecure-manifests/01-privileged-pod.yaml
kubectl apply -f insecure-manifests/02-hostpath-pod.yaml
kubectl apply -f insecure-manifests/03-root-user-pod.yaml

# 4. Безопасные поды (ожидается успех)
kubectl apply -f secure-manifests/
```

## Политики Gatekeeper

| Правило | ConstraintTemplate | Constraint |
|---------|-------------------|------------|
| `privileged: true` запрещён | `k8sdenyprivileged` | `deny-privileged-containers` |
| `hostPath` запрещён | `k8sdenyhostpath` | `deny-hostpath-volumes` |
| `runAsNonRoot: true` и `readOnlyRootFilesystem: true` | `k8srequiresecuritycontext` | `require-nonroot-readonly-rootfs` |

Ограничения действуют только в namespace `audit-zone`.

## Нарушения в insecure-manifests

1. **01-privileged-pod.yaml** — `securityContext.privileged: true`
2. **02-hostpath-pod.yaml** — volume `hostPath` на `/tmp`
3. **03-root-user-pod.yaml** — `runAsUser: 0`, `runAsNonRoot: false`

## Исправления в secure-manifests

- Без privileged и hostPath; вместо hostPath — `emptyDir`
- `runAsNonRoot: true`, `runAsUser: 101` (nginx)
- `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`
- `seccompProfile: RuntimeDefault`
- Дополнительные `emptyDir` для `/tmp`, `/var/cache/nginx`, `/var/run` (требование read-only root)

## Автоматическая проверка

```bash
chmod +x verify/*.sh
./verify/validate-security.sh   # состояние PSA и Gatekeeper
./verify/verify-admission.sh    # отказ insecure + успех secure
```

## Audit policy

Файл `audit-policy.yaml` подключается на control plane (флаги `kube-apiserver`):

```text
--audit-policy-file=/etc/kubernetes/audit-policy.yaml
--audit-log-path=/var/log/kubernetes/audit/audit.log
```

В лог попадают создание/изменение подов в `audit-zone` и изменения Constraint/ConstraintTemplate.

## Ожидаемый результат

- `kubectl apply -f insecure-manifests/` → **Forbidden** (Pod Security и/или Gatekeeper)
- `kubectl apply -f secure-manifests/` → поды создаются
- `kubectl get constraints` — ограничения в статусе без ошибок синхронизации
