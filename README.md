# grimoire

Skills and plugins I use with coding agents.

## Install (Claude Code)

```
/plugin marketplace add sfrankle/grimoire
/plugin install <plugin>@grimoire
```

## Plugins

- **articulate**: `/bruv` restates the last message in plain language; `/unslop` strips AI tells from a piece of writing.
- **notion-hub**: uses a Notion database as an agent's long-term memory index, with `/notion-setup`, `/notion-refresh` and `/notion-save`.
- **productivity**: `/handoff` writes a handoff document so a fresh session can continue the work.
- **terminal**: `commit` writes a one-line Conventional Commit with the harness's co-author trailer.

## Other agents

Each skill is a plain `SKILL.md` folder under `plugins/<plugin>/skills/`.
Agents that read the `SKILL.md` format can use them by copying or linking a skill folder into that agent's skills directory.
Hooks and plugin manifests are Claude Code only.

## License

MIT, see [LICENSE](LICENSE).
Some skills are adapted from other projects; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
