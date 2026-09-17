---
name: pidly
description: Use when picking up, working on, or finishing work tracked in .pidly/ — claiming a ticket before starting, handing one back, closing one, or asking what there is to do. Covers the workflow; the format itself is in .pidly/README.md.
---

# pidly

Work lives in `.pidly/` as plain files. This skill is the loop an agent
follows; **the rules of the format are in `.pidly/README.md`**, which is
generated and kept in step by `pidly check`. Read it when you need a rule you
do not already know, rather than guessing from the file layout.

## The loop

```sh
pidly list                    # ready work: unclaimed, unblocked, not deferred
pidly claim 7                 # take it BEFORE you start
# ...do the work...
pidly close 7                 # finished
```

If you stop before finishing, say where you got to. The next agent reads it:

```sh
pidly release -m "Parser works; the lexer still loses nested quotes." 7
```

## Rules that matter more than they look

- **Claim before starting.** A claim is how two agents avoid the same ticket.
  It records your process, so a claim left by an agent that died is
  detectable — `pidly check` reports it and `pidly reap` clears it.
- **Never delete a ticket.** Numbers are never reused, and deleting one lets
  its number be issued again to something else. Close it.
- **A ticket cannot close while it has open children.**
- **A claim you cannot verify is not a dead one.** Leave it alone.
- **Write findings into the ticket body** — `pidly edit -a 7` — before the
  context is gone. Anything else you learned disappears when the session does.

## If you are a subagent

A subagent shares its parent's process, so a pid cannot tell you apart. Claim
as an agent, with a lease, and release when you finish:

```sh
PIDLY_AGENT=sub-review-parser PIDLY_LEASE=1h pidly claim 19
```

## Making a ticket

```sh
pidly new -f effort=M "Short title"   # body on stdin; -p N for a subtask
```

Not for work you are finishing in the same breath — a ticket opened and
closed at once is a log entry wearing a ticket costume, and it spends a
number that can never be reused.

## Without pidly installed

Everything above is files, and `.pidly/README.md` gives the `find`, `sed` and
`mv` equivalent of every command here — for a checkout where the script was
never installed, which the format is built to survive.
