/* =============================================================================
   CoCo Automations probe: what can a scheduled CoCo agent actually do?
   Companion to "Night Shift Agent vs CoCo Automations" (Snowflake AI, Hands-On).

   Run as YOUR DEFAULT ROLE (automations always run as your user's default role).
   Replace MCP_LAB_WH with any warehouse you can use.
   Cost: one automation run, ~0.2-0.3 credits (measured: 0.20-0.26).

   Note: CREATE AGENT TASK is the statement Snowsight itself runs when you create
   an automation (I read it from query history). It isn't documented yet, so it
   may change during the preview. Tested 8 Nov 2026.
============================================================================= */

-- 1) A scratch table. Create it with your default role, so the INSERT test is fair.
-- USE ROLE <your default role>;
CREATE DATABASE IF NOT EXISTS AUTOMATION_PROBE_DB;
CREATE OR REPLACE TABLE AUTOMATION_PROBE_DB.PUBLIC.PROBE (NOTE STRING);
INSERT INTO AUTOMATION_PROBE_DB.PUBLIC.PROBE VALUES ('written by me, interactively');   -- works

-- 2) The automation: an AGENT TASK in your personal database
CREATE OR REPLACE AGENT TASK "USER$".PUBLIC.COCO_ROUTINE_AUTOMATION_PROBE
  SCHEDULE = 'USING CRON 0 0 1 1 * UTC'   -- effectively never; we run it by hand
  COMMENT  = 'automation probe'
FROM SPECIFICATION $${
  "origin_application": "sql_function",
  "parent_message_id": 0,
  "messages": [{"role": "user", "content": [{"type": "text", "text":
    "You are running unattended in a Snowflake AGENT TASK. This is a capability probe. Do NOT ask questions. Run each SQL statement below with the SQL tool, separately, exactly once, in order, even if an earlier one fails. Then reply with the exact result or exact error of each.\n1. SELECT 'PROBE-1' AS STEP, CURRENT_USER() AS U, CURRENT_ROLE() AS R, CURRENT_SECONDARY_ROLES() AS SR\n2. INSERT INTO AUTOMATION_PROBE_DB.PUBLIC.PROBE VALUES ('PROBE-2')\n3. SELECT 'PROBE-3' AS STEP, AI_COMPLETE('llama3.1-8b', 'Reply with the single word OK') AS A"}]}],
  "experimental": {
    "EnableSandboxPermissionSystem": false,
    "EnableToolPermissionSystem": false,
    "FallbackWarehouse": "MCP_LAB_WH",
    "codingAgent": {"HeadlessSandboxClient": true, "SandboxEnable": true, "SandboxTools": "*",
                    "originApplication": "cortex-code-routine", "sessionId": "automation-probe"}
  }
}$$;

EXECUTE AGENT TASK "USER$".PUBLIC.COCO_ROUTINE_AUTOMATION_PROBE;

-- 3) Wait ~1 minute (an email also arrives), then read what the agent's SQL did:
SELECT START_TIME, ROLE_NAME, EXECUTION_STATUS, LEFT(QUERY_TEXT, 80) AS QUERY, ERROR_MESSAGE
FROM TABLE(AUTOMATION_PROBE_DB.INFORMATION_SCHEMA.QUERY_HISTORY_BY_USER(RESULT_LIMIT => 200))
WHERE QUERY_TEXT ILIKE 'SELECT ''PROBE-%' OR QUERY_TEXT ILIKE 'INSERT INTO AUTOMATION_PROBE_DB%'
ORDER BY START_TIME DESC;

-- 4) Compare: the same AI call, run by you
SELECT AI_COMPLETE('llama3.1-8b', 'Reply with the single word OK') AS A;

-- 5) Clean up
-- DROP AGENT TASK IF EXISTS "USER$".PUBLIC.COCO_ROUTINE_AUTOMATION_PROBE;
-- DROP DATABASE IF EXISTS AUTOMATION_PROBE_DB;
