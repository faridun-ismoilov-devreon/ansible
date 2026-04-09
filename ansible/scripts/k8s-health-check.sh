#!/bin/bash

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

BOT_TOKEN="8359814100:AAGg-q6WDH18hUAcrEeaEBY69TTzu6v0U1I"
CHAT_ID="-4998909049"

DATE=$(date '+%Y-%m-%d %H:%M')

OKD=$(kubectl --context=okd top node 2>&1)
EKS=$(kubectl --context=eks top node 2>&1 | sed 's/\.ap-southeast-1\.compute\.internal//')

MESSAGE="☸️ Kubernetes Health Check
🗓 $DATE

🟠 OKD Cluster:
$OKD

🔵 EKS Cluster:
$EKS"

curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="$CHAT_ID" \
  --data-urlencode text="$MESSAGE" \
  > /dev/null
