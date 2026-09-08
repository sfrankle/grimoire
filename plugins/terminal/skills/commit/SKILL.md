---
name: commit
description: Use when creating a git commit that Claude authors or co-authors. Produces a one-line conventional-commit subject plus the standard Claude attribution trailer. Replaces caveman-commit for message generation. Triggers on "commit this", "make a commit", "commit these changes".
---

# Commit

## Overview

Write the commit message and commit. One line of subject, then the Claude attribution trailer. Nothing else by default.


## Format

```
<type>: <subject>

Co-Authored-By: Claude <model> <noreply@anthropic.com>
```

Rules:

- Subject: Conventional Commits, imperative, lowercase after the type, no trailing period. Aim for 50 chars including the `<type>: ` prefix, hard limit 72.
- One subject line. No body unless the "why" is non-obvious from the diff and the subject; a body is the exception, not the default.
- Always end with the `Co-Authored-By: Claude ...` trailer. Take `<model>` from the trailer instruction the harness gives this session; never from this file or memory.
