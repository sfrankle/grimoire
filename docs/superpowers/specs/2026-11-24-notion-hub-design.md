# notion-hub: a shareable Notion memory setup for Claude Code

## Intent

The author uses one Notion database (a "Document Hub") as Claude's long-term memory.
Every session starts with an index of that database in context, Claude fetches only the pages a task needs, and Claude writes new durable facts back as pages.
Today that setup is hand-wired across a settings hook, a script in `~/.claude/bin`, a personal skill, and paragraphs of rules in `CLAUDE.md` files, all hardcoded to one person's database, field names and folders.

The goal is to package it as a Claude Code plugin in this repo so anyone can run "this Notion setup" on their own Notion account and their own structure.
Everything personal lives in a local config on the user's machine; the plugin ships only generic code, thin skills and an example config.
It also serves as the answer to "how do you use Notion with Claude?": the README explains the workflow.

## Goals

- Install with `/plugin marketplace add sfrankle/grimoire` then `/plugin install notion-hub@grimoire`, then one `/notion-setup` run.
- Work with any Notion database used as an index, with the user's own property names and values.
- Let the user describe "what goes where" in plain language, including places outside Notion, without the plugin needing a routing engine.
- Scope what each folder sees, so private pages can be hidden outside a chosen folder.
- Make a stale index visible instead of silently serving old data.
- Keep the skills short: they read the user's config and do what it says.

## Non-goals

- Session-start loading for agents other than Claude Code. The hook is Claude Code only; the skills are written harness-neutral so other agents can run setup, refresh and save by hand.
- A Notion API token or integration. The index refreshes through the claude.ai Notion connector only.
- More than one index database per user (v1).
- Live index freshness at session start.
- Migrating the author's existing install. That happens locally, outside this repo, after v1 works.

## Anti-goals

- Anything personal in the repo: no real database IDs, names, folder paths or example content drawn from a real person's hub.
- A session start that blocks, errors loudly, or slows noticeably when config is missing or broken.
- Skills that grow into long rulebooks. Rules belong in the user's config.
- Silent staleness: an index that looks current but isn't.

## Constraints

- The SessionStart hook runs before Claude and cannot call MCP tools, so it can only print local files.
- The claude.ai Notion connector is per user and cannot be bundled. Setup must check it is connected and say so plainly if not.
- The repo is on GitHub and may be public.

## Approaches considered

Packaging:

- **Claude Code plugin (chosen).** One install brings the hook, script and skills; `/plugin update` keeps users current. Claude Code only, but the hook needs Claude Code anyway.
- Plain skills folder plus a setup skill that edits the user's `settings.json`. Rejected: more invasive, hand-edited hooks drift, updates are manual.

Index refresh:

- **Through the Notion connector (chosen).** The hook prints a cached index; a refresh skill rebuilds the cache through MCP, and every save ends with a refresh. No token or database sharing, which is the step that most often breaks. Cost: pages added by hand in Notion appear only after the next refresh, so the index header shows its age.
- API token queried by the hook (the author's current setup). Rejected: extra setup per user and a silent fallback when sharing is missing.
- Both, connector by default with an optional token. Rejected for v1: two code paths to maintain.

Config format was chosen after looking at two published workflows.
mattpocock/skills keeps per-user config as plain-language Markdown that identical skills read and follow, written by a user-invoked setup skill.
cursor/plugins (pstack, Benny) ships an example config with placeholders and keeps the real one outside the shipped files, never overwritten.
This design does both: prose for rules, a small structured file only for what the hook script must parse.

## Design

### Repo layout

```
.claude-plugin/marketplace.json        # lists notion-hub; room for more plugins later
plugins/notion-hub/
  .claude-plugin/plugin.json
  hooks/hooks.json                     # SessionStart -> scripts/session-start.sh
  scripts/session-start.sh
  skills/notion-setup/SKILL.md         # user-invoked only
  skills/notion-refresh/SKILL.md
  skills/notion-save/SKILL.md
  examples/config.json                 # placeholders only
  examples/rules.md                    # placeholders only
  README.md                            # how the workflow works, install, setup
```

### User files (never in the repo)

All in `~/.claude/notion-hub/`:

- `config.json`: what the hook and refresh skill need to parse.
- `rules.md`: the user's own rules in plain language.
- `index.md`: the cached index, written by the refresh skill.

`config.json` holds:

- `data_source`: the hub's `collection://` ID and its database URL.
- `fields`: mapping from roles to the user's property names. Required: `title`, `summary`. Optional: `keywords`, `category`, `access`, `load`, `visibility`, `maintainer`.
- `values`: mapping of the user's option names to meanings, for example which `access` value means read-only, and which `load` values mean always, when relevant, and only when asked.
- `scopes`: which pages are private and where they show. Private means every value of the `visibility` field is in `private_values`. Private rows are shown only when the session folder is under one of `private_paths`, except rows whose `load` means always.
- `new_pages`: default property values and an optional template page for pages Claude creates.

`rules.md` holds everything else, in the user's words: what kinds of facts go to the hub and what goes elsewhere (local folders, other tools), when to suggest turning a note into a page, and anything personal about how they work.
Setup seeds it from an interview; the user edits it freely afterwards.

`rules.private.md` (optional) holds rules that would reveal private material, such as where personal documents live.
It follows the same scope as private index rows: it is printed only when the session folder is under one of `private_paths`.

Edit permission is decided by `config.json`: a page whose `access` value maps to read-only is never edited, and `/notion-save` checks this against the index row before writing.
`rules.md` may add further restrictions but cannot loosen that check.

### Session start

`session-start.sh` prints, in order:

1. `rules.md`, and `rules.private.md` when in scope, so the rules no longer live in `CLAUDE.md`.
2. The index from `index.md`, filtered by `scopes` for the current folder (`CLAUDE_PROJECT_DIR`, falling back to `PWD`).
3. A header line with the index build date and its age in days, and a nudge to run `/notion-refresh` when it is older than 7 days.
4. A list of in-scope pages whose `load` value means always, with an instruction for Claude to fetch them through the connector before its first answer.
   Page bodies are never cached on disk.

Index rows stay one line each.
If the total output would exceed what Claude Code injects from a SessionStart hook, the hook prints a visible warning saying how many rows were cut, never a silent truncation.
The builder confirms the current limit against the Claude Code hooks documentation.

With no config it prints one line telling the user to run `/notion-setup`.
It always exits 0 and never makes network calls.

### Skills

- **`/notion-setup`** (`disable-model-invocation: true`): checks the Notion connector is available; asks for the hub database or searches for it; fetches its schema and proposes the field and value mapping; asks which pages are private and where they may show; interviews briefly for `rules.md`; shows both files and writes them only after the user confirms; runs a first refresh. Re-running it edits existing files rather than overwriting.
- **`/notion-refresh`**: queries the hub through the connector, writes `index.md` with one row per page (title, mapped fields, URL) and the build date. Model-invocable so other skills and Claude can call it.
- **`/notion-save`** (`disable-model-invocation: true`): Claude never writes to the hub unasked; `rules.md` tells it when to suggest a save, and the user runs the skill. It turns what Claude learned, or a note the user points at, into hub pages by following `rules.md` and `config.json`: match against the index, update an existing page or create a new one with `new_pages` defaults, never edit read-only pages (propose changes in chat instead), then refresh and report one line per page.

### README

Explains the workflow for someone new: the hub as an index, load rules, private scopes, saving facts back.
Then install, setup, what each file is for, and how to change your structure later.

## Left to the builder

- Hook script language and how it parses JSON. Prefer no dependency beyond what macOS and common Linux ship; if `jq` is used, a missing `jq` must degrade to a one-line message, not an error.
- Exact `index.md` row format, as long as the hook can filter it by visibility and load values.
- Example config contents, using an invented hub.
- Plugin and marketplace manifest details, version numbering, and the `SessionStart` matcher.
- How setup detects an existing config and merges changes.
