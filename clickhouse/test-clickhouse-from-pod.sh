#!/bin/bash
# Тест подключения к ClickHouse из Kubernetes pod

echo "=== Testing ClickHouse connectivity from Kubernetes pod ==="
echo ""

# Test 1: Through Service
echo "1. Testing through Kubernetes Service (clickhouse.clickhouse.svc.cluster.local):"
kubectl run clickhouse-test-svc --image=curlimages/curl --rm -i --restart=Never -- \
  curl -v --max-time 10 --connect-timeout 5 \
  "http://clickhouse.default.svc.cluster.local:8123/?query=SELECT+1" 2>&1 | grep -E "(Connected|Failed|timeout)"

echo ""
echo "2. Testing direct IP (192.168.150.1):"
kubectl run clickhouse-test-direct --image=curlimages/curl --rm -i --restart=Never -- \
  curl -v --max-time 10 --connect-timeout 5 \
  "http://192.168.150.1:8123/?query=SELECT+1" 2>&1 | grep -E "(Connected|Failed|timeout)"

echo ""
echo "3. Testing network connectivity:"
kubectl run clickhouse-test-net --image=alpine --rm -i --restart=Never -- \
  sh -c "ping -c 2 192.168.150.1 && echo '---' && nc -zv -w 5 192.168.150.1 8123"

echo ""
echo "4. Testing from worker node directly:"
kubectl debug node/okd-worker-0 -it --image=alpine --restart=Never -- \
  sh -c "wget -O- --timeout=5 'http://192.168.150.1:8123/?query=SELECT+1' || echo 'FAILED'"

