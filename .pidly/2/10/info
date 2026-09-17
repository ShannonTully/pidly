claim:
needs: 8
title: pidly edit
desc:12
Open a ticket's body in $EDITOR and rewrite desc: to match the new last
line on save. This is the command that keeps the derived line number
honest; without it, every hand-edit is a chance for the header to start
lying about where the body ends.

Takes the lock from 8, since it rewrites the same file claim does. Should
also be usable non-interactively so an agent can replace a body and get the
header fixed for free.
effort: S
area: cli
