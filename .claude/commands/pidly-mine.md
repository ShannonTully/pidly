---
description: Show which .pidly tickets this session is holding.
---

Find the tickets this session has claimed and report them.

```sh
pidly list -a            # the claimed ones are marked
pidly status <n>         # who holds it, and whether that can be verified
```

A claim records the holding process, so a ticket held by this session shows
the same pid `pidly claim` would write here. Report, for each:

- the number and title,
- whether it is still claimed by this session,
- and whether anything has been written to it — `pidly list --stale 1h` shows
  what has been sitting.

If a ticket has been held without progress, say so and offer to release it
with a handoff (`pidly release -m "..." <n>`) rather than leaving a claim
nobody will clear.
