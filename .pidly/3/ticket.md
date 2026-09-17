claim:
needs: 8
title: Stale claim detection
desc:14
A claim is a pid, so liveness is checkable: kill -0 <pid> tells you whether
the agent that claimed the ticket is still running. An agent that died
mid-task leaves its pid behind, and nothing else distinguishes that from
active work.

check should report claims whose pid is dead. Open question is whether it
also clears them, and whether the pid needs a hostname alongside it to stay
meaningful in a repository shared between machines — a bare pid from
another host is worse than useless, since it may match a live local
process.
effort: M
area: format
