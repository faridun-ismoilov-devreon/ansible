# 🏗️ Production-Ready ClickHouse Infrastructure

[![Ansible](https://img.shields.io/badge/Ansible-2.15+-EE0000?logo=ansible&logoColor=white)](https://www.ansible.com/)
[![ClickHouse](https://img.shields.io/badge/ClickHouse-Cluster-FFCC00?logo=clickhouse&logoColor=black)](https://clickhouse.com/)
[![Kafka](https://img.shields.io/badge/Kafka-KRaft-231F20?logo=apachekafka&logoColor=white)](https://kafka.apache.org/)
[![OKD](https://img.shields.io/badge/OKD-4.x-EE0000?logo=redhat&logoColor=white)](https://www.okd.io/)

Полностью автоматизированная инфраструктура на базе **KVM-виртуализации**: разворачивание ClickHouse-кластера с репликацией, Kafka (KRaft), OKD-кластера, HAProxy и вспомогательных сервисов — всё через Ansible.

---

## 📐 Архитектура

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Hetzner Dedicated Server                            │
│                     37.27.173.224 (KVM Host)                            │
│                                                                         │
│  ┌──────────────┐   UFW Firewall   ┌──────────────┐                    │
│  │   HAProxy    │◄────────────────►│  Cloudflare   │                    │
│  │  :80 :443    │   :6443 :8123    │   (CDN/WAF)   │                    │
│  │  :6443 :8123 │   :9000 :5432   └──────────────┘                    │
│  │  :9000 :5432 │                                                       │
│  └──────┬───────┘                                                       │
│         │                                                               │
│         ▼          192.168.150.0/24 (okdnet)                            │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                    Virtual Machines                              │    │
│  │                                                                 │    │
│  │  ┌─────────────────────────────────────────────────────────┐   │    │
│  │  │              OKD Cluster (Kubernetes)                    │   │    │
│  │  │  ┌──────────┐  ┌──────────┐  ┌──────────┐              │   │    │
│  │  │  │ master-0 │  │ master-1 │  │ master-2 │   Masters    │   │    │
│  │  │  │   .100   │  │   .101   │  │   .102   │   16GB/8cpu  │   │    │
│  │  │  └──────────┘  └──────────┘  └──────────┘              │   │    │
│  │  │  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐          │   │    │
│  │  │  │ wrk-0  │ │ wrk-1  │ │ wrk-2  │ │ wrk-3  │ Workers  │   │    │
│  │  │  │  .103  │ │  .105  │ │  .153  │ │  .154  │ 16GB/4cpu │   │    │
│  │  │  └────────┘ └────────┘ └────────┘ └────────┘          │   │    │
│  │  └─────────────────────────────────────────────────────────┘   │    │
│  │                                                                 │    │
│  │  ┌───────────────────────┐   ┌──────────────────────────────┐  │    │
│  │  │   ClickHouse Cluster  │   │     ClickHouse Keeper        │  │    │
│  │  │  ┌───────┐ ┌───────┐  │   │  ┌────────┐ ┌────────┐      │  │    │
│  │  │  │ ch-01 │ │ ch-02 │  │   │  │ kpr-01 │ │ kpr-02 │      │  │    │
│  │  │  │ .140  │ │ .141  │  │◄─►│  │  .143  │ │  .144  │      │  │    │
│  │  │  ├───────┤ ├───────┤  │   │  ├────────┤ ├────────┤      │  │    │
│  │  │  │ ch-03 │ │       │  │   │  │ kpr-03 │ │        │      │  │    │
│  │  │  │ .142  │ │       │  │   │  │  .145  │ │        │      │  │    │
│  │  │  └───────┘ └───────┘  │   │  └────────┘ └────────┘      │  │    │
│  │  │  16GB/8cpu  3 replicas│   │  4GB/2cpu   Raft consensus   │  │    │
│  │  └───────────────────────┘   └──────────────────────────────┘  │    │
│  │                                                                 │    │
│  │  ┌──────────────────────┐  ┌────────┐  ┌────────┐             │    │
│  │  │    Kafka (KRaft)     │  │  NFS   │  │ PSQL   │             │    │
│  │  │ ┌──────┐ ┌──────┐   │  │  .120  │  │  .121  │             │    │
│  │  │ │ kf-01│ │ kf-02│   │  └────────┘  └────────┘             │    │
│  │  │ │ .150 │ │ .151 │   │                                      │    │
│  │  │ ├──────┤ ├──────┤   │                                      │    │
│  │  │ │ kf-03│ │      │   │                                      │    │
│  │  │ │ .152 │ │      │   │                                      │    │
│  │  │ └──────┘ └──────┘   │                                      │    │
│  │  │ 8GB/4cpu  RF=3      │                                      │    │
│  │  └──────────────────────┘                                      │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 🔌 Сетевая схема и порты

```
                         INTERNET
                            │
                     ┌──────┴──────┐
                     │  Cloudflare │
                     │  CDN / WAF  │
                     └──────┬──────┘
                            │
                ┌───────────┴───────────┐
                │    37.27.173.224      │
                │    UFW Firewall       │
                │                       │
                │  Port    Service      │
                │  ──────  ──────────── │
                │  22      SSH (limit)  │
                │  80/443  HAProxy→OKD  │
                │  6443    HAProxy→API  │
                │  8123    HAProxy→CH   │
                │  9000    HAProxy→CH   │
                │  5432    HAProxy→PSQL │
                │  9100    Node Export. │
                └───────────┬───────────┘
                            │
                   192.168.150.0/24
                            │
            ┌───────┬───────┼───────┬───────┐
            ▼       ▼       ▼       ▼       ▼
          OKD    ClickH.  Keeper   Kafka   NFS/PG
```

| Порт | Протокол | Сервис | Откуда доступен |
|------|----------|--------|-----------------|
| `22` | TCP | SSH | Everywhere (rate-limited) |
| `80`, `443` | TCP | HTTP/S → OKD Ingress | Cloudflare IPs + VPN |
| `6443` | TCP | Kubernetes API | VPN only |
| `8123` | TCP | ClickHouse HTTP | VPN only |
| `9000` | TCP | ClickHouse Native | VPN + K8s |
| `5432` | TCP | PostgreSQL | VPN only |
| `9092` | TCP | Kafka PLAINTEXT | Internal only |
| `9094` | TCP | Kafka SASL | Internal only |
| `9181` | TCP | Keeper TCP | Internal only |
| `9363` | TCP | CH/Keeper Prometheus | Internal only |
| `9404` | TCP | Kafka JMX Exporter | Internal only |
| `9100` | TCP | Node Exporter | VPN only |

---

## 📂 Структура репозитория

```
production-ready-clickhouse/
├── README.md
├── unseal_vault.sh                        # Vault unseal скрипт
│
└── ansible/
    ├── ansible.cfg                        # Конфигурация Ansible
    ├── inventory/
    │   └── hosts.ini                      # Все хосты, группы и переменные
    ├── keys/                              # SSH-ключи (не коммитить!)
    │
    │── ── PLAYBOOKS ─────────────────────────────────────────
    │
    ├── provision-clickhouse-cluster.yml   # 🔧 Создание VM + деплой CH+Keeper
    ├── provision-okd-masters.yml          # 🔧 Создание OKD master VM
    ├── provision-okd-workers.yml          # 🔧 Создание OKD worker VM
    ├── provision-vms.yml                  # 🔧 Создание Kafka VM
    ├── deploy-clickhouse.yml              # 🚀 Деплой CH + Keeper (на готовые VM)
    ├── deploy-kafka.yml                   # 🚀 Деплой Kafka KRaft
    ├── configure-haproxy.yml              # ⚙️  Настройка HAProxy LB
    ├── configure-firewall.yml             # 🔒 Настройка UFW firewall
    ├── approve-okd-csrs.yml              # ✅ Одобрение OKD CSR-сертификатов
    ├── test-connection.yml                # 🩺 Health-check KVM хоста
    ├── manage-psql.yml                    # 🩺 Диагностика PostgreSQL
    ├── manage-nfs.yml                     # 🩺 Диагностика NFS
    ├── manage-kvm-metrics.yml             # 📊 Установка Node Exporter
    │
    │── ── TEMPLATES ─────────────────────────────────────────
    │
    ├── haproxy.cfg.j2                     # Шаблон HAProxy конфигурации
    │
    │── ── ROLES ─────────────────────────────────────────────
    │
    └── roles/
        ├── clickhouse/                    # Установка и настройка ClickHouse
        │   ├── tasks/main.yml
        │   ├── handlers/main.yml
        │   └── templates/
        │       ├── keeper.xml.j2          # Подключение к Keeper
        │       ├── remote_servers.xml.j2  # Топология кластера
        │       ├── macros.xml.j2          # Shard/Replica макросы
        │       ├── network.xml.j2         # Сетевые настройки
        │       ├── prometheus.xml.j2      # Метрики Prometheus
        │       ├── users_admin.xml.j2     # Пользователь admin
        │       └── users_default.xml.j2   # Пользователь default
        │
        ├── clickhouse_keeper/             # ClickHouse Keeper (Raft consensus)
        │   ├── tasks/main.yml
        │   ├── handlers/main.yml
        │   └── templates/
        │       ├── keeper_config.xml.j2   # Конфигурация Keeper
        │       └── prometheus.xml.j2      # Метрики
        │
        ├── kafka/                         # Apache Kafka (KRaft mode)
        │   ├── defaults/main.yml
        │   ├── tasks/main.yml
        │   ├── handlers/main.yml
        │   └── templates/
        │       ├── server.properties.j2   # Конфигурация Kafka
        │       ├── kafka.service.j2       # Systemd unit
        │       └── jmx_exporter.yaml.j2   # JMX метрики для Prometheus
        │
        ├── vm_provisioner/                # Создание KVM виртуальных машин
        │   ├── tasks/main.yml
        │   └── templates/
        │       └── cloud-init.yaml.j2     # Cloud-init конфигурация
        │
        ├── nfs/                           # Диагностика NFS-сервера
        │   └── tasks/main.yml
        │
        ├── psql/                          # Диагностика PostgreSQL
        │   └── tasks/main.yml
        │
        └── node_exporter/                 # Prometheus Node Exporter
            └── tasks/main.yml
```

---

## 🚀 Быстрый старт

### Предварительные требования

- **Ansible** ≥ 2.15
- **SSH-ключ** для KVM-хоста (`~/.ssh/kvm`)
- **SSH-ключ** для VM (`ansible/keys/okd-bootstrap-key`)
- Доступ к **Hetzner** серверу `37.27.173.224`

### 1. Проверка связности

```bash
cd ansible

# Проверить связь с KVM-хостом
ansible kvm_host -m ping

# Полная диагностика KVM-хоста
ansible-playbook test-connection.yml
```

### 2. Провижинг виртуальных машин

```bash
# Поднять ClickHouse + Keeper VM (создаёт 6 VM + деплоит софт)
ansible-playbook provision-clickhouse-cluster.yml

# Поднять Kafka VM (создаёт 3 VM)
ansible-playbook provision-vms.yml
```

### 3. Деплой сервисов

```bash
# Деплой Kafka кластера (на уже готовые VM)
ansible-playbook deploy-kafka.yml

# Деплой ClickHouse + Keeper (на уже готовые VM)
ansible-playbook deploy-clickhouse.yml
```

### 4. Настройка инфраструктуры

```bash
# Настроить HAProxy балансировщик
ansible-playbook configure-haproxy.yml

# Настроить UFW firewall
ansible-playbook configure-firewall.yml

# Установить Node Exporter для мониторинга
ansible-playbook manage-kvm-metrics.yml
```

### 5. OKD кластер

```bash
# Поднять master-ноды OKD
ansible-playbook provision-okd-masters.yml

# Поднять worker-ноды OKD
ansible-playbook provision-okd-workers.yml

# Одобрить сертификаты нод
ansible-playbook approve-okd-csrs.yml
```

### 6. Диагностика

```bash
# Проверить PostgreSQL
ansible-playbook manage-psql.yml

# Проверить NFS
ansible-playbook manage-nfs.yml
```

---

## ⚙️ Конфигурация кластеров

### ClickHouse

| Параметр | Значение |
|----------|----------|
| Ноды | 3 × `ch-node-{01,02,03}` |
| Топология | 1 shard, 3 replicas |
| Keeper | Отдельный 3-нодный кластер |
| HTTP порт | `8123` |
| Native порт | `9000` |
| Prometheus | `:9363/metrics` |
| Репликация | `internal_replication = true` |

### Kafka

| Параметр | Значение |
|----------|----------|
| Ноды | 3 × `kafka-{01,02,03}` |
| Режим | KRaft (без ZooKeeper) |
| Версия | `3.9.0` |
| Партиции | 3 per topic |
| Replication Factor | 3 |
| Min ISR | 2 |
| Retention | 7 дней |
| Heap | `-Xmx4G -Xms4G` |
| JMX Exporter | `:9404` |
| SASL | SCRAM-SHA-256 (порт `9094`) |

### OKD (Kubernetes)

| Параметр | Значение |
|----------|----------|
| Masters | 3 × 16GB RAM, 8 vCPU |
| Workers | 4 × 16GB RAM, 4 vCPU |
| OS | CentOS Stream CoreOS 9 |
| API | `api.okddev.devreon.dev:6443` |

---

## 📊 Мониторинг

```
 Prometheus Targets
 ├── KVM Host ──────── :9100  (node_exporter)
 ├── ClickHouse ────── :9363  (встроенный /metrics)
 ├── CH Keeper ─────── :9363  (встроенный /metrics)
 └── Kafka ─────────── :9404  (JMX Exporter)
```

---

## 🔒 Безопасность

### Firewall (UFW)

- **Входящие по умолчанию**: `DENY`
- **Исходящие по умолчанию**: `ALLOW`
- SSH: открыт + rate-limiting
- HTTP/HTTPS: только Cloudflare IP + VPN
- Сервисные порты (6443, 8123, 9000, 5432, 9100, 9177): только VPN

### Доступ к сервисам

```
Internet → Cloudflare → HAProxy :80/:443 → OKD Workers
VPN IPs  → HAProxy :6443                 → OKD Masters (API)
VPN IPs  → HAProxy :8123/:9000           → ClickHouse
VPN IPs  → HAProxy :5432                 → PostgreSQL
Internal → Kafka :9092                    → PLAINTEXT (внутри сети)
Internal → Kafka :9094                    → SASL_PLAINTEXT
```

---

## 🔄 Порядок развёртывания

```
 1. provision-clickhouse-cluster.yml
    │  Создание 6 VM (3 CH + 3 Keeper)
    │  Установка и настройка софта
    ▼
 2. provision-vms.yml → deploy-kafka.yml
    │  Создание 3 Kafka VM → деплой Kafka
    ▼
 3. provision-okd-masters.yml
    │  Создание 3 master VM + bootstrap OKD
    ▼
 4. provision-okd-workers.yml
    │  Создание 4 worker VM + join кластер
    ▼
 5. approve-okd-csrs.yml
    │  Одобрение CSR-сертификатов нод
    ▼
 6. configure-haproxy.yml
    │  Настройка HAProxy балансировщика
    ▼
 7. configure-firewall.yml
    │  Настройка UFW правил
    ▼
 8. manage-kvm-metrics.yml
       Установка Node Exporter
```

---

## 📝 Лицензия

Private infrastructure repository.
