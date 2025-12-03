# Ansible готов для управления Kafka

## ✅ Настройка завершена

Ansible теперь может подключаться к Kafka нодам и применять изменения автоматически.

## Проверка подключения:

```bash
cd /home/ff/production-ready-clickhouse
ansible kafka -i ansible/inventory/hosts.ini -m ping
```

**Результат:** ✅ Все ноды отвечают (SUCCESS => ping: pong)

## Применение изменений:

```bash
cd /home/ff/production-ready-clickhouse
ansible-playbook -i ansible/inventory/hosts.ini ansible/deploy-kafka.yml
```

Этот playbook:
1. ✅ Обновит конфигурацию `server.properties` из шаблона
2. ✅ Перезапустит Kafka на всех нодах (через handler)
3. ✅ Применит изменения автоматически

## Что исправлено:

1. ✅ Путь к SSH ключу: `/home/ff/production-ready-clickhouse/ansible/keys/okd-bootstrap-key`
2. ✅ Права доступа: `chmod 600` на ключ
3. ✅ Host key verification: `StrictHostKeyChecking=no` и `UserKnownHostsFile=/dev/null`

## Текущая конфигурация Kafka:

- `auto.create.topics.enable=true` ✅ (применено на всех нодах)
- Шаблон обновлен: `ansible/roles/kafka/templates/server.properties.j2`

## В будущем:

Любые изменения в шаблоне `server.properties.j2` будут автоматически применены на все Kafka ноды при запуске:

```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/deploy-kafka.yml
```

Kafka будет автоматически перезапущен благодаря handler'у `Restart Kafka`.

