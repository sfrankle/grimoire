---
name: notion-refresh
description: Use when the user asks to refresh, rebuild or update the Notion index, or when notion-setup or notion-save load it as their last step. Re-reads the hub database through the Notion connector and rebuilds the local index.
---

# Notion refresh

Rebuild `index.md` from the hub database.
This needs the Notion connector.
If it is not available, say so in one line and stop.

The hub folder is `$NOTION_HUB_DIR`, or `~/.claude/notion-hub` when that is unset.
`build-index.sh` and `scoped-index.sh` live in this plugin at `../../scripts/`, relative to this skill's folder.
In Claude Code that is `${CLAUDE_PLUGIN_ROOT}/scripts/`.

1. Read `config.json` in the hub folder.
   If it is missing, tell the user to run `notion-setup` and stop.
2. Query the data source in `hub.data_source` through the Notion connector.
   Request the largest page the connector allows, and keep requesting pages (by cursor or offset) until it reports no more rows.
   If any page request fails, report it and stop without writing `rows.json`.
   If the connector says more rows exist and you cannot fetch them, report the truncation plainly and stop without writing `rows.json`.
   Count the rows fetched.
3. Write every row to `rows.json` in the hub folder as an array of `{"url": "<page url>", "properties": {"<property name>": <value>}}`.
   Use the connector's property names exactly.
   A single-value property (title, text, select) is a string, and a multi-select or other list is an array of strings.
   If the connector hands a list back as a JSON-encoded string such as `"[\"a\",\"b\"]"`, decode it into a real array.
   Leave out properties the row does not have.
4. Run `build-index.sh rows.json` with the hub folder's `rows.json`.
   It prints `Indexed N pages.` or one error line, which you report before stopping.
   N must equal the row count from step 2, or report both numbers and stop.
5. Run `scoped-index.sh` and keep only its `shared/` rows, preferring `shared/auto` or `shared/always`.
   Spot-check the first, middle and last of those, or fewer when fewer exist, and count how many you checked.
   Fetch each row's URL through the connector.
   Normalise the fetched title and summary the way the index does (`|` becomes `/`, whitespace collapses to single spaces, ends trimmed), then compare them with the row.
   Compare the page's properties, since a page title can carry an icon prefix.
   A failed fetch counts as a mismatch.
6. On any mismatch, report it and repeat steps 2 to 5 once.
   If it still mismatches, report the shared rows that differ (never a private title) and stop.
7. Report one line: `Indexed N pages, K spot-checked.`
