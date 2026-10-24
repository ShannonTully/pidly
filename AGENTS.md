<!-- pidly:begin -->
## Issue tracking with pidly

Work lives in `.pidly/` as plain files. The full rules are in
`.pidly/README.md`; read it before doing anything beyond what is here.

A ticket is a directory named by its number, which is never reused, and
`info` inside it is what's known about it. **State is location**: open
tickets sit directly in their container, closed ones in its `c/`. So
`.pidly/7/12/info` is open ticket 12 under 7, and `.pidly/7/c/13/info` is
closed ticket 13.

`info` is `claim:` (empty, or who holds it), `needs:` (numbers that must be
closed first) and `title:`, then `created:`, `updated:` and whatever fields
`.pidly/schema` declares, then a blank line and the body. A ticket is
takeable when `claim:` is empty, it has no `defer:` value, and every number
in `needs:` is under a `c/`.

```sh
find .pidly -type d -name c -prune -o -name info -print   # open tickets
pidly list                             # the takeable ones

pidly claim 7                          # names your agent's process
PIDLY_AGENT=ci-run-4821 PIDLY_LEASE=2h pidly claim 7   # no local process
pidly release -m "Where I got to" 7    # stopping before it is done
pidly close 7      # by hand: mkdir -p .pidly/c && mv .pidly/7 .pidly/c/
```

- Claim before starting; release or close when done. Renew a lease by
  claiming again before it runs out. A subagent gets a child ticket and
  claims it with `PIDLY_AGENT`, a name you pick.
- **Never delete a ticket** — close it. A ticket with open children cannot.
- An expired lease is free to take, and a dead local claim is cleared with
  `pidly reap`. Any other claim you cannot verify, leave alone.
<!-- pidly:end -->
