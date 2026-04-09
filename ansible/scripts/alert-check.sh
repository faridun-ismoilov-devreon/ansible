#!/bin/bash

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
CHAT_ID="${TELEGRAM_CHAT_ID}"

ALERTS=""

add_alert() {
  ALERTS="${ALERTS}\n$1"
}

# --- Check VMs via virsh ---
RUNNING=$(virsh list --state-running --name 2>/dev/null)

EXPECTED_VMS="okd-master-0 okd-master-1 okd-master-2 okd-worker-0 okd-worker-1 okd-worker-2 okd-worker-3 okd-worker-4 ch-node-01 ch-node-02 ch-node-03 keeper-01 keeper-02 keeper-03 kafka-01 kafka-02 kafka-03 nfs psql"

for vm in $EXPECTED_VMS; do
  if ! echo "$RUNNING" | grep -qx "$vm"; then
    add_alert "🔴 VM DOWN: $vm"
  fi
done

# --- Check ClickHouse services via Prometheus ---
for host in 192.168.150.140 192.168.150.141 192.168.150.142; do
  UP=$(curl -sf --max-time 3 "http://${host}:9363/metrics" | grep -m1 '^ClickHouseMetrics_' | wc -l)
  if [ "$UP" -eq 0 ]; then
    name=$([ "$host" = "192.168.150.140" ] && echo "ch-node-01" || [ "$host" = "192.168.150.141" ] && echo "ch-node-02" || echo "ch-node-03")
    add_alert "🔴 ClickHouse DOWN: $name"
  fi
done

# --- Check Keeper services ---
for host in 192.168.150.143 192.168.150.144 192.168.150.145; do
  UP=$(curl -sf --max-time 3 "http://${host}:9363/metrics" | grep -m1 '^ClickHouseMetrics_' | wc -l)
  if [ "$UP" -eq 0 ]; then
    name=$([ "$host" = "192.168.150.143" ] && echo "keeper-01" || [ "$host" = "192.168.150.144" ] && echo "keeper-02" || echo "keeper-03")
    add_alert "🔴 Keeper DOWN: $name"
  fi
done

# --- Check Kafka via JMX exporter ---
for host in 192.168.150.150 192.168.150.151 192.168.150.152; do
  UP=$(curl -sf --max-time 3 "http://${host}:9404/metrics" | grep -m1 '^kafka_' | wc -l)
  if [ "$UP" -eq 0 ]; then
    name=$([ "$host" = "192.168.150.150" ] && echo "kafka-01" || [ "$host" = "192.168.150.151" ] && echo "kafka-02" || echo "kafka-03")
    add_alert "🔴 Kafka DOWN: $name"
  fi
done

# --- Check PostgreSQL ---
PG_UP=$(curl -sf --max-time 3 "http://192.168.150.121:9187/metrics" | grep '^pg_up ' | awk '{print $2}')
if [ "$PG_UP" != "1" ]; then
  add_alert "🔴 PostgreSQL DOWN or exporter unreachable"
fi

# --- Check NFS export ---
NFS_CHECK=$(showmount -e 192.168.150.120 2>&1)
if ! echo "$NFS_CHECK" | grep -q '/'; then
  add_alert "🔴 NFS export unavailable: $NFS_CHECK"
fi

# --- Check Kafka under-replicated partitions ---
for host in 192.168.150.150 192.168.150.151 192.168.150.152; do
  URP=$(curl -sf --max-time 3 "http://${host}:9404/metrics" | grep '^kafka_server_ReplicaManager_UnderReplicatedPartitions ' | awk '{print $2}')
  if [ -n "$URP" ] && [ "${URP%.*}" -gt 0 ] 2>/dev/null; then
    name=$([ "$host" = "192.168.150.150" ] && echo "kafka-01" || [ "$host" = "192.168.150.151" ] && echo "kafka-02" || echo "kafka-03")
    add_alert "⚠️ Kafka under-replicated partitions: $name ($URP)"
  fi
done

# --- Check ClickHouse replication errors ---
for host in 192.168.150.140 192.168.150.141 192.168.150.142; do
  METRICS=$(curl -sf --max-time 3 "http://${host}:9363/metrics")
  DATA_LOSS=$(echo "$METRICS" | grep '^ClickHouseProfileEvents_ReplicatedDataLoss ' | awk '{print $2}')
  PART_CHECKS=$(echo "$METRICS" | grep '^ClickHouseMetrics_ReplicatedChecks ' | awk '{print $2}')
  name=$([ "$host" = "192.168.150.140" ] && echo "ch-node-01" || [ "$host" = "192.168.150.141" ] && echo "ch-node-02" || echo "ch-node-03")
  if [ -n "$DATA_LOSS" ] && [ "${DATA_LOSS%.*}" -gt 0 ] 2>/dev/null; then
    add_alert "🔴 ClickHouse data loss detected: $name (ReplicatedDataLoss=$DATA_LOSS)"
  fi
  if [ -n "$PART_CHECKS" ] && [ "${PART_CHECKS%.*}" -gt 100 ] 2>/dev/null; then
    add_alert "⚠️ ClickHouse replication lag: $name (ReplicatedChecks=$PART_CHECKS)"
  fi
done

# --- Check OKD nodes NotReady ---
OKD_NOTREADY=$(kubectl --context=okd get nodes --no-headers 2>/dev/null | grep -v ' Ready' | awk '{print $1}')
for node in $OKD_NOTREADY; do
  add_alert "🔴 OKD node NotReady: $node"
done

# --- Check EKS nodes NotReady ---
EKS_NOTREADY=$(kubectl --context=eks get nodes --no-headers 2>/dev/null | grep -v ' Ready' | awk '{print $1}' | sed 's/\.ap-southeast-1\.compute\.internal//')
for node in $EKS_NOTREADY; do
  add_alert "🔴 EKS node NotReady: $node"
done

# --- Check KVM host RAM ---
RAM_PCT=$(free -m | awk '/Mem:/{printf "%.0f", $3/$2*100}')
if [ "$RAM_PCT" -gt 95 ]; then
  add_alert "🧠 KVM host RAM: ${RAM_PCT}% used"
fi

# --- Check OKD certificates ---
SOON=$(kubectl --context=okd get secret -A -o json 2>/dev/null | \
  python3 -c "
import sys, json, datetime
data = json.load(sys.stdin)
now = datetime.datetime.utcnow()
for item in data.get('items', []):
    for k, v in item.get('data', {}).items():
        if k.endswith('.crt'):
            import base64, ssl, re
            try:
                pem = base64.b64decode(v).decode()
                from cryptography import x509
                from cryptography.hazmat.backends import default_backend
                cert = x509.load_pem_x509_certificate(pem.encode(), default_backend())
                exp = cert.not_valid_after
                days = (exp - now).days
                if days < 30:
                    ns = item['metadata']['namespace']
                    name = item['metadata']['name']
                    print(f'{ns}/{name} ({k}): {days}d')
            except:
                pass
" 2>/dev/null)
if [ -n "$SOON" ]; then
  while IFS= read -r line; do
    add_alert "⚠️ OKD cert expiring soon: $line"
  done <<< "$SOON"
fi

# --- Check KVM host disk ---
DISK_PCT=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
if [ "$DISK_PCT" -gt 85 ]; then
  add_alert "💾 KVM host disk: ${DISK_PCT}% used"
fi

# --- Send only if there are alerts ---
if [ -n "$ALERTS" ]; then
  DATE=$(date '+%Y-%m-%d %H:%M')
  MSG="🚨 INFRASTRUCTURE ALERT — $DATE
$(echo -e "$ALERTS")"

  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="$CHAT_ID" \
    --data-urlencode text="$MSG" \
    > /dev/null
fi
