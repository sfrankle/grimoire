# Move personal skills into grimoire

2026-11-24.
Came up during repo setup.

Consider making grimoire the home for skills that live loose in `~/.claude/skills/` today.

Rough triage:

- Generic and ready to move: `c4-model`.
- Need personal references cleaned out first: `pressure-test`, `go-to-market`, `learning-plan`, `ui-designer`. The first three could form a strategy plugin.
- Replaced by notion-hub's `/notion-save` once it works: `notion-memory`.
- Project-specific, belongs in that project's own `.claude/skills/`: `haven-pr-readiness`.
- Third-party, already installed as plugins, stay out: `caveman`, `find-skills`.
- Synced from claude.ai, stay out.

Open:

- Does a moved skill keep a working copy in `~/.claude/skills/`, or is grimoire the only home, with every machine installing it?
- A skill can carry an `agents/openai.yaml` beside `SKILL.md` to run in Codex too; worth adopting for cross-agent support.
