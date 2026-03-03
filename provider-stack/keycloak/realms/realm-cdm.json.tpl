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
      { "name": "cdm-admin",    "description": "Platform administrator (CDM devices & tenants)" },
      { "name": "cdm-operator", "description": "Fleet operator" },
      { "name": "cdm-viewer",   "description": "Read-only access" },
      { "name": "platform-admin",    "description": "Full administrative access to the CDM platform and all tenants" },
      { "name": "platform-operator", "description": "Day-to-day platform operations; read access to tenants" },
      { "name": "pgadmin-users",     "description": "Users allowed to access pgAdmin via OIDC" },
      {
        "name": "matrix-viewer",
        "description": "Read-only access to users and roles for the Role Matrix page",
        "composite": true,
        "composites": {
          "client": {
            "realm-management": ["view-users", "query-users", "view-realm"]
          }
        }
      }
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
      "realmRoles": ["cdm-admin", "matrix-viewer"],
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
    },
    {
      "username": "${KC_ADMIN_USER}",
      "email": "${KC_ADMIN_USER}@example.com",
      "firstName": "Platform",
      "lastName": "Superadmin",
      "enabled": true,
      "emailVerified": true,
      "realmRoles": ["platform-admin", "pgadmin-users", "matrix-viewer"],
      "clientRoles": { "account": ["manage-account", "view-profile"] },
      "credentials": [
        { "type": "password", "value": "${KC_ADMIN_PASSWORD}", "temporary": false }
      ]
    },
    {
      "username": "provider-operator",
      "email": "provider-operator@example.com",
      "firstName": "Provider",
      "lastName": "Operator",
      "enabled": true,
      "emailVerified": true,
      "realmRoles": ["platform-operator", "pgadmin-users", "matrix-viewer"],
      "clientRoles": { "account": ["manage-account", "view-profile"] },
      "credentials": [
        { "type": "password", "value": "${PROVIDER_OPERATOR_PASSWORD}", "temporary": true }
      ]
    }
  ],
  "clientScopes": [
    {
      "name": "rabbitmq.tag:administrator",
      "description": "RabbitMQ management tag: administrator",
      "protocol": "openid-connect",
      "attributes": { "include.in.token.scope": "true", "display.on.consent.screen": "false" }
    },
    {
      "name": "rabbitmq.tag:monitoring",
      "description": "RabbitMQ management tag: monitoring (read-only UI)",
      "protocol": "openid-connect",
      "attributes": { "include.in.token.scope": "true", "display.on.consent.screen": "false" }
    },
    {
      "name": "rabbitmq.read:*/*",
      "description": "RabbitMQ: read access on all vhosts/resources",
      "protocol": "openid-connect",
      "attributes": { "include.in.token.scope": "true", "display.on.consent.screen": "false" }
    },
    {
      "name": "rabbitmq.write:*/*",
      "description": "RabbitMQ: write access on all vhosts/resources",
      "protocol": "openid-connect",
      "attributes": { "include.in.token.scope": "true", "display.on.consent.screen": "false" }
    },
    {
      "name": "rabbitmq.configure:*/*",
      "description": "RabbitMQ: configure access on all vhosts/resources",
      "protocol": "openid-connect",
      "attributes": { "include.in.token.scope": "true", "display.on.consent.screen": "false" }
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
        },
        {
          "name": "username",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-usermodel-property-mapper",
          "consentRequired": false,
          "config": {
            "claim.name": "preferred_username",
            "user.attribute": "username",
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
      "clientId": "dashboard",
      "name": "CDM Dashboard",
      "description": "Public OIDC client for the provider stack landing page – silent SSO check, user info & logout",
      "enabled": true,
      "protocol": "openid-connect",
      "publicClient": true,
      "redirectUris": ["*"],
      "webOrigins": ["*"],
      "standardFlowEnabled": true,
      "implicitFlowEnabled": false,
      "directAccessGrantsEnabled": false,
      "attributes": { "post.logout.redirect.uris": "*", "pkce.code.challenge.method": "S256" }
    },
    {
      "clientId": "rabbitmq-management",
      "name": "RabbitMQ Management",
      "description": "OAuth2/OIDC login for the RabbitMQ management UI",
      "enabled": true,
      "protocol": "openid-connect",
      "publicClient": false,
      "secret": "${RABBITMQ_MANAGEMENT_OIDC_SECRET}",
      "redirectUris": ["*"],
      "webOrigins": ["*"],
      "standardFlowEnabled": true,
      "implicitFlowEnabled": false,
      "directAccessGrantsEnabled": true,
      "attributes": { "post.logout.redirect.uris": "*" },
      "defaultClientScopes": [
        "openid", "profile", "email",
        "rabbitmq.tag:administrator",
        "rabbitmq.read:*/*",
        "rabbitmq.write:*/*",
        "rabbitmq.configure:*/*"
      ],
      "optionalClientScopes": ["rabbitmq.tag:monitoring"],
      "protocolMappers": [
        {
          "name": "rabbitmq-audience",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-audience-mapper",
          "consentRequired": false,
          "config": {
            "included.custom.audience": "rabbitmq",
            "id.token.claim": "false",
            "access.token.claim": "true"
          }
        },
        {
          "name": "preferred-username",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-usermodel-property-mapper",
          "consentRequired": false,
          "config": {
            "claim.name": "preferred_username",
            "user.attribute": "username",
            "jsonType.label": "String",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "userinfo.token.claim": "true"
          }
        },
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
      "clientId": "pgadmin",
      "name": "pgAdmin",
      "description": "OIDC login for pgAdmin",
      "enabled": true,
      "protocol": "openid-connect",
      "publicClient": false,
      "secret": "${PGADMIN_OIDC_SECRET}",
      "redirectUris": [
        "${EXTERNAL_URL}/pgadmin/oauth2/authorize",
        "${EXTERNAL_URL}/pgadmin/oauth2/authorize*",
        "http://localhost:443/pgadmin/oauth2/authorize",
        "http://localhost:443/pgadmin/oauth2/authorize*",
        "http://localhost:8888/pgadmin/oauth2/authorize",
        "http://localhost:8888/pgadmin/oauth2/authorize*"
      ],
      "webOrigins": ["${EXTERNAL_URL}", "http://localhost:8888"],
      "standardFlowEnabled": true,
      "implicitFlowEnabled": false,
      "directAccessGrantsEnabled": false,
      "attributes": { "post.logout.redirect.uris": "${EXTERNAL_URL}/pgadmin/*" },
      "defaultClientScopes": ["openid", "profile", "email", "roles"],
      "protocolMappers": [
        {
          "name": "preferred-username",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-usermodel-property-mapper",
          "consentRequired": false,
          "config": {
            "claim.name": "preferred_username",
            "user.attribute": "username",
            "jsonType.label": "String",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "userinfo.token.claim": "true"
          }
        },
        {
          "name": "email",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-usermodel-property-mapper",
          "consentRequired": false,
          "config": {
            "claim.name": "email",
            "user.attribute": "email",
            "jsonType.label": "String",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "userinfo.token.claim": "true"
          }
        },
        {
          "name": "realm-roles",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-usermodel-realm-role-mapper",
          "consentRequired": false,
          "config": {
            "claim.name": "roles",
            "multivalued": "true",
            "jsonType.label": "String",
            "access.token.claim": "true",
            "id.token.claim": "true",
            "userinfo.token.claim": "true"
          }
        }
      ]
    }
  ],
  "identityProviders": [],
  "identityProviderMappers": [],
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
