%% advanced.config – RabbitMQ OAuth2 / Keycloak integration (CDM Provider Stack)
%%
%% This file is templated by rabbitmq/docker-entrypoint.sh at container start
%% using sed to substitute PLACEHOLDER values from environment variables:
%%   RABBITMQ_MANAGEMENT_OIDC_SECRET_PLACEHOLDER → RABBITMQ_MANAGEMENT_OIDC_SECRET
%%   EXTERNAL_URL_PLACEHOLDER                    → EXTERNAL_URL
%%
%% Using advanced.config (Erlang syntax) instead of rabbitmq.conf for all
%% auth_oauth2.* settings because RabbitMQ 4.x's cuttlefish config enforces
%% HTTPS on every auth_oauth2 URL — which is not satisfied in a plain HTTP
%% local-dev / Codespaces environment.
[
  %% ── Auth backends ──────────────────────────────────────────────────────
  %% Priority 1: validate JWT tokens from Keycloak (management UI SSO + AMQP)
  %% Priority 2: internal credentials (local admin user, telegraf)
  {rabbit, [
    {auth_backends, [rabbit_auth_backend_oauth2, rabbit_auth_backend_internal]}
  ]},

  %% ── OAuth2 Auth Backend (JWT validation) ───────────────────────────────
  %% Validates access tokens issued by the Keycloak provider realm.
  %% jwks_url: JWKS endpoint used to verify token signatures (server-to-server,
  %%           internal Docker hostname – avoids TLS issues).
  %% issuer:   Expected "iss" claim in tokens for additional validation.
  %%           Note: cuttlefish (rabbitmq.conf) enforces HTTPS on this setting;
  %%           advanced.config bypasses that restriction for HTTP dev setups.
  {rabbitmq_auth_backend_oauth2, [
    {resource_server_id, <<"rabbitmq">>},
    {key_config, [
      {jwks_url, <<"http://keycloak:8080/auth/realms/provider/protocol/openid-connect/certs">>}
    ]},
    {issuer, <<"http://keycloak:8080/auth/realms/provider">>},
    {algorithms, [<<"RS256">>]},
    %% Use preferred_username from the JWT payload as the RabbitMQ user name
    %% so the management UI shows the Keycloak username instead of the sub UUID.
    {preferred_username_claims, [<<"preferred_username">>, <<"email">>, <<"sub">>]}
  ]},

  %% ── Management UI – OAuth2/OIDC single-sign-on ──────────────────────────
  %% oauth_provider_url            → internal Keycloak URL for OIDC discovery
  %%                                 (token/JWKS endpoint, server-to-server)
  %% oauth_authorization_endpoint  → browser-facing Keycloak auth URL via Caddy
  %%                                 (external URL, supports Codespaces forwarding)
  {rabbitmq_management, [
    {oauth_enabled,                 true},
    {oauth_client_id,               <<"rabbitmq-management">>},
    {oauth_client_secret,           <<"RABBITMQ_MANAGEMENT_OIDC_SECRET_PLACEHOLDER">>},
    {oauth_provider_url,            <<"http://keycloak:8080/auth/realms/provider">>},
    {oauth_authorization_endpoint,  <<"EXTERNAL_URL_PLACEHOLDER/auth/realms/provider/protocol/openid-connect/auth">>},
    {oauth_scopes,                  <<"openid profile">>},
    {oauth_initiated_logon_type,    <<"sp_initiated">>}
  ]}
].
