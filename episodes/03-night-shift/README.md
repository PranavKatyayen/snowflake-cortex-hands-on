# Episode 3: The Night Shift

Every night, a Snowflake task wakes up `NIGHT_SHIFT_AGENT`, a named Cortex coding agent. It follows your company **playbook**, a skill stored on a stage, and then:
1. checks the new day with your own anomaly script;
2. investigates what moved, connecting stores and translating reviews;
3. writes a morning brief with owners and deadlines;
4. keeps a live **Snowbrew Morning Brief** app up to date in your house style.

There's no chat and nobody clicking: it runs under a locked-down role.

**Standalone:** you don't need Episodes 1 or 2. Run on top of them, it creates its own schema and leaves the rest alone.

## Files

| File | Run where | What it does |
|---|---|---|
| [`setup-part1.sql`](setup-part1.sql) | Snowsight worksheet → **Run All** (~3 min) | Creates the data, the playbook skill (`SKILL.md` + `detect_anomalies.py`) on a stage, the named agent `NIGHT_SHIFT_AGENT`, `NIGHT_SHIFT_ROLE`, the procedures and the nightly task. Then it runs night 1 and has the agent build the app. |
| [`setup-part2.sql`](setup-part2.sql) | Snowsight worksheet → **Run All** (~2-3 min) | Night 2 through the real task (waits for it to finish), then teaches the agent a new rule and shows night 2 before vs after. |
| [`cleanup.sql`](cleanup.sql) | Snowsight worksheet | Suspends the task and drops the `NIGHT_SHIFT` schema and role |

## Quick start

1. Run `setup-part1.sql` (Run All). At the end you'll see night 1's brief.
2. Open **Snowsight → Apps → Streamlit → Snowbrew Morning Brief**.
3. Run `setup-part2.sql` (Run All): night 2 via the real task, then one new plain-English rule. The last result shows night 2 before vs after the rule; refresh the app to see the new "Sell-out:" card.
4. Optional one-liners (rebuild the app, nightly schedule on/off, run log) are at the end of `setup-part2.sql`.

## How is this different from CoCo Automations?

CoCo Automations also run an agent on a schedule. I'm testing them properly and will publish the comparison as a separate post.

## Gotchas

- **Owner's-rights procedures removed the coding tools** in my first, inline `AGENT_RUN` version. The final version calls the named agent with `DATA_AGENT_RUN` from an `EXECUTE AS CALLER` procedure. The warning I got was *"Code execution tools are unavailable when an agent is invoked from an owner's rights stored procedure."*
- **In a task, the agent's own writes are blocked** by Restricted Session Scope (*"Restricted session scope: USER SPECIFIED does not include DELETE access…"*). So the agent only reads and returns the brief as JSON, and the procedure writes it. That's the safer design anyway.
- **Skills from a stage:** the agent loads the skill and runs the scripts in the skill folder.
- **Snowflake's docs say `PUT` can't run from a Snowsight worksheet,** so `setup-part1.sql` writes the skill files with a tiny Python procedure (`WRITE_STAGE_FILE`).

**Tested:** 1–11 Nov 2026 · AWS ap-northeast-1 · Enterprise edition + a fresh trial account in Snowsight · the final two-part scripts run end to end twice (part 1: 173–189 s, part 2: 129–130 s) · night 2 via the scheduled task: SUCCEEDED 9 of 9 · house-rule demo: flagged 8 of 8 · cleanup leaves Episodes 1–2 working · budget ~3 credits
