# TODO-Notizen

## Dashboard

- [X] Create a page with matrix of users and groups from keycloak
- [ ] Add a suspend/resume (toggle) and a delete button beside the realm-status
- [ ] Auto-Refresh of realms
- [ ] Status indicators for services
- [ ] Join "Infrastructure & Ops" with "Management UIs"
- [ ] Hide Cards based on roles of logged in user
- [ ] Remove CDM and PROV Badges from cards (keep PKI badge)

## Stack

- [ ] provider-rabbitmq            | 2026-03-03 10:17:01.664104+00:00 [warning] <0.5691.0> rabbitmqctl node_health_check and its HTTP API counterpart are DEPRECATED. See https://www.rabbitmq.com/docs/monitoring#health-checks for replacement options.
- [ ] provider-telegraf            | 2026-03-03T10:37:01Z E! [inputs.rabbitmq] Error in plugin: getting "/api/federation-links" failed: 404 Not Found
- [ ] Make it easier to deploy a fresh provider stack (automated CA fingerprint handling, virgin-init-script with first-run-detection,...)
- [ ] Add a SW-Signing Service (Including API-Access through bridge)
- [ ] Low-Prio: Add a CI-Service

## Auth

- [ ] JWT Renewal: provider-rabbitmq            | 2026-03-03 15:02:12.386744+00:00 [error] <0.10835.0> Provided JWT token has expired at timestamp 1772550131 (validated at 1772550132)
