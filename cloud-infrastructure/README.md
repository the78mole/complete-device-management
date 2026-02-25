# cloud-infrastructure — Legacy Stack

> **⚠ DEPRECATED — kept for reference only.**
>
> This directory contains the original monolithic Docker Compose stack that was replaced
> by the two-stack architecture in Phase 1.  **Do not add new features here.**

---

## What replaced this?

| Old (monolithic) | New (two-stack) |
|---|---|
| Single `docker-compose.yml` running everything | [`provider-stack/`](../provider-stack/) + [`tenant-stack/`](../tenant-stack/) |
| nginx as reverse proxy | Caddy with automatic HTTPS |
| Fixed tenant realms (`tenant1`, `tenant2`) | Dynamic tenant onboarding via JOIN workflow |
| Manual cert management | Automated PKI via step-ca Root CA → Sub-CA chain |
| Single RabbitMQ with shared credentials | Per-tenant vHosts with mTLS EXTERNAL auth |

---

## Migration

If you are running the old `cloud-infrastructure` stack, migrate as follows:

1. Export your data from ThingsBoard (Entities → Export), hawkBit (artefacts), InfluxDB
   (`influx backup`) and Grafana (dashboard JSON).
2. Set up the **Provider-Stack** first — see
   [`docs/installation/provider-stack.md`](../docs/installation/provider-stack.md).
3. For each tenant, set up a **Tenant-Stack** and run the JOIN workflow — see
   [`docs/installation/tenant-stack.md`](../docs/installation/tenant-stack.md).
4. Import your previously exported data into the new stacks.
5. Update device firmware / environment to point to the Tenant-Stack endpoints.

---

This directory will be removed in a future release once the migration guide has been
officially validated.
