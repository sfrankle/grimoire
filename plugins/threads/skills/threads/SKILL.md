---
name: threads
description: Use when starting or resuming work that spans sessions, or when about to write a spec or plan.
---

# Threads

Multi-session work lives in the threads folder, `$THREADS_DIR`, or `~/.claude/threads` when that is unset.
A **project** is the user's: a repo, a class, a client.
A **unit** is yours: one ticket-sized piece of work inside a project, which you create, name, update and close unprompted.
The scripts are in this plugin's `../../scripts/`, relative to this skill's folder (`${CLAUDE_PLUGIN_ROOT}/scripts/` in Claude Code).
In Claude Code a SessionStart hook prints `rules.md`, the active projects, the likely project's `state.md` and its active units, most recent first.
In other harnesses, read those files yourself and match the session folder against each project's `paths`.

## Layout

```
<root>/config.json, rules.md
<root>/<project>/state.md        what the project is, what's live, traps
<root>/<project>/units/<unit>/
  state.md        where it stands, then a "Where to continue" checklist
  notes.md        current truth; may split into more files
  decisions.md    one entry per decision, newest first
  log.md          one line per session
  specs/, plans/  docs other skills write, when config sends them here
```

## Pick up the thread

1. Match the first message to a project, folder first: the hook's `Likely project:` line.
   - A message too vague to name a unit ("what's next") resumes the first unit listed.
   - When the work belongs to another project, list that project's `units/` folder to find the unit.
   - New work gets a new unit: `bash new.sh unit <project> <slug> "<one-line summary>"`.
   - When no project fits, ask once whether one should, or carry on with no thread.
2. Say `Logged under <project> / <unit>` in one line and carry on; a wrong guess is cheap for the user to correct.
3. Read only the unit's `state.md`; open notes, decisions or older log lines when the task needs them.

## Write when settled

Write once a thing is known to be right, and keep it to what the next session needs: a few lines, not a narrative.

- `notes.md` holds current truth: rewrite the line that changed, so the file reads as if it always said this.
- `state.md` changes when what's next changes.
- `decisions.md` gains an entry, at the top, when a decision is made; earlier entries stay as written.
- `log.md` gets one line per session: `bash log-line.sh <project> <unit> <session-id> "<what moved>"`.
  Use the hook's `Session:` id (Claude Code only), or `-` without one.
  Rerunning with the same id replaces your line, so refresh it if the session moves on; with `-`, run it once.
- A finished unit gets `status: closed` in its `state.md`; say so in one line.

## Specs and plans

Specs and plans go where `docs` in `config.json` says, and that setting overrides a skill's built-in path such as `docs/superpowers/`.
Highest first: the repo's own `AGENTS.md` or `CLAUDE.md` when it names a docs location, then `docs.projects.<project>`, then `docs.default`.
`unit` means the unit's `specs/` or `plans/`, `project` the same folders in the project's folder, and `repo:<path>` that path inside the project's repo.

## Projects and Notion

Projects belong to the user: when work looks project-sized, ask once and point to `/threads-project`, which creates, renames and closes them.
When the hook printed the `/notion-save` line and `notion-save` is in your skill list, suggest `/notion-save` for settled facts that outlive the unit.
