/* =============================================================================
   SNOWFLAKE AI, HANDS-ON · EPISODE 3
   "The Night Shift": an AI agent that works while you sleep, by your playbook

   Every night a Snowflake task wakes up NIGHT_SHIFT_AGENT, a named Cortex
   coding agent. It reads your company
   playbook (a SKILL stored on a stage), checks the new day's numbers with your
   own anomaly script, investigates what moved, writes a morning brief and
   keeps a live Streamlit "Morning Brief" app up to date, styled your way.
   No chat, no clicks: it runs under a locked-down role that can only write
   to one schema.

   Standalone: you do NOT need Episodes 1 or 2. Safe to run on top of them.
   How to run : Snowsight > SQL worksheet > paste > Run All (~2-3 minutes).
   Run as     : a user who can use ACCOUNTADMIN (STEP 0 only).
   Cleanup    : cleanup.sql
============================================================================= */


/* -----------------------------------------------------------------------------
   STEP 0 · Admin setup (ACCOUNTADMIN)
----------------------------------------------------------------------------- */
USE ROLE ACCOUNTADMIN;

ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';   -- adjust if you have data-residency rules

-- The lab role you work with (same as Episodes 1-2)
CREATE ROLE IF NOT EXISTS MCP_LAB_ROLE COMMENT = 'Snowflake AI Hands-On labs';
GRANT ROLE MCP_LAB_ROLE TO ROLE SYSADMIN;
SET my_user = CURRENT_USER();
GRANT ROLE MCP_LAB_ROLE TO USER IDENTIFIER($my_user);
GRANT CREATE DATABASE  ON ACCOUNT TO ROLE MCP_LAB_ROLE;
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE MCP_LAB_ROLE;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER       TO ROLE MCP_LAB_ROLE;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE MCP_LAB_ROLE;

-- The agent's own role: it can read the night-shift data and write ONLY its brief + app.
CREATE ROLE IF NOT EXISTS NIGHT_SHIFT_ROLE COMMENT = 'Episode 3: unattended night-shift agent';
GRANT ROLE NIGHT_SHIFT_ROLE TO ROLE MCP_LAB_ROLE;        -- you can see everything it builds
GRANT EXECUTE TASK ON ACCOUNT TO ROLE NIGHT_SHIFT_ROLE;   -- it may run its own scheduled task
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER       TO ROLE NIGHT_SHIFT_ROLE;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE NIGHT_SHIFT_ROLE;


/* -----------------------------------------------------------------------------
   STEP 1 · Warehouse, database, schema
----------------------------------------------------------------------------- */
USE ROLE MCP_LAB_ROLE;

CREATE WAREHOUSE IF NOT EXISTS MCP_LAB_WH
  WAREHOUSE_SIZE = XSMALL  AUTO_SUSPEND = 60  AUTO_RESUME = TRUE  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Snowflake AI Hands-On lab warehouse';
GRANT USAGE ON WAREHOUSE MCP_LAB_WH TO ROLE NIGHT_SHIFT_ROLE;

CREATE DATABASE IF NOT EXISTS SNOWBREW_LAB;
CREATE OR REPLACE SCHEMA SNOWBREW_LAB.NIGHT_SHIFT;      -- this episode's own world, reset on every run
USE WAREHOUSE MCP_LAB_WH;
USE SCHEMA SNOWBREW_LAB.NIGHT_SHIFT;


/* -----------------------------------------------------------------------------
   STEP 2 · Data: Snowbrew Coffee Co. (fictional), 8 stores, Jun 1 – Sep 30 2026
   Same deterministic data as Episodes 1-2. New days arrive later via LOAD_NEXT_DAY().
----------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE STORES AS
SELECT $1::VARCHAR AS STORE_ID, $2::VARCHAR AS STORE_NAME, $3::VARCHAR AS CITY, $4::VARCHAR AS COUNTRY,
       $5::VARCHAR AS STORE_FORMAT, $6::FLOAT AS TRAFFIC
FROM VALUES
  ('S01','Shibuya Crossing','Tokyo','Japan','Flagship',1.30),
  ('S02','Shinjuku Station','Tokyo','Japan','Kiosk',1.10),
  ('S03','Indiranagar','Bengaluru','India','Cafe',1.00),
  ('S04','Bandra West','Mumbai','India','Cafe',0.90),
  ('S05','Soho','London','United Kingdom','Flagship',1.00),
  ('S06','SoHo Broadway','New York','United States','Flagship',1.20),
  ('S07','Tanjong Pagar','Singapore','Singapore','Cafe',0.80),
  ('S08','Surry Hills','Sydney','Australia','Drive-thru',0.70);

CREATE OR REPLACE TABLE PRODUCTS AS
SELECT $1::VARCHAR AS PRODUCT_ID, $2::VARCHAR AS PRODUCT_NAME, $3::VARCHAR AS CATEGORY,
       $4::NUMBER(6,2) AS BASE_PRICE_USD, $5::NUMBER(6,2) AS UNIT_COST_USD, $6::NUMBER AS BASE_DEMAND
FROM VALUES
  ('P01','Caffe Latte','Coffee',5.20,1.30,60), ('P02','Flat White','Coffee',5.00,1.25,35),
  ('P03','Espresso','Coffee',3.20,0.60,22),    ('P04','Cold Brew','Coffee',5.50,1.10,30),
  ('P05','Mocha','Coffee',5.80,1.60,18),       ('P06','Matcha Latte','Tea',5.60,1.70,25),
  ('P07','Masala Chai','Tea',4.20,0.90,20),    ('P08','Butter Croissant','Food',3.80,1.20,30),
  ('P09','Banana Bread','Food',3.60,1.00,15),  ('P10','Oat Cookie','Food',2.80,0.70,25);

-- One deterministic generator for any day: the base demand plus each day's "story" multiplier.
CREATE OR REPLACE FUNCTION SALES_FOR_DAYS(FROM_DAY DATE, TO_DAY DATE)
RETURNS TABLE (ORDER_DATE DATE, STORE_ID VARCHAR, PRODUCT_ID VARCHAR, UNITS NUMBER, UNIT_PRICE_USD NUMBER(6,2), UNIT_COST_USD NUMBER(6,2))
AS
$$
  WITH days AS (
    SELECT DATEADD(day, ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, FROM_DAY) AS D
    FROM TABLE(GENERATOR(ROWCOUNT => 400))
    QUALIFY D <= TO_DAY
  )
  SELECT D, s.STORE_ID, p.PRODUCT_ID,
    GREATEST(0, ROUND(
        p.BASE_DEMAND * s.TRAFFIC
        * CASE WHEN p.PRODUCT_NAME = 'Masala Chai'  AND s.COUNTRY = 'India' THEN 3.0
               WHEN p.PRODUCT_NAME = 'Matcha Latte' AND s.CITY    = 'Tokyo' THEN 2.0
               WHEN p.PRODUCT_NAME = 'Cold Brew'    AND s.CITY IN ('New York','Sydney') THEN 1.5
               ELSE 1.0 END
        * IFF(DAYOFWEEKISO(D) IN (6,7), 1.25, 1.0)
        * CASE
            -- September stories (Episodes 1-2)
            WHEN D BETWEEN '2026-09-01' AND '2026-09-30' AND s.STORE_ID = 'S01' AND p.CATEGORY = 'Coffee' THEN 0.55
            WHEN D BETWEEN '2026-09-01' AND '2026-09-30' AND s.STORE_ID = 'S01' THEN 0.80
            WHEN D BETWEEN '2026-09-01' AND '2026-09-30' AND s.STORE_ID = 'S02' THEN 1.12
            WHEN D >= '2026-09-01' AND s.STORE_ID = 'S05' AND p.PRODUCT_NAME = 'Cold Brew' THEN 0.50
            WHEN D >= '2026-08-01' AND s.COUNTRY = 'India' AND p.PRODUCT_NAME = 'Masala Chai' THEN 1.40
            -- Night 1 · Oct 1: Sydney drive-thru card terminals down; Shibuya's second espresso machine arrives
            WHEN D = '2026-10-01' AND s.STORE_ID = 'S08' THEN 0.50
            WHEN D = '2026-10-01' AND s.STORE_ID = 'S01' THEN 1.15
            -- Night 2 · Oct 2: Bengaluru evening power cut; Singapore runs out of oat cookies by noon
            WHEN D = '2026-10-02' AND s.STORE_ID = 'S03' THEN 0.62
            WHEN D = '2026-10-02' AND s.STORE_ID = 'S07' AND p.PRODUCT_NAME = 'Oat Cookie' THEN 0.20
            WHEN D >= '2026-10-02' AND s.STORE_ID = 'S01' THEN 1.10
            ELSE 1.0 END
        * (0.85 + MOD(ABS(HASH(D, s.STORE_ID, p.PRODUCT_ID)), 31) / 100)
    ))::NUMBER,
    ROUND(p.BASE_PRICE_USD * CASE s.COUNTRY WHEN 'India' THEN 0.60 WHEN 'United Kingdom' THEN 1.15
                                            WHEN 'United States' THEN 1.20 WHEN 'Australia' THEN 1.05 ELSE 1.00 END, 2)::NUMBER(6,2),
    p.UNIT_COST_USD
  FROM days CROSS JOIN SNOWBREW_LAB.NIGHT_SHIFT.STORES s CROSS JOIN SNOWBREW_LAB.NIGHT_SHIFT.PRODUCTS p
$$;

CREATE OR REPLACE TABLE SALES AS
SELECT * FROM TABLE(SALES_FOR_DAYS('2026-06-01'::DATE, '2026-09-30'::DATE));

CREATE OR REPLACE TABLE FEEDBACK (
  FEEDBACK_ID NUMBER, FEEDBACK_DATE DATE, STORE_ID VARCHAR, CHANNEL VARCHAR, RATING NUMBER, FEEDBACK_TEXT VARCHAR);

INSERT INTO FEEDBACK VALUES
 (1,'2026-09-19','S01','Google',1,'Third time this month the espresso machine is down. I switched to the Shinjuku store.'),
 (2,'2026-09-25','S01','App',3,'Coffee is back but the wait is still 20+ minutes. They need a second machine.'),
 (3,'2026-09-11','S05','Google',2,'Cold brew used to be great, now it is acidic. Please bring back the old recipe.'),
 (4,'2026-09-20','S05','Email',3,'Lattes are still good but I stopped ordering cold brew after the recipe change.'),
 (5,'2026-09-27','S08','App',5,'Cold brew is my go-to. Staff remember my order.'),
 (6,'2026-09-08','S07','App',4,'Oat cookies sold out by noon every day. Make more please.'),
 (7,'2026-09-15','S03','App',4,'Bahut acchi chai hai, but the wifi keeps dropping when I work here.');

-- Tomorrow's feedback, released together with each new day of sales
CREATE OR REPLACE TABLE INCOMING_FEEDBACK AS SELECT * FROM FEEDBACK WHERE 1 = 0;
INSERT INTO INCOMING_FEEDBACK VALUES
 (101,'2026-10-01','S08','Google',1,'Drive-thru card machine was down, cash only. I left the queue after 10 minutes.'),
 (102,'2026-10-01','S08','App',2,'Card terminal not working again at the drive-thru. Half the cars drove off.'),
 (103,'2026-10-01','S01','App',5,'二台目のエスプレッソマシンが入って、待ち時間がほとんどなくなりました！'),
 (104,'2026-10-01','S01','Google',5,'Finally a second espresso machine. Latte in 4 minutes, like the old days.'),
 (108,'2026-10-01','S02','App',4,'Much quieter this morning. Looks like the Shibuya crowd went back now that their machines work.'),
 (105,'2026-10-02','S03','App',2,'Power went out at 6pm, they closed early. Chai was half made.'),
 (106,'2026-10-02','S03','Google',2,'Light chali gayi, no generator. Evening rush completely lost.'),
 (107,'2026-10-02','S07','App',3,'No oat cookies left at 11:30am again. Please bake more!');

-- "The data team's nightly load": appends the next day of sales + that day's reviews
CREATE OR REPLACE PROCEDURE LOAD_NEXT_DAY()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
  next_day DATE;
BEGIN
  SELECT DATEADD(day, 1, MAX(ORDER_DATE)) INTO :next_day FROM SNOWBREW_LAB.NIGHT_SHIFT.SALES;
  INSERT INTO SNOWBREW_LAB.NIGHT_SHIFT.SALES SELECT * FROM TABLE(SNOWBREW_LAB.NIGHT_SHIFT.SALES_FOR_DAYS(:next_day, :next_day));
  INSERT INTO SNOWBREW_LAB.NIGHT_SHIFT.FEEDBACK
    SELECT * FROM SNOWBREW_LAB.NIGHT_SHIFT.INCOMING_FEEDBACK WHERE FEEDBACK_DATE = :next_day;
  RETURN 'Loaded ' || TO_VARCHAR(:next_day);
END;
$$;

-- What the agent writes every night
CREATE OR REPLACE TABLE MORNING_BRIEF (
  BRIEF_DATE DATE, STORE_NAME VARCHAR, SEVERITY VARCHAR, HEADLINE VARCHAR,
  EVIDENCE VARCHAR, CUSTOMER_VOICE VARCHAR, ACTION VARCHAR, CREATED_AT TIMESTAMP_LTZ);

CREATE OR REPLACE TABLE NIGHT_SHIFT_LOG (
  RUN_AT TIMESTAMP_LTZ, STATUS VARCHAR, SUMMARY VARCHAR, TOOL_CALLS NUMBER, RESPONSE VARIANT);

-- Least privilege for the agent's role
GRANT USAGE ON DATABASE SNOWBREW_LAB TO ROLE NIGHT_SHIFT_ROLE;
GRANT USAGE ON SCHEMA SNOWBREW_LAB.NIGHT_SHIFT TO ROLE NIGHT_SHIFT_ROLE;
GRANT SELECT ON TABLE STORES   TO ROLE NIGHT_SHIFT_ROLE;
GRANT SELECT ON TABLE PRODUCTS TO ROLE NIGHT_SHIFT_ROLE;
GRANT SELECT ON TABLE SALES    TO ROLE NIGHT_SHIFT_ROLE;
GRANT SELECT ON TABLE FEEDBACK TO ROLE NIGHT_SHIFT_ROLE;
GRANT SELECT, INSERT, DELETE ON TABLE MORNING_BRIEF TO ROLE NIGHT_SHIFT_ROLE;
GRANT SELECT, INSERT ON TABLE NIGHT_SHIFT_LOG TO ROLE NIGHT_SHIFT_ROLE;
GRANT USAGE ON PROCEDURE LOAD_NEXT_DAY() TO ROLE NIGHT_SHIFT_ROLE;   -- so you can play "data team" from the same role
GRANT CREATE STAGE, CREATE STREAMLIT, CREATE PROCEDURE, CREATE TASK ON SCHEMA SNOWBREW_LAB.NIGHT_SHIFT TO ROLE NIGHT_SHIFT_ROLE;


/* -----------------------------------------------------------------------------
   STEP 3 · The company playbook, as an agent SKILL on a stage
   A skill is a folder with a SKILL.md (+ any scripts). Edit the text below to
   make it yours: the agent follows it every night.
----------------------------------------------------------------------------- */
CREATE OR REPLACE STAGE PLAYBOOK DIRECTORY = (ENABLE = TRUE) COMMENT = 'Company playbook skills for agents';
GRANT READ ON STAGE PLAYBOOK TO ROLE NIGHT_SHIFT_ROLE;

-- Tiny helper so you can write skill files straight from a worksheet (no local files, no PUT)
CREATE OR REPLACE PROCEDURE WRITE_STAGE_FILE(STAGE_PATH VARCHAR, CONTENT VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS
$$
import io
def run(session, stage_path, content):
    session.file.put_stream(io.BytesIO(content.encode("utf-8")), stage_path, auto_compress=False, overwrite=True)
    return "wrote " + stage_path
$$;

CALL WRITE_STAGE_FILE('@SNOWBREW_LAB.NIGHT_SHIFT.PLAYBOOK/skills/snowbrew-playbook/SKILL.md', $$---
name: snowbrew-playbook
description: Snowbrew Coffee Co. operating playbook. Use it for every Snowbrew overnight review, morning brief, analysis or data app. It defines the KPIs, the anomaly rules, how to investigate, the house style for apps, and the hard rules.
---

# Snowbrew playbook

## Data (all in SNOWBREW_LAB.NIGHT_SHIFT)
- SALES(ORDER_DATE, STORE_ID, PRODUCT_ID, UNITS, UNIT_PRICE_USD, UNIT_COST_USD)
- STORES(STORE_ID, STORE_NAME, CITY, COUNTRY, STORE_FORMAT), PRODUCTS(PRODUCT_ID, PRODUCT_NAME, CATEGORY)
- FEEDBACK(FEEDBACK_ID, FEEDBACK_DATE, STORE_ID, CHANNEL, RATING, FEEDBACK_TEXT)
- Revenue = UNITS * UNIT_PRICE_USD, in USD. Warehouse: MCP_LAB_WH.

## Overnight review (do this every night, in this order)
0. Read house_rules.md in this skill folder. Every rule in it is part of this playbook and overrides anything below.
1. Run `python3 /mnt/skills/snowbrew-playbook/detect_anomalies.py` (or find detect_anomalies.py next to this file). It prints JSON for the latest day: every store's revenue vs the average of the same weekday over the previous 4 weeks (Snowbrew never compares a Thursday with a Saturday), the change in percent, and a severity. Trust its numbers; do not recompute them differently.
2. For each store with severity HIGH, MEDIUM or GOOD_NEWS, read that store's FEEDBACK from the last 3 days. Quote at most 2 reviews, translated to English if needed (keep the original language in brackets). Look for links between stores in the same city: one store's loss is often another's gain.
3. Decide one concrete action per store: who (store manager, ops, marketing) and by when.
4. The overnight review is READ-ONLY: never write to any table. Your answer is the output. Reply with a 3-line summary of the night, then the brief as a JSON array between the markers <BRIEF> and </BRIEF>, nothing after it. One object per flagged store, plus one object with STORE_NAME "ALL STORES" and SEVERITY "SUMMARY" that sums up the night in one sentence (put that sentence in ACTION). Keys exactly: BRIEF_DATE (latest sales date, YYYY-MM-DD), STORE_NAME, SEVERITY, HEADLINE (max 80 chars), EVIDENCE (the numbers), CUSTOMER_VOICE (quotes, or "No feedback in the last 3 days."), ACTION.

## Building the Morning Brief app (only when asked to build it)
Build SNOWBREW_LAB.NIGHT_SHIFT.MORNING_BRIEF_APP: a Streamlit app that reads SNOWBREW_LAB.NIGHT_SHIFT.MORNING_BRIEF live, styled with the house style below. Write all files in one step, test the queries once, deploy once.

## Severity rules
- Baseline: the same weekday over the previous 4 weeks.
- HIGH: revenue at least 15% below the baseline.
- MEDIUM: 7% to 15% below.
- GOOD_NEWS: at least 10% above.
- Otherwise OK. Do not write OK stores to the brief.

## House style for apps (Morning Brief)
- Title: "☕ Snowbrew Morning Brief", subtitle with the brief date written like "Thursday, 1 October 2026".
- Dark espresso theme with st.markdown HTML/CSS (unsafe_allow_html=True): page background #1B110B, cards #2A1B12 with 14px rounded corners, text #F5E6D3, accent crema #D9A066.
- Severity colours: HIGH #E5484D, MEDIUM #F2B84B, GOOD_NEWS #3DD68C, SUMMARY #D9A066. Each card shows a coloured pill with the severity.
- Layout: the SUMMARY row as a hero banner, then a row of metric tiles (number of HIGH / MEDIUM / GOOD_NEWS), then one card per store, HIGH first. Each card: store name, headline, evidence, customer voice in italics, action in bold.
- A date picker (st.selectbox over the BRIEF_DATE values, newest first) so past briefs stay browsable.
- Footer: "Written overnight by the Snowbrew Night Shift agent · data: SNOWBREW_LAB.NIGHT_SHIFT".

## Hard rules
- Never modify SALES, STORES, PRODUCTS, FEEDBACK or MORNING_BRIEF. Create apps and stages only in SNOWBREW_LAB.NIGHT_SHIFT, and only when asked to build the app.
- Streamlit: put streamlit_app.py and environment.yml on a stage in SNOWBREW_LAB.NIGHT_SHIFT, deploy with CREATE STREAMLIT SNOWBREW_LAB.NIGHT_SHIFT.MORNING_BRIEF_APP ... MAIN_FILE = 'streamlit_app.py' RUNTIME_NAME = 'SYSTEM$WAREHOUSE_RUNTIME' QUERY_WAREHOUSE = MCP_LAB_WH TITLE = 'Snowbrew Morning Brief'. Pin streamlit=1.42.0 and pandas in environment.yml; no altair or plotly. Use get_active_session() from snowflake.snowpark.context in the app.
- Test every query in the sandbox before deploying. Work in as few steps as possible.
$$);

CALL WRITE_STAGE_FILE('@SNOWBREW_LAB.NIGHT_SHIFT.PLAYBOOK/skills/snowbrew-playbook/detect_anomalies.py', $$"""Snowbrew's official anomaly check: latest day vs the same weekday of the previous 4 weeks, per store."""
import json, os
from snowflake.snowpark import Session

def session():
    token = open(os.environ.get("SNOWFLAKE_TOKEN_FILE_PATH", "/snowflake/session/token")).read().strip()
    cfg = {"authenticator": "oauth", "token": token, "warehouse": "MCP_LAB_WH"}
    for key, env in (("account", "SNOWFLAKE_ACCOUNT"), ("host", "SNOWFLAKE_HOST")):
        if os.environ.get(env):
            cfg[key] = os.environ[env]
    return Session.builder.configs(cfg).create()

# Snowbrew compares a day with the SAME WEEKDAY of the previous 4 weeks (weekends are always busier).
SQL = """
WITH daily AS (
  SELECT ORDER_DATE, STORE_ID, SUM(UNITS * UNIT_PRICE_USD) AS REV
  FROM SNOWBREW_LAB.NIGHT_SHIFT.SALES GROUP BY 1, 2),
latest AS (SELECT MAX(ORDER_DATE) AS D FROM daily),
baseline AS (
  SELECT p.STORE_ID, AVG(p.REV) AS BASE
  FROM daily p, latest l
  WHERE p.ORDER_DATE IN (l.D - 7, l.D - 14, l.D - 21, l.D - 28)
  GROUP BY 1)
SELECT st.STORE_NAME, st.CITY, l.D AS DAY, ROUND(t.REV, 2) AS REVENUE,
       ROUND(b.BASE, 2) AS BASELINE,
       ROUND(100 * (t.REV / b.BASE - 1), 1) AS CHANGE_PCT
FROM latest l
JOIN daily t    ON t.ORDER_DATE = l.D
JOIN baseline b ON b.STORE_ID = t.STORE_ID
JOIN SNOWBREW_LAB.NIGHT_SHIFT.STORES st ON st.STORE_ID = t.STORE_ID
ORDER BY CHANGE_PCT
"""

def severity(pct):
    if pct <= -15: return "HIGH"
    if pct <= -7:  return "MEDIUM"
    if pct >= 10:  return "GOOD_NEWS"
    return "OK"

rows = session().sql(SQL).collect()
out = [{"store": r["STORE_NAME"], "city": r["CITY"], "day": str(r["DAY"]),
        "revenue": float(r["REVENUE"]), "same_weekday_avg_4w": float(r["BASELINE"]),
        "change_pct": float(r["CHANGE_PCT"]), "severity": severity(float(r["CHANGE_PCT"]))} for r in rows]
print(json.dumps(out, indent=2))
$$);

-- Your team's own rules, in plain English. Add a line, and the agent follows it from the next night on.
CALL WRITE_STAGE_FILE('@SNOWBREW_LAB.NIGHT_SHIFT.PLAYBOOK/skills/snowbrew-playbook/house_rules.md', $$# Snowbrew house rules
- Write money as USD with thousands separators, e.g. $1,234.56.
- Name the city next to every store, e.g. "Surry Hills (Sydney)".
$$);

LIST @PLAYBOOK;

-- The Night Shift agent itself: a named Cortex Agent with the coding tools and the playbook skill.
-- You (MCP_LAB_ROLE) own its instructions; the night-shift role may only RUN it, never change it.
CREATE OR REPLACE AGENT SNOWBREW_LAB.NIGHT_SHIFT.NIGHT_SHIFT_AGENT
  COMMENT = 'Episode 3: the Snowbrew Night Shift agent'
  FROM SPECIFICATION
$$
models:
  orchestration: auto
instructions:
  system: "You are the Snowbrew Night Shift, an unattended agent. Nobody is awake to answer questions, so never ask: decide, act and report. Always load and follow the snowbrew-playbook skill."
tools:
  - tool_spec:
      type: "code_toolset_all"
      name: "code_toolset_all"
tool_resources:
  code_toolset_all:
    permission_policy:
      type: "always_allow"
skills:
  - name: "snowbrew-playbook"
    source:
      type: "STAGE"
      path: "@SNOWBREW_LAB.NIGHT_SHIFT.PLAYBOOK/skills/snowbrew-playbook"
$$;
GRANT USAGE ON AGENT SNOWBREW_LAB.NIGHT_SHIFT.NIGHT_SHIFT_AGENT TO ROLE NIGHT_SHIFT_ROLE;


/* -----------------------------------------------------------------------------
   STEP 4 · The night shift: procedures that wake the agent, and a task that
   runs it every night. All owned by NIGHT_SHIFT_ROLE, so the agent can never
   do more than that role. permission_policy = always_allow (nobody is awake to
   click Allow), which is exactly why the role is locked down.
----------------------------------------------------------------------------- */
USE ROLE NIGHT_SHIFT_ROLE;
USE WAREHOUSE MCP_LAB_WH;
USE SCHEMA SNOWBREW_LAB.NIGHT_SHIFT;

-- Runs the NIGHT_SHIFT_AGENT with a message, logs the run, returns its final answer.
CREATE OR REPLACE PROCEDURE ASK_NIGHT_SHIFT(TASK_TEXT VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER   -- caller's rights: Snowflake removed the code tools when I ran the agent from an owner's-rights procedure
AS
$$
DECLARE
  request VARCHAR;
  resp VARIANT;
  answer VARCHAR;
  run_status VARCHAR;
  tool_calls NUMBER;
BEGIN
  -- Only the message: the model, instructions, tools and skill all come from the agent object.
  request := TO_JSON(OBJECT_CONSTRUCT(
    'messages', ARRAY_CONSTRUCT(OBJECT_CONSTRUCT('role', 'user',
      'content', ARRAY_CONSTRUCT(OBJECT_CONSTRUCT('type', 'text', 'text', :TASK_TEXT))))));
  resp   := TRY_PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN('SNOWBREW_LAB.NIGHT_SHIFT.NIGHT_SHIFT_AGENT', :request));
  answer     := COALESCE(resp:content[ARRAY_SIZE(resp:content) - 1]:text::VARCHAR, LEFT(TO_VARCHAR(resp), 2000));
  run_status := resp:status::VARCHAR;
  tool_calls := REGEXP_COUNT(TO_VARCHAR(resp), '"type":"tool_use"');
  INSERT INTO SNOWBREW_LAB.NIGHT_SHIFT.NIGHT_SHIFT_LOG
    SELECT CURRENT_TIMESTAMP(), :run_status, :answer, :tool_calls, :resp;
  RETURN answer;
END;
$$;

-- The nightly review. The agent only READS and hands back a brief; this procedure writes it.
-- (In a task, Snowflake's Restricted Session Scope blocks the agent's own writes anyway.)
CREATE OR REPLACE PROCEDURE RUN_NIGHT_SHIFT()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
  answer VARCHAR;
  brief VARIANT;
  brief_date DATE;
BEGIN
  CALL SNOWBREW_LAB.NIGHT_SHIFT.ASK_NIGHT_SHIFT(
    'Night shift: run the overnight review from the snowbrew-playbook skill for the latest day of data.') INTO :answer;
  brief := TRY_PARSE_JSON(REGEXP_SUBSTR(:answer, '<BRIEF>(.*)</BRIEF>', 1, 1, 's', 1));
  IF (brief IS NULL OR ARRAY_SIZE(brief) = 0) THEN
    RETURN 'No brief returned. Agent said: ' || answer;
  END IF;
  brief_date := brief[0]:BRIEF_DATE::DATE;
  DELETE FROM SNOWBREW_LAB.NIGHT_SHIFT.MORNING_BRIEF WHERE BRIEF_DATE = :brief_date;
  INSERT INTO SNOWBREW_LAB.NIGHT_SHIFT.MORNING_BRIEF
    SELECT v.value:BRIEF_DATE::DATE, v.value:STORE_NAME::VARCHAR, v.value:SEVERITY::VARCHAR, v.value:HEADLINE::VARCHAR,
           v.value:EVIDENCE::VARCHAR, v.value:CUSTOMER_VOICE::VARCHAR, v.value:ACTION::VARCHAR, CURRENT_TIMESTAMP()
    FROM TABLE(FLATTEN(INPUT => :brief)) v;
  RETURN SPLIT_PART(answer, '<BRIEF>', 1);
END;
$$;

-- One-off: the agent builds the Morning Brief app in the house style (run while you watch).
CREATE OR REPLACE PROCEDURE BUILD_MORNING_BRIEF_APP()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
  answer VARCHAR;
BEGIN
  CALL SNOWBREW_LAB.NIGHT_SHIFT.ASK_NIGHT_SHIFT(
    'Build and deploy the Morning Brief app exactly as described in the snowbrew-playbook skill (sections "Building the Morning Brief app" and "House style"). Reply with 3 lines: what you built, the app name, and how you tested it.') INTO :answer;
  RETURN answer;
END;
$$;

-- 06:00 Tokyo every day. Tasks are created SUSPENDED; STEP 5 runs it by hand.
CREATE OR REPLACE TASK NIGHTLY_REVIEW
  WAREHOUSE = MCP_LAB_WH
  SCHEDULE  = 'USING CRON 0 6 * * * Asia/Tokyo'
  USER_TASK_TIMEOUT_MS = 1800000
  COMMENT   = 'Episode 3: the Snowbrew Night Shift agent'
AS
  CALL SNOWBREW_LAB.NIGHT_SHIFT.RUN_NIGHT_SHIFT();


/* -----------------------------------------------------------------------------
   STEP 5 · Try it now (takes ~2 minutes; don't wait for 6am)
----------------------------------------------------------------------------- */
USE ROLE NIGHT_SHIFT_ROLE;
CALL SNOWBREW_LAB.NIGHT_SHIFT.LOAD_NEXT_DAY();             -- Night 1: Oct 1 lands
CALL SNOWBREW_LAB.NIGHT_SHIFT.RUN_NIGHT_SHIFT();           -- the agent reviews it (~1 min)
CALL SNOWBREW_LAB.NIGHT_SHIFT.BUILD_MORNING_BRIEF_APP();   -- the agent builds your app (~1 min)

SELECT STORE_NAME, SEVERITY, HEADLINE, CUSTOMER_VOICE, ACTION
FROM SNOWBREW_LAB.NIGHT_SHIFT.MORNING_BRIEF ORDER BY BRIEF_DATE DESC, SEVERITY;
-- Open it: Snowsight > Apps > Streamlit > Snowbrew Morning Brief

/* Night 2, fully unattended, via the real task (run these two lines, wait ~1 min, refresh the app):
     CALL SNOWBREW_LAB.NIGHT_SHIFT.LOAD_NEXT_DAY();
     EXECUTE TASK SNOWBREW_LAB.NIGHT_SHIFT.NIGHTLY_REVIEW;
   Every night from now on (measured: 0.09-0.36 agent credits a night, plus warehouse time):
     ALTER TASK SNOWBREW_LAB.NIGHT_SHIFT.NIGHTLY_REVIEW RESUME;
   Every run is logged:
     SELECT RUN_AT, STATUS, TOOL_CALLS, SUMMARY FROM SNOWBREW_LAB.NIGHT_SHIFT.NIGHT_SHIFT_LOG ORDER BY RUN_AT DESC;
*/
