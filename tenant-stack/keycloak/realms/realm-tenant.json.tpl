{
  "id": "${TENANT_ID}",
  "realm": "${TENANT_ID}",
  "displayName": "${TENANT_DISPLAY_NAME}",
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
      "username": "admin",
      "email": "${TENANT_ADMIN_EMAIL}",
      "firstName": "Tenant",
      "lastName": "Admin",
      "enabled": true,
      "emailVerified": true,
      "realmRoles": ["cdm-admin"],
      "clientRoles": { "realm-management": ["realm-admin"], "account": ["manage-account", "view-profile"] },
      "credentials": [
        { "type": "password", "value": "${TENANT_ADMIN_PASSWORD}", "temporary": true }
      ]
    },
    {
      "username": "operator",
      "email": "${TENANT_OPERATOR_EMAIL}",
      "firstName": "Tenant",
      "lastName": "Operator",
      "enabled": true,
      "emailVerified": true,
      "realmRoles": ["cdm-operator"],
      "clientRoles": { "account": ["manage-account", "view-profile"] },
      "credentials": [
        { "type": "password", "value": "${TENANT_OPERATOR_PASSWORD}", "temporary": true }
      ]
    },
    {
      "username": "viewer",
      "email": "${TENANT_VIEWER_EMAIL}",
      "firstName": "Tenant",
      "lastName": "Viewer",
      "enabled": true,
      "emailVerified": true,
      "realmRoles": ["cdm-viewer"],
      "clientRoles": { "account": ["manage-account", "view-profile"] },
      "credentials": [
        { "type": "password", "value": "${TENANT_VIEWER_PASSWORD}", "temporary": true }
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
      "secret": "${GRAFANA_OIDC_SECRET}",
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
    },
    {
      "clientId": "grafana",
      "name": "Grafana",
      "enabled": true,
      "protocol": "openid-connect",
      "publicClient": false,
      "secret": "${GRAFANA_OIDC_SECRET}",
      "redirectUris": [
        "${EXTERNAL_URL}/grafana/*",
        "http://localhost:3000/*"
      ],
      "webOrigins": ["*"],
      "standardFlowEnabled": true,
      "implicitFlowEnabled": false,
      "directAccessGrantsEnabled": false,
      "attributes": {
        "post.logout.redirect.uris": "${EXTERNAL_URL}/grafana/login"
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
      "clientId": "thingsboard",
      "name": "ThingsBoard",
      "enabled": true,
      "protocol": "openid-connect",
      "publicClient": false,
      "secret": "${TB_OIDC_SECRET}",
      "redirectUris": [
        "${TB_EXTERNAL_URL}/*"
      ],
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
    },
    {
      "clientId": "hawkbit",
      "name": "hawkBit",
      "enabled": true,
      "protocol": "openid-connect",
      "publicClient": false,
      "secret": "${HB_OIDC_SECRET}",
      "redirectUris": [
        "${EXTERNAL_URL}/hawkbit/*"
      ],
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
    },
    {
      "clientId": "iot-bridge",
      "name": "IoT Bridge API",
      "enabled": true,
      "protocol": "openid-connect",
      "publicClient": false,
      "secret": "${BRIDGE_OIDC_SECRET}",
      "redirectUris": ["${EXTERNAL_URL}/api/*"],
      "webOrigins": ["*"],
      "standardFlowEnabled": true,
      "implicitFlowEnabled": false,
      "directAccessGrantsEnabled": true,
      "serviceAccountsEnabled": true,
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
      "attributes": { "post.logout.redirect.uris": "*" }
    },
    {
      "clientId": "terminal-proxy",
      "name": "Terminal Proxy",
      "enabled": true,
      "protocol": "openid-connect",
      "publicClient": true,
      "redirectUris": ["${EXTERNAL_URL}/terminal/*"],
      "webOrigins": ["*"],
      "standardFlowEnabled": true,
      "implicitFlowEnabled": false,
      "directAccessGrantsEnabled": false,
      "attributes": { "post.logout.redirect.uris": "*" }
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
