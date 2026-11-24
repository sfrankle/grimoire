---
name: commit
description: Use when creating a git commit that an agent authors or co-authors. Produces a one-line conventional-commit subject plus the harness's co-author trailer. Triggers on "commit this", "make a commit", "commit these changes".
---

# Commit

## Overview

Write the commit message and commit. One line of subject, then the co-author trailer. Nothing else by default.


## Format

```
<type>: <subject>

Co-Authored-By: <agent and model> <address>
```

Rules:

- Subject: Conventional Commits, imperative, lowercase after the type, no trailing period. Aim for 50 chars including the `<type>: ` prefix, hard limit 72.
- One subject line. No body unless the "why" is non-obvious from the diff and the subject; a body is the exception, not the default.
- End with the `Co-Authored-By:` trailer exactly as the harness or the user's instructions give it for this session, never from this file or memory. With no trailer given, omit it.
- Pass the subject and the trailer as two `-m` flags, so the subject stays on one line:

```bash
git commit -m "<type>: <subject>" -m "Co-Authored-By: <agent and model> <address>"
```
