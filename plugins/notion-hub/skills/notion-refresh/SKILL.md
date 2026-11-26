---
name: notion-refresh
description: Use when the user asks to refresh, rebuild or update the Notion index, or when notion-setup or notion-save load it as their last step. Re-reads a hub database through its connector and rebuilds the local index.
argument-hint: "[hub id]"
---

# Notion refresh

Rebuild a hub's `index.md` from its database.
The hub root is `$NOTION_HUB_DIR`, or `~/.claude/notion-hub` when that is unset.
A hub is a subfolder of the root with a `config.json`; its folder name is its id.
Each hub uses the connector named in its `hub.connector`, or the Notion connector when that is unset.
`build-index.sh` lives in this plugin at `../../scripts/`, relative to this skill's folder (`${CLAUDE_PLUGIN_ROOT}/scripts/` in Claude Code).
Take an optional hub id; without one, refresh every hub.
A hub that fails doesn't stop the others.

For each hub:

1. Read its `config.json`, or tell the user to run `notion-setup` if it is missing.
2. Query the data source in `hub.data_source`, paging until the connector reports no more rows.
   If rows are truncated, report it and skip this hub.
   If a `fields` value is not a property of the data source, say which and suggest `notion-setup`.
3. Write every row to `rows.json` in that hub's folder as an array of `{"url": "<page url>", "properties": {"<property name>": <value>}}`.
   Use the connector's property names exactly.
   A single value is a string and a multi-select is an array of strings, decoded if the connector returns it as a JSON string.
4. Run `build-index.sh rows.json <id>`, then delete `rows.json`.
   If it indexed fewer pages than you fetched, report both numbers.

Report one result per hub, with its id and any failure.
