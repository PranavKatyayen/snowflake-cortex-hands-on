/* =============================================================================
   SNOWFLAKE AI, HANDS-ON · EPISODE 3 · PART 2 of 2
   "The Night Shift": night 2, then teach the agent a new rule

   Run this AFTER setup-part1.sql has finished.
   How to run : Snowsight > SQL worksheet > paste > Run All (~3 minutes).
   Measured   : ~0.2 agent credits (night 2 ~0.07, the re-run with the new rule ~0.1).
   Last result: night 2 BEFORE vs AFTER the new rule, side by side.
============================================================================= */


/* -----------------------------------------------------------------------------
   STEP 6 · Night 2, fully unattended            role: NIGHT_SHIFT_ROLE · ~1 min
   Why : prove the real scheduled task works with nobody involved.
   What happens: loads 2 Oct, then runs the actual NIGHTLY_REVIEW task once.
   The task wakes the agent, the agent reviews 2 Oct, and the procedure saves
   the brief. The block below waits until the task has finished (it checks
   every 10 seconds, for up to 5 minutes) so the next step doesn't overlap it.
   Expect: "Night 2 task: SUCCEEDED". In the app (pick 2026-10-02):
   Indiranagar (Bengaluru) HIGH -31.1% after a power cut.
----------------------------------------------------------------------------- */
USE ROLE NIGHT_SHIFT_ROLE;
USE WAREHOUSE MCP_LAB_WH;
CALL SNOWBREW_LAB.NIGHT_SHIFT.LOAD_NEXT_DAY();             -- 2 Oct lands

EXECUTE IMMEDIATE $$
DECLARE
  started TIMESTAMP_LTZ;
  st VARCHAR DEFAULT 'SCHEDULED';
  i INTEGER DEFAULT 0;
BEGIN
  started := DATEADD('second', -5, CURRENT_TIMESTAMP());
  EXECUTE TASK SNOWBREW_LAB.NIGHT_SHIFT.NIGHTLY_REVIEW;
  WHILE (i < 30 AND st NOT IN ('SUCCEEDED', 'FAILED', 'CANCELLED')) DO
    SELECT SYSTEM$WAIT(10);
    st := (SELECT COALESCE(MAX_BY(STATE, SCHEDULED_TIME), 'SCHEDULED')
           FROM TABLE(SNOWBREW_LAB.INFORMATION_SCHEMA.TASK_HISTORY(TASK_NAME => 'NIGHTLY_REVIEW'))
           WHERE SCHEDULED_TIME >= :started);
    i := i + 1;
  END WHILE;
  RETURN 'Night 2 task: ' || st;
END;
$$;

-- What night 2 flagged with the current playbook (kept for the comparison at the end)
SET night2_old_rules = (
  SELECT LISTAGG(STORE_NAME || ' ' || SEVERITY, ' | ') WITHIN GROUP (ORDER BY SEVERITY, STORE_NAME)
  FROM SNOWBREW_LAB.NIGHT_SHIFT.MORNING_BRIEF
  WHERE BRIEF_DATE = '2026-10-02' AND SEVERITY <> 'SUMMARY');


/* -----------------------------------------------------------------------------
   STEP 7 · Teach it a new rule, in plain English   roles: MCP_LAB_ROLE, then NIGHT_SHIFT_ROLE · ~1 min
   Why : the playbook only checks store revenue, so night 2 misses Singapore's
   oat-cookie sell-out (store revenue was only -3.2%). One new sentence in
   house_rules.md fixes that. No code change.
   What happens: rewrites house_rules.md with a third rule, then re-runs the
   review of the same night. Edit the rule text to try your own!
   Expect: Tanjong Pagar (Singapore) MEDIUM "Sell-out: ...", Oat Cookie
   4 units vs 19.75 same-weekday average (20.3% of normal).
----------------------------------------------------------------------------- */
USE ROLE MCP_LAB_ROLE;
CALL SNOWBREW_LAB.NIGHT_SHIFT.WRITE_STAGE_FILE(
  '@SNOWBREW_LAB.NIGHT_SHIFT.PLAYBOOK/skills/snowbrew-playbook/house_rules.md',
'# Snowbrew house rules
- Write money as USD with thousands separators, e.g. $1,234.56.
- Name the city next to every store, e.g. "Surry Hills (Sydney)".
- Sell-outs: for every store, compare each product''s units on the latest day with the same weekday over the previous 4 weeks. If a product sold less than 40% of normal, add it to the brief as MEDIUM with a headline starting "Sell-out:", even if the store''s total revenue looks fine.
');

USE ROLE NIGHT_SHIFT_ROLE;
CALL SNOWBREW_LAB.NIGHT_SHIFT.RUN_NIGHT_SHIFT();           -- the same night, new rule


/* -----------------------------------------------------------------------------
   RESULT · Night 2, before vs after the new rule
   Then refresh the app (Snowsight > Apps > Streamlit > Snowbrew Morning Brief,
   pick 2026-10-02) to see the new "Sell-out:" card.
----------------------------------------------------------------------------- */
SELECT $night2_old_rules AS BEFORE_NEW_RULE,
       (SELECT LISTAGG(STORE_NAME || ' ' || SEVERITY, ' | ') WITHIN GROUP (ORDER BY SEVERITY, STORE_NAME)
        FROM SNOWBREW_LAB.NIGHT_SHIFT.MORNING_BRIEF
        WHERE BRIEF_DATE = '2026-10-02' AND SEVERITY <> 'SUMMARY') AS AFTER_NEW_RULE,
       (SELECT HEADLINE || ' · ' || EVIDENCE FROM SNOWBREW_LAB.NIGHT_SHIFT.MORNING_BRIEF
        WHERE BRIEF_DATE = '2026-10-02' AND HEADLINE ILIKE 'Sell-out%' LIMIT 1) AS THE_NEW_CATCH;


/* -----------------------------------------------------------------------------
   OPTIONAL (one line each; select the line and press Ctrl+Enter / Cmd+Enter)
   Rebuild the app if you deleted it (~1 min, ~0.4 agent credits):
     CALL SNOWBREW_LAB.NIGHT_SHIFT.BUILD_MORNING_BRIEF_APP();
   Run the review every night at 06:00 Tokyo (0.07-0.31 agent credits a night):
     ALTER TASK SNOWBREW_LAB.NIGHT_SHIFT.NIGHTLY_REVIEW RESUME;
   Stop it:
     ALTER TASK SNOWBREW_LAB.NIGHT_SHIFT.NIGHTLY_REVIEW SUSPEND;
   See every run the agent did:
     SELECT RUN_AT, STATUS, TOOL_CALLS, SUMMARY FROM SNOWBREW_LAB.NIGHT_SHIFT.NIGHT_SHIFT_LOG ORDER BY RUN_AT DESC;
   Clean up everything from this episode: run cleanup.sql
----------------------------------------------------------------------------- */
