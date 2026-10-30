/* ============================================================================
   Snowflake Cortex Hands-On · Episode 2: a coding agent inside Snowflake
   Adds a CODING_AGENT tool to Episode 1's MCP server. Your AI client (Claude,
   Cursor...) hands a job to an agent that writes, runs and deploys code inside
   Snowflake, as your role, asking your approval before every change.

   Prerequisite: Episode 1 lab.sql + clients.sql (data, role, OAuth client).
   Run in a Snowsight SQL worksheet → Run All. Safe to re-run.
   ============================================================================ */

USE ROLE MCP_LAB_ROLE;
USE WAREHOUSE MCP_LAB_WH;
USE SCHEMA SNOWBREW_LAB.CORE;

-- Everything the agent builds goes here, so it's easy to see and to clean up
CREATE SCHEMA IF NOT EXISTS SNOWBREW_LAB.APPS;

-- Same server, same URL, same Claude/Cursor connector: one new tool at the bottom
CREATE OR REPLACE MCP SERVER SNOWBREW_LAB.CORE.SNOWBREW_MCP
  FROM SPECIFICATION
$$
tools:
  - name: "snowbrew_copilot"
    type: "CORTEX_AGENT_RUN"
    identifier: "SNOWBREW_LAB.CORE.SNOWBREW_COPILOT"
    title: "Snowbrew Copilot (agent)"
    description: "Ask any business question about Snowbrew Coffee Co.: sales, revenue, margin, stores, products, customer feedback, or price what-ifs. Returns an analysed answer."
    annotations:
      readOnlyHint: true
  - name: "search_customer_feedback"
    type: "CORTEX_SEARCH_SERVICE_QUERY"
    identifier: "SNOWBREW_LAB.CORE.FEEDBACK_SEARCH"
    title: "Search customer feedback"
    description: "Semantic search over Snowbrew customer reviews (English, Japanese, Hinglish). Filter by STORE_NAME, CITY, CHANNEL, RATING."
  - name: "sales_analyst"
    type: "CORTEX_ANALYST_MESSAGE"
    identifier: "SNOWBREW_LAB.CORE.SNOWBREW_SALES"
    title: "Sales analyst (text-to-SQL)"
    description: "Turns a sales question into SQL over the SNOWBREW_SALES semantic view."
  - name: "simulate_price_change"
    type: "GENERIC"
    identifier: "SNOWBREW_LAB.CORE.SIMULATE_PRICE_CHANGE"
    title: "Price change simulator"
    description: "Projects units, revenue and margin over 30 days if a product's price changes by a percentage."
    annotations:
      readOnlyHint: true
    config:
      type: "procedure"
      warehouse: "MCP_LAB_WH"
      query_timeout: 60
      input_schema:
        type: "object"
        properties:
          PRODUCT_NAME:
            type: "string"
            description: "Exact product name, e.g. 'Cold Brew' or 'Caffe Latte'"
          PRICE_CHANGE_PCT:
            type: "number"
            description: "Price change in percent, e.g. 8 for +8%, -5 for -5%"
        required: ["PRODUCT_NAME", "PRICE_CHANGE_PCT"]

  # ---- NEW in Episode 2 -----------------------------------------------------
  - name: "snowbrew_builder"
    type: "CODING_AGENT"
    title: "Snowbrew builder (coding agent in Snowflake)"
    description: "A coding agent that runs inside Snowflake. It writes and runs Python and SQL in a managed sandbox, and can build and deploy Streamlit apps, stages and files in SNOWBREW_LAB.APPS. Use it for anything that needs code: forecasts, charts, data apps. Pending commands need the user's approval."
    config:
      instructions:
        orchestration: "Work in as few approved steps as possible, because every command that changes something waits for the user to click Allow. Plan the whole job first, then: (1) write all files in one step, (2) run one combined python test script, (3) run one deploy step that creates the stage, uploads the files and creates the app. Read-only queries need no approval, so explore freely with SELECT and SHOW. Data lives in SNOWBREW_LAB.CORE: DAILY_SALES, STORES, PRODUCTS, CUSTOMER_FEEDBACK. Use warehouse MCP_LAB_WH. Create every new object (apps, stages, tables) in schema SNOWBREW_LAB.APPS, never in CORE. Streamlit apps: put streamlit_app.py and environment.yml (Snowflake Conda channel packages) on a stage in SNOWBREW_LAB.APPS, then deploy with CREATE STREAMLIT ... MAIN_FILE = 'streamlit_app.py' RUNTIME_NAME = 'SYSTEM$WAREHOUSE_RUNTIME' QUERY_WAREHOUSE = MCP_LAB_WH. Always set RUNTIME_NAME explicitly: new accounts otherwise default to the container runtime, which needs pyproject.toml and fails with environment.yml. The sandbox has newer libraries than the app runtime, so: pin streamlit=1.42.0 in environment.yml, use only Streamlit's built-in charts (st.bar_chart, st.line_chart, st.dataframe; no altair or plotly), and pin every other package you list. Before deploying, run the app's queries and data code in the sandbox with python to prove they work. Give the Snowsight link: https://app.snowflake.com/<org>/<account>/#/streamlit-apps/<DB>.<SCHEMA>.<APP> using lowercase org and account names."
        response: "Be brief. List what you created (objects and files) and give links. Do not paste full source code unless asked."
$$;

-- Check: the server should now include snowbrew_builder
DESCRIBE MCP SERVER SNOWBREW_LAB.CORE.SNOWBREW_MCP;
SHOW OBJECTS IN SCHEMA SNOWBREW_LAB.APPS;
