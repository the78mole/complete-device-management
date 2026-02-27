{
  "id": "provider",
  "realm": "provider",
  "displayName": "CDM Provider – Platform Operations",
  "displayNameHtml": "<b>CDM Provider</b> – Platform Operations",
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
      {
        "name": "platform-admin",
        "description": "Full administrative access to the CDM platform and all tenants"
      },
      {
        "name": "platform-operator",
        "description": "Day-to-day platform operations; read access to tenants"
      }
    ]
  },
  "users": [
    {
      "username": "${KC_ADMIN_USER}",
      "email": "${KC_ADMIN_USER}@example.com",
      "firstName": "Platform",
      "lastName": "Superadmin",
      "enabled": true,
      "emailVerified": true,
      "realmRoles": ["platform-admin"],
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
      "realmRoles": ["platform-operator"],
      "clientRoles": { "account": ["manage-account", "view-profile"] },
      "credentials": [
        { "type": "password", "value": "${PROVIDER_OPERATOR_PASSWORD}", "temporary": true }
      ]
    }
  ],
  "clientScopes": [
    {
      "name": "openid",
      "description": "OpenID Connect built-in scope – signals that an ID token should be returned",
      "protocol": "openid-connect",
      "attributes": { "include.in.token.scope": "true", "display.on.consent.screen": "false" }
    },
    {
      "name": "profile",
      "description": "OpenID Connect built-in scope – adds standard profile claims (name, username, etc.)",
      "protocol": "openid-connect",
      "attributes": { "include.in.token.scope": "true", "display.on.consent.screen": "true" },
      "protocolMappers": [
        { "name": "username", "protocol": "openid-connect", "protocolMapper": "oidc-usermodel-property-mapper",
          "config": { "claim.name": "preferred_username", "user.attribute": "username",
                      "id.token.claim": "true", "access.token.claim": "true", "userinfo.token.claim": "true", "jsonType.label": "String" }},
        { "name": "full name", "protocol": "openid-connect", "protocolMapper": "oidc-full-name-mapper",
          "config": { "id.token.claim": "true", "access.token.claim": "true", "userinfo.token.claim": "true" }},
        { "name": "given name", "protocol": "openid-connect", "protocolMapper": "oidc-usermodel-attribute-mapper",
          "config": { "claim.name": "given_name", "user.attribute": "firstName",
                      "id.token.claim": "true", "access.token.claim": "true", "userinfo.token.claim": "true", "jsonType.label": "String" }},
        { "name": "family name", "protocol": "openid-connect", "protocolMapper": "oidc-usermodel-attribute-mapper",
          "config": { "claim.name": "family_name", "user.attribute": "lastName",
                      "id.token.claim": "true", "access.token.claim": "true", "userinfo.token.claim": "true", "jsonType.label": "String" }}
      ]
    },
    {
      "name": "email",
      "description": "OpenID Connect built-in scope – adds email claim",
      "protocol": "openid-connect",
      "attributes": { "include.in.token.scope": "true", "display.on.consent.screen": "true" },
      "protocolMappers": [
        { "name": "email", "protocol": "openid-connect", "protocolMapper": "oidc-usermodel-attribute-mapper",
          "config": { "claim.name": "email", "user.attribute": "email",
                      "id.token.claim": "true", "access.token.claim": "true", "userinfo.token.claim": "true", "jsonType.label": "String" }},
        { "name": "email verified", "protocol": "openid-connect", "protocolMapper": "oidc-usermodel-property-mapper",
          "config": { "claim.name": "email_verified", "user.attribute": "emailVerified",
                      "id.token.claim": "true", "access.token.claim": "true", "userinfo.token.claim": "true", "jsonType.label": "boolean" }}
      ]
    },
    {
      "name": "rabbitmq.tag:administrator",
      "description": "RabbitMQ management tag: administrator",
      "protocol": "openid-connect",
      "attributes": {
        "include.in.token.scope": "true",
        "display.on.consent.screen": "false"
      }
    },
    {
      "name": "rabbitmq.tag:monitoring",
      "description": "RabbitMQ management tag: monitoring (read-only UI)",
      "protocol": "openid-connect",
      "attributes": {
        "include.in.token.scope": "true",
        "display.on.consent.screen": "false"
      }
    },
    {
      "name": "rabbitmq.read:*/*",
      "description": "RabbitMQ: read access on all vhosts/resources",
      "protocol": "openid-connect",
      "attributes": {
        "include.in.token.scope": "true",
        "display.on.consent.screen": "false"
      }
    },
    {
      "name": "rabbitmq.write:*/*",
      "description": "RabbitMQ: write access on all vhosts/resources",
      "protocol": "openid-connect",
      "attributes": {
        "include.in.token.scope": "true",
        "display.on.consent.screen": "false"
      }
    },
    {
      "name": "rabbitmq.configure:*/*",
      "description": "RabbitMQ: configure access on all vhosts/resources",
      "protocol": "openid-connect",
      "attributes": {
        "include.in.token.scope": "true",
        "display.on.consent.screen": "false"
      }
    }
  ],
  "clients": [
    {
      "clientId": "rabbitmq-management",
      "name": "RabbitMQ Management",
      "description": "OAuth2/OIDC login for the RabbitMQ management UI (provider-realm admins)",
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
        "openid",
        "profile",
        "email",
        "rabbitmq.tag:administrator",
        "rabbitmq.read:*/*",
        "rabbitmq.write:*/*",
        "rabbitmq.configure:*/*"
      ],
      "optionalClientScopes": [
        "rabbitmq.tag:monitoring"
      ],
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
      "clientId": "grafana-broker",
      "name": "Grafana Identity Broker",
      "description": "Used by the cdm realm to broker provider-realm logins into Grafana.",
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
