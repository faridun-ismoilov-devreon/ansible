# Статус обновления Kafka конфигурации

## ✅ Изменение применено в шаблоне

**Файл:** `ansible/roles/kafka/templates/server.properties.j2`  
**Строка 23:** `auto.create.topics.enable=true` ✅

## ⚠️ Проблема с применением

Ansible не может подключиться к Kafka нодам из-за недоступности jump host (`37.27.173.224`):
- SSH Connection refused на порту 22
- Возможно сервер перезагружается или SSH временно недоступен

## 📋 Что нужно сделать

### Когда SSH будет доступен, выполните:

```bash
cd /home/ff/production-ready-clickhouse
ansible-playbook -i ansible/inventory/hosts.ini ansible/deploy-kafka.yml
```

### Или вручную на каждой ноде:

```bash
# Подключиться к каждой Kafka ноде
# 192.168.150.150, 192.168.150.151, 192.168.150.152

# Изменить конфигурацию
sed -i 's/auto.create.topics.enable=false/auto.create.topics.enable=true/' /opt/kafka/config/server.properties

# Проверить
grep auto.create.topics.enable /opt/kafka/config/server.properties
# Должно быть: auto.create.topics.enable=true

# Перезапустить Kafka
systemctl restart kafka

# Проверить статус
systemctl status kafka
```

## 🔍 Проверка после применения

После применения на всех нодах проверьте:

```bash
ansible kafka -i ansible/inventory/hosts.ini -m shell -a "grep auto.create.topics.enable /opt/kafka/config/server.properties"
```

Все ноды должны показать: `auto.create.topics.enable=true`

## 📝 По умолчанию

Да, по умолчанию в Kafka `auto.create.topics.enable=false` (начиная с версии 0.9.0.0). Это сделано для безопасности.

