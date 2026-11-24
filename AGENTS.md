# grimoire

A public collection of agent skills, packaged as a Claude Code plugin marketplace.
The Claude plugin files are the install route today; the skills themselves follow the open `SKILL.md` format so other agents (Codex, Cursor, Gemini CLI) can load them too.

## Layout

- `.claude-plugin/marketplace.json` lists every plugin. A new plugin is not installable until it has an entry here.
- `plugins/<plugin>/.claude-plugin/plugin.json` is each plugin's manifest.
- `plugins/<plugin>/skills/<skill>/SKILL.md` is a skill. Supporting files sit beside it and are linked by relative path.
- `docs/superpowers/specs/` holds design specs; `docs/superpowers/plans/` holds implementation plans.

## Writing skills

- Write each skill harness-neutral: name the action ("load the skill", "ask the user"), not a harness's tool name.
- Keep harness-specific parts (hooks, plugin manifests, `disable-model-invocation`) in the files that need them, and say in the skill when a step only works in one harness.
- Keep skills short. Rules a user would customise belong in that user's config, not in the skill.

## Public repo

Everything here is public.
Use invented names, IDs, paths and example content; real people's databases, folders, clients and personal details stay out.
A skill copied from another repo gets its source and license notice added to `THIRD_PARTY_NOTICES.md` in the same commit.

## Before committing

- Run `claude plugin validate .` after changing any manifest or skill frontmatter.
- Bump the plugin's `version` in `plugin.json` when its skills change, so `/plugin update` picks them up.
- Commit messages are Conventional Commits.

## Markdown

Break lines at sentence ends, one sentence per line, never mid-sentence.
