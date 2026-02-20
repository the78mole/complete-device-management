## Summary

<!-- One or two sentences explaining what this PR does and why. -->

Closes #<!-- issue number -->

---

## Type of Change

- [ ] 🐛 Bug fix (non-breaking)
- [ ] 🚀 New feature (non-breaking)
- [ ] 💥 Breaking change (requires a migration note)
- [ ] 📖 Documentation only
- [ ] 🧹 Refactor / chore (no behaviour change)
- [ ] ⚙️ CI / tooling

---

## Affected Components

<!-- Check all that apply -->

- [ ] cloud-infrastructure / docker-compose
- [ ] step-ca (PKI)
- [ ] keycloak (IAM)
- [ ] thingsboard (UI / Rule Chain / Widgets)
- [ ] hawkbit (OTA backend)
- [ ] monitoring (InfluxDB / Grafana)
- [ ] wireguard (VPN server)
- [ ] glue-services / iot-bridge-api
- [ ] glue-services / terminal-proxy
- [ ] device-stack
- [ ] docs

---

## Changes Made

<!-- List the concrete changes: new files, modified functions, config changes, etc. -->

-
-
-

---

## Testing

<!-- Describe how you verified your changes work. -->

- [ ] `ruff check . && mypy app && pytest -q` passes (iot-bridge-api)
- [ ] `npm run lint && npm test` passes (terminal-proxy)
- [ ] `docker compose config --quiet` passes for modified compose files
- [ ] All JSON files are valid
- [ ] `mkdocs build --strict` passes (if docs were changed)
- [ ] Manual smoke test performed (describe below)

**Manual test steps:**

```
# describe what you ran and what output you observed
```

---

## Documentation

- [ ] I updated the relevant docs in `docs/` (or no doc update is needed)
- [ ] I updated `.env.example` if I added new env vars

---

## Screenshots (if UI/widget changes)

<!-- Paste screenshots here -->

---

## Reviewer Notes

<!-- Anything specific you want reviewers to focus on or be aware of. -->
