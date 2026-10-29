/* =============================================================================
   SNOWFLAKE CORTEX HANDS-ON SERIES · EPISODE 1
   "Talk to your Snowflake data from Claude & Cursor — Snowflake-managed MCP server"

   Scenario : Snowbrew Coffee Co. (fictional), 8 stores in 6 countries.
              Sales for the Tokyo Shibuya store drop sharply in September 2026.
              Your AI client must figure out WHY by combining
              structured sales (Cortex Analyst) + customer feedback (Cortex Search).

   What you build
     1. Demo data   : STORES, PRODUCTS, DAILY_SALES (~9.7k rows), CUSTOMER_FEEDBACK
     2. AI objects  : Cortex Search service, Semantic view, price-simulator procedure,
                      Cortex Agent ("Snowbrew Copilot")
     3. MCP server  : exposes the agent + tools to any MCP client
                      (Claude, Cursor, ChatGPT, VS Code...)

   How to run : Snowsight > Projects > Workspaces (or a SQL worksheet) > paste > Run All.
   Run as     : a user who can use ACCOUNTADMIN (only for STEP 0).
   Re-runnable: yes — every object uses CREATE OR REPLACE.
   Cleanup    : cleanup.sql
============================================================================= */


/* -----------------------------------------------------------------------------
   STEP 0 · One-time admin setup (ACCOUNTADMIN)
   - a dedicated lab role (least privilege, NOT granted to PUBLIC)
   - Cortex database roles
   - cross-region inference (most LLMs are not hosted in every region)
----------------------------------------------------------------------------- */
USE ROLE ACCOUNTADMIN;

-- If your region does not host the models, Cortex routes to another region.
-- Skip/adjust this line if your company has data-residency rules.
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';

CREATE ROLE IF NOT EXISTS MCP_LAB_ROLE COMMENT = 'Episode 1: Snowflake MCP server lab';
GRANT ROLE MCP_LAB_ROLE TO ROLE SYSADMIN;            -- keep role hierarchy tidy

SET my_user = CURRENT_USER();
GRANT ROLE MCP_LAB_ROLE TO USER IDENTIFIER($my_user);

GRANT CREATE DATABASE  ON ACCOUNT TO ROLE MCP_LAB_ROLE;
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE MCP_LAB_ROLE;

GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER       TO ROLE MCP_LAB_ROLE;  -- AI functions, Search, Analyst
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE MCP_LAB_ROLE;  -- Cortex Agents


/* -----------------------------------------------------------------------------
   STEP 1 · Warehouse, database, schema (everything below runs as MCP_LAB_ROLE)
----------------------------------------------------------------------------- */
USE ROLE MCP_LAB_ROLE;

CREATE OR REPLACE WAREHOUSE MCP_LAB_WH
  WAREHOUSE_SIZE = XSMALL
  AUTO_SUSPEND   = 60
  AUTO_RESUME    = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Episode 1 lab warehouse';

CREATE OR REPLACE DATABASE SNOWBREW_LAB;
CREATE OR REPLACE SCHEMA SNOWBREW_LAB.CORE;
USE WAREHOUSE MCP_LAB_WH;
USE SCHEMA SNOWBREW_LAB.CORE;


/* -----------------------------------------------------------------------------
   STEP 2 · Demo data
   Deterministic (HASH-based, no RANDOM) so your numbers match the article.
----------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE STORES (
  STORE_ID     VARCHAR PRIMARY KEY,
  STORE_NAME   VARCHAR,
  CITY         VARCHAR,
  COUNTRY      VARCHAR,
  STORE_FORMAT VARCHAR,
  OPENED_ON    DATE,
  TRAFFIC      FLOAT          -- relative foot traffic, used only to generate data
);

INSERT INTO STORES VALUES
  ('S01','Shibuya Crossing','Tokyo','Japan','Flagship','2021-04-01',1.30),
  ('S02','Shinjuku Station','Tokyo','Japan','Kiosk','2022-09-15',1.10),
  ('S03','Indiranagar','Bengaluru','India','Cafe','2023-01-10',1.00),
  ('S04','Bandra West','Mumbai','India','Cafe','2023-06-20',0.90),
  ('S05','Soho','London','United Kingdom','Flagship','2020-11-05',1.00),
  ('S06','SoHo Broadway','New York','United States','Flagship','2019-08-12',1.20),
  ('S07','Tanjong Pagar','Singapore','Singapore','Cafe','2024-02-01',0.80),
  ('S08','Surry Hills','Sydney','Australia','Drive-thru','2024-07-18',0.70);

CREATE OR REPLACE TABLE PRODUCTS (
  PRODUCT_ID     VARCHAR PRIMARY KEY,
  PRODUCT_NAME   VARCHAR,
  CATEGORY       VARCHAR,
  BASE_PRICE_USD NUMBER(6,2),
  UNIT_COST_USD  NUMBER(6,2),
  BASE_DEMAND    NUMBER        -- units per store per day, used only to generate data
);

INSERT INTO PRODUCTS VALUES
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

-- 122 days (Jun 1 – Sep 30, 2026) x 8 stores x 10 products = 9,760 rows
CREATE OR REPLACE TABLE DAILY_SALES AS
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
      -- regional taste
      * CASE WHEN PRODUCT_NAME = 'Masala Chai'  AND COUNTRY = 'India' THEN 3.0
             WHEN PRODUCT_NAME = 'Matcha Latte' AND CITY    = 'Tokyo' THEN 2.0
             WHEN PRODUCT_NAME = 'Cold Brew'    AND CITY IN ('New York','Sydney') THEN 1.5
             ELSE 1.0 END
      -- weekends are busier
      * IFF(DAYOFWEEKISO(ORDER_DATE) IN (6,7), 1.25, 1.0)
      -- the stories hidden in the data
      * CASE WHEN STORE_ID = 'S01' AND ORDER_DATE >= '2026-09-01' AND CATEGORY = 'Coffee' THEN 0.55  -- Shibuya espresso machine outage
             WHEN STORE_ID = 'S01' AND ORDER_DATE >= '2026-09-01'                         THEN 0.80  -- long queues hit everything
             WHEN STORE_ID = 'S02' AND ORDER_DATE >= '2026-09-01'                         THEN 1.12  -- Shibuya regulars move to Shinjuku
             WHEN STORE_ID = 'S05' AND ORDER_DATE >= '2026-09-01' AND PRODUCT_NAME = 'Cold Brew' THEN 0.50  -- London new cold brew recipe
             WHEN COUNTRY  = 'India' AND ORDER_DATE >= '2026-08-01' AND PRODUCT_NAME = 'Masala Chai' THEN 1.40  -- monsoon chai boom
             ELSE 1.0 END
      -- deterministic noise 0.85 – 1.15
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

CREATE OR REPLACE TABLE CUSTOMER_FEEDBACK (
  FEEDBACK_ID   NUMBER,
  FEEDBACK_DATE DATE,
  STORE_ID      VARCHAR,
  STORE_NAME    VARCHAR,
  CITY          VARCHAR,
  CHANNEL       VARCHAR,
  RATING        NUMBER,
  FEEDBACK_TEXT VARCHAR
);

INSERT INTO CUSTOMER_FEEDBACK VALUES
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
   STEP 3 · Cortex Search service over customer feedback (unstructured)
   snowflake-arctic-embed-l-v2.0 is multilingual (English, Japanese, Hinglish...)
----------------------------------------------------------------------------- */
CREATE OR REPLACE CORTEX SEARCH SERVICE FEEDBACK_SEARCH
  ON FEEDBACK_TEXT
  ATTRIBUTES STORE_NAME, CITY, CHANNEL, RATING, FEEDBACK_DATE
  WAREHOUSE = MCP_LAB_WH
  TARGET_LAG = '1 day'
  EMBEDDING_MODEL = 'snowflake-arctic-embed-l-v2.0'
  COMMENT = 'Customer reviews & complaints for Snowbrew stores'
AS
  SELECT FEEDBACK_ID, FEEDBACK_TEXT, STORE_NAME, CITY, CHANNEL, RATING, FEEDBACK_DATE
  FROM CUSTOMER_FEEDBACK;


/* -----------------------------------------------------------------------------
   STEP 4 · Semantic view over sales (structured) — used by Cortex Analyst
----------------------------------------------------------------------------- */
CREATE OR REPLACE SEMANTIC VIEW SNOWBREW_SALES
  TABLES (
    sales AS SNOWBREW_LAB.CORE.DAILY_SALES
      PRIMARY KEY (ORDER_DATE, STORE_ID, PRODUCT_ID)
      WITH SYNONYMS ('orders', 'transactions', 'daily sales')
      COMMENT = 'Units sold per store, product and day',
    stores AS SNOWBREW_LAB.CORE.STORES
      PRIMARY KEY (STORE_ID)
      WITH SYNONYMS ('shops', 'cafes', 'locations')
      COMMENT = 'Snowbrew store master data',
    products AS SNOWBREW_LAB.CORE.PRODUCTS
      PRIMARY KEY (PRODUCT_ID)
      WITH SYNONYMS ('menu items', 'drinks')
      COMMENT = 'Menu items with price and unit cost'
  )
  RELATIONSHIPS (
    sales_to_stores   AS sales (STORE_ID)   REFERENCES stores,
    sales_to_products AS sales (PRODUCT_ID) REFERENCES products
  )
  FACTS (
    sales.units_sold AS sales.UNITS
      COMMENT = 'Number of items sold',
    sales.revenue AS sales.UNITS * sales.UNIT_PRICE_USD
      COMMENT = 'Revenue in USD',
    sales.cogs AS sales.UNITS * sales.UNIT_COST_USD
      COMMENT = 'Cost of goods sold in USD'
  )
  DIMENSIONS (
    sales.order_date AS sales.ORDER_DATE
      WITH SYNONYMS ('date', 'day')
      COMMENT = 'Date of sale',
    sales.order_month AS DATE_TRUNC('MONTH', sales.ORDER_DATE)
      WITH SYNONYMS ('month')
      COMMENT = 'Month of sale (first day of month)',
    stores.store_name AS stores.STORE_NAME
      WITH SYNONYMS ('store', 'shop', 'location')
      COMMENT = 'Store name, e.g. Shibuya Crossing',
    stores.city AS stores.CITY
      COMMENT = 'City of the store',
    stores.country AS stores.COUNTRY
      COMMENT = 'Country of the store',
    stores.store_format AS stores.STORE_FORMAT
      COMMENT = 'Flagship, Kiosk, Cafe or Drive-thru',
    products.product_name AS products.PRODUCT_NAME
      WITH SYNONYMS ('product', 'item', 'drink')
      COMMENT = 'Menu item name',
    products.category AS products.CATEGORY
      COMMENT = 'Coffee, Tea or Food'
  )
  METRICS (
    sales.total_revenue AS SUM(sales.revenue)
      WITH SYNONYMS ('sales', 'turnover', 'revenue')
      COMMENT = 'Total revenue in USD',
    sales.total_units AS SUM(sales.units_sold)
      WITH SYNONYMS ('volume', 'units', 'cups sold')
      COMMENT = 'Total units sold',
    sales.gross_margin AS SUM(sales.revenue) - SUM(sales.cogs)
      COMMENT = 'Revenue minus cost of goods sold, USD',
    sales.gross_margin_pct AS (SUM(sales.revenue) - SUM(sales.cogs)) / NULLIF(SUM(sales.revenue), 0)
      COMMENT = 'Gross margin as a fraction of revenue'
  )
  COMMENT = 'Snowbrew Coffee Co. sales, Jun-Sep 2026'
  AI_SQL_GENERATION 'Revenue and margin are in USD. Data covers 2026-06-01 to 2026-09-30. "Last month" means September 2026. Round money to 2 decimals.';


/* -----------------------------------------------------------------------------
   STEP 5 · Custom tool: price-change simulator (stored procedure)
   Simple constant-elasticity model on the last 30 days of sales.
----------------------------------------------------------------------------- */
CREATE OR REPLACE PROCEDURE SIMULATE_PRICE_CHANGE(PRODUCT_NAME VARCHAR, PRICE_CHANGE_PCT FLOAT)
  RETURNS VARIANT
  LANGUAGE SQL
  COMMENT = 'What-if: projected 30-day units, revenue and margin after a price change'
AS
$$
DECLARE
  result VARIANT;
BEGIN
  SELECT OBJECT_CONSTRUCT(
           'product',                 product_name,
           'price_change_pct',        :PRICE_CHANGE_PCT::NUMBER(6,2),
           'elasticity_assumed',      elasticity,
           'baseline_units_30d',      units,
           'projected_units_30d',     ROUND(units * (1 + elasticity * :PRICE_CHANGE_PCT / 100))::NUMBER,
           'baseline_revenue_usd',    ROUND(revenue, 2),
           'projected_revenue_usd',   ROUND(revenue * (1 + :PRICE_CHANGE_PCT / 100) * (1 + elasticity * :PRICE_CHANGE_PCT / 100), 2)::NUMBER(12,2),
           'baseline_margin_usd',     ROUND(revenue - cost, 2),
           'projected_margin_usd',    ROUND((revenue * (1 + :PRICE_CHANGE_PCT / 100) - cost) * (1 + elasticity * :PRICE_CHANGE_PCT / 100), 2)::NUMBER(12,2),
           'window',                  'last 30 days of data, all stores',
           'note',                    'Constant-elasticity estimate for illustration only.')
    INTO :result
  FROM (
    SELECT p.PRODUCT_NAME AS product_name,
           CASE p.CATEGORY WHEN 'Coffee' THEN -0.6 WHEN 'Tea' THEN -0.5 ELSE -0.9 END AS elasticity,
           SUM(s.UNITS)                        AS units,
           SUM(s.UNITS * s.UNIT_PRICE_USD)     AS revenue,
           SUM(s.UNITS * s.UNIT_COST_USD)      AS cost
    FROM SNOWBREW_LAB.CORE.DAILY_SALES s
    JOIN SNOWBREW_LAB.CORE.PRODUCTS p ON p.PRODUCT_ID = s.PRODUCT_ID
    WHERE p.PRODUCT_NAME ILIKE '%' || :PRODUCT_NAME || '%'
      AND s.ORDER_DATE > DATEADD(day, -30, (SELECT MAX(ORDER_DATE) FROM SNOWBREW_LAB.CORE.DAILY_SALES))
    GROUP BY p.PRODUCT_NAME, p.CATEGORY
    ORDER BY units DESC
    LIMIT 1
  );

  IF (result IS NULL) THEN
    SELECT OBJECT_CONSTRUCT('error', 'Unknown product', 'valid_products', ARRAY_AGG(PRODUCT_NAME))
      INTO :result FROM SNOWBREW_LAB.CORE.PRODUCTS;
  END IF;
  RETURN result;
END;
$$;


/* -----------------------------------------------------------------------------
   STEP 6 · Cortex Agent: "Snowbrew Copilot" (combines all three tools)
----------------------------------------------------------------------------- */
CREATE OR REPLACE AGENT SNOWBREW_COPILOT
  COMMENT = 'Episode 1: answers sales questions, explains why, simulates prices'
  PROFILE = '{"display_name": "Snowbrew Copilot"}'
  FROM SPECIFICATION
$$
models:
  orchestration: auto

orchestration:
  budget:
    seconds: 120
    tokens: 32000

instructions:
  response: >
    You are the analytics copilot for Snowbrew Coffee Co. Be concise and specific.
    Always include the numbers (USD, units, percentages) and name the stores and products.
    When you use customer feedback, quote one or two short examples.
  orchestration: >
    For numeric questions (revenue, units, margin, trends) use sales_analyst.
    For questions about why something happened, first quantify the change with sales_analyst,
    then look for explanations in customer feedback with feedback_search, filtering by store or city when possible.
    For what-if pricing questions use price_simulator.
  sample_questions:
    - question: "Which store had the biggest revenue drop in September vs August, and why?"
    - question: "What are customers in London complaining about?"
    - question: "What happens to Caffe Latte revenue if we raise the price by 8%?"

tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "sales_analyst"
      description: "Answers questions about Snowbrew sales: revenue, units, gross margin by store, city, country, product, category, day and month (Jun-Sep 2026)."
  - tool_spec:
      type: "cortex_search"
      name: "feedback_search"
      description: "Searches customer reviews and complaints (multilingual) for Snowbrew stores. Attributes: STORE_NAME, CITY, CHANNEL, RATING, FEEDBACK_DATE."
  - tool_spec:
      type: "generic"
      name: "price_simulator"
      description: "Simulates the effect of a price change on a product's 30-day units, revenue and gross margin."
      input_schema:
        type: "object"
        properties:
          PRODUCT_NAME:
            type: "string"
            description: "Menu item name, e.g. Caffe Latte, Cold Brew, Matcha Latte"
          PRICE_CHANGE_PCT:
            type: "number"
            description: "Price change in percent, e.g. 8 for +8%, -5 for -5%"
        required: ["PRODUCT_NAME", "PRICE_CHANGE_PCT"]

tool_resources:
  sales_analyst:
    semantic_view: "SNOWBREW_LAB.CORE.SNOWBREW_SALES"
    execution_environment:
      type: "warehouse"
      warehouse: "MCP_LAB_WH"
  feedback_search:
    search_service: "SNOWBREW_LAB.CORE.FEEDBACK_SEARCH"
    max_results: 5
    id_column: "FEEDBACK_ID"
    title_column: "STORE_NAME"
  price_simulator:
    type: "procedure"
    identifier: "SNOWBREW_LAB.CORE.SIMULATE_PRICE_CHANGE"
    execution_environment:
      type: "warehouse"
      warehouse: "MCP_LAB_WH"
$$;


/* -----------------------------------------------------------------------------
   STEP 7 · The MCP server
   One server, four tools. The agent is the recommended "front door";
   the other three let MCP clients call each capability directly.
   NOTE: we deliberately do NOT add SYSTEM_EXECUTE_SQL here — raw SQL next to
   governed tools lets a client bypass the semantic layer.
----------------------------------------------------------------------------- */
CREATE OR REPLACE MCP SERVER SNOWBREW_MCP
  FROM SPECIFICATION
$$
tools:
  - name: "snowbrew_copilot"
    type: "CORTEX_AGENT_RUN"
    identifier: "SNOWBREW_LAB.CORE.SNOWBREW_COPILOT"
    title: "Snowbrew Copilot (agent)"
    description: "Ask any business question about Snowbrew Coffee Co. sales, customer feedback or pricing. Combines sales analytics, feedback search and a price simulator."
    annotations:
      readOnlyHint: true
      destructiveHint: false
      idempotentHint: true
      openWorldHint: false

  - name: "search_customer_feedback"
    type: "CORTEX_SEARCH_SERVICE_QUERY"
    identifier: "SNOWBREW_LAB.CORE.FEEDBACK_SEARCH"
    title: "Search customer feedback"
    description: "Semantic search over Snowbrew customer reviews and complaints in any language."

  - name: "sales_analyst"
    type: "CORTEX_ANALYST_MESSAGE"
    identifier: "SNOWBREW_LAB.CORE.SNOWBREW_SALES"
    title: "Sales analyst (text-to-SQL)"
    description: "Turns a natural-language question about Snowbrew sales into SQL over the governed semantic view."

  - name: "simulate_price_change"
    type: "GENERIC"
    identifier: "SNOWBREW_LAB.CORE.SIMULATE_PRICE_CHANGE"
    title: "Price-change simulator"
    description: "What-if: projected 30-day units, revenue and margin for a product after a price change (percent)."
    annotations:
      readOnlyHint: true
      destructiveHint: false
      idempotentHint: true
      openWorldHint: false
    config:
      type: "procedure"
      warehouse: "MCP_LAB_WH"
      query_timeout: 60
      input_schema:
        type: "object"
        properties:
          PRODUCT_NAME:
            type: "string"
            description: "Menu item, e.g. Caffe Latte"
          PRICE_CHANGE_PCT:
            type: "number"
            description: "Price change in percent, e.g. 8 or -5"
        required: ["PRODUCT_NAME", "PRICE_CHANGE_PCT"]
$$;


/* -----------------------------------------------------------------------------
   STEP 8 · Quick checks (should all return rows)
----------------------------------------------------------------------------- */
SHOW MCP SERVERS IN SCHEMA SNOWBREW_LAB.CORE;
DESCRIBE MCP SERVER SNOWBREW_MCP;

-- The story in the numbers: Shibuya revenue Aug vs Sep
SELECT * FROM SEMANTIC_VIEW(
  SNOWBREW_SALES
  DIMENSIONS stores.store_name, sales.order_month
  METRICS sales.total_revenue
  WHERE stores.store_name = 'Shibuya Crossing'
)
ORDER BY order_month;

-- The story in the words (multilingual semantic search)
SELECT PARSE_JSON(
  SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'SNOWBREW_LAB.CORE.FEEDBACK_SEARCH',
    '{"query": "machine broken long wait", "columns": ["STORE_NAME","RATING","FEEDBACK_TEXT"], "limit": 3}'
  )
):results AS top_matches;

-- The custom tool
CALL SIMULATE_PRICE_CHANGE('Caffe Latte', 8);
