# Some notes

Dashboard links not working:
- ThingsBoard
- Grafana
- hawkBit
- Influx (Auth Proxy)

## RabbitMQ

### Deprecated features

cdm-rabbitmq        | 2026-02-24 12:35:26.366749+00:00 [warning] <0.986.0> Deprecated features: `transient_nonexcl_queues`: Feature `transient_nonexcl_queues` is deprecated.
cdm-rabbitmq        | 2026-02-24 12:35:26.366749+00:00 [warning] <0.986.0> By default, this feature can still be used for now.
cdm-rabbitmq        | 2026-02-24 12:35:26.366749+00:00 [warning] <0.986.0> Its use will not be permitted by default in a future minor RabbitMQ version and the feature will be removed from a future major RabbitMQ version; actual versions to be determined.
cdm-rabbitmq        | 2026-02-24 12:35:26.366749+00:00 [warning] <0.986.0> To continue using this feature when it is not permitted by default, set the following parameter in your configuration:
cdm-rabbitmq        | 2026-02-24 12:35:26.366749+00:00 [warning] <0.986.0>     "deprecated_features.permit.transient_nonexcl_queues = true"
cdm-rabbitmq        | 2026-02-24 12:35:26.366749+00:00 [warning] <0.986.0> To test RabbitMQ as if the feature was removed, set this in your configuration:
cdm-rabbitmq        | 2026-02-24 12:35:26.366749+00:00 [warning] <0.986.0>     "deprecated_features.permit.transient_nonexcl_queues = false"

## Keycloak

### Update env to new names

cdm-keycloak     | 2026-02-24 12:13:06,722 WARN  [org.keycloak.services] (main) KC-SERVICES0110: Environment variable 'KEYCLOAK_ADMIN_PASSWORD' is deprecated, use 'KC_BOOTSTRAP_ADMIN_PASSWORD' instead
cdm-keycloak     | 2026-02-24 12:13:06,902 INFO  [org.keycloak.services] (main) KC-SERVICES0077: Created temporary admin user with username admin

## hawkBit

### Schema Updates

Re-occuring schema updates

cdm-hawkbit         | 2026-02-24T12:35:10.440Z  INFO 1 --- [update-server] [:] [           main] o.f.c.i.s.JdbcTableSchemaHistory         : Creating Schema History table "PUBLIC"."schema_version" ...
cdm-hawkbit         | 2026-02-24T12:35:10.550Z  INFO 1 --- [update-server] [:] [           main] o.f.core.internal.command.DbMigrate      : Current version of schema "PUBLIC": << Empty Schema >>
cdm-hawkbit         | 2026-02-24T12:35:10.593Z  INFO 1 --- [update-server] [:] [           main] o.f.core.internal.command.DbMigrate      : Migrating schema "PUBLIC" to version "1.0.1 - init   "
cdm-hawkbit         | 2026-02-24T12:35:10.758Z  INFO 1 --- [update-server] [:] [           main] o.f.core.internal.command.DbMigrate      : Migrating schema "PUBLIC" to version "1.2.0 - update target info for message   "
cdm-hawkbit         | 2026-02-24T12:35:10.776Z  INFO 1 --- [update-server] [:] [           main] o.f.core.internal.command.DbMigrate      : Migrating schema "PUBLIC" to version "1.4.0 - cascade delete   "
cdm-hawkbit         | 2026-02-24T12:35:10.822Z  INFO 1 --- [update-server] [:] [           main] o.f.core.internal.command.DbMigrate      : Migrating schema "PUBLIC" to version "1.4.1 - cascade delete   "
[...]
cdm-hawkbit         | 2026-02-24T12:35:12.225Z  INFO 1 --- [update-server] [:] [           main] o.f.core.internal.command.DbMigrate      : Migrating schema "PUBLIC" to version "1.12.29 - add ds sm locked   "
cdm-hawkbit         | 2026-02-24T12:35:12.255Z  INFO 1 --- [update-server] [:] [           main] o.f.core.internal.command.DbMigrate      : Migrating schema "PUBLIC" to version "1.12.30 - add distrubuted lock   "
cdm-hawkbit         | 2026-02-24T12:35:12.270Z  INFO 1 --- [update-server] [:] [           main] o.f.core.internal.command.DbMigrate      : Migrating schema "PUBLIC" to version "1.12.31 - add type to ds index   "
cdm-hawkbit         | 2026-02-24T12:35:12.284Z  INFO 1 --- [update-server] [:] [           main] o.f.core.internal.command.DbMigrate      : Migrating schema "PUBLIC" to version "1.12.32 - refactoring rename   "
cdm-hawkbit         | 2026-02-24T12:35:12.315Z  INFO 1 --- [update-server] [:] [           main] o.f.core.internal.command.DbMigrate      : Successfully applied 52 migrations to schema "PUBLIC", now at version v1.12.32 (execution time 00:01.166s)