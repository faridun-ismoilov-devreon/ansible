# Production-Ready ClickHouse Cluster

## Архитектура
- **3 ClickHouse ноды** (1 shard × 3 replicas)
- **3 Keeper ноды** (quorum для репликации)
- **6 VM** на 1 bare metal сервере (KVM)

## Спецификация VM

| VM | IP | vCPU | RAM | Disk |
|----|---------|------|-----|------|
| ch-node-01 | 192.168.150.140 | 8 | 16GB | 100GB |
| ch-node-02 | 192.168.150.141 | 8 | 16GB | 100GB |
| ch-node-03 | 192.168.150.142 | 8 | 16GB | 100GB |
| keeper-01 | 192.168.150.143 | 2 | 4GB | 30GB |
| keeper-02 | 192.168.150.144 | 2 | 4GB | 30GB |
| keeper-03 | 192.168.150.145 | 2 | 4GB | 30GB |

## Быстрый старт

### 1. Добавить DHCP резервации
```bash
# См. network-config.txt
virsh net-update okdnet add ip-dhcp-host "<host mac='52:54:00:aa:bb:01' name='ch-node-01' ip='192.168.150.140' />" --live --config
# ... повторить для всех 6 VM
```

### 2. Создать Keeper VMs
```bash
# См. create-keeper-vms.txt
cd /var/lib/libvirt/images
# Создать keeper-01, keeper-02, keeper-03
```

### 3. Установить Keeper кластер
```bash
# См. install-keeper.txt
# Установить на всех 3 keeper нодах
```

### 4. Создать ClickHouse VMs
```bash
# См. create-clickhouse-vms.txt
# Создать ch-node-01, ch-node-02, ch-node-03
```

### 5. Установить ClickHouse кластер
```bash
# См. install-clickhouse-cluster.txt
# Установить и настроить на всех 3 CH нодах
```

## Важные файлы

| Файл | Описание |
|------|----------|
| `network-config.txt` | MAC/IP адреса и DHCP резервации |
| `create-keeper-vms.txt` | Создание Keeper VM |
| `install-keeper.txt` | Установка Keeper кластера |
| `create-clickhouse-vms.txt` | Создание ClickHouse VM |
| `install-clickhouse-cluster.txt` | Установка ClickHouse кластера |

## Подключение

```bash
# CLI
clickhouse-client --host 192.168.150.140

# HTTP
http://192.168.150.140:8123/play
```

## Проверка кластера

```bash
# Статус кластера
clickhouse-client --host 192.168.150.140 --query "SELECT * FROM system.clusters WHERE cluster='production_cluster'"

# Keeper статус
echo "ruok" | nc 192.168.150.143 9181

# Репликация
clickhouse-client --host 192.168.150.140 --query "SELECT * FROM system.replicas"
```

## Создание реплицируемой таблицы

```sql
-- Создать БД
CREATE DATABASE mydb ON CLUSTER production_cluster;

-- Создать реплицируемую таблицу
CREATE TABLE mydb.events ON CLUSTER production_cluster
(
    id UInt64,
    timestamp DateTime,
    message String
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/mydb/events', '{replica}')
ORDER BY (timestamp, id);

-- Вставить данные (автоматически реплицируется на все ноды)
INSERT INTO mydb.events VALUES (1, now(), 'test');
```

## Управление

```bash
# Статус VM
virsh list | grep -E "ch-node|keeper"

# Рестарт ClickHouse ноды
ssh root@192.168.150.140 "systemctl restart clickhouse-server"

# Рестарт Keeper ноды
ssh root@192.168.150.143 "systemctl restart clickhouse-keeper"

# Принудительная синхронизация реплики
clickhouse-client --host 192.168.150.141 --query "SYSTEM RESTART REPLICA mydb.events"
```

## Порты

| Сервис | Порт | Описание |
|--------|------|----------|
| ClickHouse HTTP | 8123 | HTTP API |
| ClickHouse Native | 9000 | Клиент |
| ClickHouse Interserver | 9009 | Репликация |
| Keeper Client | 9181 | ZooKeeper-совместимый |
| Keeper Raft | 9234 | Внутренняя связь |

## Требования к серверу

- **vCPU**: 30+ (используется 30/96)
- **RAM**: 60GB+ (используется 60/251GB)
- **Disk**: 400GB+ (используется 390/1755GB)
- **OS**: Debian/Ubuntu с KVM
- **Network**: Bridge virbr1 (okdnet)

## Troubleshooting

**ClickHouse не стартует:**
```bash
ssh root@192.168.150.140 "tail -50 /var/log/clickhouse-server/clickhouse-server.err.log"
```

**Репликация не работает:**
```bash
# Проверить /etc/hosts
ssh root@192.168.150.140 "cat /etc/hosts | grep ch-node"

# Рестартнуть реплику
clickhouse-client --host 192.168.150.140 --query "SYSTEM RESTART REPLICA dbname.tablename"
```

**Keeper не работает:**
```bash
echo "ruok" | nc 192.168.150.143 9181  # Должен вернуть "imok"
```

## Критичные моменты

1. ⚠️ `/etc/hosts` должен содержать все ноды
2. ⚠️ Используй только `<zookeeper>` секцию (НЕ `<keeper>`) в конфиге CH
3. ⚠️ После установки может потребоваться `SYSTEM RESTART REPLICA`
4. ⚠️ Пароль root по умолчанию: `clickhouse123` (ИЗМЕНИТЬ!)

---

**Version**: ClickHouse 25.9.3.48, Ubuntu 24.04 LTS  
**Status**: Production Ready ✅

