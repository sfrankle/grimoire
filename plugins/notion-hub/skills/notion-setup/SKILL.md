---
name: notion-setup
description: Add, edit or migrate a Notion hub's config and rules, then build its index.
disable-model-invocation: true
argument-hint: "add | edit <hub> | migrate"
---

# Notion setup

Create or edit a hub's `config.json`, `rules.md` and optional `rules.private.md`, and the routing `rules.md` across hubs.
The hub root is `$NOTION_HUB_DIR`, or `~/.claude/notion-hub` when that is unset.
Create it if missing.
A hub is a subfolder of the root with a `config.json`; its folder name is its id.
In legacy mode the root has a top-level `config.json` and is the only hub, and subfolders are ignored.
Each hub uses the connector named in its `hub.connector`, or the Notion connector when that is unset.
The shapes to fill are `../../examples/hubs/homelab/config.json`, `../../examples/hubs/homelab/rules.md` and, for routing, `../../examples/rules.md`.
Ask the user one question at a time, as plain prose.

## Steps

1. Check `jq` is available.
   If it is missing, say so in one line, with the install command, and stop.
   Check the hub's connector once it is known: asked for in step 3, or read from `hub.connector` when editing or migrating.
   If it is missing, say so in one line and stop.
2. Ask whether to add a hub, edit one or migrate a legacy hub, unless the argument says.
   Edit loads the named hub's files and keeps every unchanged value, showing a diff before writing.
3. Add: ask for the hub id (lowercase letters, digits and dashes), the connector, the database link (or search it and let them pick), the `show_in` folders, and a one-line pointer.
   Record the connector, `show_in` and pointer as `hub.connector`, `hub.show_in` and `hub.pointer`.
   Leave `show_in` out to show the hub in every folder.
   Write into `<root>/<id>/`.
4. Migrate: a legacy hub moves into `<root>/<id>/`.
   Ask for the id, then list every move, plus the new routing `rules.md`, and wait for a yes.
   Move `rules.md`, `rules.private.md`, `index.md` and any `rows.json` first and `config.json` last, so a half-done move still reads as legacy.
   Then write a new top-level `rules.md` for routing, since in multi mode that file means routing and the old one held this hub's rules.
   The migration ends there, with no refresh needed.
5. Fetch the data source and read its schema: property names and options.
   Propose `fields` from the property names, with `title` and `summary` required.
   Propose `values` from the options:
   - Map each `edit` option to `read_only`, `small_edits` or `agent_owned`.
     If the hub splits this across two columns, such as an owner and an access column, propose merging them into one.
   - Map `load` options to `always` and `ask`.
     Anything else counts as auto.
   Confirm the mapping with the user.
   Record `version` as 1, plus `hub.name`, `hub.database_url` and `hub.data_source` (the `collection://` ID); refresh needs the last.
6. Ask which `visibility` values are private, and which folders may see private rows.
   These become `scopes.private_values` and `scopes.private_paths`.
   Ask before turning on `always_shows_everywhere`, and explain that one wrong load value would then expose a private page everywhere.
7. Set `new_pages`.
   `defaults` may not set the visibility or load field.
   Ask for an optional `template_url` and `marker`.
8. If the hub's `rules.md` exists, show it and keep or edit it, interviewing only on request.
   Otherwise seed it with three short questions: what goes in the hub, what goes elsewhere, and when to suggest a save.
   Offer `rules.private.md` for rules that would reveal private material, such as where personal documents live.
9. With two or more hubs, seed or edit the top-level `rules.md` as routing: which facts go to which hub id, and to ask the user when unclear.
10. Show every file to write, and write only after the user confirms.
11. Load the `notion-refresh` skill for that hub's id to build its index.
