/* =============================================================================
   EPISODE 3 · Cleanup. Safe to re-run.
============================================================================= */
USE ROLE ACCOUNTADMIN;

-- A) Stop the night shift and remove everything Episode 3 created.
--    Episodes 1 and 2 (if you have them) keep working.
ALTER TASK IF EXISTS SNOWBREW_LAB.NIGHT_SHIFT.NIGHTLY_REVIEW SUSPEND;
DROP SCHEMA IF EXISTS SNOWBREW_LAB.NIGHT_SHIFT CASCADE;   -- data, playbook skill, procedures, task, app
DROP ROLE   IF EXISTS NIGHT_SHIFT_ROLE;

-- B) Remove EVERYTHING from the series labs (data, warehouse, role, OAuth clients).
--    Uncomment only if you're done with all episodes.
-- SET my_user = CURRENT_USER();
-- ALTER USER IDENTIFIER($my_user) SET DEFAULT_ROLE = 'ACCOUNTADMIN';
-- ALTER USER IDENTIFIER($my_user) UNSET DEFAULT_WAREHOUSE;
-- DROP SECURITY INTEGRATION IF EXISTS SNOWBREW_MCP_CLAUDE;
-- DROP SECURITY INTEGRATION IF EXISTS SNOWBREW_MCP_CURSOR;
-- DROP DATABASE  IF EXISTS SNOWBREW_LAB;
-- DROP WAREHOUSE IF EXISTS MCP_LAB_WH;
-- DROP ROLE      IF EXISTS MCP_LAB_ROLE;
-- ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'DISABLED';   -- only if you enabled it just for these labs
