# Episode 2: a coding agent inside Snowflake

Send one message in Claude, and an agent running inside Snowflake writes, tests and deploys a live Streamlit app. It works under your role and asks before every change.

## Files

| File | Run where | What it does |
|---|---|---|
| [`setup.sql`](setup.sql) | Snowsight worksheet → **Run All** | Adds the `snowbrew_builder` tool (type `CODING_AGENT`) to Episode 1's MCP server and creates the `SNOWBREW_LAB.APPS` schema |
| [`cleanup.sql`](cleanup.sql) | Snowsight worksheet | Drops everything the agent built |

## Quick start

1. Complete [Episode 1](../01-mcp-server): run `lab.sql` and `clients.sql`, and connect Claude.
2. Run `setup.sql`.
3. In Claude, go to **Settings → Connectors**, then disconnect and reconnect the Snowbrew connector, so Claude reloads its tool list.
4. Set **Snowbrew builder** to **Always allow**. Snowflake still asks before every command that changes something.
5. In a new chat, send:
   > *Use snowbrew_builder to build and deploy a live Streamlit dashboard for Snowbrew inside Snowflake: August vs September revenue by store, a 14-day forecast with a store picker, and the latest customer complaints for the selected store. Give me the link.*
6. Click **Allow** about 3 times, then open the link it gives you.

## Gotchas

- New accounts create Streamlit apps on the **container runtime** by default, even though the `CREATE STREAMLIT` docs still say the warehouse runtime is the default. An app built with `environment.yml` then fails with *"pyproject.toml file does not exist"*. The builder's instructions set `RUNTIME_NAME = 'SYSTEM$WAREHOUSE_RUNTIME'` to avoid this.
- The agent's sandbox has newer libraries than the app runtime, so code can pass its tests and still fail in the app (for example Altair's `xOffset`). The instructions pin `streamlit=1.42.0` and use only Streamlit's built-in charts.
- Each command that changes something waits for your click, so the instructions tell the agent to work in 3 steps: write the files, test, deploy.
- The agent runs as **your** role, so that role's grants decide what it can touch.

**Tested:** 30–31 Oct 2026 · AWS ap-northeast-1 · Enterprise edition · Claude Desktop · about 3 minutes and 3 approvals per app
