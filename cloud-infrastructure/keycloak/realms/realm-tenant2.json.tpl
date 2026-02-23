{
  "id": "tenant2",
  "realm": "tenant2",
  "displayName": "Beta Industries Ltd",
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
      "username": "dave",
      "email": "dave@beta-industries.example.com",
      "firstName": "Dave",
      "lastName": "Fletcher",
      "enabled": true,
      "emailVerified": true,
      "realmRoles": ["cdm-admin"],
      "credentials": [
        { "type": "password", "value": "${TENANT2_ADMIN_PASSWORD}", "temporary": true }
      ]
    },
    {
      "username": "eve",
      "email": "eve@beta-industries.example.com",
      "firstName": "Eve",
      "lastName": "Martin",
      "enabled": true,
      "emailVerified": true,
      "realmRoles": ["cdm-operator"],
      "credentials": [
        { "type": "password", "value": "${TENANT2_OPERATOR_PASSWORD}", "temporary": true }
      ]
    },
    {
      "username": "frank",
      "email": "frank@beta-industries.example.com",
      "firstName": "Frank",
      "lastName": "Thompson",
      "enabled": true,
      "emailVerified": true,
      "realmRoles": ["cdm-viewer"],
      "credentials": [
        { "type": "password", "value": "${TENANT2_VIEWER_PASSWORD}", "temporary": true }
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
