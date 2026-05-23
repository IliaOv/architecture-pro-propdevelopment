# Отчёт по результатам анализа Kubernetes Audit Log

## Подозрительные события

1. Доступ к секретам:
   - Кто: kubernetes-admin, действующий через --as=system:serviceaccount:secure-ops:monitoring (impersonation) с IP 192.168.49.1.
   - Где: namespace kube-system, объект secrets/default-token-xxxx.
   - Почему подозрительно: сервис-аккаунт из пользовательского namespace secure-ops запрашивает токен в kube-system. Это типичный паттерн lateral movement и попытки получить токен с расширенными правами. Использование impersonation также является признаком возможного злоупотребления администраторскими полномочиями.

2. Привилегированные поды:
   - Кто: kubernetes-admin из IP 192.168.49.1, namespace secure-ops, под privileged-pod.
   - Комментарий: контейнер запущен с securityContext.privileged: true. Такой контейнер имеет доступ к устройствам и ядру хоста, может смонтировать ФС узла и выйти за пределы пода (container escape). Нарушение принципа least privilege и Pod Security Standards (baseline/restricted).

3. Использование kubectl exec в чужом поде:
   - Кто: kubernetes-admin.
   - Что делал: exec в pod coredns-xxxx в namespace kube-system с командой cat /etc/resolv.conf. Это вмешательство в системный компонент кластера, которое может использоваться для разведки сетевой конфигурации, утечки данных или подмены настроек DNS.

4. Создание RoleBinding с правами cluster-admin:
   - Кто: kubernetes-admin, создан RoleBinding/escalate-binding в secure-ops, привязывающий SA monitoring к ClusterRole/cluster-admin.
   - К чему привело: SA system:serviceaccount:secure-ops:monitoring получает административные права уровня cluster-admin в пределах namespace secure-ops. Это явная privilege escalation. Для выдачи таких прав на весь кластер использовался бы ClusterRoleBinding.

5. Удаление audit-policy.yaml:
   - Кто: kubernetes-admin с impersonation --as=admin; попытка удалить объект audit-policy в kube-system (ответ apiserver — 404, объект отсутствует в кластере, но факт попытки зафиксирован).
   - Возможные последствия: даже неуспешная попытка — это явный признак anti-forensics. При наличии нужных прав злоумышленник смог бы отключить политику аудита, что привело бы к потере видимости последующих действий и затруднило расследование.

## Ошибки и слабые места RBAC

- Использование kubernetes-admin с группой system:masters для рутинных операций — отсутствие разграничения ролей.
- Разрешено impersonation (--as=...) без отдельного контроля — администратор может действовать от имени любого SA и обходить аудит/привязку к конкретному пользователю.
- В namespace secure-ops нет ограничений: создаётся RoleBinding со ссылкой на ClusterRole/cluster-admin — нет admission-контроля (например, OPA/Gatekeeper, Kyverno), запрещающего привязку к высокопривилегированным ролям.
- SA monitoring создаётся без явных Role/RoleBinding с минимально необходимыми правами — отсутствует принцип least privilege.
- Нет Pod Security Admission (restricted), благодаря чему допускается запуск privileged: true.

## Вывод

В ходе симуляции зафиксированы все пять признаков компрометации:
доступ к секретам в kube-system через impersonation сервис-аккаунта, запуск
привилегированного пода, exec в системный pod coredns, удаление политики
аудита и создание RoleBinding с правами cluster-admin. Совокупность этих
событий — особенно эскалация привилегий SA monitoring до cluster-admin и
последующее отключение аудита — должна квалифицироваться как **критический инцидент и признак
компрометации кластера**.

Рекомендуется:
1. Включить Pod Security Admission в режиме restricted для пользовательских namespace.
2. Внедрить admission-политики (Kyverno/Gatekeeper), запрещающие privileged: true и привязки к cluster-admin.
3. Ограничить использование impersonate через RBAC.
4. Хранить audit.log вне кластера (форвардинг в SIEM), чтобы удаление политики/файла не приводило к потере истории.
5. Настроить алертинг на события: доступ к secrets в kube-system, exec в системные pod'ы, создание RoleBinding/ClusterRoleBinding с cluster-admin.