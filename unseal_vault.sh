#!/bin/bash
set -e

# Configuration
NAMESPACE="infra"
VAULT_PODS=("vault-1" "vault-2")
UNSEAL_KEY="+uACN9vb+G44JQS22LL22M/l1pFQ50N2F8rQRCKeCBI="

echo "Starting Vault unseal process..."

for pod in "${VAULT_PODS[@]}"; do
    echo "Unsealing $pod..."
    if kubectl exec -n "$NAMESPACE" "$pod" -- vault operator unseal "$UNSEAL_KEY"; then
        echo "✅ Successfully sent unseal key to $pod"
    else
        echo "❌ Failed to unseal $pod"
    fi
    echo "----------------------------------------"
done

echo "Unseal process complete. Checking status..."
kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/name=vault
