---
name: notion-refresh
description: Use when the user asks to refresh, rebuild or update the Notion index, or when notion-setup or notion-save load it as their last step. Re-reads the hub database through the Notion connector and rebuilds the local index.
---

# Notion refresh

Rebuild `index.md` from the hub database.
This needs the Notion connector.
If it is not available, say so in one line and stop.

The hub folder is `$NOTION_HUB_DIR`, or `~/.claude/notion-hub` when that is unset.
`build-index.sh` lives in this plugin at `../../scripts/build-index.sh`, relative to this skill's folder.
In Claude Code that is `${CLAUDE_PLUGIN_ROOT}/scripts/build-index.sh`.

1. Read `config.json` in the hub folder.
   If it is missing, tell the user to run `notion-setup` and stop.
2. Query the data source in `hub.data_source` through the Notion connector.
   Request the largest page the connector allows, and keep requesting pages (by cursor or offset, whichever it offers) until it reports no more rows.
   If any page request fails, report it and stop without writing `rows.json`.
   Count the rows fetched.
3. Write every row to `rows.json` in the hub folder as an array of `{"url": "<page url>", "properties": {"<property name>": <value>}}`.
   Use the property names exactly as the connector returns them.
   A single-value property (title, text, select) is a string.
   A multi-select or other list property is an array of strings.
   If the connector hands a list back as a JSON-encoded string such as `"[\"a\",\"b\"]"`, decode it into a real array.
   Leave out properties the row does not have.
4. Run `build-index.sh rows.json` with the hub folder's `rows.json`.
   It prints `Indexed N pages.` or one error line.
   On an error, report it and stop.
   N must equal the row count from step 2.
   If it does not, report both numbers and stop.
5. Spot-check three rows: the first, middle and last data rows of `index.md`.
   Fetch each row's URL through the connector and compare its title and summary with the index row.
   Compare the page's properties, since a page title can carry an icon prefix.
   A fetch that fails counts as a mismatch.
6. On any mismatch, report it and repeat steps 2 to 5 once.
   If it still mismatches, report the rows that differ and stop.
7. Report one line: `Indexed N pages, 3 spot-checked.`
