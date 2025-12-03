#!/bin/bash
# Скрипт для обновления auto.create.topics.enable на всех Kafka нодах

KAFKA_NODES=(
    "192.168.150.150"
    "192.168.150.151"
    "192.168.150.152"
)

SSH_KEY="/home/ff/production-ready-clickhouse/ansible/keys/okd-bootstrap-key"
JUMP_HOST="root@37.27.173.224"
JUMP_KEY="/home/ff/.ssh/kvm"

echo "=== Updating Kafka configuration on all nodes ==="
echo ""

for node_ip in "${KAFKA_NODES[@]}"; do
    echo "Processing Kafka node: $node_ip"
    
    ssh -i "$JUMP_KEY" "$JUMP_HOST" "ssh -i /root/.ssh/okd-bootstrap-key root@$node_ip 'sed -i \"s/auto.create.topics.enable=false/auto.create.topics.enable=true/\" /opt/kafka/config/server.properties && grep \"auto.create.topics.enable\" /opt/kafka/config/server.properties && systemctl restart kafka && sleep 3 && systemctl status kafka --no-pager | head -3'" 2>&1
    
    if [ $? -eq 0 ]; then
        echo "✅ Node $node_ip updated successfully"
    else
        echo "❌ Failed to update node $node_ip"
    fi
    echo ""
done

echo "=== Verification ==="
for node_ip in "${KAFKA_NODES[@]}"; do
    echo "Checking $node_ip:"
    ssh -i "$JUMP_KEY" "$JUMP_HOST" "ssh -i /root/.ssh/okd-bootstrap-key root@$node_ip 'grep auto.create.topics.enable /opt/kafka/config/server.properties'" 2>&1
done

