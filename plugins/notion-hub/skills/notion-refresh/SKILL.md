---
name: notion-refresh
description: Use when the user asks to refresh, rebuild or update the Notion index, or when notion-setup or notion-save load it as their last step. Re-reads the hub database through the Notion connector and rebuilds the local index.
---

# Notion refresh

Rebuild `index.md` from the hub database through the Notion connector.
The hub folder is `$NOTION_HUB_DIR`, or `~/.claude/notion-hub` when that is unset.
`build-index.sh` lives in this plugin at `../../scripts/`, relative to this skill's folder (`${CLAUDE_PLUGIN_ROOT}/scripts/` in Claude Code).

1. Read `config.json` in the hub folder, or tell the user to run `notion-setup` if it is missing.
2. Query the data source in `hub.data_source`, paging until the connector reports no more rows.
   If a page fails or rows are truncated, report it and stop.
   If a `fields` value is not a property of the data source, say which and suggest `notion-setup`.
3. Write every row to `rows.json` in the hub folder as an array of `{"url": "<page url>", "properties": {"<property name>": <value>}}`.
   Use the connector's property names exactly.
   A single value is a string and a multi-select is an array of strings, decoded if the connector returns it as a JSON string.
4. Run `build-index.sh rows.json`, then delete `rows.json`.
   Report its output and any stderr line.
   If it indexed fewer pages than you fetched, report both numbers.
