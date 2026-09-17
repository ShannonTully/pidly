claim:
needs: 7 8
title: pidly list / tree / check
desc:14
Read-only views. list defaults to takeable work — unclaimed and unblocked —
which it can determine from the first two lines of each ticket plus the
location of each needs entry, without reading a single body. tree renders
the hierarchy with open and closed children distinguished.

check validates every ticket against schema.md, confirms desc: points at
the real last line of the body, resolves every needs entry to a real
ticket, detects cycles in the needs graph, reports claims and locks whose
pid is no longer running, and confirms no number appears twice. It never
modifies anything and exits nonzero on problems, so it can run in CI.
effort: L
area: cli
