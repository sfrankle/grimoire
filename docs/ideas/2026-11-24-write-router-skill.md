# One `write` skill that routes by kind of text

2026-11-24.
Came up while comparing `unslop` with a separate personal `humaniser` skill.

`unslop` and `humaniser` share most of their tells but pull in opposite directions on voice.
`humaniser` adds opinions, feelings and tangents; `unslop` wants the mechanism, one idea per sentence, and no feelings.
Both claim docs, so both can fire on the same text.
Skill names alone don't tell the agent which one fits.

Idea: one `write` skill whose first step asks "what kind of text is this?", then loads only the rules for that kind.

```
plugins/articulate/skills/write/
  SKILL.md       classify, load core.md + the kind's file, check every rule
  core.md        shared tells
  technical.md   docs, READMEs, PRs, code comments
  voice.md       posts, essays, captions, bios; load the user's voice guide if their instructions name one
  message.md     email or chat to a person
```

Open:

- `humaniser` is adapted from blader/humanizer; check its license before folding it in.
- `bruv` and a personal `wait-what` skill do the same job (re-pitch the last message); merge into one.
