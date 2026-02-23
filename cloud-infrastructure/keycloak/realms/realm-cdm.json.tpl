{
  "id": "cdm",
  "realm": "cdm",
  "displayName": "Complete Device Management",
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
      { "name": "cdm-admin",    "description": "Platform administrator" },
      { "name": "cdm-operator", "description": "Fleet operator" },
      { "name": "cdm-viewer",   "description": "Read-only access" }
    ]
  },
  "users": [
    {
      "username": "cdm-admin",
      "email": "cdm-admin@example.com",
      "firstName": "CDM",
      "lastName": "Admin",
      "enabled": true,
      "emailVerified": true,
      "realmRoles": ["cdm-admin"],
      "clientRoles": { "account": ["manage-account", "view-profile"] },
      "credentials": [
        { "type": "password", "value": "changeme", "temporary": true }
      ]
    },
    {
      "username": "cdm-operator",
      "email": "cdm-operator@example.com",
      "firstName": "CDM",
      "lastName": "Operator",
      "enabled": true,
      "emailVerified": true,
      "realmRoles": ["cdm-operator"],
      "clientRoles": { "account": ["manage-account", "view-profile"] },
      "credentials": [
        { "type": "password", "value": "changeme", "temporary": true }
      ]
    }
  ],
  "clients": [
    {
      "clientId": "hawkbit",
      "name": "hawkBit Update Server",
      "enabled": true,
      "protocol": "openid-connect",
      "publicClient": false,
      "secret": "${HB_OIDC_SECRET}",
      "redirectUris": ["*"],
      "webOrigins": ["*"],
      "standardFlowEnabled": true,
      "implicitFlowEnabled": false,
      "directAccessGrantsEnabled": false
    },
    {
      "clientId": "thingsboard",
      "name": "ThingsBoard",
      "enabled": true,
      "protocol": "openid-connect",
      "publicClient": false,
      "secret": "${TB_OIDC_SECRET}",
      "redirectUris": ["*"],
      "webOrigins": ["*"],
      "standardFlowEnabled": true,
      "implicitFlowEnabled": false,
      "directAccessGrantsEnabled": true
    },
    {
      "clientId": "grafana",
      "name": "Grafana",
      "enabled": true,
      "protocol": "openid-connect",
      "publicClient": false,
      "secret": "${GRAFANA_OIDC_SECRET}",
      "redirectUris": ["*"],
      "webOrigins": ["*"],
      "standardFlowEnabled": true,
      "implicitFlowEnabled": false,
      "directAccessGrantsEnabled": false,
      "attributes": {
        "post.logout.redirect.uris": "*"
      },
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
    },
    {
      "clientId": "iot-bridge",
      "name": "IoT Bridge API",
      "enabled": true,
      "protocol": "openid-connect",
      "publicClient": false,
      "secret": "${BRIDGE_OIDC_SECRET}",
      "serviceAccountsEnabled": true,
      "standardFlowEnabled": false,
      "directAccessGrantsEnabled": false,
      "authorizationServicesEnabled": false
    },
    {
      "clientId": "terminal-proxy",
      "name": "Terminal Proxy",
      "enabled": true,
      "protocol": "openid-connect",
      "publicClient": true,
      "redirectUris": ["*"],
      "webOrigins": ["*"],
      "standardFlowEnabled": true,
      "implicitFlowEnabled": false,
      "directAccessGrantsEnabled": false
    },
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
      "clientId": "influxdb-proxy",
      "name": "InfluxDB Proxy",
      "enabled": true,
      "protocol": "openid-connect",
      "publicClient": false,
      "secret": "${INFLUX_PROXY_OIDC_SECRET}",
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
    "REGISTER",
    "LOGIN",
    "CLIENT_LOGIN",
    "UPDATE_PROFILE",
    "UPDATE_PASSWORD"
  ],
  "adminEventsEnabled": true,
  "adminEventsDetailsEnabled": true
}
