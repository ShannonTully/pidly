<!-- pidly:begin -->
## Issue tracking with pidly

Work lives in `.pidly/` as plain files. **Full rules: `.pidly/README.md`** —
read it before doing anything beyond the commands below.

A ticket is a directory; `info` inside it is what's known about it. The
directory name is its number, which never changes and is never reused.
**State is location**: open tickets sit directly in their container, closed
ones in that container's `c/`. Closing is a move.

```
.pidly/7/info        ticket 7, open
.pidly/7/12/info     ticket 12, an open subtask of 7
.pidly/7/c/13/info   ticket 13, finished
```

`info` is four header lines, then the body, then project fields:

```
claim:                1  empty, or who holds it
needs: 3 8            2  must be closed before this starts
title: Short title    3
effort: M             4  project fields, then a blank line,
                         then the body to the end of the file
```

```sh
# open tickets, never descending into finished work
find .pidly -type d -name c -prune -o -name info -print

# takeable = line 1 empty, and every number on line 2 resolves to a
# directory whose path contains /c/
sed -n 1,2p .pidly/7/info

PIDLY_PID=$$ pidly claim 7    # $$ is your process, not the CLI's
pidly status 7                # who holds it, and if that is checkable
pidly release 7
pidly release -m "Where I got to" 7   # if you stop before finishing

# no local process (cloud, CI)? claim with a lease and renew before it ends
PIDLY_AGENT=$SESSION_ID PIDLY_LEASE=2h pidly claim 7

# finish: move into the container's c/
pidly close 7                 # by hand: mkdir -p .pidly/c && mv .pidly/7 .pidly/c/
```

Claim before starting; release or close when done. Delegating real work to a
subagent? Open a child ticket and pass it the number — see the reference, and
note a subagent claims with `PIDLY_AGENT`, not a pid.

- **Never delete a ticket** — numbers are never reused. Close it.
- A ticket cannot close while it has children outside its own `c/`.
- A claim you cannot verify is not a dead one. Leave it alone.
<!-- pidly:end -->
