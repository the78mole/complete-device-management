{
  "rabbit_version": "4.0",
  "rabbitmq_version": "4.0",
  "product_name": "RabbitMQ",
  "users": [
    {
      "name": "RABBITMQ_ADMIN_USER_PLACEHOLDER",
      "password": "RABBITMQ_ADMIN_PASSWORD_PLACEHOLDER",
      "tags": ["administrator"]
    }
  ],
  "vhosts": [
    { "name": "/" },
    { "name": "cdm-metrics" }
  ],
  "permissions": [
    {
      "user":      "RABBITMQ_ADMIN_USER_PLACEHOLDER",
      "vhost":     "/",
      "configure": ".*",
      "write":     ".*",
      "read":      ".*"
    },
    {
      "user":      "RABBITMQ_ADMIN_USER_PLACEHOLDER",
      "vhost":     "cdm-metrics",
      "configure": ".*",
      "write":     ".*",
      "read":      ".*"
    }
  ],
  "topic_permissions": [],
  "parameters": [],
  "global_parameters": [
    {
      "name": "internal_cluster_id",
      "value": "rabbitmq-cluster-id-cdm-provider"
    }
  ],
  "policies": [],
  "queues": [],
  "exchanges": [],
  "bindings": []
}
