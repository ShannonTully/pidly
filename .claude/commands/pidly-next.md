---
description: Show what is ready to start in .pidly, and claim one if asked.
argument-hint: [ticket number to claim]
---

Run `pidly list`. That is ready work: unclaimed, unblocked and not deferred.

If the user named a number, claim it with `pidly claim <n>` and say what the
ticket asks for, reading its body with `pidly edit`-free tools — `cat` the
`info` file or use `pidly tree` for context. Print the handoff if `claim`
shows one; somebody stopped part-way and it says where.

If the user named nothing, show the list and stop. Picking is theirs unless
they say otherwise.

`pidly list -a` is the fuller picture — blocked, claimed and deferred work
with the reason for each — and worth showing if the ready list is empty.
