#!/bin/bash

BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
CHAT_ID="${TELEGRAM_CHAT_ID}"
DATE=$(date '+%Y-%m-%d %H:%M')

# KVM host metrics
HOST_DISK=$(df -h / | tail -1 | awk '{print $5}')
HOST_RAM=$(free -m | awk '/Mem:/{printf "%.0f%%", $3/$2*100}')
HOST_CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}' | cut -d. -f1)

# Get metrics from ClickHouse/Keeper prometheus endpoint (:9363)
ch_metrics() {
  local ip=$1 name=$2
  local M=$(curl -s --connect-timeout 2 http://$ip:9363/metrics)
  local STATE=$(virsh domstate "$name" 2>/dev/null | tr -d ' ')
  local ICON="🔴"; [ "$STATE" = "running" ] && ICON="🟢"

  local MEM_TOTAL=$(echo "$M" | awk '/^ClickHouseAsyncMetrics_OSMemoryTotal /{print $2}')
  local MEM_FREE=$(echo "$M" | awk '/^ClickHouseAsyncMetrics_OSMemoryFreePlusCached /{print $2}')
  local CPU_IDLE=$(echo "$M" | awk '/^ClickHouseAsyncMetrics_OSIdleTimeCPU/{sum+=$2;n++} END{if(n>0)printf "%.0f",sum/n*100}')

  if [ -n "$MEM_TOTAL" ] && [ "$MEM_TOTAL" != "0" ]; then
    local RAM_PCT=$(awk "BEGIN{printf \"%.0f\", ($MEM_TOTAL-$MEM_FREE)/$MEM_TOTAL*100}")
    local RAM_USED=$(awk "BEGIN{printf \"%.1f\", ($MEM_TOTAL-$MEM_FREE)/1073741824}")
    local RAM_TOT=$(awk "BEGIN{printf \"%.0f\", $MEM_TOTAL/1073741824}")
    local CPU_PCT=$(( 100 - ${CPU_IDLE:-0} ))
    echo "${ICON} ${name}: CPU ${CPU_PCT}% | RAM ${RAM_USED}/${RAM_TOT}GB (${RAM_PCT}%)"
  else
    echo "${ICON} ${name}: ${STATE}"
  fi
}

# Get metrics from Node Exporter (:9100)
node_metrics() {
  local ip=$1 name=$2
  local M=$(curl -s --connect-timeout 2 http://$ip:9100/metrics)
  local STATE=$(virsh domstate "$name" 2>/dev/null | tr -d ' ')
  local ICON="🔴"; [ "$STATE" = "running" ] && ICON="🟢"

  local MEM_TOT=$(echo "$M" | awk '/^node_memory_MemTotal_bytes /{print $2}')
  local MEM_AVL=$(echo "$M" | awk '/^node_memory_MemAvailable_bytes /{print $2}')

  if [ -n "$MEM_TOT" ] && [ "$MEM_TOT" != "0" ]; then
    local RAM_PCT=$(awk "BEGIN{printf \"%.0f\", ($MEM_TOT-$MEM_AVL)/$MEM_TOT*100}")
    local RAM_USED=$(awk "BEGIN{printf \"%.1f\", ($MEM_TOT-$MEM_AVL)/1073741824}")
    local RAM_TOT=$(awk "BEGIN{printf \"%.0f\", $MEM_TOT/1073741824}")
    echo "${ICON} ${name}: RAM ${RAM_USED}/${RAM_TOT}GB (${RAM_PCT}%)"
  else
    echo "${ICON} ${name}: ${STATE}"
  fi
}

# Get Kafka JVM heap metrics (:9404)
kafka_metrics() {
  local ip=$1 name=$2
  local M=$(curl -s --connect-timeout 2 http://$ip:9404/metrics)
  local STATE=$(virsh domstate "$name" 2>/dev/null | tr -d ' ')
  local ICON="🔴"; [ "$STATE" = "running" ] && ICON="🟢"

  local HEAP_USED=$(echo "$M" | awk '/^jvm_memory_bytes_used\{area="heap"/{print $2}')
  local HEAP_MAX=$(echo "$M" | awk '/^jvm_memory_bytes_max\{area="heap"/{print $2}')

  if [ -n "$HEAP_USED" ] && [ -n "$HEAP_MAX" ] && [ "$HEAP_MAX" != "-1.0" ]; then
    local HEAP_PCT=$(awk "BEGIN{printf \"%.0f\", $HEAP_USED/$HEAP_MAX*100}")
    local HEAP_USED_GB=$(awk "BEGIN{printf \"%.1f\", $HEAP_USED/1073741824}")
    local HEAP_MAX_GB=$(awk "BEGIN{printf \"%.0f\", $HEAP_MAX/1073741824}")
    echo "${ICON} ${name}: JVM heap ${HEAP_USED_GB}/${HEAP_MAX_GB}GB (${HEAP_PCT}%)"
  else
    echo "${ICON} ${name}: ${STATE}"
  fi
}

# OKD from kubectl
OKD_TOP=$(kubectl --context=okd top node --no-headers 2>/dev/null)
okd_line() {
  local name=$1
  local LINE=$(echo "$OKD_TOP" | grep "$name")
  local STATE=$(virsh domstate "$name" 2>/dev/null | tr -d ' ')
  local ICON="🔴"; [ "$STATE" = "running" ] && ICON="🟢"
  if [ -n "$LINE" ]; then
    local CPU=$(echo "$LINE" | awk '{print $3}')
    local MEM=$(echo "$LINE" | awk '{print $4}')
    local MEM_PCT=$(echo "$LINE" | awk '{print $5}')
    echo "${ICON} ${name}: CPU ${CPU} | RAM ${MEM} (${MEM_PCT})"
  else
    echo "${ICON} ${name}: ${STATE}"
  fi
}

MSG="🖥 KVM Health Check — $DATE
CPU: ${HOST_CPU}% | RAM: ${HOST_RAM} | Disk: ${HOST_DISK}

☁️ OKD Masters:
$(okd_line okd-master-0)
$(okd_line okd-master-1)
$(okd_line okd-master-2)

⚙️ OKD Workers:
$(okd_line okd-worker-0)
$(okd_line okd-worker-1)
$(okd_line okd-worker-2)
$(okd_line okd-worker-3)

🏠 ClickHouse:
$(ch_metrics 192.168.150.140 ch-node-01)
$(ch_metrics 192.168.150.141 ch-node-02)
$(ch_metrics 192.168.150.142 ch-node-03)

🔑 Keeper:
$(ch_metrics 192.168.150.143 keeper-01)
$(ch_metrics 192.168.150.144 keeper-02)
$(ch_metrics 192.168.150.145 keeper-03)

📨 Kafka:
$(kafka_metrics 192.168.150.150 kafka-01)
$(kafka_metrics 192.168.150.151 kafka-02)
$(kafka_metrics 192.168.150.152 kafka-03)

🗄 Storage/DB:
$(node_metrics 192.168.150.120 nfs)
$(
  STATE=$(virsh domstate psql 2>/dev/null | tr -d ' ')
  ICON="🔴"; [ "$STATE" = "running" ] && ICON="🟢"
  M=$(curl -s --connect-timeout 2 http://192.168.150.121:9187/metrics)
  PG_UP=$(echo "$M" | awk '/^pg_up /{print $2}')
  CONNS=$(echo "$M" | awk '/^pg_stat_database_numbackends/{sum+=$2} END{print sum+0}')
  if [ "$PG_UP" = "1" ]; then
    echo "${ICON} psql: UP | connections: ${CONNS}"
  else
    echo "${ICON} psql: ${STATE}"
  fi
)"

curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="$CHAT_ID" \
  --data-urlencode text="$MSG" \
  > /dev/null
