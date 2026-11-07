# Episode 3: The Night Shift

Every night, a Snowflake task wakes up a coding agent. It follows your company **playbook**, a skill stored on a stage, and then:
1. checks the new day with your own anomaly script;
2. investigates what moved, connecting stores and translating reviews;
3. writes a morning brief with owners and deadlines;
4. keeps a live **Snowbrew Morning Brief** app up to date in your house style.

There's no chat and nobody clicking: it runs under a locked-down role.

**Standalone:** you don't need Episodes 1 or 2. Run on top of them, it creates its own schema and leaves the rest alone.

## Files

| File | Run where | What it does |
|---|---|---|
| [`setup.sql`](setup.sql) | Snowsight worksheet → **Run All** (~4 min) | Creates the data, the playbook skill (`SKILL.md` + `detect_anomalies.py`) on a stage, `NIGHT_SHIFT_ROLE`, the procedures and the nightly task. Then it runs night 1 and has the agent build the app. |
| [`cleanup.sql`](cleanup.sql) | Snowsight worksheet | Suspends the task and drops the `NIGHT_SHIFT` schema and role |

## Quick start

1. Run `setup.sql`. At the end you'll see night 1's brief.
2. Open **Snowsight → Projects → Streamlit → Snowbrew Morning Brief**.
3. Night 2, unattended:
   ```sql
   USE ROLE NIGHT_SHIFT_ROLE;
   CALL SNOWBREW_LAB.NIGHT_SHIFT.LOAD_NEXT_DAY();
   EXECUTE TASK SNOWBREW_LAB.NIGHT_SHIFT.NIGHTLY_REVIEW;
   ```
   Wait about 2 minutes and refresh the app.
4. Teach it a new rule in plain English. The night-2 review misses the Singapore oat-cookie sell-out, because the playbook only checks store revenue. Add one line to `house_rules.md`:
   ```sql
   USE ROLE MCP_LAB_ROLE;
   CALL SNOWBREW_LAB.NIGHT_SHIFT.WRITE_STAGE_FILE(
     '@SNOWBREW_LAB.NIGHT_SHIFT.PLAYBOOK/skills/snowbrew-playbook/house_rules.md', $$# Snowbrew house rules
   - Write money as USD with thousands separators, e.g. $1,234.56.
   - Name the city next to every store, e.g. "Surry Hills (Sydney)".
   - Sell-outs: for every store, compare each product's units on the latest day with the same weekday over the previous 4 weeks. If a product sold less than 40% of normal, add it to the brief as MEDIUM with a headline starting "Sell-out:", even if the store's total revenue looks fine.
   $$);
   USE ROLE NIGHT_SHIFT_ROLE;
   CALL SNOWBREW_LAB.NIGHT_SHIFT.RUN_NIGHT_SHIFT();   -- the same night, now with the sell-out flagged
   ```

## Night Shift vs CoCo Automations

Snowflake's **CoCo Automations** (preview, under *Snowsight → CoCo → Automations*) also runs an agent on a schedule. Under the hood, each automation is an `AGENT TASK` in your personal `USER$` database. It runs the same coding-agent engine as your **user**, with your default role (there's no option to choose another). Approval prompts are turned off, and the result is emailed to you through the `gather_email_content` tool.

| | CoCo Automations | The Night Shift |
|---|---|---|
| Built for | You: "email me a report" | A team: "do our review, our way" |
| Runs as | Your user and default role | A dedicated least-privilege role |
| Company rules | Inside each prompt | A shared playbook skill on a stage (`SKILL.md`, scripts, house rules) |
| Output | An email plus run history | A `MORNING_BRIEF` table plus a live team app |
| Writing to tables | Blocked by Restricted Session Scope (tested) | The agent reads; a procedure writes the results |

Tested 7 Nov 2026: creating an agent task outside a personal database fails with *"Agent tasks can only be created in a personal database"*. An automation's `INSERT` fails with *"Restricted session scope: USER SPECIFIED does not include INSERT access"*.

**Use Automations** for personal reports and alerts. **Use this pattern** when the agent works for a team, follows versioned company rules, must run under a service role and has to deliver to a table or app.

## Gotchas

- **Owner's-rights procedures remove the coding tools.** Call `AGENT_RUN` from an `EXECUTE AS CALLER` procedure. Otherwise the response warns *"Code execution tools are unavailable when an agent is invoked from an owner's rights stored procedure."*
- **In a task, the agent's own writes are blocked** by Restricted Session Scope (*"Restricted session scope: USER SPECIFIED does not include DELETE access…"*). So the agent only reads and returns the brief as JSON, and the procedure writes it. That's the safer design anyway.
- **Skills from a stage:** the agent mounts them read-only and runs the scripts in the skill folder.
- **Snowsight can't PUT local files,** so `setup.sql` writes the skill files with a tiny Python procedure (`WRITE_STAGE_FILE`).

**Tested:** 1–7 Nov 2026 · AWS ap-northeast-1 · Enterprise edition · full reader run 156 s · night 2 via the scheduled task: SUCCEEDED · house-rule demo verified · budget ~3 credits
