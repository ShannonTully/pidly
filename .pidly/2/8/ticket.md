claim:
needs: 1
title: pidly claim / release, and the lock
desc:19
claim writes the caller's pid into line 1; release blanks it back to
"claim:". Both rewrite ticket.md, as does edit, so all three must serialize
against each other.

The lock is a directory: mkdir ticket-dir/.lock, which fails atomically if
it already exists. Write the holder's pid to .lock/pid so a lock left
behind by a crashed agent is detectable with kill -0 and can be broken by
the next caller. The lock is held only for the rewrite, so a repository at
rest never contains one.

Without this, two agents both read "claim:", both write their pid, and the
loser never learns it lost. A pid proves the holder is alive; it cannot
prove the holder is the only one.

claim should also refuse a ticket whose needs are not all closed.
effort: M
area: cli
