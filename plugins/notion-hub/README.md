# notion-hub

Use Notion databases as Claude's long-term memory, one hub per workspace.
Every session starts with an index of each hub, Claude fetches only the pages a task needs, and new durable facts get saved back as pages.

The examples below use two invented hubs: "Homelab Notes", for a home lab (a NAS, a small k3s cluster and the home network), and "Garden Journal", for sowing dates and plant care.

## How it works

A hub is a Notion database with one row per page.
Each row has a title and a one-line summary, and can carry a few flags.
The plugin caches those rows as a local index and prints them at the start of every Claude Code session.
Claude reads the index, then fetches the pages that match the task.
It never loads the whole hub.

Each row carries three flags, which you map from your own columns:

- **visibility**: `shared` or `private`.
- **load**: `always` (fetch at session start), `auto` (fetch when relevant) or `ask` (only when you ask).
- **edit**: `ro` (read only, Claude proposes changes in chat), `edit` (smallest edit to the right section) or `own` (Claude's page to keep current).

Private rows show only when the session folder is under one of your private paths.
In a Homelab Notes setup, a "Personal" page appears in `~/notes/personal` and nowhere else by default.
The one exception is the option `scopes.always_shows_everywhere`, which is off by default and shows private rows whose load flag is `always` in every folder.
Leave it off unless you need it, because one wrong load value would expose a private page everywhere.

At session start the hook prints your rules, then the in-scope rows, `always` rows first.
The header carries the build date, so Claude can suggest `/notion-refresh` when the index is over a week old.
Output stays under 9500 characters (`NOTION_HUB_MAX_CHARS`): `ask` rows, then `auto` rows, are left out past that, and a line says how many.

Saving goes the other way.
`/notion-save` turns what a session learned into hub pages, checking each row's edit flag first.
Claude never writes to a hub unasked.

## Why it works this way

Each column in the hub answers a question Claude would otherwise have to guess.

| Column | Tells Claude | Why |
| --- | --- | --- |
| Summary | What the page says | Write the facts, not the topic, and the index alone often answers the question |
| Keywords | Which tasks the page is for | Claude picks the right page without opening the whole hub |
| Load | When to open the page | Every `always` page costs every session, so keep that list short |
| Visibility | Which folders see the page | Personal pages stay out of shared projects |
| Edit | Whether it may change the page | Your decisions stay in your words; Claude suggests changes in chat instead |

Why an edit column and not Notion's page lock?
A lock only blocks edits in the Notion app, not through the API the connector uses ([Notion API docs](https://developers.notion.com/reference/patch-page)).
It also locks you out of your own page.
The column is an instruction Claude follows, not a hard block, but Claude sees it in the index before it opens anything.

A few other choices:

- Notion, not `CLAUDE.md`, because you already read and edit it there, from any device.
- The index is a local file because the session-start hook runs before Claude and can't reach Notion. The header shows its age so you know when to refresh.
- Refresh goes through each hub's connector, an MCP server you already sign in to, so there's no API token for the plugin to store or lose.
- Claude never saves unasked. It suggests a save and you decide.

## Install

```
/plugin marketplace add sfrankle/grimoire
/plugin install notion-hub@grimoire
```

You need:

- One Notion MCP server per hub, named in its `hub.connector`.
  The claude.ai Notion connector covers one workspace; each extra workspace needs its own Notion MCP server with its own credentials.
  The plugin stores no API token: refresh goes through the connector.
- `jq`, for example `brew install jq`.

## Set up

Run `/notion-setup`.
It asks whether to add a hub or edit one.
Adding asks for the hub id, its connector, its database, the folders it shows in and a one-line pointer, then reads the database's columns and proposes how they map to the three flags.
It then asks which values are private and which folders may see them, and asks a few questions to seed your rules.
It shows the files, writes them only after you confirm, and builds the first index.

## Several hubs

Each hub is a subfolder of the root, named by its id (lowercase letters, digits and dashes), with its own `config.json`, `rules.md`, `index.md` and optional `rules.private.md`.
A folder with another name is ignored, and the session start says so.

```
~/.claude/notion-hub/
  rules.md          routing: which facts go to which hub
  homelab/          config.json, rules.md, index.md
  garden/           config.json, rules.md, index.md
```

- **`hub.connector`** names the connector that reads and writes that hub, so each hub can sit in a different workspace.
  When it is unset the Notion connector is used.
- **`hub.show_in`** lists the folders where the hub loads in full: its rules, index header and rows.
  Leave it out to load the hub everywhere.
- **`hub.pointer`** is the one line printed for a hub that is not loaded in this folder, with the command to list it.
- **Always rows outside `show_in`**: a hub that is not loaded still prints its in-scope `always` rows, so facts you marked as needed everywhere are not lost.
  Private rows follow the usual scope rules.
- **Routing rules** are the top-level `rules.md`.
  It tells Claude which hub a fact belongs in, and to ask you when it is unclear.
  See `examples/rules.md`.
- **Output cap**: all hubs share the one 9500 character budget, and `always` rows are never cut.

`scoped-index.sh` with no id lists every hub under a `## <name> (<id>)` heading, and `scoped-index.sh <id>` lists one.
`/notion-refresh` takes an optional hub id and refreshes every hub without one.

One hub is just one subfolder; with only one, the scripts need no id.

### Upgrading from 0.1.0

0.1.0 kept a single hub's files at the top of the root.
Move `config.json`, `rules.md`, `rules.private.md` and `index.md` into a subfolder named after the hub, such as `homelab/`.
Until then the session start prints one line saying so.

## Your files

All live in `~/.claude/notion-hub/`, or in `$NOTION_HUB_DIR` when that is set.
None of them are in this repo.

At the top level:

- `rules.md`: routing rules for several hubs, such as which facts go to which hub.
  See `examples/rules.md`.

In each hub's folder, such as `homelab/`:

- `config.json`: where the hub is, which connector it uses, which folders show it, which columns and values map to the flags, which values are private, and defaults for new pages.
  See `examples/hubs/homelab/config.json`.
- `rules.md`: that hub's rules in plain language, such as what goes in it, what goes elsewhere, and when to suggest a save.
  See `examples/hubs/homelab/rules.md`.
- `rules.private.md`: optional rules that would reveal private material, shown only in private folders.
- `index.md`: the cached index, written by `/notion-refresh`.
  A new index applies from the next session, because the hook runs at session start.
- `rows.json`: transient, written and deleted by `/notion-refresh`.

## Changing things later

Edit a hub's `config.json` or `rules.md` directly, or run `/notion-setup edit <hub>`.
Setup keeps existing values and shows a diff before writing.
Then run `/notion-refresh <hub>` to rebuild its index.

## Other agents

The session-start hook is Claude Code only.
The skills are plain `SKILL.md` files, so other agents can run setup, refresh and save by hand.
They need a Notion connector of their own.

## Tests

```
bash plugins/notion-hub/tests/run.sh
```
