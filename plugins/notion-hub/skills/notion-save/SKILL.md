---
name: notion-save
description: Save or update what this session learned in the Notion hub, filed so the right future session finds it and no other does.
disable-model-invocation: true
argument-hint: "What to save, or a note to file"
---

# Notion save

Turn facts from this session, or a note the user names, into hub pages, using the Notion connector.
The hub folder is `$NOTION_HUB_DIR`, or `~/.claude/notion-hub` when that is unset.
If `config.json` or `index.md` is missing there, tell the user to run `notion-setup` or `notion-refresh` and stop.
Read index rows only through `scoped-index.sh` in this plugin's `../../scripts/` (`${CLAUDE_PLUGIN_ROOT}/scripts/` in Claude Code), which hides rows this folder may not see.

## Guardrails

Read their specifics from `config.json` and `rules.md`, which may add restrictions but never loosen these.

1. **Edit level**: check the row's edit flag before writing.
   A value not listed under `values.edit` counts as read-only.
2. **Visibility**: `scopes` says what is private.
   Choose it per page, and give anything personal a private value.
   A personal fact never goes into a shared page: create a private page, or propose it in chat.
3. **Load cost**: the `values.load` always value costs every session, so ask the user first.
4. **Write discipline**: write only what the user asked to save.
   New pages start with the `new_pages.marker` line when one is set.
5. **Filing quality**: the summary states the facts themselves, and keywords are words a future task would contain.

## Steps

1. Distill the facts worth keeping, each with its reason, or read the note the user names.
   `rules.md` says what belongs in the hub and what goes elsewhere.
2. Match each fact to a row from `scoped-index.sh` and fetch the closest page.
3. Act on that row's edit flag:
   - `ro`: propose the change in chat and make no edit.
   - `edit`: make the smallest edit, in the section the fact belongs in.
   - `own`: rewrite stale lines instead of appending contradictions.
4. With no match, create an agent-owned page.
   Apply `new_pages.defaults`, copy `new_pages.template_url` when set, and start the body with the marker line.
   Then set the `edit` field to a `values.edit.agent_owned` value whatever `defaults` says, and stop if none is mapped.
5. Set the fields named in `fields`, in the connector's own format, including for multi-select values:
   - `visibility`: one of the values you chose per page under guardrail 2.
   - `load`: a value in neither `values.load.always` nor `values.load.ask`, as existing `auto` rows carry, or leave it unset.
     Only set the always value after the user agrees.
   - `summary`: one line of facts, such as "Kiln runs cone 6, 11 hours", not "Notes about the kiln".
   - `keywords`: reuse existing options and add a new one only when none fits.
   - `category`, `title`: the closest existing option, and a short specific name.
6. Load the `notion-refresh` skill to rebuild the index.
7. Report one line per page (created or updated, title, visibility, load, link), then any changes you proposed to read-only pages.
