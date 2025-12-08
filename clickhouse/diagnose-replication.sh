#!/bin/bash
# Диагностика и исправление проблем синхронизации ClickHouse кластера

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# IP адреса нод
NODES=("192.168.150.140" "192.168.150.141" "192.168.150.142")
NODE_NAMES=("ch-node-01" "ch-node-02" "ch-node-03")

echo "=========================================="
echo "ClickHouse Cluster Replication Diagnostic"
echo "=========================================="
echo ""

# Функция для выполнения запроса на ноде
execute_query() {
    local node=$1
    local query=$2
    clickhouse-client --host "$node" --query "$query" 2>/dev/null || echo "ERROR"
}

# Функция для проверки подключения к ноде
check_node_connection() {
    local node=$1
    local name=$2
    echo -n "Checking $name ($node)... "
    if execute_query "$node" "SELECT 1" > /dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
        return 0
    else
        echo -e "${RED}FAILED${NC}"
        return 1
    fi
}

# 1. Проверка подключения к нодам
echo "1. Checking node connectivity..."
echo "-----------------------------------"
for i in "${!NODES[@]}"; do
    check_node_connection "${NODES[$i]}" "${NODE_NAMES[$i]}"
done
echo ""

# 2. Проверка статуса кластера
echo "2. Checking cluster configuration..."
echo "-----------------------------------"
execute_query "${NODES[0]}" "SELECT cluster, shard_num, replica_num, host_name, port FROM system.clusters WHERE cluster = 'production_cluster' ORDER BY replica_num"
echo ""

# 3. Проверка подключения к Keeper
echo "3. Checking Keeper connection..."
echo "-----------------------------------"
for i in "${!NODES[@]}"; do
    echo -n "${NODE_NAMES[$i]}: "
    result=$(execute_query "${NODES[$i]}" "SELECT count() FROM system.zookeeper WHERE path = '/'")
    if [ "$result" != "ERROR" ] && [ "$result" != "" ]; then
        echo -e "${GREEN}Connected${NC}"
    else
        echo -e "${RED}Not connected${NC}"
    fi
done
echo ""

# 4. Проверка статуса реплик
echo "4. Checking replica status..."
echo "-----------------------------------"
execute_query "${NODES[0]}" "SELECT database, table, is_leader, is_readonly, zookeeper_exception, total_replicas, active_replicas FROM system.replicas ORDER BY database, table"
echo ""

# 5. Проверка существования таблицы quotes на всех нодах
echo "5. Checking 'quotes' table existence..."
echo "-----------------------------------"
TABLE_NAME="quotes"
DATABASE_NAME="default"

# Определяем базу данных (может быть default или другая)
for db in "default" "quotes_db" "trading" "market"; do
    echo "Checking database: $db"
    for i in "${!NODES[@]}"; do
        echo -n "  ${NODE_NAMES[$i]}: "
        result=$(execute_query "${NODES[$i]}" "SELECT count() FROM system.tables WHERE database = '$db' AND name = '$TABLE_NAME'")
        if [ "$result" = "1" ]; then
            echo -e "${GREEN}EXISTS${NC}"
            DATABASE_NAME="$db"
        elif [ "$result" = "0" ]; then
            echo -e "${RED}NOT FOUND${NC}"
        else
            echo -e "${YELLOW}ERROR${NC}"
        fi
    done
    echo ""
done

# 6. Проверка структуры таблицы (если существует)
echo "6. Checking table structure (if exists)..."
echo "-----------------------------------"
for i in "${!NODES[@]}"; do
    echo "${NODE_NAMES[$i]}:"
    result=$(execute_query "${NODES[$i]}" "SHOW CREATE TABLE ${DATABASE_NAME}.${TABLE_NAME}" 2>&1)
    if [[ "$result" == *"doesn't exist"* ]] || [[ "$result" == "ERROR" ]]; then
        echo -e "  ${RED}Table does not exist${NC}"
    else
        echo -e "  ${GREEN}Table exists${NC}"
        echo "$result" | head -5
    fi
    echo ""
done

# 7. Проверка количества строк (если таблица существует)
echo "7. Checking row counts..."
echo "-----------------------------------"
for i in "${!NODES[@]}"; do
    echo -n "${NODE_NAMES[$i]}: "
    result=$(execute_query "${NODES[$i]}" "SELECT count() FROM ${DATABASE_NAME}.${TABLE_NAME}" 2>&1)
    if [[ "$result" == *"doesn't exist"* ]] || [[ "$result" == "ERROR" ]]; then
        echo -e "${RED}Table not found${NC}"
    else
        echo -e "${GREEN}$result rows${NC}"
    fi
done
echo ""

# 8. Проверка ошибок репликации
echo "8. Checking replication errors..."
echo "-----------------------------------"
for i in "${!NODES[@]}"; do
    echo "${NODE_NAMES[$i]}:"
    result=$(execute_query "${NODES[$i]}" "SELECT database, table, zookeeper_exception FROM system.replicas WHERE zookeeper_exception != ''")
    if [ -z "$result" ] || [ "$result" = "ERROR" ]; then
        echo -e "  ${GREEN}No errors${NC}"
    else
        echo -e "  ${RED}Errors found:${NC}"
        echo "$result"
    fi
    echo ""
done

# 9. Рекомендации по исправлению
echo "=========================================="
echo "RECOMMENDATIONS"
echo "=========================================="
echo ""

# Проверяем, существует ли таблица хотя бы на одной ноде
table_exists_anywhere=false
for i in "${!NODES[@]}"; do
    result=$(execute_query "${NODES[$i]}" "SELECT count() FROM system.tables WHERE name = '$TABLE_NAME'")
    if [ "$result" = "1" ]; then
        table_exists_anywhere=true
        break
    fi
done

if [ "$table_exists_anywhere" = false ]; then
    echo -e "${YELLOW}Table '$TABLE_NAME' does not exist on any node.${NC}"
    echo "Create it using:"
    echo ""
    echo "clickhouse-client --host ${NODES[0]} --query \\"
    echo "  \"CREATE TABLE ${DATABASE_NAME}.${TABLE_NAME} ON CLUSTER production_cluster (...)\""
    echo ""
else
    echo -e "${YELLOW}Table exists but may not be synchronized.${NC}"
    echo ""
    echo "To fix synchronization:"
    echo ""
    echo "1. Restart replicas on all nodes:"
    for i in "${!NODES[@]}"; do
        echo "   clickhouse-client --host ${NODES[$i]} --query \"SYSTEM RESTART REPLICA ${DATABASE_NAME}.${TABLE_NAME}\""
    done
    echo ""
    echo "2. Or recreate table with ON CLUSTER:"
    echo "   clickhouse-client --host ${NODES[0]} --query \"DROP TABLE IF EXISTS ${DATABASE_NAME}.${TABLE_NAME} ON CLUSTER production_cluster\""
    echo "   clickhouse-client --host ${NODES[0]} --query \"CREATE TABLE ${DATABASE_NAME}.${TABLE_NAME} ON CLUSTER production_cluster (...)\""
    echo ""
fi

echo "=========================================="
echo "Diagnostic complete"
echo "=========================================="

