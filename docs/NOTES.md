# Some notes

## Important Features

- Tenant Keycloak soll auch an mehrere IAM des Kunden (Google OAuth, Azure AD/Microsoft, Keycloak,...) angebunden werden können (aus docker-compose.yml)
  * Social Auth soll über switch in ENV einfach aktiviert werden und dann einfach einen Button zur Verfügung stellen...


## Future Features

### Tenant Instanz

- Soll Device Isolation ermöglichen, so dass man "Sub-Tenants" spezifische Rechte auf selbst hinzugefügte Geräte geben kann (Self-Service-/Maker-Devices).
  * Hier soll man einzelne Devices für Kunden anlegen können, die kein eigenes Dev-Mgmt betreiben möchten, z.B. Einzelstückzahl-Kunden eines Tenant
- Workflow-Unterstützung für Device Decommissioning

### Provider Instanz

- Workflow-Unterstützung für Tenant Commissioning/Shutdown/Suspend/Unsuspend/Decommissioning

## Allgemeine Anmerkungen

- step-ca soll auf ein TPM oder HSM zugreifen, um Schlüssel zu speichern oder die Key-Files zu verschlüsseln -> Audit-Log

## Allgemeine Fragen

- Muss die Keycloak Federation über Cedentials gelöst werden? Kann das nicht über Zertifikate passieren
- Wie wird ein Update der Zertifikate durchgeführt? Dokumentieren für alle Use-Cases
  * Device, Federation, MQTT/mTLS,...