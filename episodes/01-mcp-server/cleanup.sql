/* =============================================================================
   EPISODE 1 · Cleanup — removes everything the lab created. Safe to re-run.
============================================================================= */
USE ROLE ACCOUNTADMIN;

SET my_user = CURRENT_USER();
ALTER USER IDENTIFIER($my_user) SET DEFAULT_ROLE = 'ACCOUNTADMIN';   -- or your usual role
ALTER USER IDENTIFIER($my_user) UNSET DEFAULT_WAREHOUSE;

DROP SECURITY INTEGRATION IF EXISTS SNOWBREW_MCP_CLAUDE;
DROP SECURITY INTEGRATION IF EXISTS SNOWBREW_MCP_CURSOR;

DROP DATABASE  IF EXISTS SNOWBREW_LAB;      -- tables, search service, semantic view, agent, MCP server
DROP WAREHOUSE IF EXISTS MCP_LAB_WH;
DROP ROLE      IF EXISTS MCP_LAB_ROLE;

-- Optional: revert cross-region inference if you changed it only for this lab
-- ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'DISABLED';
