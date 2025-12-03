# Обновление Kafka конфигурации: auto.create.topics.enable=true

## Изменение применено в шаблоне

Файл `ansible/roles/kafka/templates/server.properties.j2` обновлен:
- `auto.create.topics.enable=true` (было `false`)

## Применение изменений на все Kafka ноды

### Вариант 1: Через Ansible (если SSH работает)

```bash
cd /home/ff/production-ready-clickhouse
ansible-playbook -i ansible/inventory/hosts.ini ansible/deploy-kafka.yml
```

### Вариант 2: Вручную через SSH (если Ansible не работает)

Подключитесь к каждой Kafka ноде и выполните:

```bash
# На каждой ноде (192.168.150.150, 192.168.150.151, 192.168.150.152)
ssh root@192.168.150.150  # или .151, .152

# Изменить конфигурацию
sed -i 's/auto.create.topics.enable=false/auto.create.topics.enable=true/' /opt/kafka/config/server.properties

# Проверить изменение
grep auto.create.topics.enable /opt/kafka/config/server.properties

# Перезапустить Kafka
systemctl restart kafka

# Проверить статус
systemctl status kafka
```

### Вариант 3: Через jump host

```bash
# С вашего ПК через jump host
ssh root@37.27.173.224 "ssh root@192.168.150.150 'sed -i \"s/auto.create.topics.enable=false/auto.create.topics.enable=true/\" /opt/kafka/config/server.properties && systemctl restart kafka'"

# Повторить для всех нод:
# 192.168.150.151
# 192.168.150.152
```

## Проверка после применения

```bash
# Проверить конфигурацию на всех нодах
for ip in 192.168.150.150 192.168.150.151 192.168.150.152; do
  echo "=== Node $ip ==="
  ssh root@37.27.173.224 "ssh root@$ip 'grep auto.create.topics.enable /opt/kafka/config/server.properties'"
done
```

## Важно

⚠️ После изменения `auto.create.topics.enable=true`:
- Kafka будет автоматически создавать топики при первом обращении
- Это удобно для разработки, но менее безопасно для production
- Убедитесь, что это соответствует вашим требованиям безопасности

## По умолчанию

Да, по умолчанию в Kafka `auto.create.topics.enable=false` (начиная с версии 0.9.0.0). Это сделано для безопасности, чтобы предотвратить случайное создание топиков.

