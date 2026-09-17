---
description: Hand a .pidly ticket back with a note about where you got to.
argument-hint: <ticket number>
---

Release the ticket the user named, with a handoff that says where the work
actually got to:

```sh
pidly release -m "Where I got to, in one line." <n>
```

The note is one line and it is overwritten by the next one, so write the
state of the work rather than a log of the session. Anything longer belongs
in the body: `pidly edit -a <n>`.

Before releasing, put anything worth keeping into the body — findings, what
was tried, what failed. A dropped claim with no note makes the next agent
reconstruct your progress from the diff.

If the work is finished, `pidly close <n>` instead.
