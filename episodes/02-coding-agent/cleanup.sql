/* =============================================================================
   EPISODE 2 · Cleanup. Safe to re-run.
============================================================================= */
USE ROLE ACCOUNTADMIN;

-- A) Remove what Episode 2 added: the agent's apps, stages, models and the builder server.
--    Episode 1 (if you have it) keeps working.
DROP SCHEMA     IF EXISTS SNOWBREW_LAB.APPS CASCADE;
DROP MCP SERVER IF EXISTS SNOWBREW_LAB.CORE.SNOWBREW_BUILDER_MCP;

-- B) Remove EVERYTHING (data, warehouse, role, OAuth clients), including Episode 1.
--    Uncomment and run only if you're done with the series labs.
-- SET my_user = CURRENT_USER();
-- ALTER USER IDENTIFIER($my_user) SET DEFAULT_ROLE = 'ACCOUNTADMIN';   -- or your usual role
-- ALTER USER IDENTIFIER($my_user) UNSET DEFAULT_WAREHOUSE;
-- DROP SECURITY INTEGRATION IF EXISTS SNOWBREW_MCP_CLAUDE;
-- DROP SECURITY INTEGRATION IF EXISTS SNOWBREW_MCP_CURSOR;
-- DROP DATABASE  IF EXISTS SNOWBREW_LAB;
-- DROP WAREHOUSE IF EXISTS MCP_LAB_WH;
-- DROP ROLE      IF EXISTS MCP_LAB_ROLE;
-- ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'DISABLED';   -- only if you enabled it just for these labs
