# 🏗️ Production-Ready ClickHouse Infrastructure

[![Ansible](https://img.shields.io/badge/Ansible-2.15+-EE0000?logo=ansible&logoColor=white)](https://www.ansible.com/)
[![RKE2](https://img.shields.io/badge/RKE2-v1.32-0075FF?logo=rancher&logoColor=white)](https://docs.rke2.io/)
[![ClickHouse](https://img.shields.io/badge/ClickHouse-Altinity%20Operator-FFCC00?logo=clickhouse&logoColor=black)](https://clickhouse.com/)
[![ArgoCD](https://img.shields.io/badge/GitOps-ArgoCD-EF7B4D?logo=argo&logoColor=white)](https://argo-cd.readthedocs.io/)

Инфраструктура на базе **KVM-виртуализации**: Ansible поднимает VM и **RKE2 HA-кластер**, а прикладные сервисы (ClickHouse, Kafka, Vault, мониторинг, тенанты) деплоятся **внутри Kubernetes** через операторы и **ArgoCD GitOps**.

> **Миграция:** ранее инфраструктура работала на OKD + standalone-VM (ClickHouse / Keeper / Kafka). Сейчас OKD выведен из эксплуатации, все эти сервисы перенесены в RKE2. Ansible отвечает за слой VM + RKE2; всё, что выше — GitOps в репозиториях `infra-charts` и `gitops2.0`.

---

## 📐 Архитектура

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Hetzner Dedicated Server                              │
│                     37.27.173.224 (KVM Host, libvirt)                     │
│                                                                           │
│   UFW Firewall ◄──► Cloudflare (CDN/WAF)      MetalLB LoadBalancer        │
│                                                                           │
│                  192.168.150.0/24 (okdnet, NAT)                           │
│  ┌─────────────────────────────────────────────────────────────────┐     │
│  │                    RKE2 HA Cluster (Kubernetes v1.32)            │     │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐                       │     │
│  │  │ master-1 │  │ master-2 │  │ master-3 │  control-plane+etcd   │     │
│  │  │   .160   │  │   .161   │  │   .162   │  8Gi RAM, tainted     │     │
│  │  └──────────┘  └──────────┘  └──────────┘                       │     │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐                       │     │
│  │  │ worker-1 │  │ worker-2 │  │ worker-3 │  32Gi RAM, 100Gi disk │     │
│  │  │   .163   │  │   .164   │  │   .165   │  Cilium CNI           │     │
│  │  └──────────┘  └──────────┘  └──────────┘                       │     │
│  │                                                                 │     │
│  │  In-cluster: ClickHouse+Keeper (Altinity op), Kafka (Strimzi),  │     │
│  │  Vault, Loki, VictoriaMetrics, Grafana, Tempo, RabbitMQ, Redis, │     │
│  │  ArgoCD, cert-manager, NFS provisioner, тенанты devreon          │     │
│  └─────────────────────────────────────────────────────────────────┘     │
│                                                                           │
│  ┌────────┐  ┌────────┐  ┌────────────────┐                              │
│  │  NFS   │  │  PSQL  │  │ mt-edge-engine │   вспомогательные VM          │
│  │  .120  │  │  .121  │  │     .208       │                              │
│  └────────┘  └────────┘  └────────────────┘                              │
└─────────────────────────────────────────────────────────────────────────┘
```

**Диски KVM:** 4× NVMe ~1.8Ti в двух RAID1 — `md3` (`/`, диски k8s VM) и `md4` (`/mnt/vmstore-new`, psql/nfs/base image).

---

## 🔌 Сетевая схема и порты

```
INTERNET → Cloudflare (CDN/WAF) → 37.27.173.224 (UFW) → 192.168.150.0/24
                                                          ├── RKE2 (MetalLB LB IP)
                                                          ├── NFS / PostgreSQL
                                                          └── mt-edge-engine
```

| Порт | Сервис | Откуда доступен |
|------|--------|-----------------|
| `22` | SSH | Everywhere (rate-limited) |
| `80`, `443` | HTTP/S → Ingress (MetalLB) | Cloudflare IPs + VPN |
| `6443` | Kubernetes API | VPN only |
| `5432` | PostgreSQL | VPN only |
| `9100` | Node Exporter | VPN only |

Доступ к сервисам кластера (ClickHouse `8123`/`9000`, Kafka, Keeper, метрики) — **внутри кластера** по ClusterIP / через port-forward; наружу не публикуются.

---

## 📂 Структура репозитория

```
production-ready-clickhouse/
├── README.md
├── CLAUDE.md                              # Контекст инфраструктуры (детально)
├── unseal_vault.sh                        # Vault unseal скрипт
│
├── kubernetes/
│   ├── metallb/                           # IP-pool + L2 advertisement
│   └── gateway-api/                        # Gateway API манифесты
│
└── ansible/
    ├── ansible.cfg                        # forks=3 (против UFW rate-limit)
    ├── inventory/hosts.ini                # kvm, k8s_masters, k8s_workers, nfs, psql
    ├── keys/                              # SSH-ключи (не коммитить!)
    │
    │── ── RKE2 PROVISIONING ─────────────────────────────────
    ├── provision-k8s-masters.yml          # Создание master VM
    ├── provision-k8s-workers.yml          # Создание worker VM
    ├── setup-rke2-masters.yml             # RKE2 server + node-taint
    ├── setup-rke2-workers.yml             # RKE2 agent
    ├── rke2-cluster.yml                    # Альтернатива (lablabs.rke2 role)
    ├── deploy-k8s.yml                      # Обёртка провижна
    │
    │── ── CLUSTER ADD-ONS ───────────────────────────────────
    ├── install-cilium.yml                 # CNI
    ├── install-metallb.yml                # LoadBalancer
    ├── install-cert-manager.yml           # TLS
    ├── install-nfs.yml                     # RWX storage class
    ├── install-argocd.yml                 # GitOps
    │
    │── ── INFRA / OPS ───────────────────────────────────────
    ├── configure-haproxy.yml              # + haproxy.cfg.j2
    ├── configure-firewall.yml             # UFW
    ├── provision-vms.yml / deploy-to-kvm.yml
    ├── manage-psql.yml / manage-nfs.yml / manage-kvm-metrics.yml
    ├── setup-daily-cron.yml / setup-k8s-cron.yml / setup-alert-cron.yml
    ├── infrastructure-alerts.yml
    ├── scripts/                           # health-check.sh, k8s-health-check.sh
    │
    └── roles/
        ├── vm_provisioner/                # Создание KVM VM (cloud-init)
        ├── nfs/                           # Диагностика NFS
        ├── psql/                          # Диагностика PostgreSQL
        └── node_exporter/                 # Prometheus Node Exporter
```

---

## 🚀 Быстрый старт

### Предварительные требования

- **Ansible** ≥ 2.15
- SSH-ключ для KVM-хоста (`~/.ssh/kvm`), прописанный как `Host kvm` в `~/.ssh/config`
- SSH-ключ для VM (`ansible/keys/okd-bootstrap-key`)
- Доступ к Hetzner серверу `37.27.173.224`

### Развёртывание RKE2 с нуля

```bash
cd ansible

# 1. Создать VM
ansible-playbook provision-k8s-masters.yml
ansible-playbook provision-k8s-workers.yml

# 2. Поднять RKE2 (мастера с node-taint CriticalAddonsOnly, затем агенты)
ansible-playbook setup-rke2-masters.yml
ansible-playbook setup-rke2-workers.yml

# 3. Add-ons (порядок важен)
ansible-playbook install-cilium.yml         # CNI — без него ноды NotReady
ansible-playbook install-metallb.yml
ansible-playbook install-cert-manager.yml
ansible-playbook install-nfs.yml
ansible-playbook install-argocd.yml         # дальше всё через GitOps
```

После `install-argocd.yml` прикладные сервисы подтягиваются ArgoCD из `infra-charts` (`rke/*`) и `gitops2.0` — вручную их деплоить не нужно.

### Работа с кластером

```bash
ssh -J kvm -i ansible/keys/okd-bootstrap-key root@192.168.150.160 \
  "KUBECONFIG=/etc/rancher/rke2/rke2.yaml /var/lib/rancher/rke2/bin/kubectl get nodes"
```

---

## ⚙️ Конфигурация

### RKE2

| Параметр | Значение |
|----------|----------|
| Версия | `v1.32.4+rke2r1` |
| Masters | 3 × 8Gi RAM, 4 vCPU — `control-plane,etcd`, taint `CriticalAddonsOnly=true:NoExecute` |
| Workers | 3 × 32Gi RAM, 8 vCPU, 100Gi disk |
| CNI | Cilium (`cni: none`), kube-proxy off |
| CIDR | pods `10.200.0.0/16`, services `10.96.0.0/12` |

### ClickHouse (в кластере)

| Параметр | Значение |
|----------|----------|
| Оператор | Altinity clickhouse-operator `0.24.0` (NS `clickhouse`) |
| Топология | 1 shard, 3 replicas (CHI) |
| Keeper | CHK, 3 реплики, required pod anti-affinity (по нодам) |
| Storage | NFS storage class |

### Kafka (в кластере)

| Параметр | Значение |
|----------|----------|
| Оператор | Strimzi (NS `kafka`) |
| Auth | KafkaUser `kafka-app`, SCRAM-SHA-512 |
| ACL | Read/Write/Create/Describe/Alter/AlterConfigs на topic `*` |

---

## 📊 Мониторинг

Стек внутри кластера: **VictoriaMetrics** (+ vmagent) вместо Prometheus, **Loki** для логов, **Tempo** для трейсов, **Grafana** как UI. На уровне VM — `node_exporter` + cron-скрипты.

### Health-check / Алерты (cron на KVM)

| Скрипт | Cron (UTC) | Назначение |
|--------|------------|-----------|
| `health-check.sh` | 07:00 | Метрики всех VM (CPU/RAM/disk) → Telegram |
| `k8s-health-check.sh` | 07:05 | Статус k8s нод → Telegram |
| alert cron | каждые 15 мин | Алерты при падении VM / сервисов |

---

## 🔒 Безопасность

### Firewall (UFW)

- Входящие по умолчанию: `DENY`, исходящие: `ALLOW`
- SSH: открыт + rate-limiting (потому `forks = 3` в Ansible)
- HTTP/HTTPS: только Cloudflare IP + VPN
- Сервисные порты (6443, 5432, 9100): только VPN

### Доступ

```
Internet → Cloudflare → Ingress (MetalLB LB) → сервисы в кластере
VPN IPs  → Kubernetes API :6443
VPN IPs  → PostgreSQL :5432
```

### AmneziaVPN + Split DNS

- VPN-интерфейс `amn0` — `172.29.172.1/24`
- dnsmasq split DNS: `*.devreon.dev` → внутренние сервисы через VPN; `*.eks.devreon.dev` → AWS EKS (публичный IP)

---

## 🔄 Порядок развёртывания

```
 1. provision-k8s-masters.yml  →  provision-k8s-workers.yml   (VM)
 2. setup-rke2-masters.yml     →  setup-rke2-workers.yml      (RKE2)
 3. install-cilium → metallb → cert-manager → nfs → argocd    (add-ons)
 4. configure-firewall.yml / configure-haproxy.yml            (периметр)
 5. ArgoCD синкает infra-charts + gitops2.0                   (прикладные сервисы)
```

---

## 📝 Лицензия

Private infrastructure repository.
