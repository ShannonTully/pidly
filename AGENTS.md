<!-- pidly:begin -->
## Issue tracking with pidly

Work is tracked in `.pidly/` at the repo root. It is plain files: you can do
everything below with `find`, `sed` and `mv` if `pidly` is not installed.

**A ticket is a directory; `info` inside it is what's known about it.** The
directory name is the ticket's number, and it never changes or gets reused.

**State is location.** A ticket is open if it sits directly in its container,
closed if it sits in that container's `c/`. Closing is a move. Nothing else
records state.

```
.pidly/7/info        ticket 7, open
.pidly/7/12/info     ticket 12, an open subtask of 7
.pidly/7/c/13/info   ticket 13, a finished subtask of 7
.pidly/c/4/info      ticket 4, a finished top-level ticket
```

`info` has four fixed header lines, then the body, then project fields:

```
claim:                      line 1  empty, or who holds it
needs: 3 8                  line 2  tickets that must close before this starts
title: Short human title    line 3
desc:11                     line 4  the body's last line number
...body from line 5 to the number in desc:...
effort: M                   after the body: fields from .pidly/schema.md
```

Read only what you need — `sed -n 1,2p` answers "can I take this?" without
touching a body.

### Finding work

```sh
# every open ticket, never descending into finished work
find .pidly -type d -name c -prune -o -name info -print
```

A ticket is takeable when line 1 is empty and every number on line 2 resolves
to a directory whose path contains `/c/`.

### Taking work

```sh
PIDLY_PID=$$ pidly claim 7      # you have a local process
pidly status 7                  # who holds it, and whether that is checkable
pidly release 7                 # give it back
```

If you are a cloud or CI agent with no process anyone here can check, claim
with a lease instead, and renew by claiming again before it expires:

```sh
PIDLY_AGENT=$SESSION_ID PIDLY_LEASE=2h pidly claim 7
```

Claim before starting, release or close when done. A claim you never release
blocks the ticket until your process exits or your lease runs out.

### Subtasks

Create a child directory inside the parent ticket's directory, numbered one
higher than any number in the tree. Its `info` follows the same four-line
header. Subtasks are how work is delegated: each child can be claimed
independently.

### Finishing

Move the ticket into its container's `c/`, creating `c/` if needed. A ticket
cannot close while it still has children sitting outside its own `c/`.

### Rules

- Never delete a ticket. Numbers are never reused, and deleting one lets its
  number be handed out again. Close it instead.
- If you edit a body by hand, fix `desc:` to match the new last line.
- `needs` references numbers, never paths. Paths change; numbers do not.
<!-- pidly:end -->
