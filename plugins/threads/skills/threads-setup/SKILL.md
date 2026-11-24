---
name: threads-setup
description: Set up or edit the threads config and rules, then create the first project.
disable-model-invocation: true
---

# Threads setup

Create or edit `config.json` and `rules.md` in the threads folder, `$THREADS_DIR`, or `~/.claude/threads` when that is unset.
Create the folder if missing.
The shapes to fill are `${CLAUDE_PLUGIN_ROOT}/examples/config.json` and `rules.md` beside it.
`${CLAUDE_PLUGIN_ROOT}` is set by Claude Code to this plugin's folder; in other harnesses it is `../..` from this skill's folder.
Ask the user one question at a time, as plain prose.

## Steps

1. Check `jq` is installed, since the hook needs it to read the config.
   If it is missing, say so in one line with the install command (`brew install jq` or `sudo apt install jq`), then carry on.
2. If `config.json` or `rules.md` exists, load it and treat this run as an edit.
   Keep every unchanged value and show a diff before writing.
3. Fill `config.json`, with `version` as 1:
   - `docs.default`: where specs and plans go, `unit` (the unit's folder), `project` (the project's folder) or `repo:<path>` (inside the project's repo).
   - `docs.projects`: per-project overrides, such as a project whose specs are committed to its repo.
   - `notion_hub`: `auto` suggests `/notion-save` for settled facts when that skill is installed, `off` never does.
4. Fill `rules.md`: short free-form rules the hook prints at the start of every session, such as how to name units.
   Offer the example's lines as a starting point, and keep it brief, since every session pays for it.
5. Show both files and write only after the user confirms.
   Check the written config with `jq . config.json`.
6. If the folder holds no project yet, offer to create the first one.
   On a yes, read `../threads-project/SKILL.md` and follow its Create steps.
