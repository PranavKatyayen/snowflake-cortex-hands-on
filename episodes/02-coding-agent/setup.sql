/* =============================================================================
   SNOWFLAKE AI, HANDS-ON · EPISODE 2
   "An AI agent inside Snowflake writes, tests and deploys a live app"

   One message in Claude -> a CODING_AGENT tool on a Snowflake-managed MCP server
   -> an agent in a Snowflake-managed sandbox writes Python, tests it against
   your tables and deploys a Streamlit app, asking your approval for every change.

   Standalone: you do NOT need Episode 1. Everything below is created only if it
   doesn't exist yet, so it is also safe to run on top of Episode 1.

   How to run : Snowsight > SQL worksheet > paste > Run All (~1 minute).
   Run as     : a user who can use ACCOUNTADMIN (STEP 0 and STEP 4 only).
   Cleanup    : cleanup.sql
============================================================================= */


/* -----------------------------------------------------------------------------
   STEP 0 · Admin setup (ACCOUNTADMIN)
----------------------------------------------------------------------------- */
USE ROLE ACCOUNTADMIN;

-- The coding agent runs on models that aren't hosted in every region.
-- Skip/adjust this line if your company has data-residency rules.
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';

CREATE ROLE IF NOT EXISTS MCP_LAB_ROLE COMMENT = 'Snowflake AI Hands-On labs';
GRANT ROLE MCP_LAB_ROLE TO ROLE SYSADMIN;

SET my_user = CURRENT_USER();
GRANT ROLE MCP_LAB_ROLE TO USER IDENTIFIER($my_user);

GRANT CREATE DATABASE  ON ACCOUNT TO ROLE MCP_LAB_ROLE;
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE MCP_LAB_ROLE;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER       TO ROLE MCP_LAB_ROLE;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE MCP_LAB_ROLE;


/* -----------------------------------------------------------------------------
   STEP 1 · Warehouse, database, schemas (everything below runs as MCP_LAB_ROLE)
----------------------------------------------------------------------------- */
USE ROLE MCP_LAB_ROLE;

CREATE WAREHOUSE IF NOT EXISTS MCP_LAB_WH
  WAREHOUSE_SIZE = XSMALL  AUTO_SUSPEND = 60  AUTO_RESUME = TRUE  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Snowflake AI Hands-On lab warehouse';

CREATE DATABASE IF NOT EXISTS SNOWBREW_LAB;
CREATE SCHEMA   IF NOT EXISTS SNOWBREW_LAB.CORE;   -- source data
CREATE SCHEMA   IF NOT EXISTS SNOWBREW_LAB.APPS;   -- everything the agent builds goes here
USE WAREHOUSE MCP_LAB_WH;
USE SCHEMA SNOWBREW_LAB.CORE;


/* -----------------------------------------------------------------------------
   STEP 2 · Demo data: Snowbrew Coffee Co. (fictional), 8 stores, Jun–Sep 2026
   Same deterministic data as Episode 1, so your numbers match the article.
   IF NOT EXISTS: an existing Episode 1 setup is left untouched.
----------------------------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS STORES AS
SELECT $1::VARCHAR AS STORE_ID, $2::VARCHAR AS STORE_NAME, $3::VARCHAR AS CITY, $4::VARCHAR AS COUNTRY,
       $5::VARCHAR AS STORE_FORMAT, $6::DATE AS OPENED_ON, $7::FLOAT AS TRAFFIC
FROM VALUES
  ('S01','Shibuya Crossing','Tokyo','Japan','Flagship','2021-04-01',1.30),
  ('S02','Shinjuku Station','Tokyo','Japan','Kiosk','2022-09-15',1.10),
  ('S03','Indiranagar','Bengaluru','India','Cafe','2023-01-10',1.00),
  ('S04','Bandra West','Mumbai','India','Cafe','2023-06-20',0.90),
  ('S05','Soho','London','United Kingdom','Flagship','2020-11-05',1.00),
  ('S06','SoHo Broadway','New York','United States','Flagship','2019-08-12',1.20),
  ('S07','Tanjong Pagar','Singapore','Singapore','Cafe','2024-02-01',0.80),
  ('S08','Surry Hills','Sydney','Australia','Drive-thru','2024-07-18',0.70);

CREATE TABLE IF NOT EXISTS PRODUCTS AS
SELECT $1::VARCHAR AS PRODUCT_ID, $2::VARCHAR AS PRODUCT_NAME, $3::VARCHAR AS CATEGORY,
       $4::NUMBER(6,2) AS BASE_PRICE_USD, $5::NUMBER(6,2) AS UNIT_COST_USD, $6::NUMBER AS BASE_DEMAND
FROM VALUES
  ('P01','Caffe Latte','Coffee',5.20,1.30,60),
  ('P02','Flat White','Coffee',5.00,1.25,35),
  ('P03','Espresso','Coffee',3.20,0.60,22),
  ('P04','Cold Brew','Coffee',5.50,1.10,30),
  ('P05','Mocha','Coffee',5.80,1.60,18),
  ('P06','Matcha Latte','Tea',5.60,1.70,25),
  ('P07','Masala Chai','Tea',4.20,0.90,20),
  ('P08','Butter Croissant','Food',3.80,1.20,30),
  ('P09','Banana Bread','Food',3.60,1.00,15),
  ('P10','Oat Cookie','Food',2.80,0.70,25);

-- 122 days x 8 stores x 10 products = 9,760 rows
CREATE TABLE IF NOT EXISTS DAILY_SALES AS
WITH days AS (
  SELECT DATEADD(day, ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, '2026-06-01'::DATE) AS ORDER_DATE
  FROM TABLE(GENERATOR(ROWCOUNT => 122))
),
grid AS (
  SELECT d.ORDER_DATE, s.STORE_ID, s.CITY, s.COUNTRY, s.TRAFFIC,
         p.PRODUCT_ID, p.PRODUCT_NAME, p.CATEGORY, p.BASE_PRICE_USD, p.UNIT_COST_USD, p.BASE_DEMAND
  FROM days d CROSS JOIN STORES s CROSS JOIN PRODUCTS p
)
SELECT
  ORDER_DATE,
  STORE_ID,
  PRODUCT_ID,
  GREATEST(0, ROUND(
      BASE_DEMAND * TRAFFIC
      * CASE WHEN PRODUCT_NAME = 'Masala Chai'  AND COUNTRY = 'India' THEN 3.0
             WHEN PRODUCT_NAME = 'Matcha Latte' AND CITY    = 'Tokyo' THEN 2.0
             WHEN PRODUCT_NAME = 'Cold Brew'    AND CITY IN ('New York','Sydney') THEN 1.5
             ELSE 1.0 END
      * IFF(DAYOFWEEKISO(ORDER_DATE) IN (6,7), 1.25, 1.0)
      * CASE WHEN STORE_ID = 'S01' AND ORDER_DATE >= '2026-09-01' AND CATEGORY = 'Coffee' THEN 0.55
             WHEN STORE_ID = 'S01' AND ORDER_DATE >= '2026-09-01'                         THEN 0.80
             WHEN STORE_ID = 'S02' AND ORDER_DATE >= '2026-09-01'                         THEN 1.12
             WHEN STORE_ID = 'S05' AND ORDER_DATE >= '2026-09-01' AND PRODUCT_NAME = 'Cold Brew' THEN 0.50
             WHEN COUNTRY  = 'India' AND ORDER_DATE >= '2026-08-01' AND PRODUCT_NAME = 'Masala Chai' THEN 1.40
             ELSE 1.0 END
      * (0.85 + MOD(ABS(HASH(ORDER_DATE, STORE_ID, PRODUCT_ID)), 31) / 100)
  ))::NUMBER AS UNITS,
  ROUND(BASE_PRICE_USD * CASE COUNTRY
          WHEN 'India'          THEN 0.60
          WHEN 'United Kingdom' THEN 1.15
          WHEN 'United States'  THEN 1.20
          WHEN 'Australia'      THEN 1.05
          ELSE 1.00 END, 2)::NUMBER(6,2) AS UNIT_PRICE_USD,
  UNIT_COST_USD
FROM grid;

CREATE TABLE IF NOT EXISTS CUSTOMER_FEEDBACK AS
SELECT $1::NUMBER AS FEEDBACK_ID, $2::DATE AS FEEDBACK_DATE, $3::VARCHAR AS STORE_ID, $4::VARCHAR AS STORE_NAME,
       $5::VARCHAR AS CITY, $6::VARCHAR AS CHANNEL, $7::NUMBER AS RATING, $8::VARCHAR AS FEEDBACK_TEXT
FROM VALUES
 (1,'2026-06-04','S01','Shibuya Crossing','Tokyo','App',5,'Best flat white in Shibuya. Fast service even at 8am rush hour.'),
 (2,'2026-06-18','S01','Shibuya Crossing','Tokyo','Google',5,'Matcha latte is perfect, not too sweet. Staff were super friendly.'),
 (3,'2026-07-09','S01','Shibuya Crossing','Tokyo','App',4,'Great coffee, a bit crowded on weekends but worth it.'),
 (4,'2026-09-03','S01','Shibuya Crossing','Tokyo','App',2,'Waited 25 minutes for a latte. Staff said the espresso machine keeps breaking down.'),
 (5,'2026-09-06','S01','Shibuya Crossing','Tokyo','Google',1,'No espresso drinks at all today - machine under repair. Only matcha and tea available. Very disappointing.'),
 (6,'2026-09-10','S01','Shibuya Crossing','Tokyo','Email',2,'エスプレッソマシンが故障していて、ラテが注文できませんでした。待ち時間も長すぎます。'),
 (7,'2026-09-14','S01','Shibuya Crossing','Tokyo','App',2,'The queue was out the door and the coffee tasted burnt. The machine seems to be struggling.'),
 (8,'2026-09-19','S01','Shibuya Crossing','Tokyo','Google',1,'Third time this month the espresso machine is down. I switched to the Shinjuku store.'),
 (9,'2026-09-25','S01','Shibuya Crossing','Tokyo','App',3,'Coffee is back but the wait is still 20+ minutes. They need a second machine.'),
 (10,'2026-07-12','S02','Shinjuku Station','Tokyo','App',5,'Perfect kiosk for a quick espresso before the train.'),
 (11,'2026-09-12','S02','Shinjuku Station','Tokyo','Google',4,'Busier than usual lately, many people coming from Shibuya, but service is still quick.'),
 (12,'2026-09-21','S02','Shinjuku Station','Tokyo','Email',5,'抹茶ラテが最高です。毎朝来ています。'),
 (13,'2026-06-22','S03','Indiranagar','Bengaluru','App',5,'The masala chai here tastes like home. Love the cozy seating.'),
 (14,'2026-08-05','S03','Indiranagar','Bengaluru','Google',5,'Monsoon special chai is amazing on a rainy evening. Please keep it on the menu.'),
 (15,'2026-08-21','S03','Indiranagar','Bengaluru','App',4,'Chai is great but seating is always full now. Need more tables.'),
 (16,'2026-09-15','S03','Indiranagar','Bengaluru','App',4,'Bahut acchi chai hai, but the wifi keeps dropping when I work here.'),
 (17,'2026-07-02','S04','Bandra West','Mumbai','Google',4,'Good cold coffee, a little pricey for Bandra.'),
 (18,'2026-08-28','S04','Bandra West','Mumbai','App',5,'Masala chai and banana bread combo is the best breakfast.'),
 (19,'2026-09-17','S04','Bandra West','Mumbai','Email',3,'Delivery orders arrive late and the chai is cold by then.'),
 (20,'2026-06-10','S05','Soho','London','Google',5,'Proper flat white, finally a place in Soho that gets it right.'),
 (21,'2026-07-25','S05','Soho','London','App',5,'Cold brew is smooth and chocolatey. My summer favourite.'),
 (22,'2026-09-04','S05','Soho','London','App',2,'What happened to the cold brew? The new recipe tastes sour and watery.'),
 (23,'2026-09-11','S05','Soho','London','Google',2,'Cold brew used to be great, now it is acidic. Please bring back the old recipe.'),
 (24,'2026-09-20','S05','Soho','London','Email',3,'Lattes are still good but I stopped ordering cold brew after the recipe change.'),
 (25,'2026-06-15','S06','SoHo Broadway','New York','Google',5,'Cold brew on a hot NYC day is unbeatable. Fast line too.'),
 (26,'2026-08-09','S06','SoHo Broadway','New York','App',4,'Mocha is rich and the croissants are fresh. Prices went up a bit.'),
 (27,'2026-09-23','S06','SoHo Broadway','New York','App',5,'Ordered ahead on the app and it was ready in 3 minutes. Love it.'),
 (28,'2026-07-19','S07','Tanjong Pagar','Singapore','Google',4,'Nice place to work, good matcha. Air-con is very cold.'),
 (29,'2026-09-08','S07','Tanjong Pagar','Singapore','App',4,'Oat cookies sold out by noon every day. Make more please.'),
 (30,'2026-06-28','S08','Surry Hills','Sydney','Google',5,'Drive-thru is quick and the flat white is spot on.'),
 (31,'2026-08-14','S08','Surry Hills','Sydney','App',3,'Drive-thru queue is long on weekend mornings, 15 minutes wait.'),
 (32,'2026-09-27','S08','Surry Hills','Sydney','App',5,'Cold brew is my go-to. Staff remember my order.');


/* -----------------------------------------------------------------------------
   STEP 3 · The MCP server with one tool: a coding agent
   No stored agent object: the whole agent config lives in the tool.
   Snowflake adds the sandbox toolset (bash, read/write/edit files, SQL,
   web search, skills) on every run.
   The instructions are the result of testing: each line fixes a real failure.
----------------------------------------------------------------------------- */
CREATE OR REPLACE MCP SERVER SNOWBREW_LAB.CORE.SNOWBREW_BUILDER_MCP
  FROM SPECIFICATION
$$
tools:
  - name: "snowbrew_builder"
    type: "CODING_AGENT"
    title: "Snowbrew builder (coding agent in Snowflake)"
    description: "A coding agent that runs inside Snowflake. It writes and runs Python and SQL in a managed sandbox, and can build and deploy Streamlit apps, stages and files in SNOWBREW_LAB.APPS. Use it for anything that needs code: forecasts, charts, data apps. Pending commands need the user's approval."
    config:
      instructions:
        orchestration: >
          Work in as few approved steps as possible, because every command that changes something
          waits for the user to click Allow. Plan the whole job first, then:
          (1) write all files in one step, (2) run one combined python test script,
          (3) run one deploy step that creates the stage, uploads the files and creates the app.
          Read-only queries need no approval, so explore freely with SELECT and SHOW.
          Data lives in SNOWBREW_LAB.CORE: DAILY_SALES, STORES, PRODUCTS, CUSTOMER_FEEDBACK.
          Use warehouse MCP_LAB_WH. Create every new object (apps, stages, tables) in schema
          SNOWBREW_LAB.APPS, never in CORE.
          Streamlit apps: put streamlit_app.py and environment.yml (Snowflake Conda channel packages)
          on a stage in SNOWBREW_LAB.APPS, then deploy with CREATE STREAMLIT ... MAIN_FILE = 'streamlit_app.py'
          RUNTIME_NAME = 'SYSTEM$WAREHOUSE_RUNTIME' QUERY_WAREHOUSE = MCP_LAB_WH.
          Always set RUNTIME_NAME explicitly: new accounts otherwise default to the container runtime,
          which needs pyproject.toml and fails with environment.yml.
          The sandbox has newer libraries than the app runtime, so pin streamlit=1.42.0 in environment.yml,
          use only Streamlit's built-in charts (st.bar_chart, st.line_chart, st.dataframe; no altair or plotly),
          and pin every other package you list.
          Before deploying, run the app's queries and data code in the sandbox with python to prove they work.
          Give the Snowsight link: https://app.snowflake.com/<org>/<account>/#/streamlit-apps/<DB>.<SCHEMA>.<APP>
          using lowercase org and account names.
        response: "Be brief. List what you created (objects and files) and give links. Do not paste full source code unless asked."
$$;


/* -----------------------------------------------------------------------------
   STEP 4 · Let Claude sign in (OAuth) — ACCOUNTADMIN
   OAuth sessions start in your DEFAULT role, and ACCOUNTADMIN is blocked for
   OAuth, so the lab role becomes your default (cleanup.sql puts it back).
   IF NOT EXISTS: if you did Episode 1, your existing Claude client is reused.
----------------------------------------------------------------------------- */
USE ROLE ACCOUNTADMIN;

ALTER USER IDENTIFIER($my_user) SET DEFAULT_ROLE = 'MCP_LAB_ROLE' DEFAULT_WAREHOUSE = 'MCP_LAB_WH';

CREATE SECURITY INTEGRATION IF NOT EXISTS SNOWBREW_MCP_CLAUDE
  TYPE = OAUTH
  OAUTH_CLIENT = CUSTOM
  OAUTH_CLIENT_TYPE = 'PUBLIC'
  OAUTH_REDIRECT_URI = 'https://claude.ai/api/mcp/auth_callback'
  OAUTH_ENFORCE_PKCE = TRUE
  OAUTH_ISSUE_REFRESH_TOKENS = TRUE
  OAUTH_REFRESH_TOKEN_VALIDITY = 86400
  OAUTH_USE_SECONDARY_ROLES = NONE
  ENABLED = TRUE
  COMMENT = 'Claude -> Snowbrew MCP servers';


/* -----------------------------------------------------------------------------
   STEP 5 · What you paste into Claude
----------------------------------------------------------------------------- */
-- Copy only the value of OAUTH_CLIENT_ID (leave the secret blank in Claude)
SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('SNOWBREW_MCP_CLAUDE');

-- Your MCP server URL
SELECT 'https://' || LOWER(CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME())
       || '.snowflakecomputing.com/api/v2/databases/SNOWBREW_LAB/schemas/CORE/mcp-servers/SNOWBREW_BUILDER_MCP'
       AS MCP_SERVER_URL;

-- Sanity check: 9,760 sales rows and 32 reviews
SELECT (SELECT COUNT(*) FROM SNOWBREW_LAB.CORE.DAILY_SALES)       AS SALES_ROWS,
       (SELECT COUNT(*) FROM SNOWBREW_LAB.CORE.CUSTOMER_FEEDBACK) AS REVIEWS;
