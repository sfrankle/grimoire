---
name: notion-save
description: Save or update what this session learned in the Notion hub, filed so the right future session finds it and no other does.
disable-model-invocation: true
argument-hint: "What to save, or a note to file"
---

# Notion save

Turn facts from this session, or a note the user names, into hub pages through each hub's connector.
The hub root is `$NOTION_HUB_DIR`, or `~/.claude/notion-hub` when that is unset.
A hub is a subfolder of the root with a `config.json`; its folder name is its id.
Each hub uses the connector named in its `hub.connector`, or the Notion connector when that is unset; if it is missing, say so and stop.
Read index rows only through `scoped-index.sh <id>` in this plugin's `../../scripts/` (`${CLAUDE_PLUGIN_ROOT}/scripts/` in Claude Code), which hides rows this folder may not see.
A hub's `config.json` and `rules.md` may tighten these steps, never loosen them.

0. With several hubs, pick a hub for each fact using the top-level `rules.md`.
1. Pick the facts worth keeping, or read the note the user names, and save only what the user asked for.
   That hub's `rules.md` says what belongs in it.
2. Match each fact to a row from `scoped-index.sh <id>` and fetch that page.
3. Act on the row's edit flag (`ro` for any value not listed under `values.edit`):
   - `ro`: propose the change in chat and make no edit.
   - `edit`: make the smallest edit, in the section the fact belongs in.
   - `own`: rewrite stale lines instead of appending contradictions.
4. With no match, create a page in that hub with its connector from `new_pages`: its `defaults`, its `template_url` when set, and its `marker` as the first line.
   Set the edit field to a `values.edit.agent_owned` value, and stop if none is mapped.
5. Fill the fields named in `fields`, reusing existing options:
   - `visibility`: a private value for anything personal; a personal fact never goes in a shared page.
   - `load`: leave it auto; set an `always` value only after the user agrees, since it costs every session.
   - `summary`: the facts themselves, such as "NAS backs up nightly at 02:00 to B2", not "Notes about backups".
   - `keywords`: words a future task would contain.
6. Load the `notion-refresh` skill for each hub you changed.
7. Report one line per page (hub id, created or updated, title, visibility, load, link), then any changes proposed for read-only pages.
