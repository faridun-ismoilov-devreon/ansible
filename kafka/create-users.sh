#!/bin/bash
# Create Kafka SASL users

# Admin user
/opt/kafka/bin/kafka-configs.sh --zookeeper localhost:2181 --alter --add-config 'SCRAM-SHA-256=[password=admin-secret-password]' --entity-type users --entity-name admin 2>/dev/null || \
/opt/kafka/bin/kafka-configs.sh --bootstrap-server localhost:9092 --alter --add-config 'SCRAM-SHA-256=[password=admin-secret-password]' --entity-type users --entity-name admin

# Application user
/opt/kafka/bin/kafka-configs.sh --bootstrap-server localhost:9092 --alter --add-config 'SCRAM-SHA-256=[password=app-secret-password]' --entity-type users --entity-name kafka-app

echo "✅ Created users: admin, kafka-app"
