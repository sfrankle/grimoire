---
name: notion-setup
description: Set up or edit the Notion hub config and rules, then build the first index.
disable-model-invocation: true
---

# Notion setup

Create or edit `config.json`, `rules.md` and optional `rules.private.md` in the hub folder, using the Notion connector.
The hub folder is `$NOTION_HUB_DIR`, or `~/.claude/notion-hub` when that is unset.
Create it if missing.
The shapes to fill are `../../examples/config.json` and `../../examples/rules.md`.
Ask the user one question at a time, as plain prose.

## Steps

1. Check the Notion connector and `jq` are available.
   If either is missing, say which in one line, with the install command for `jq`, and stop.
2. If `config.json`, `rules.md` or `rules.private.md` exists, load it and treat this run as an edit.
   Keep every unchanged value and show a diff before writing.
3. Ask the user for the hub database link, or search Notion for it and let them pick.
4. Fetch the data source and read its schema: property names and options.
   Propose `fields` from the property names, with `title` and `summary` required.
   Propose `values` from the options:
   - Map each `edit` option to `read_only`, `small_edits` or `agent_owned`.
     If the hub splits this across two columns, such as an owner and an access column, propose merging them into one.
   - Map `load` options to `always` and `ask`.
     Anything else counts as auto.
   Confirm the mapping with the user.
   Record `version` as 1, plus `hub.name`, `hub.database_url` and `hub.data_source` (the `collection://` ID); refresh needs the last.
5. Ask which `visibility` values are private, and which folders may see private rows.
   These become `scopes.private_values` and `scopes.private_paths`.
   Ask before turning on `always_shows_everywhere`, and explain that one wrong load value would then expose a private page everywhere.
6. Set `new_pages`.
   `defaults` may not set the visibility or load field.
   Ask for an optional `template_url` and `marker`.
7. If `rules.md` exists, show it and keep or edit it, interviewing only on request.
   Otherwise seed it with three short questions: what goes in the hub, what goes elsewhere, and when to suggest a save.
   Offer `rules.private.md` for rules that would reveal private material, such as where personal documents live.
8. Show `config.json`, `rules.md` and `rules.private.md` if used, and write only after the user confirms.
9. Load the `notion-refresh` skill to build the first index.

