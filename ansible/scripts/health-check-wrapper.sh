#!/bin/bash
# Wrapper to run Ansible health checks via Cron
# logs output to /var/log/ansible-health-check.log

REPO_DIR="/root/production-ready-clickhouse"
LOG_FILE="/var/log/ansible-health-check.log"

echo "=== Health Check Started: $(date) ===" >> $LOG_FILE
cd $REPO_DIR/ansible

# Run the playbook
ansible-playbook -i inventory/hosts.ini daily-health-check.yml >> $LOG_FILE 2>&1

echo "=== Health Check Finished: $(date) ===" >> $LOG_FILE
echo "----------------------------------------" >> $LOG_FILE
