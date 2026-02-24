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
  "identityProviders": [
    {
      "alias": "tenant1",
      "displayName": "Acme Devices GmbH (Tenant 1)",
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
        "tokenUrl": "http://keycloak:8080/auth/realms/tenant1/protocol/openid-connect/token",
        "authorizationUrl": "${EXTERNAL_URL}/auth/realms/tenant1/protocol/openid-connect/auth",
        "jwksUrl": "http://keycloak:8080/auth/realms/tenant1/protocol/openid-connect/certs",
        "logoutUrl": "http://keycloak:8080/auth/realms/tenant1/protocol/openid-connect/logout",
        "userInfoUrl": "http://keycloak:8080/auth/realms/tenant1/protocol/openid-connect/userinfo",
        "issuer": "http://keycloak:8080/auth/realms/tenant1",
        "validateSignature": "true",
        "useJwksUrl": "true",
        "syncMode": "FORCE"
      }
    },
    {
      "alias": "tenant2",
      "displayName": "Beta Industries Ltd (Tenant 2)",
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
        "tokenUrl": "http://keycloak:8080/auth/realms/tenant2/protocol/openid-connect/token",
        "authorizationUrl": "${EXTERNAL_URL}/auth/realms/tenant2/protocol/openid-connect/auth",
        "jwksUrl": "http://keycloak:8080/auth/realms/tenant2/protocol/openid-connect/certs",
        "logoutUrl": "http://keycloak:8080/auth/realms/tenant2/protocol/openid-connect/logout",
        "userInfoUrl": "http://keycloak:8080/auth/realms/tenant2/protocol/openid-connect/userinfo",
        "issuer": "http://keycloak:8080/auth/realms/tenant2",
        "validateSignature": "true",
        "useJwksUrl": "true",
        "syncMode": "FORCE"
      }
    },
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
      "name": "tenant1-tenant-attr",
      "identityProviderAlias": "tenant1",
      "identityProviderMapper": "hardcoded-attribute-idp-mapper",
      "config": { "syncMode": "INHERIT", "attribute": "tenant", "attribute.value": "tenant1" }
    },
    {
      "name": "tenant1-role-admin",
      "identityProviderAlias": "tenant1",
      "identityProviderMapper": "oidc-role-idp-mapper",
      "config": { "syncMode": "INHERIT", "claim": "roles", "claim.value": "cdm-admin", "role": "cdm-admin" }
    },
    {
      "name": "tenant1-role-operator",
      "identityProviderAlias": "tenant1",
      "identityProviderMapper": "oidc-role-idp-mapper",
      "config": { "syncMode": "INHERIT", "claim": "roles", "claim.value": "cdm-operator", "role": "cdm-operator" }
    },
    {
      "name": "tenant1-role-viewer",
      "identityProviderAlias": "tenant1",
      "identityProviderMapper": "oidc-role-idp-mapper",
      "config": { "syncMode": "INHERIT", "claim": "roles", "claim.value": "cdm-viewer", "role": "cdm-viewer" }
    },
    {
      "name": "tenant2-tenant-attr",
      "identityProviderAlias": "tenant2",
      "identityProviderMapper": "hardcoded-attribute-idp-mapper",
      "config": { "syncMode": "INHERIT", "attribute": "tenant", "attribute.value": "tenant2" }
    },
    {
      "name": "tenant2-role-admin",
      "identityProviderAlias": "tenant2",
      "identityProviderMapper": "oidc-role-idp-mapper",
      "config": { "syncMode": "INHERIT", "claim": "roles", "claim.value": "cdm-admin", "role": "cdm-admin" }
    },
    {
      "name": "tenant2-role-operator",
      "identityProviderAlias": "tenant2",
      "identityProviderMapper": "oidc-role-idp-mapper",
      "config": { "syncMode": "INHERIT", "claim": "roles", "claim.value": "cdm-operator", "role": "cdm-operator" }
    },
    {
      "name": "tenant2-role-viewer",
      "identityProviderAlias": "tenant2",
      "identityProviderMapper": "oidc-role-idp-mapper",
      "config": { "syncMode": "INHERIT", "claim": "roles", "claim.value": "cdm-viewer", "role": "cdm-viewer" }
    },
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
