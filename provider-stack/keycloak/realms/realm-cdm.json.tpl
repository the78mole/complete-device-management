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
      "attributes": { "tenant": ["cdm"] },
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
      "attributes": { "tenant": ["cdm"] },
      "realmRoles": ["cdm-operator"],
      "clientRoles": { "account": ["manage-account", "view-profile"] },
      "credentials": [
        { "type": "password", "value": "changeme", "temporary": true }
      ]
    }
  ],
  "clients": [
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
        },
        {
          "name": "tenant-claim",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-usermodel-attribute-mapper",
          "consentRequired": false,
          "config": {
            "claim.name": "tenant",
            "user.attribute": "tenant",
            "jsonType.label": "String",
            "multivalued": "false",
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
  "identityProviders": [
    {
      "alias": "provider",
      "displayName": "CDM Provider – Platform Operations",
      "providerId": "keycloak-oidc",
      "enabled": true,
      "trustEmail": true,
      "storeToken": false,
      "addReadTokenRoleOnCreate": false,
      "authenticateByDefault": false,
      "linkOnly": false,
      "firstBrokerLoginFlowAlias": "first broker login",
      "config": {
        "clientId": "grafana-broker",
        "clientSecret": "${GRAFANA_BROKER_SECRET}",
        "tokenUrl": "http://keycloak:8080/auth/realms/provider/protocol/openid-connect/token",
        "authorizationUrl": "${EXTERNAL_URL}/auth/realms/provider/protocol/openid-connect/auth",
        "jwksUrl": "http://keycloak:8080/auth/realms/provider/protocol/openid-connect/certs",
        "logoutUrl": "http://keycloak:8080/auth/realms/provider/protocol/openid-connect/logout",
        "userInfoUrl": "http://keycloak:8080/auth/realms/provider/protocol/openid-connect/userinfo",
        "issuer": "http://keycloak:8080/auth/realms/provider",
        "validateSignature": "true",
        "useJwksUrl": "true",
        "syncMode": "FORCE"
      }
    }
  ],
  "identityProviderMappers": [
    {
      "name": "provider-tenant-attr",
      "identityProviderAlias": "provider",
      "identityProviderMapper": "hardcoded-attribute-idp-mapper",
      "config": { "syncMode": "INHERIT", "attribute": "tenant", "attribute.value": "provider" }
    },
    {
      "name": "provider-role-admin",
      "identityProviderAlias": "provider",
      "identityProviderMapper": "oidc-role-idp-mapper",
      "config": { "syncMode": "INHERIT", "claim": "roles", "claim.value": "platform-admin", "role": "cdm-admin" }
    },
    {
      "name": "provider-role-operator",
      "identityProviderAlias": "provider",
      "identityProviderMapper": "oidc-role-idp-mapper",
      "config": { "syncMode": "INHERIT", "claim": "roles", "claim.value": "platform-operator", "role": "cdm-operator" }
    }
  ],
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
