# notion-hub

Use one Notion database as Claude's long-term memory.
Every session starts with an index of the database, Claude fetches only the pages a task needs, and new durable facts get saved back as pages.

The examples below use an invented hub called "Field Notes", for a small pottery studio.

## How it works

The hub is a Notion database with one row per page.
Each row has a title and a one-line summary, and can carry a few flags.
The plugin caches those rows as a local index and prints them at the start of every Claude Code session.
Claude reads the index, then fetches the pages that match the task.
It never loads the whole hub.

Each row carries three flags, which you map from your own columns:

- **visibility**: `shared` or `private`.
- **load**: `always` (fetch at session start), `auto` (fetch when relevant) or `ask` (only when you ask).
- **edit**: `ro` (read only, Claude proposes changes in chat), `edit` (smallest edit to the right section) or `own` (Claude's page to keep current).

Private rows show only when the session folder is under one of your private paths.
In a Field Notes setup, a "Personal" page appears in `~/notes/personal` and nowhere else by default.
The one exception is the option `scopes.always_shows_everywhere`, which is off by default and shows private rows whose load flag is `always` in every folder.
Leave it off unless you need it, because one wrong load value would expose a private page everywhere.

At session start the hook prints, in order:

1. Your rules.
2. Your private rules, when the folder is in scope.
3. The index header, with the date it was built and its age in days.
4. The index rows that are in scope.
5. A list of `always` pages for Claude to fetch before its first answer.

The age is there so a stale index is never silent.
After 7 days the header suggests running `/notion-refresh`.
Output is capped at 9500 characters, set by `NOTION_HUB_MAX_CHARS`.
If rows are cut, a visible warning says how many and suggests shortening summaries or moving pages to the ask load value.

Saving goes the other way.
`/notion-save` turns what a session learned into hub pages, checking each row's edit flag first.
Claude never writes to the hub unasked.

## Install

```
/plugin marketplace add sfrankle/grimoire
/plugin install notion-hub@grimoire
```

You need:

- The claude.ai Notion connector, connected to your workspace.
  There is no API token: refresh goes through the connector.
- `jq`, for example `brew install jq`.

## Set up

Run `/notion-setup`.
It asks for your hub database, reads its columns, and proposes how they map to the three flags.
It then asks which values are private and which folders may see them, and asks a few questions to seed your rules.
It shows the files, writes them only after you confirm, and builds the first index.

## Your files

All live in `~/.claude/notion-hub/`, or in `$NOTION_HUB_DIR` when that is set.
None of them are in this repo.

- `config.json`: where the hub is, which columns and values map to the flags, which values are private, and defaults for new pages.
  See `examples/config.json`.
- `rules.md`: your rules in plain language, such as what goes in the hub, what goes elsewhere, and when to suggest a save.
  See `examples/rules.md`.
- `rules.private.md`: optional rules that would reveal private material, shown only in private folders.
- `index.md`: the cached index, written by `/notion-refresh`.
  A new index applies from the next session, because the hook runs at session start.
- `rows.json`: transient, written by `/notion-refresh` before it builds the index.
  It holds every row, including private ones, so keep it out of shared folders.

## Changing things later

Edit `config.json` or `rules.md` directly, or run `/notion-setup` again.
Setup keeps existing values and shows a diff before writing.
Then run `/notion-refresh` to rebuild the index.

## Other agents

The session-start hook is Claude Code only.
The skills are plain `SKILL.md` files, so other agents can run setup, refresh and save by hand.
They need a Notion connector of their own.

## Tests

```
bash plugins/notion-hub/tests/run.sh
```
