# threads

Give multi-session work a home your agent finds on its own.
Every session starts with your projects in context, Claude matches the work to a project and a unit, and it leaves short notes as it goes.

Examples use two invented projects: `homelab` (a repo at `~/code/homelab`) and `calculus` (a class).

## How it works

Notes live in one central folder, outside any repo, in two tiers:

- A **project** is yours: a repo, a class, a client.
  Claude never creates, renames or closes one without asking.
- A **unit** is Claude's: one ticket-sized piece of work inside a project, such as `dns-cutover` in `homelab`.
  Claude creates, names, updates and closes units unprompted, and says so in one line: `Logged under homelab / dns-cutover`.

At session start the hook prints your rules, then one line per active project.
If the session folder sits under a project's `paths`, that project is the likely match, and the hook prints its `state.md` and active units, most recent first.
Claude reads the unit's `state.md`, ending in a "Where to continue" checklist, and opens other files only when needed.
A vague message such as "what's next" resumes the first unit listed.

While it works, Claude writes once a thing is settled:

- `notes.md` holds current truth, rewritten in place.
- `decisions.md` gains an entry at the top when a decision is made.
- `log.md` gets one line per session, with the session id so you can find the transcript.

The plugin never deletes your files, and renaming a project moves its folder only after you confirm.

## Install

```
/plugin marketplace add sfrankle/grimoire
/plugin install threads@grimoire
```

You need `jq`, for example `brew install jq`; without it the hook prints one line saying so.

## Set up

Run `/threads-setup`.
It checks for `jq`, asks where specs and plans should go and whether to suggest `/notion-save`, helps you write a few rules, and shows the files before writing them.
It then offers to create your first project.
Later, `/threads-project` creates, renames and closes projects.

## Your files

All live in `~/.claude/threads/`, or in `$THREADS_DIR` when that is set.
None of them are in this repo.

```
config.json, rules.md
homelab/state.md                what the project is, what's live, traps
homelab/units/dns-cutover/      state.md, notes.md, decisions.md, log.md
calculus/state.md
```

- `config.json`: where specs and plans go, and the Notion setting (see `examples/config.json`).
- `rules.md`: short rules printed at every session start, so keep it brief.
  The hook prints the first 1,000 characters and points to the file for the rest.
  See `examples/rules.md`.
- `<project>/state.md`: frontmatter with `name`, `summary`, `paths` and `status` (`active` or `closed`), then one paragraph.
  Units have the same frontmatter minus `paths`.
  Only active ones appear in the hook; set `status: closed` to retire one.

## Where specs and plans go

`docs.default` in `config.json` is `unit` (the unit's `specs/` and `plans/`), `project` (the same folders in the project's folder) or `repo:<path>` (inside the project's repo).
`docs.projects` overrides it per project, so `homelab` can commit its specs to its repo while `calculus` keeps them in the workspace.
A repo's own `AGENTS.md` or `CLAUDE.md` wins when it names a docs location; otherwise this setting overrides a skill's built-in path.

## Notion

With `notion_hub` set to `auto`, Claude suggests `/notion-save` for settled facts that outlive a unit, when notion-hub is installed.
Set it to `off` to never suggest it; threads works without notion-hub.

## Limits

The hook output stays under 9500 characters (`THREADS_MAX_CHARS`), cutting unit lines first, then other project lines.
Two parallel sessions sent the same vague message resume the same unit; the one-line announcement is your cue to redirect one.

## Other agents

The session-start hook and the session id are Claude Code only.
The skills are plain `SKILL.md` files, so other agents read the workspace themselves and match the session folder against each project's `paths`.
They run scripts as `../../scripts/…` from the skill folder, and log lines use `-` for the session id.

## Tests

Run `bash plugins/threads/tests/run.sh`.
