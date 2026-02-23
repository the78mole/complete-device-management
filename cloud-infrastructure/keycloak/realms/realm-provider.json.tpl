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
  "clients": [],
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
