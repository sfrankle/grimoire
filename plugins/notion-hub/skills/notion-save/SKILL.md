---
name: notion-save
description: Use when the user asks to save to a Notion hub, or when a settled fact from this session changes an agent-owned hub page or belongs in a new one. Files it so the right future session finds it and no other does.
argument-hint: "What to save, or a note to file"
---

# Notion save

Turn facts from this session, or a note the user names, into hub pages through each hub's connector.
The hub root is `$NOTION_HUB_DIR`, or `~/.claude/notion-hub` when that is unset.
A hub is a subfolder of the root with a `config.json`; its folder name is its id.
Each hub uses the connector named in its `hub.connector`, or the Notion connector when that is unset; if it is missing, say so and stop.
Read index rows only through `scoped-index.sh <id>` in this plugin's `../../scripts/` (`${CLAUDE_PLUGIN_ROOT}/scripts/` in Claude Code), which hides rows this folder may not see.
A hub's `config.json` and `rules.md` may tighten these steps, never loosen them.

Each hub's `saves` in `config.json` says when Claude may write without asking:

- `saves.update_owned`: `auto` updates `own` pages unasked; `ask` suggests the change in one line and waits for a yes.
- `saves.create`: `auto` creates agent-owned pages unasked; `ask` suggests the page in one line and waits for a yes.
- A missing or unknown value means `ask`.
- `edit` and `ro` pages always wait for the user, whatever `saves` says.

When the user ran this skill or asked for the save, their request is the yes.

0. With several hubs, pick a hub for each fact using the top-level `rules.md`.
1. Pick the facts worth keeping, or read the note the user names.
   Save only what the user asked for, or settled facts that hub's `rules.md` says belong in it.
2. Match each fact to a row from `scoped-index.sh <id>` and fetch that page.
3. Act on the row's edit flag (`ro` for any value not listed under `values.edit`):
   - `ro`: propose the change in chat and make no edit.
   - `edit`: make the smallest edit, in the section the fact belongs in, only when the user asked for the save.
   - `own`: rewrite stale lines instead of appending contradictions, following `saves.update_owned`.
4. With no match, follow `saves.create`, then create a page in that hub with its connector from `new_pages`: its `defaults`, its `template_url` when set, and its `marker` as the first line.
   Set the edit field to a `values.edit.agent_owned` value, and stop if none is mapped.
5. Fill the fields named in `fields`, reusing existing options:
   - `visibility`: a private value for anything personal or unclear; a personal fact never goes in a shared page.
   - `load`: leave it auto; set an `always` value only after the user agrees, since it costs every session.
   - `summary`: the facts themselves, such as "NAS backs up nightly at 02:00 to B2", not "Notes about backups".
   - `keywords`: words a future task would contain.
6. Load the `notion-refresh` skill for each hub you changed.
7. Report one line per page, including pages written unasked (hub id, created or updated, title, visibility, load, link), then any changes proposed for read-only pages.
