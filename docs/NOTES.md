# Notes

## Important Features

- Tenant Keycloak should also be connectable to multiple customer IAM systems (Google OAuth, Azure AD/Microsoft, Keycloak, ...) — see `docker-compose.yml`
  * Social Auth should be easy to enable via an ENV switch and simply provide a login button.


## Future Features

### Tenant Instance

- Should support device isolation so that "sub-tenants" can be granted specific rights to devices they add themselves (self-service / maker devices).
  * Individual devices should be registerable for customers who do not operate their own device management, e.g. single-unit customers of a tenant.
- Workflow support for device decommissioning

### Provider Instance

- Workflow support for tenant commissioning / shutdown / suspend / unsuspend / decommissioning

## General Remarks

- step-ca should be able to access a TPM or HSM to store keys or encrypt key files → audit log

## Open Questions

- Does Keycloak federation have to be solved via credentials? Can it be done via certificates instead?
- How are certificate updates performed? Document for all use cases:
  * Device, Federation, MQTT/mTLS, ...
