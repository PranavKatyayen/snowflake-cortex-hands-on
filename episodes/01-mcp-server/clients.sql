/* =============================================================================
   EPISODE 1 · STEP 9 — Connect AI clients (Claude, Cursor) with OAuth
   Run AFTER lab.sql. Needs ACCOUNTADMIN (security integrations).
============================================================================= */
USE ROLE ACCOUNTADMIN;

-- 9.1  OAuth sessions start in your DEFAULT role + DEFAULT warehouse.
--      ACCOUNTADMIN / SECURITYADMIN are blocked for OAuth, so point them at the lab role.
--      (cleanup.sql puts your default role back.)
SET my_user = CURRENT_USER();
ALTER USER IDENTIFIER($my_user) SET DEFAULT_ROLE = 'MCP_LAB_ROLE' DEFAULT_WAREHOUSE = 'MCP_LAB_WH';

-- 9.2  Claude (claude.ai web & Claude Desktop): public client + PKCE
CREATE OR REPLACE SECURITY INTEGRATION SNOWBREW_MCP_CLAUDE
  TYPE = OAUTH
  OAUTH_CLIENT = CUSTOM
  OAUTH_CLIENT_TYPE = 'PUBLIC'
  OAUTH_REDIRECT_URI = 'https://claude.ai/api/mcp/auth_callback'
  OAUTH_ENFORCE_PKCE = TRUE
  OAUTH_ISSUE_REFRESH_TOKENS = TRUE
  OAUTH_REFRESH_TOKEN_VALIDITY = 86400
  OAUTH_USE_SECONDARY_ROLES = NONE
  ENABLED = TRUE
  COMMENT = 'Episode 1: Claude -> Snowbrew MCP server';

-- 9.3  Cursor: confidential client with Cursor's loopback callback.
--      (Snowflake only allows custom schemes like cursor:// on PUBLIC clients.)
CREATE OR REPLACE SECURITY INTEGRATION SNOWBREW_MCP_CURSOR
  TYPE = OAUTH
  OAUTH_CLIENT = CUSTOM
  OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
  OAUTH_REDIRECT_URI = 'http://localhost:8787/callback'
  OAUTH_ALLOW_NON_TLS_REDIRECT_URI = TRUE
  OAUTH_ISSUE_REFRESH_TOKENS = TRUE
  OAUTH_REFRESH_TOKEN_VALIDITY = 86400
  OAUTH_USE_SECONDARY_ROLES = NONE
  ENABLED = TRUE
  COMMENT = 'Episode 1: Cursor -> Snowbrew MCP server';

-- 9.4  Copy your client ID (and secret, for Cursor). Keep these private.
SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('SNOWBREW_MCP_CLAUDE');
SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('SNOWBREW_MCP_CURSOR');

-- 9.5  Your MCP server URL (paste this into the client):
SELECT 'https://' || LOWER(CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME())
       || '.snowflakecomputing.com/api/v2/databases/SNOWBREW_LAB/schemas/CORE/mcp-servers/SNOWBREW_MCP' AS MCP_SERVER_URL;
