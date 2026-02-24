{
  "id": "tenant1",
  "realm": "tenant1",
  "displayName": "Acme Devices GmbH",
  "enabled": true,
  "sslRequired": "external",
  "registrationAllowed": false,
  "loginWithEmailAllowed": true,
  "duplicateEmailsAllowed": false,
  "resetPasswordAllowed": true,
  "editUsernameAllowed": false,
  "bruteForceProtected": true,
  "roles": {
    "realm": [
      { "name": "cdm-admin",    "description": "Tenant administrator" },
      { "name": "cdm-operator", "description": "Fleet operator" },
      { "name": "cdm-viewer",   "description": "Read-only access" }
    ]
  },
  "users": [
    {
      "username": "alice",
      "email": "alice@acme-devices.example.com",
      "firstName": "Alice",
      "lastName": "Hoffman",
      "enabled": true,
      "emailVerified": true,
      "realmRoles": ["cdm-admin"],
      "clientRoles": { "realm-management": ["realm-admin"], "account": ["manage-account", "view-profile"] },
      "credentials": [
        { "type": "password", "value": "${TENANT1_ADMIN_PASSWORD}", "temporary": true }
      ]
    },
    {
      "username": "bob",
      "email": "bob@acme-devices.example.com",
      "firstName": "Bob",
      "lastName": "Schneider",
      "enabled": true,
      "emailVerified": true,
      "realmRoles": ["cdm-operator"],
      "clientRoles": { "account": ["manage-account", "view-profile"] },
      "credentials": [
        { "type": "password", "value": "${TENANT1_OPERATOR_PASSWORD}", "temporary": true }
      ]
    },
    {
      "username": "carol",
      "email": "carol@acme-devices.example.com",
      "firstName": "Carol",
      "lastName": "Bauer",
      "enabled": true,
      "emailVerified": true,
      "realmRoles": ["cdm-viewer"],
      "clientRoles": { "account": ["manage-account", "view-profile"] },
      "credentials": [
        { "type": "password", "value": "${TENANT1_VIEWER_PASSWORD}", "temporary": true }
      ]
    }
  ],
  "clients": [
    {
      "clientId": "portal",
      "name": "CDM Tenant Portal",
      "enabled": true,
      "protocol": "openid-connect",
      "publicClient": false,
      "secret": "${PORTAL_OIDC_SECRET}",
      "redirectUris": ["*"],
      "webOrigins": ["*"],
      "standardFlowEnabled": true,
      "implicitFlowEnabled": false,
      "directAccessGrantsEnabled": false,
      "attributes": { "post.logout.redirect.uris": "*" }
    },
    {
      "clientId": "grafana-broker",
      "name": "Grafana Identity Broker",
      "description": "Used by the cdm realm to broker logins from this tenant into Grafana.",
      "enabled": true,
      "protocol": "openid-connect",
      "publicClient": false,
      "secret": "${GRAFANA_BROKER_SECRET}",
      "redirectUris": ["*"],
      "webOrigins": ["*"],
      "standardFlowEnabled": true,
      "implicitFlowEnabled": false,
      "directAccessGrantsEnabled": false,
      "attributes": { "post.logout.redirect.uris": "*" },
      "protocolMappers": [
        {
          "name": "realm-roles",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-usermodel-realm-role-mapper",
          "consentRequired": false,
          "config": {
            "claim.name": "roles",
            "multivalued": "true",
            "jsonType.label": "String",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "userinfo.token.claim": "true"
          }
        }
      ]
    }
  ],
  "identityProviders": [],
  "defaultDefaultClientScopes": ["profile", "email", "roles", "web-origins"],
  "defaultOptionalClientScopes": ["offline_access", "address", "phone"],
  "smtpServer": {},
  "eventsEnabled": true,
  "eventsListeners": ["jboss-logging"],
  "enabledEventTypes": [
    "LOGIN",
    "LOGIN_ERROR",
    "UPDATE_PROFILE",
    "UPDATE_PASSWORD"
  ],
  "adminEventsEnabled": true,
  "adminEventsDetailsEnabled": true
}
