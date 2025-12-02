#!/bin/bash
# ClickHouse Connection Test Script
# Tests connectivity from Kubernetes pods to ClickHouse

echo "=== ClickHouse Connection Diagnostics ==="
echo ""

# Test 1: Direct connection to ClickHouse nodes
echo "1. Testing direct connection to ClickHouse nodes:"
for ip in 192.168.150.140 192.168.150.141 192.168.150.142; do
    echo -n "  $ip:8123 - "
    timeout 3 curl -s "http://$ip:8123/?query=SELECT+1" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "✅ OK"
    else
        echo "❌ FAILED"
    fi
done

echo ""
echo "2. Testing HAProxy gateway (192.168.150.1):"
echo -n "  192.168.150.1:8123 - "
timeout 3 curl -s "http://192.168.150.1:8123/?query=SELECT+1" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✅ OK"
else
    echo "❌ FAILED"
fi

echo -n "  192.168.150.1:9000 - "
timeout 3 nc -zv 192.168.150.1 9000 > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✅ OK"
else
    echo "❌ FAILED"
fi

echo ""
echo "3. Network routes:"
ip route | grep -E "192.168.150|default" || echo "  No routes found"

echo ""
echo "4. DNS resolution:"
nslookup 192.168.150.1 2>/dev/null || echo "  nslookup not available"

echo ""
echo "=== Test from Kubernetes pod ==="
echo "Run this command from your application pod:"
echo ""
echo "kubectl run clickhouse-test --image=curlimages/curl --rm -it --restart=Never -- \\"
echo "  curl -v --max-time 10 'http://192.168.150.1:8123/?query=SELECT+1'"
echo ""
echo "Or test with authentication:"
echo "curl -v --max-time 10 'http://default:YOUR_PASSWORD@192.168.150.1:8123/?query=SELECT+1'"

