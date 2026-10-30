/* ============================================================================
   Snowflake Cortex Hands-On · Episode 2 cleanup
   Removes everything the coding agent built (apps, stages, views, models).
   Episode 1 keeps working. The builder tool stays on the MCP server until you
   re-run Episode 1's lab.sql (STEP 7 recreates the server without it).
   To remove both episodes, run episodes/01-mcp-server/cleanup.sql instead.
   ============================================================================ */

USE ROLE MCP_LAB_ROLE;

DROP SCHEMA IF EXISTS SNOWBREW_LAB.APPS CASCADE;
