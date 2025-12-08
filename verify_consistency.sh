#!/bin/bash

# Configuration
URL="http://37.27.173.224:8123"
USER="admin"
PASS="clickhouse_admin_2024"
DB="quotes-storage-dev"
TABLE="quotes"
EXPECTED_COUNT=54
ITERATIONS=1000

echo "Starting consistency check..."
echo "Target: $URL"
echo "Expected Count: $EXPECTED_COUNT"
echo "Iterations: $ITERATIONS"
echo "----------------------------------------"

errors=0
success=0

for ((i=1; i<=ITERATIONS; i++)); do
    # Perform query
    count=$(curl -s -u "$USER:$PASS" "$URL/?query=SELECT+count()+FROM+%60$DB%60.%60$TABLE%60")
    
    # Check result
    if [[ "$count" -eq "$EXPECTED_COUNT" ]]; then
        ((success++))
        # Print progress every 100 requests
        if ((i % 100 == 0)); then
            echo "[$i/$ITERATIONS] OK (Count: $count)"
        fi
    else
        ((errors++))
        echo "[$i/$ITERATIONS] ❌ ERROR! Expected $EXPECTED_COUNT, got '$count'"
        # Optional: exit on first error
        # exit 1
    fi
done

echo "----------------------------------------"
echo "Check complete."
echo "✅ Success: $success"
echo "❌ Errors:  $errors"

if [[ "$errors" -eq 0 ]]; then
    echo "Result: PASS"
    exit 0
else
    echo "Result: FAIL"
    exit 1
fi
