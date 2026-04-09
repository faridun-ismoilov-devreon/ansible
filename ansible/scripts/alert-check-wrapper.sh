#!/bin/bash
# Wrapper to run Ansible Smart Alerting
# Runs every 15 minutes via cron

cd /root/production-ready-clickhouse/ansible
/usr/bin/ansible-playbook -i inventory/hosts.ini infrastructure-alerts.yml >> /var/log/ansible-alerts.log 2>&1
