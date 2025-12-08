#!/bin/bash
# Скрипт для исправления проблем синхронизации таблиц в ClickHouse кластере

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# IP адреса нод
NODES=("192.168.150.140" "192.168.150.141" "192.168.150.142")
NODE_NAMES=("ch-node-01" "ch-node-02" "ch-node-03")

# Параметры таблицы (измените при необходимости)
TABLE_NAME="${1:-quotes}"
DATABASE_NAME="${2:-default}"

echo "=========================================="
echo "ClickHouse Replication Fix Script"
echo "=========================================="
echo "Table: ${DATABASE_NAME}.${TABLE_NAME}"
echo ""

# Функция для выполнения запроса на ноде
execute_query() {
    local node=$1
    local query=$2
    clickhouse-client --host "$node" --query "$query" 2>/dev/null || echo "ERROR"
}

# Функция для проверки существования таблицы
table_exists() {
    local node=$1
    local db=$2
    local table=$3
    local result=$(execute_query "$node" "SELECT count() FROM system.tables WHERE database = '$db' AND name = '$table'")
    [ "$result" = "1" ]
}

# Шаг 1: Проверка существования таблицы на всех нодах
echo "Step 1: Checking table existence on all nodes..."
echo "---------------------------------------------------"
table_on_nodes=()
for i in "${!NODES[@]}"; do
    if table_exists "${NODES[$i]}" "$DATABASE_NAME" "$TABLE_NAME"; then
        echo -e "${NODE_NAMES[$i]}: ${GREEN}Table exists${NC}"
        table_on_nodes+=("${NODES[$i]}")
    else
        echo -e "${NODE_NAMES[$i]}: ${RED}Table NOT found${NC}"
    fi
done
echo ""

# Шаг 2: Если таблица существует не на всех нодах - исправляем
if [ ${#table_on_nodes[@]} -gt 0 ] && [ ${#table_on_nodes[@]} -lt ${#NODES[@]} ]; then
    echo -e "${YELLOW}Table exists on ${#table_on_nodes[@]} out of ${#NODES[@]} nodes${NC}"
    echo ""
    echo "Step 2: Restarting replicas to force synchronization..."
    echo "---------------------------------------------------"
    
    for i in "${!NODES[@]}"; do
        echo -n "Restarting replica on ${NODE_NAMES[$i]}... "
        result=$(execute_query "${NODES[$i]}" "SYSTEM RESTART REPLICA ${DATABASE_NAME}.${TABLE_NAME}" 2>&1)
        if [[ "$result" == *"doesn't exist"* ]]; then
            echo -e "${RED}Table doesn't exist on this node${NC}"
        else
            echo -e "${GREEN}OK${NC}"
        fi
    done
    echo ""
    
    echo "Waiting 10 seconds for synchronization..."
    sleep 10
    echo ""
    
    # Проверяем снова
    echo "Step 3: Re-checking table existence..."
    echo "---------------------------------------------------"
    all_exist=true
    for i in "${!NODES[@]}"; do
        if table_exists "${NODES[$i]}" "$DATABASE_NAME" "$TABLE_NAME"; then
            echo -e "${NODE_NAMES[$i]}: ${GREEN}Table exists${NC}"
        else
            echo -e "${NODE_NAMES[$i]}: ${RED}Table still NOT found${NC}"
            all_exist=false
        fi
    done
    echo ""
    
    if [ "$all_exist" = false ]; then
        echo -e "${RED}Table still missing on some nodes after restart.${NC}"
        echo ""
        echo "You need to recreate the table with ON CLUSTER clause:"
        echo ""
        echo "1. First, get the CREATE TABLE statement from a node where it exists:"
        echo "   clickhouse-client --host ${table_on_nodes[0]} --query \"SHOW CREATE TABLE ${DATABASE_NAME}.${TABLE_NAME}\""
        echo ""
        echo "2. Then recreate it on all nodes:"
        echo "   clickhouse-client --host ${NODES[0]} --query \"DROP TABLE IF EXISTS ${DATABASE_NAME}.${TABLE_NAME} ON CLUSTER production_cluster\""
        echo "   clickhouse-client --host ${NODES[0]} --query \"CREATE TABLE ${DATABASE_NAME}.${TABLE_NAME} ON CLUSTER production_cluster (...)\""
        echo ""
        exit 1
    fi
fi

# Шаг 3: Если таблица не существует ни на одной ноде
if [ ${#table_on_nodes[@]} -eq 0 ]; then
    echo -e "${RED}Table does not exist on any node!${NC}"
    echo ""
    echo "You need to create it with ON CLUSTER clause:"
    echo ""
    echo "clickhouse-client --host ${NODES[0]} --query \\"
    echo "  \"CREATE TABLE ${DATABASE_NAME}.${TABLE_NAME} ON CLUSTER production_cluster ("
    echo "    -- your columns here"
    echo "  ) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/${DATABASE_NAME}/${TABLE_NAME}', '{replica}')"
    echo "  ORDER BY (...)\""
    echo ""
    exit 1
fi

# Шаг 4: Проверка синхронизации данных
echo "Step 4: Checking data synchronization..."
echo "---------------------------------------------------"
row_counts=()
for i in "${!NODES[@]}"; do
    count=$(execute_query "${NODES[$i]}" "SELECT count() FROM ${DATABASE_NAME}.${TABLE_NAME}" 2>&1)
    if [[ "$count" =~ ^[0-9]+$ ]]; then
        echo "${NODE_NAMES[$i]}: $count rows"
        row_counts+=("$count")
    else
        echo -e "${NODE_NAMES[$i]}: ${RED}Error reading count${NC}"
    fi
done
echo ""

# Проверяем, все ли счетчики одинаковые
if [ ${#row_counts[@]} -eq ${#NODES[@]} ]; then
    unique_counts=$(printf '%s\n' "${row_counts[@]}" | sort -u | wc -l)
    if [ "$unique_counts" -eq 1 ]; then
        echo -e "${GREEN}✓ Data is synchronized across all nodes${NC}"
    else
        echo -e "${YELLOW}⚠ Row counts differ between nodes${NC}"
        echo "This may indicate replication lag. Wait a few seconds and check again."
    fi
fi
echo ""

# Шаг 5: Финальная проверка статуса реплик
echo "Step 5: Final replica status check..."
echo "---------------------------------------------------"
execute_query "${NODES[0]}" "SELECT database, table, is_leader, is_readonly, total_replicas, active_replicas FROM system.replicas WHERE database = '$DATABASE_NAME' AND table = '$TABLE_NAME'"
echo ""

echo "=========================================="
echo -e "${GREEN}Fix script completed${NC}"
echo "=========================================="

