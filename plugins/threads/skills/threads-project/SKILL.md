---
name: threads-project
description: Create, rename or close a threads project.
disable-model-invocation: true
argument-hint: "create, rename or close, and the project name"
---

# Threads project

Create, rename or close a project in the threads folder, `$THREADS_DIR`, or `~/.claude/threads` when that is unset.
Commands use `${CLAUDE_PLUGIN_ROOT}`, which Claude Code sets to this plugin's folder; in other harnesses it is `../..` from this skill's folder.
Names are slugs matching `^[a-z0-9][a-z0-9-]*$`.
Ask one question at a time, as plain prose, and show each change and write it only after the user confirms.

## Create

1. Ask for the name, a one-line summary, and the repo folders that map to it, offering the current folder.
   A project with no folder, such as a class, is fine.
2. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/new.sh" project <name> "<summary>" "<path>"...`, quoting each path so `~` stays as typed.
   Exit 2 means an invalid name or summary, and 4 that the project exists: ask for another name.
3. Offer to add the body of its `state.md`: one paragraph on what the project is, what's live, and its traps.

## Rename

1. Check the new name is a slug and that no folder of that name exists.
2. Move `<root>/<old>` to `<root>/<new>` and set `name:` in its `state.md` frontmatter to the new name.
3. If `docs.projects` in `config.json` names the old project, update that key too.

## Close

Set `status: closed` in the project's `state.md` frontmatter.
Nothing is deleted; the hook stops listing it, and setting `status: active` reopens it.
