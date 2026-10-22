# pidly — design

A file-based issue tracker. No server, no database, no required install.
A `.pidly/` directory at the project root holds everything; a human reads it
with `ls` and `cat`, an agent reads it with `find` and `sed`, and anyone you
hand the repo to can navigate it with neither pidly nor a runtime installed.

The name: an agent that picks up a ticket writes its **pid** onto it.

## Principles

These are the tiebreakers. When a design question comes up, resolve it against
this list in order.

1. **Zero-install readability.** The tree must be fully navigable with a POSIX
   shell and an editor. Tooling may make things faster; it may never be the only
   way to understand the data.
2. **Structure carries meaning.** Anything the filesystem can express —
   identity, parentage, state — is expressed by the filesystem, not by a field
   that has to be kept in sync with it.
3. **Relations are paths where the tree can express them.** Parentage is a
   path, never a field. Dependencies are the documented exception — a DAG is
   not a tree — and they reference tickets by number, not by path.
4. **Bounded reads.** A reader should be able to take exactly the lines it
   needs and stop. Deciding what to work on should not mean reading a single
   body.
5. **Humans and agents read the same bytes.** No separate index, cache, or
   machine format that can drift from the source of truth.

## Layout

```
.pidly/
  schema          # the ticket schema for this project
  1/
    info          # ticket 1 itself
    3/            # an open child
      info
      8/
        info
    c/
      5/          # a closed child
        info
  c/
    2/            # a closed root, moved here whole
      info
      4/
        info
```

**Every ticket is a directory, and what's known about it is the file `info`
inside.** Leaves too. The alternative — a leaf is a file, a parent is a
directory — means promoting a leaf to a parent rewrites its path, and means
every tool needs two code paths. Uniformity is worth one extra inode.

The file is not called `ticket`, because it isn't one: the *directory* is the
ticket. It has the identity, the position in the tree, the children and the
state, none of which live in the file. What the file holds is the ticket's
information, so that is what it is called.

`info` has no extension because the content isn't any established format:
three header lines, project fields, then a markdown body. Calling it `.md` would promise a
rendering that turns the header into one mangled paragraph, which is worse than
no rendering at all.

The name also cannot be mistaken for a ticket number, which keeps two idioms
unambiguous and separate:

```sh
find .pidly -name info       # every ticket
find .pidly -name 8          # ticket 8, and only it
```

Naming the file after its own number — `8/8` — would break both: the second
lookup would return a directory and a file, and the first would have no single
name left to match. A one-letter name would work too, but the saving is
illusory: the filename is rarely typed, since you `cd` to the directory and
`find` should print `%h`, while an opaque name costs something every time
someone opens the tree without having read this document.

## State is location

**One rule, true at every depth: a ticket is open if it sits directly in its
container, and closed if it sits in that container's `c/`.** Closing is a move.
There is no marker file and no status field, so there is nothing that can
disagree with where the ticket actually is.

The rule includes the root, which is why there is no `o/` — an open root sits
directly in `.pidly/`, exactly as an open child sits directly in its parent, and
`.pidly/c/` holds closed roots exactly as `1/c/` holds ticket 1's closed
children.

Only closed tickets pay the extra path segment, which is what makes recursion
affordable here. Live work keeps flat paths (`.pidly/1/3/8/`) and finished
work sinks one level out of the way at whatever depth it finished. And because
`c` is a directory name rather than a marker inside each ticket, it prunes:

```sh
# every open ticket, at any depth, without descending into finished work
find .pidly -type d -name c -prune -o -name info -print
```

That single idiom is both the query and the performance story. A mature project
with hundreds of closed trees never descends into them.

A ticket cannot close while it has open children — children sitting directly in
it rather than in its `c/`. That is what keeps a closed tree from containing
live work.

Closing also empties `claim:`: finished work is held by nobody, and a claim
carried into `c/` would read as someone still on it. A close done by hand with
`mv` does not, so `check` reports a claim under a `c/` — as a note rather than
a problem, whoever the holder is, because the claim is stale but no work is at
risk.

**Reopening cascades upward.** Moving a ticket out of its container's `c/` is
only half the job: if that container is itself closed, a closed tree now holds
live work. So reopening a ticket reopens every closed ancestor between it and
the surface, one `mv` per level.

That isn't a mechanical wart, it's the right answer. If subtask 4 needs redoing
then its parent isn't finished either, and neither is the root above it. The
constraint the filesystem imposes and the constraint the work imposes are the
same one.

`reopen` therefore takes a ticket that is already open, if a closed ancestor
holds it. That state is reachable — a `mkdir`/`mv` close done by hand does not
check for open children — and the cascade is exactly its repair, so refusing
it as "already open" would leave the one command that can fix it unable to.
`check` reports the state; `reopen` clears it. A ticket with no `c/` anywhere
between it and the surface is the only one that is already open.

Reopening does *not* cascade downward: a reopened parent keeps its finished
children in its `c/`. And a reopened ticket does not reopen tickets that
`needs` it — dependencies constrain when work may *start*, not whether
completed work stays completed.

What's lost by dropping the marker file is the timestamp and one-line
resolution it used to carry. Git records when the move happened and in which
commit, which covers the common case; a project that wants a written resolution
can add it as a schema field.

## Where results go

A subagent's output is ephemeral — it lands in the lead agent's context, is
summarised, and is gone at the next compaction. That is a real problem, and
the answer is that findings go in the **body** of the ticket the subagent
worked on, written before the context is lost. A long body costs only the
agent that committed to the ticket, since scanning never opens one.

A standalone artifact goes in the repo, and the body references it by path.

An earlier draft made any file in a ticket directory an attachment —
`.pidly/7/review.md` — on the grounds that a ticket is a directory and the
affordance was free. It was withdrawn, for three reasons worth keeping:

- **No convention.** Everything else here is fixed: line 1 is the claim, the
  file is always `info`. An attachment is whatever the writing agent named
  it, so a reading agent has to `ls` and guess — the unbounded poking the
  format exists to prevent.
- **Nothing announces it.** A reader taking the header and the body gets no
  signal that another file exists. The obvious fix, a field listing them, is
  derived data that can drift, which the format now has none of.
- **Wrong location.** An artifact worth keeping is usually about the *code*,
  not the ticket. A parser review belongs next to the parser, where everyone
  finds it; filed in a ticket it is visible only to that ticket's readers,
  and closing the ticket drags it into `c/` while the parser stays put.

So attachments were neither in the repo where artifacts are findable nor in
the body where they are read. What survives is the rule `check` enforces
anyway: a directory inside a ticket that is neither a number nor `c` is
invalid, because the tree scan reads it as a phantom ticket.

## Names## Names

**A ticket's name is one number, unique across the whole project, never
zero-padded and never reused.** Parentage is not in the name; it's the path.

The path is readable as lineage because every segment except `c` is a ticket:
`.pidly/1/3/8/` is ticket 8 under 3 under 1. `find .pidly -name 8` locates it
in one command, and the answer shows you its ancestry for free.

**The next number is the highest already issued, plus one.** That is the
greater of what the tree contains and what the registry records — there is no
counter holding a value someone has to keep current.

### The number registry

Allocation also writes `.pidly/.n/<number>`, holding a nonce and the title.
It is never modified afterwards, and it is committed.

Its job is to make a collision that git would otherwise merge silently into
one that git refuses. Branches cannot see each other while they allocate, so
the lock cannot help: branch A creating `.pidly/5` and branch B creating
`.pidly/7/5` merge cleanly and leave two tickets numbered 5, at which point
`find .pidly -name 5` has two answers and every `needs: 5` is ambiguous. With
a registry both branches write `.pidly/.n/5` with different content, and the
merge stops:

```
CONFLICT (add/add): Merge conflict in .pidly/.n/5
```

Different numbers merge cleanly, so there are no false conflicts. Both
behaviours are covered by `tests/merge.sh`, which drives real merges, because
the whole feature is a claim about what git does.

**This detects rather than prevents.** Only a non-coordinating id — a hash, a
timestamp — could prevent it, and that costs the readable number the format is
built around. Being told at merge time, before anything is built on the bad
state, is the trade. Resolution still means renumbering one side.

Two things fall out of it. A number is never reissued even if a ticket
directory is deleted by hand, which previously would have recycled it. And a
dangling `needs: 5` has something to say about what 5 was.

The registry can legitimately lag, because the format allows creating a ticket
with `mkdir`. That is why the next number considers the tree as well, and why
`pidly init` backfills any number it finds without an entry.

Allocation is the one operation that needs the repository lock (see Claims).
`mkdir` arbitrates only between siblings, so two agents adding children to
*different* parents would otherwise both take the same number and both succeed.
Allocation is rare and the lock is held for microseconds.

Two consequences:

- **Numbers are never reused, so there is no delete.** Finishing a ticket means
  closing it, and a closed ticket stays in the tree inside a `c/`. The registry
  makes this hold even against a hand-deleted directory, since the entry
  outlives the ticket.
- **`ls` sorts `1, 10, 2`.** Use `ls -v` or `sort -V`, and have `pidly list`
  sort numerically by default.

### Why not names that carry ancestry

An earlier draft named tickets by their lineage — the second child of the first
child of ticket 1 was `1-1-2` — so that a name could be spoken and resolved
without a lookup. Removing `o/` undercut that. Paths are now made of ticket
numbers and nothing else, so looking a name up already tells you where it sits;
the prefix was restating what the path says.

What settled it is that composite names are not stable. Re-parenting a ticket
would rename it *and every descendant*, which means every commit message, code
comment, and conversation that referenced the old name silently goes stale. A
bare number never changes: re-parenting is a plain `mv`, and a reference written
today still resolves in a year. The scheme justified as "good for referencing"
was the one whose references rot.

That also deletes work — no `move` subcommand, no name-matches-position
invariant for `check` to enforce, and no duplicated path data in the format.

## The ticket file

Three header lines, then the project's fields, then a blank line, then the
body to the end of the file.

```
claim:
needs: 1 4
title: Write the pidly shell script
effort: L
handoff: Parser works; lexer fails on nested quotes.

A single POSIX shell script providing the ergonomics layer over the format.
Not a runtime dependency: every command must be something a person could
have done by hand.
```

The header is fixed-position on purpose, and the order falls out of how much
a reader needs:

| want | read |
|---|---|
| can I take this? | `sed -n 1,2p` |
| a listing line | `sed -n 3p` |
| project fields | `awk 'NR>3 { if ($0=="") exit; print }'` |
| the body | `awk 'b { print } !b && $0=="" { b=1 }'` |

The first two lines are the status pair and the third is the title, so the
scheduling question — *what can I start right now?* — is answered by two
lines per ticket and never touches a body. Add line 3 and you have a full
listing.

**Nothing records where the body starts or ends.** It ends at the end of the
file, which nothing can spoof, and the fields end at the first blank line
after line 3 — a boundary that sits *ahead* of the body, so nothing written
in a body can be mistaken for it. A body may contain as many blank lines as
it likes, and a body line that reads as `handoff: something` is still body.
All three are covered by tests.

Title is a human title, not the number; the number is the directory name and
would be redundant here.

### Why the fields come first

An earlier layout put the body immediately after the header and the fields
after it, with a fourth header line `desc:` holding the body's last line
number. That bought exact reads — no scanning, no delimiter a body could
spoof — at the cost of derived data living inside the file it described.
Edit a body by hand and the header started lying, and nothing but
`pidly check` would ever notice.

Inverting the layout removes the cost rather than guarding it. `desc:`
existed only to say where the body ended; put the fields first and the end
of the file says it instead. The delimiter objection does not survive the
move either, because the boundary is no longer something a body could
contain — it is passed before the body begins.

What this gives up is a fixed line number for the start of the body, which
now depends on how many fields a ticket has. Nothing stores that number, so
nothing can disagree with it. Reading the fields got cheaper as well: a
short scan from the top rather than a seek past the body.

The payoff is that **appending to a body needs no bookkeeping at all**,
which is what the retraction in ticket 19 made the central operation, and
principle 5 loses its only exception.

## Dependencies

Line 2 is `needs:`, a space-separated list of ticket numbers that must be
closed before this ticket can start. Empty means unblocked.

This is the one relation carried as a field rather than a path, because it is
the one relation a tree cannot hold: dependencies form a DAG, and a ticket can
need a sibling, a cousin, or something in an unrelated tree. Nesting can't
express that without duplicating tickets.

**Referencing by number rather than by path is what makes it safe.** A number
is permanent — that is exactly what the single-number naming scheme bought —
while a path changes every time a ticket is closed or re-parented. A `needs: 7`
written today still resolves after 7 has been closed, moved into a `c/`, and
re-parented twice. Storing a path there would produce a reference that rots on
the first `mv`.

Blocked-ness is computed without opening any file: a ticket is closed if its
path runs through a `c/`.

**Resolve numbers with one traversal, not one search per dependency.** The
naive form — `find .pidly -name <n>` per entry — is quadratic, and it shows: on
a 2003-ticket tree it takes 26.5s, against 2.0s for a single `find` that builds
a number-to-path map and answers every lookup from it. The map is derived on
each run and never stored, so there is nothing to keep in sync. Any tool
enumerating tickets is already walking the tree once; this is the same walk.

Two rules keep this distinct from parentage:

- **`needs` blocks starting; children block closing.** A parent isn't blocked
  by its own children — it just can't close until they're all in its `c/`.
  These are different questions and neither implies the other.
- **A parent is not an implicit dependency of its children.** Children usually
  *are* the way a parent gets done, so making them wait on it would deadlock.

`check` owns the integrity of the graph: every entry resolves to a real ticket,
and there are no cycles. Both are silent corruptions otherwise — a typo'd number
blocks a ticket forever, and a cycle blocks a whole group with nothing to show
for it.

## Claims

Line 1 is the claim: `claim:` when free, and when held one of

```
claim:<pid>.<starttime>@<runtime>        an agent with a process table
claim:<agent>@- <expiry>                 an agent without one
```

The pid is the point where there is one. An agent that dies mid-task cannot
release what it holds, and a claim with no liveness information is
indistinguishable from active work. A pid is checkable, so a stale claim is
detectable rather than merely suspicious, and `pidly check` reports claims
whose holder is gone.

**Claiming is the one operation the format does not make atomic.** Because the
claim lives inside `info`, taking it is read-modify-write, and two agents can
both see `claim:` and both write their pid, with the loser never finding out.
A separate claim file would have made this free (`set -C` fails when the file
exists) at the cost of another file per ticket.

So claim, release and edit take a transient lock. The lock is a file whose
content is the holder's pid, and it is **published with `link(2)`**, which
either makes the name appear whole or does nothing:

```sh
lock() {
	_d=$1 _t="$_d/.lock.$$" _n=0
	printf '%s\n' "$$" > "$_t" || return 1      # pid first, in private
	while [ "$_n" -lt 100 ]; do
		_n=$((_n+1))
		if ln "$_t" "$_d/.lock" 2>/dev/null; then
			rm -f "$_t"; return 0               # published: we own it
		fi
		_owner=""
		[ -r "$_d/.lock" ] && read -r _owner < "$_d/.lock" 2>/dev/null || true
		[ -z "$_owner" ] && continue                # in flight; never break
		if kill -0 "$_owner" 2>/dev/null; then
			rm -f "$_t"; return 1               # a live holder
		fi
		rm -f "$_d/.lock"                           # a dead one: break it
	done
	rm -f "$_t"; return 1
}
```

**Why the pid is written before the lock is published.** The pid is not
decoration; it is how a crashed holder is distinguished from a live one. So
the lock must never be visible without it. Writing the pid into a private file
first and then linking that file into place means the instant `.lock` exists,
it already names its owner — there is no window in which the lock is visible
but anonymous.

That window is not hypothetical. An earlier version created a lock *directory*
and then wrote `pid` inside it. A second caller arriving in between saw a lock
with no owner, concluded the holder was dead, deleted it and took the lock:
**4 of 30 racing claims won instead of 1.** Narrowing the gap is not a fix, and
`O_EXCL` on a file only narrows it — `link` closes it, and is also the
primitive that stays atomic over NFS, where `O_EXCL` historically is not.

The empty-lock branch survives anyway, because the cost of guessing wrong is
two writers: **an empty lock means in-flight, never abandoned.**

Three properties matter. The lock is **transient** — held for the microseconds
of one rewrite, so a repository at rest still has exactly one file per ticket.
It is **self-healing**: a crash leaves a pid that the next caller finds dead
and breaks, rather than wedging the ticket forever. And that recovery is **the
same idiom as stale claim detection**, so the system has one liveness
mechanism rather than two.

The pid in the lock is the `pidly` process's own, not the agent's. A lock is
alive exactly as long as the command holding it; a claim outlives many.

Measured: 100 concurrent claims on one free ticket, one winner, no leftovers.

**Whether to wait for the lock is the caller's decision.** `claim` returns
immediately if someone else holds it: there is other work to pick up, and
blocking would be worse than moving on. `new` cannot do that — the caller
wants a ticket and has no alternative — so it waits, up to ten seconds in 50ms
steps.

Getting this wrong is not subtle. With no wait, 34 of 40 concurrent
creations failed with "the tracker is busy" while still producing correct,
unique numbers: the invariant held and the command was useless.

The same lock, at `.pidly/.lock`, serializes number allocation. The expensive
part of allocating — scanning the tree for the highest number — happens
*before* the lock is taken. A stale answer only costs a few extra `mkdir`
attempts, and it keeps the critical section down to those attempts rather
than a full traversal.

### What a pid is worth, and when

A pid on its own identifies nothing. It is meaningful only relative to a
particular process table, and only until the number is recycled. Both halves
have to be recorded or the check gives confident wrong answers:

```
claim:<pid>.<starttime>@<runtime>
claim:19248.117009904@31917916.u1000
```

`<starttime>` is the process's start time, so a later process that inherits
the number reads as a different identity rather than as the original still
running. `<runtime>` identifies the process table: boot id, uid, and pid
namespace where readable, all **derived at run time, never stored**.

Each component closes a hole that was live in the first implementation:

- **Boot id.** The old `.pidly/.id` was a file, so it survived reboots. Pids
  do not. A claim written before a reboot kept matching, and its number had
  since been handed to something else.
- **Uid.** `kill -0` returns the same failure for "no such process" and "not
  your process", so an agent running as another user read as *dead* and would
  have been reaped while working. With the uid in the runtime, a mismatch is
  never checked in the first place, and a match means the process is ours —
  where a `kill -0` failure really does mean gone.
- **Pid namespace.** Two containers sharing a checkout shared one `.pidly/.id`
  and had entirely separate process tables.

The rule underneath all three: **never report dead without positive evidence.**
Unknown must resolve to unverifiable, because calling a live claim dead puts
two agents on one ticket, while the reverse only parks one.

### Why not a unique id instead of a pid

Because uniqueness is the easy half. The hard half is liveness, and only the
operating system keeps a registry of live processes — `kill -0` and
`/proc/<pid>` work precisely because something else is maintaining them. A
UUID has no registry behind it: it would tell you *which* agent holds a
ticket and never whether that agent still exists.

Pairing the pid with its start time gets the uniqueness a UUID would give,
while keeping the free liveness check. So the pid stays wherever there is a
process table to ask.

### Subagents share their parent's process

A subagent spawned inside an agent runner is usually not a process of its
own. Under Claude Code, a `Bash` call from a subagent reports the same
`CLAUDE_PID` as the lead agent, so a pid identifies the *runner*, not the
agent doing the work: two claims, one pid, both live, and no way to tell
which is which.

So a subagent claims the way a cloud agent does — `PIDLY_AGENT` plus a
lease. The mechanism built for agents with no reachable process table turns
out to cover agents with a process table they *share*, which is the more
common case.

`PIDLY_PID` therefore defaults to `$CLAUDE_PID` where it is set, falling
back to `$PPID`. The two are usually the same process, but only because a
tool call's shell is a direct child of the runner; wrap that call in another
shell and `$PPID` quietly becomes the wrapper. Naming the runner explicitly
is free and does not guess.

**Delegation is a convention, not a hook.** Claude Code has `SubagentStart`
and `SubagentStop`, but `PreToolUse` cannot modify tool input, so a hook
cannot put a ticket number into a subagent's prompt. It does not need to:
the lead agent *writes* that prompt, so it can create a child ticket and
include the number itself.

And a ticket per subagent would be the wrong default regardless. Most
subagent calls are lookups; numbers are never reused and tickets are never
deleted, so the noise would be permanent — and an open child blocks its
parent from closing, so it would also wedge the work it was meant to track.

### Leases, for agents with no process table

A cloud agent, a CI job, a container nobody else can see: these have no pid
anyone can check, and no amount of identity fixes that. For them, liveness
has to come from a clock instead of a kernel.

```
claim:<agent>@- <expiry>
claim:cloud-sess-9f2@- 2026-09-17T05:37:26Z
```

`@-` means "no reachable process table". The expiry is an ISO-8601 UTC
instant, so lexical comparison is chronological and no date parsing is needed
to evaluate it.

This is a **lease, not a heartbeat**: a promise with an end rather than a
signal that must keep arriving. No refresh traffic, nothing to run in the
background, and no server — but a claim whose holder dies frees itself when
the lease runs out, which is the thing a bare unverifiable claim could never
do. An agent that outlives its lease renews by claiming again.

`PIDLY_AGENT` requires `PIDLY_LEASE`. An agent that can neither be checked nor
expire would wedge a ticket permanently, so the format refuses to record one.

Resolution order, once for every claim:

| | state | meaning |
|---|---|---|
| 1 | `expired` | the lease has run out; anyone may take it |
| 2 | `live` | our runtime, and the process is there |
| 3 | `dead` | our runtime, and it positively is not |
| 4 | `unverifiable` | someone else's runtime, lease still good |

Only `free` and `expired` allow a claim. Only `dead` may be reaped, and only
locally.

The costs are the ones a clock always brings: skew between machines, which
UTC and generous leases absorb, and the chance of preempting a slow agent that
forgot to renew.

### Clearing dead claims

`check` reports; it never clears. Keeping it side-effect-free is what lets it
run in CI and what lets anyone run it without thinking, and a command that
silently edits tickets while you're reading its output is a bad trade for the
keystrokes it saves.

Clearing is `pidly reap`, explicit and separate. It removes only claims that are
both **local** (`@<id>` matches this checkout) and **dead** (`kill -0` fails).
A foreign claim is never reaped, because the information needed to judge it
doesn't exist on this machine.

## Configurable schema

`.pidly/schema` defines the fields for this project. It is the format's own
shape applied to its own configuration: one stanza per field, `key: value`
lines, a blank line between, read with the idioms tickets are read with. It
has two audiences and this serves both — a human reads it as documentation,
an agent reads it as a spec, and nobody needs a TOML or JSON parser in bash.

```
field: effort
match: S|M|L
note: rough size

field: area
required: yes
match: format|cli|docs
note: which part of the project
```

It was a markdown table until a value needed a regex. A table separates its
cells on `|` and an ERE alternates on `|`, so the one validator worth having
could not live in the container. The stanza has no delimiter after
`match: `, which is exactly what buys a pattern its `|`, brackets, braces and
spaces with no escaping. The file loses its extension for the reason `info`
never had one: an editor that thinks this is markdown will reflow it.

`claim`, `needs` and `title` are structural and always present, in that
order. They are not declared here — the schema is only for the project's own
fields, which live between those three lines and the body.

Those are validated by `pidly check` rather than by the format, so a ticket
missing a required field is still a readable ticket.

**`match:` is a POSIX ERE, tested anchored.** pidly asks `^(<pattern>)$`, so
`S|M|L` cannot half-match `M extra` and a pattern its author already anchored
still works. No `match:` means anything, which is what a prose `values` cell
meant before. An empty value is never matched against a pattern: absence is
`required:`'s question, and folding the two together would make every
optional field carry a trailing `?` and read like a mistake.

**The matcher is `grep -E`, never awk.** mawk 1.3.4 has no interval
expressions: `[0-9]{4}` matches `2026` under `grep -E` and does not under
mawk, in a literal `/re/` or in a dynamic `$0 ~ p`. gawk does support them,
which is the point — a pattern's meaning must not depend on which awk is
installed. Measured 2026-09-17 on aarch64 Linux, mawk 1.3.4 20200120.

**A permissive grep hides a dialect error.** ugrep 7.8.4 accepts `\d`, where
GNU `grep -E` leaves it undefined, so a pattern written against whatever is
installed locally can behave differently on the next machine. `check` lints
the pattern text for `\d \w \s \b` and `(?...)` rather than trusting the
local tool, and asks grep whether the pattern compiles at all — exit 2 rather
than 1 says it does not, which makes a broken schema a finding instead of a
crash. Both are properties of the tools rather than of this checkout, so
re-test them wherever the work happens.

### The format's own fields

`claim`, `needs`, `title`, `created` and `updated` are declared in the same
language, in `format_text()`, **compiled into the script**. Until then they
were three greps written by hand in `check` — `^claim:`, `^needs:`,
`^title: .` — each weaker than what any project could ask for its own
fields: `claim:garbage` was a valid ticket, and `needs: yesterday` was caught
only later and indirectly, when the dependency resolver failed to find a
ticket called "yesterday". The project could say `effort` must match
`S|M|L`; pidly could not say what its own claim line looked like.

Compiled in rather than seeded, and not overridable: a schema that could
redeclare `title` could say it may be empty, and every listing prints it.
`check` reports a stanza that names one of them, and `pidly fields` and
`pidly set` will not write one into the field block whatever the schema says.
The alternative — seeded stanzas a project may tighten but not loosen —
needs a rule for what tightening means, which is more machinery than the
problem deserves.

`line:` is the one key only the format has. A pattern cannot say "this is the
first line", and position is real for exactly these three: the takeable scan
reads lines 1 and 2 by number without parsing anything. A schema using
`line:` is a finding.

A finding about one of these prints the stanza's `note:` rather than its
pattern — `claim is 'garbage', which is not <pid>.<starttime>@<runtime>,
alone or followed by a lease expiry, or <agent>@- <expiry>`. The pattern is
in the script, not in a file the reader can open, so quoting a 130-character
ERE at them helps nobody; a project's pattern is in a file the project wrote,
so naming it points at the line to go and read.

`handoff` is deliberately left without a `match:`. It is the project's field,
it ships in the seeded schema, and any one line is a valid handoff — a
pattern for it could only be `.*`, which checks nothing, since an empty value
is never matched against a pattern anyway.

A fault in the schema is reported once, by `check`, before any ticket: one
mistake there would otherwise be a finding against every ticket that carries
the field. `new -f` and `set` refuse a value the pattern rejects, so the two
ways of writing a field agree with what `check` would say a moment later.

**`required: yes` means a value, not a key.** An empty field and an absent
one are the same thing to `get_field` and to every awk that goes looking, so
a schema that only demanded the line would demand nothing a reader can use.
`check` reports the empty one as well as the missing one, and `pidly new`
refuses to create a ticket whose required field has no value — which is why
`new` takes `-f name=value`, the first way to set a field at all.

`new` writes a line for **every** field the schema declares, in declaration
order, valued or empty. An empty slot is a prompt — what the project expects,
without opening the schema — and uniform blocks make two tickets diff
against each other. It buys nothing for readers: a field is still found by
name, because counting lines is correct only until the schema changes and then
silently wrong for exactly the old tickets worth reading.

A stanza added to the schema after tickets exist leaves every one of them
without the slot, so `pidly fields` rolls it out: it adds the missing keys to
every ticket, open and closed, and does nothing else. It never removes a
field the schema dropped — that is data — and never moves a line that is
already there, because a ticket written by hand may order its fields however
it likes and nothing may depend on where they sit. It does not bump
`updated`: pidly is writing, but this is not activity on the work, and a
migration that stamped every ticket would flatten `list --stale` the day it
ran, the same reason `close` and `reopen` leave the stamp alone. It is an
explicit command and never part of `init`, which is what you run after an
upgrade and must not quietly rewrite the tracker.

It needs no `--dry-run` of its own: `pidly check` reports the drift it would
close, from the command that already changes nothing and already runs in CI.
That report is a **note** rather than a problem — printed, but it leaves the
exit status alone. A ticket made with `mkdir` and an editor is a legal
ticket, and it will not have a slot for every row the schema has grown since;
failing CI over that would turn the format's central promise into a build
break.

The `values` column stays documentation; nothing checks that `effort` is one
of S, M, L. Validating it would make the column a grammar and the schema no
longer free-form, which is a bigger decision than this one and belongs with
the rest of schema validation.

**`handoff` ships in the default schema.** One line, written by
`pidly release -m`, holding where the last agent got to when it stopped
without finishing. `pidly claim` prints it to whoever picks the ticket up,
which is the whole point: a note nobody is shown is a note nobody reads.

It is a field rather than a header line for the same reason priority is. It
does not help answer *can I start this?*, which is what the header's fixed
positions are for, and every structural line is a cost every ticket carries
forever. It is read after a ticket has already been chosen, alongside the
body.

It is one line on purpose. A multi-line dump invites an agent to paste its
reasoning, which is exactly the context bloat the format is built to avoid;
anything longer belongs in the body. And it is overwritten rather than
accumulated, so it always describes the most
recent stop rather than growing into an unread log.

This also covers what closing lost when the marker file went away: a project
wanting a written resolution has somewhere to put one.

**`created` is pidly's field, not the project's.** It is written by `new`,
sits in the field block like any other, and is valid whether or not the
schema declares it — otherwise every tracker that predates the field
would fail `check` until someone edited a file the project owns.

It records something no other part of the format carries. A path gives
identity, parentage and state; the registry gives the number; `git` gives
history, but only to a checkout that has it, and only at the cost of a `log`
per ticket. So `created` is not a second copy of anything, which is the test
that `desc:` failed: a field that duplicates something in the same file can
disagree with it, and a field that records an event cannot.

Nothing updates it, and it is ISO-8601 UTC so lexical order is chronological
order — the same reason lease expiries are.

`init` backfills a missing one from the commit that added the file, and from
the file's mtime outside a repo. That dating uses `git log --follow`, because
closing is a move and a move without it reads as an add: every finished
ticket would be dated the day it finished. A ticket it cannot date keeps no
`created` line at all — a guess that cannot be told apart from a record is
worse than the gap it fills.

**`updated` is maintained, and that makes it the one field that can lie.**
It records an event on one ticket — `claim`, `release`, `edit`, `set`,
`reap` — rather than every write to the file. The test is whether the write
says something about *this* ticket: `pidly fields` writes to every info in
the tracker and says nothing about any single piece of work, so it leaves the
stamp alone, and stamping the lot would flatten `list --stale` the day it
ran. `close` and `reopen` do not bump it either, because they are moves —
the one write either makes is `close` emptying `claim:`, which is part of the
close rather than an event of its own — and a hand-edit cannot bump anything
at all. So it means *when something last happened to this ticket, as far as
pidly saw* — not mtime, and not a log of writes.

Claiming is on the bumping side of that line, which is worth saying because
it looks like the migration case: nothing in the ticket's content changes.
But a claim is one agent taking one ticket at one moment, and `--stale` asks
what has been forgotten — a ticket somebody picked up ten minutes ago has
not been. What a claim is *not* evidence of is progress, and the ticket
picked up and then dropped is answered by liveness rather than by a
timestamp: `claim_state` resolves it from the process table, `reap` clears
it, and `check` reports it.

This is the trade `desc:` was rejected for, taken deliberately. The
difference is what a wrong value costs. A stale `desc:` broke a bounded read
— the body was cut short and nothing said so. A stale `updated` makes one
ticket look quieter than it is in one query, and the query is a prompt for
attention rather than an input to anything. The alternative was deriving it
from `git log` per ticket at query time: always truthful, and useless in a
checkout without history, which is exactly the situation pidly is meant to
survive.

`pidly list --stale 7d` is what the field is for. Without it the field is
dead weight, and without the field the query is a `git log` per ticket. It
takes the same durations a lease does, lists the oldest first, and includes
tickets with no `updated` line at all: an undated ticket cannot be shown to
be fresh, and the question being asked is what has been forgotten.

**`list` resolves what it can without a process.** It decided a ticket was
claimed because line 1 was not empty, while `claim` resolved the same line
through `claim_state` — free, expired, live, dead, unverifiable. They
disagreed about exactly one case, and it was the expensive one to get wrong:
an expired lease is takeable, `claim` grants it, and no listing offered it.

The two halves of `claim_state` cost differently. An expiry is on the line
and ISO-8601 sorts lexically, so the single awk pass decides it against a
`now` passed in with `-v` — a string comparison, no process. A pid needs the
process table, which is a process per ticket, the shape every query here is
built to avoid. So `survey` does the first and not the second: a dead claim
still reads `claimed` in `list`, which is also what `claim` says about it —
it refuses until `reap` clears it. The two now agree about everything a
caller can act on, which is the property that was missing rather than
completeness for its own sake.

**`defer` is the fourth state, and it is a field rather than a location.**
`list` was the one view an agent could trust without opening anything: every
line it printed was something to pick up. Four deferred design questions —
34, 35, 36, 37, each opening with the trigger that would justify starting it
— broke that, because *ready* meant unclaimed and unblocked and they were
both. A quarter of the list was work nobody should start, and the only way to
tell was to read four bodies, which is the unbounded reading the format
exists to prevent.

"State is location" would suggest a `.pidly/d/` beside `c/`. That is wrong
here. The two states that are locations are the two that change what a ticket
*is*; deferred does not — a deferred ticket is an open ticket that nobody
should pick. It belongs with `blocked` and `claimed`, which are also computed
rather than structural: from `needs:` and `claim:` respectively, and now from
`defer:`, which holds the trigger.

Putting the trigger *on the ticket* is the half that pays. It used to live in
a design document nobody reads while choosing what to do next; now it is the
thing `list -a` prints, and clearing the field is what "the trigger fired"
looks like.

`claim` prints the trigger and takes the ticket anyway. A blocker is a fact
about the tracker and refusing is right; a deferral is an opinion about the
work, and the person asking for it by number has already looked.

`defer` is pidly's own field, like `created` and `updated`: declared in
`format_text()`, not in the project's schema, not stubbed by `new` and not
backfilled by `fields` — an empty `defer:` on every ticket would be noise on
a field that is almost always absent. That split is why `settable_fields`
(what `set` will write) is no longer the same list as `slate_fields` (what
every ticket gets a line for).

No `closed` field. Where a ticket is *is* whether it is closed, and a second
record of that can disagree with the first — `reopen` would have to clear it,
and a hand-run `mv` never would. The date of a close is the commit that made
the move.

**Priority is a project field, not a structural one.** The header earns its
fixed positions by answering *can I start this?* in two lines, and priority
doesn't help with that — it answers *which of these should I pick?*, a sort over
candidates that have already survived the filter. That set is small, so reading
past the body of each one is cheap, and projects that don't want priority pay
nothing for it. Every structural line is a cost every ticket carries forever.

## Why this shape suits agents

The tree is the work breakdown, so it's also the delegation graph. A lead agent
claims `2` by writing its pid to line 1 of `.pidly/2/info`. Each child
directory under it is a unit of work a subagent can claim independently, and the
subagent's working context is one directory — its own `info` plus whatever
children it spawns. Parent completion is a question about the filesystem: are
there any children left outside my `c/`?

Scanning is cheap in the way that matters for an agent: picking the next piece
of work across a hundred open tickets is one `find` that never enters closed
work, plus two lines read per ticket, plus one `find` per dependency. No bodies
are read until something has actually been chosen.

## Tooling

Deliberately thin, and deliberately optional.

`pidly` is a POSIX shell script — `init`, `new`, `claim`, `release`,
`status`, `close`, `reopen`, `edit`, `list`, `tree`, `check`, `reap`,
`agents`. It is
not a runtime dependency of the format; it's an ergonomics layer. The acceptance
test for every command is that a person could have done the same thing with
`mkdir`, `mv` and a text editor, and the repository would be byte-identical.

**POSIX means the tools too, and `find` is where that slipped.** `map()` —
the single traversal every command goes through — was written with
`-printf '%f %p\n'`, which is a GNU extension BSD find does not have, so
every command would have failed on macOS: the platform a Homebrew tap exists
to serve. It went unnoticed for the most ordinary reason: the machine pidly
was written on has bfs as its `find`, which implements the GNU options, so
nothing ever complained. The basename now comes from the `awk` every caller
already pipes through, and `ticket_dir` stops with `head -n 1` rather than
`-quit`. `-mindepth` stays, being the one non-POSIX primary BSD ships too.

A suite running on one machine cannot prove portability, so `tests/
portable.sh` does the two things it can: it greps the script and both
generated documents for the extensions — the documents publish `find`
commands that agents will run, and those are the ones nothing else exercises
— and it re-runs every command with a `find` on `PATH` that refuses them.
That catches the habit coming back, which is the failure mode; it does not
replace running pidly on a Mac.

The suites had the same problem one layer up, and a suite that will not run
on the machine someone is porting to cannot check the port. `sed -i` is the
worst of it — GNU takes it bare, BSD requires an argument, and there is no
spelling that works on both — so `tests/lib.sh` holds a `sedi` that writes a
temp file and renames it, which is what the script does internally anyway.
`mktemp -d` wants a template on BSD, `addr,+N` and `3a text` are GNU-only sed,
and both are now awk or `head`/`sed -n` instead. `portable.sh` greps the
suites for all four, skipping itself and `lib.sh`, which have to be able to
write the spellings down in order to forbid and explain them.

The locking tests are only as good as the number of processes they race, and
that number is a property of the machine rather than of pidly — a proot
sandbox gives out long before a workstation does. `PIDLY_TEST_RACE` carries
it, defaulting to 32 and overridable through a gitignored `.env`, so a
constrained environment turns itself down without weakening the suite
everywhere else.

**`check` reports into a file, not a variable.** Almost every check runs
inside a pipeline, and a pipeline's commands run in subshells, so a counter
incremented there never reaches the caller — the first version always exited
0 no matter what it found. Findings append to a temp file and the exit code
comes from its size.

**Sorting structural keys runs under `LC_ALL=C`.** `tree` orders tickets by
a key of zero-padded ancestor numbers, and a locale-aware collation ignores
the `/` between segments, which put children ahead of their own parents.

**Tab-separated output never emits an empty field.** Tab is IFS whitespace,
so a shell `read` collapses two tabs into one and every later field shifts
left. `survey` writes `-` for "no blockers" rather than nothing.

**`reap` is a command rather than a step inside `claim` or `check`.** It
clears exactly one state — same runtime, process positively absent — and the
separation is the point: clearing someone else's claim is the only
destructive operation in the tracker, so it happens because someone asked for
it. `claim` therefore refuses a dead claim and names `reap` rather than
taking the ticket, and `check` reports one without touching it.

It refuses everything else, and the refusals are the interesting half. An
unverifiable claim is another machine's pid and stays alone, because reading
silence as death is exactly how two agents end up on one ticket. An expired
lease needs nothing: it is already takeable, so `claim` handles it and `reap`
would only add a second way to do the same thing. A stale `.lock` is not its
business either — `lock()` breaks a dead one on the next attempt, so it heals
itself.

The sweep re-reads each claim under the lock before clearing it. The scan is
not a snapshot: between finding a dead claim and clearing it, the holder's
replacement may have taken the ticket, and that one is alive.

**`edit` does not hold the lock while the editor runs.** A lock held for the
length of a human edit blocks every claim on that ticket for as long as the
session lasts, and a session that is never closed leaves one behind for `reap`
to find. So the editor works on a copy, and the install takes the lock, checks
that `info` is byte-for-byte what it was, and refuses if it is not — most
likely a `claim` that landed on line 1 meanwhile. Noticing the other writer
costs one comparison; excluding them costs the ticket. A refused edit is kept
and its path printed: it is the user's work and the only copy of it.

**`edit` reads what was saved before installing it.** An editor makes it easy
to save something that is no longer a ticket — a deleted header line, a field
that lost its colon, a body that lost the blank line in front of it. The rules
are the same ones `check` applies to an info file, so they live in one
function, `info_faults`, and `check` is now its other caller. It answers only
what is true of the file itself; dependencies, the registry and cycles are
facts about the tracker and stay in `check`.

The command's justification changed under it. `edit` existed to keep `desc:`
honest — a hand-edit could leave that derived line lying, and only `check`
would notice. Dropping `desc:` removed the derived data, so what is left is
ergonomics: the lock and the structural read, neither of which a person
running `$EDITOR` or `cat >>` on the file gets.

**Closed-ness is matched relative to `.pidly`, through one helper.** The rule
is *is there a `c/` between this ticket and the tracker root*, and the first
implementation asked it of the absolute path — `case $dir in */c/*)`. A
checkout under a directory named `c`, and every ticket in it reads as
finished: `claim` sees nothing blocked, `list` offers everything as ready.
The failure is silent and in the direction that loses work, which is why the
test suite now runs a checkout at `$TMPDIR/c/proj`. The rule is written once,
in `in_closed`, because it was wrong in three places at once.

**A loop's exit status becomes its caller's.** `init`'s backfill ended with
`[ "$did" = yes ] && printf ... >> log`, which is an AND-list `set -e`
ignores — but it was the last command in a `while` body, so its status became
the loop's, the loop was a pipeline, and the pipeline was a plain command in
`cmd_init`. Every `init` with nothing left to date exited 1. The fix is an
`if`, which is 0 when its condition is false. The general rule: an AND-list
is only exempt from `set -e` where it stands, not where its status ends up.

**`tree` is iterative, not recursive.** A recursive shell function cannot
hold loop state: the inner call clobbers the outer one's cursor, and
per-function variable prefixes do not help when a function collides with
itself. Sorting a precomputed key does the same job in one pass.

**Every function prefixes its variables.** POSIX shell has one global
namespace, so a helper's locals and its caller's locals are the same
variables. `lock()` used `_n` as a spin counter while `cmd_new()` used `_n` as
the ticket number it was allocating, so taking the lock silently overwrote the
allocation — the first ticket in a fresh tracker came out as `2`, and under
contention numbering skewed by however many times the lock had spun. Nothing
about the symptom pointed at the lock. Helpers therefore use a per-function
prefix (`_lk_`, `_td_`, `_ho_`), and the test suite asserts that a fresh
tracker's first ticket is `1`.

One carve-out. Claiming is the single operation that is *not* safe to do by
hand while other agents are running, because it needs the lock — one
function's worth of shell, and the price of having the claim on line 1
rather than in a file of its own. Everything else, including editing a body,
is a plain file edit with nothing to keep in sync.

## Starting a tracker

`pidly init` creates `.pidly/` in the current directory, seeds `schema`,
writes the ignore rules, and installs both documents. A project can adopt
pidly without hand-building anything.

**Re-running is a refresh, not a reset.** Everything generated — the
reference, the summary, the ignore rules — is rewritten; `schema` is left
alone the moment it exists, because from then on it belongs to the project.
That makes `init` safe after an upgrade and safe in a hook, which a command
that clobbered the schema could never be.

**The ignore rules live in `.pidly/.gitignore`, not the repo root.** The
tracker stays self-contained: copy the directory into another project and its
rules come along, delete it and nothing stale is left behind in a file it
does not own.

Migrating this repo to that layout exposed that its root rules had been wrong
for some time. They read `.pidly/**/.lock/` — with a trailing slash, matching
only directories — and had not been updated when the lock became a file. A
lock file was never actually ignored:

```
$ git check-ignore -v .pidly/2/.lock     # under the old root rules
$                                        # no match
```

Nothing was ever committed, because a lock is removed before the command that
took it returns, but the safety net had not been there for a while. Rules that
travel with the thing they describe do not drift out from under it this way.

**A tracker inside a tracker is refused.** The outer one's traversals would
walk the inner one, its numbers would collide, and `find .pidly -name 8` would
have two answers.

## Telling agents how to use it

A project using pidly does not have this document. Everything an agent needs
in order to act correctly has to travel inside `.pidly/`, and the split is by
how often it gets read:

| tier | where | size | read |
|---|---|---|---|
| summary | a block in `AGENTS.md` | ~50 lines | every turn, always loaded |
| reference | `.pidly/README.md` | ~150 lines | on demand, for a rule |
| rationale | this document | ~550 lines | by whoever changes pidly itself |

Both of the first two are generated by `pidly agents`, so they cannot drift
from each other.

**The summary is a budget, not a document.** It sits in the context of every
agent that touches the repo, so the test suite fails if it grows past 60
lines. It carries the shape, the three header lines, how to find and claim
work, the handful of rules that cause damage when broken, and a pointer to
the reference. Everything else is a link away.

It is installed between two HTML comment markers:

```
<!-- pidly:begin -->
...
<!-- pidly:end -->
```

The markers are the whole mechanism. Re-running replaces what is between them
and leaves everything a human wrote before and after untouched, so the command
is safe on every upgrade and safe in a hook. Without them the only options are
appending a second copy or overwriting someone's file.

**The reference is wholly owned by pidly** — no markers, just overwritten,
with a line at the top saying so. It answers the questions the summary skips:
the four claim states, lease renewal, the upward cascade on reopen, how the
next number is derived, and why resolving `needs` wants one traversal rather
than one search per entry.

The dividing line between the reference and this document is **act versus
why**. A rule an agent must follow goes in the reference. The measurement that
justified the rule, the alternative that was rejected, and the bug that
produced it stay here.

Both lead with the format rather than the CLI, because they have to work for
an agent in a checkout where `pidly` was never installed. Commands are the
convenient path; `find`, `sed` and `mv` are the guaranteed one.

**The Claude Code integration is a skill, not a server.** A tool is something
a model calls with typed arguments, and the only way to add one is an MCP
server: a running process the client talks to. The premise here is that there
is nothing to run — a checkout where pidly was never installed is workable
with `find`, `sed` and `mv`, and Bash already reaches the CLI. Wrapping it
would add a process and a schema for no new capability. What tools would
genuinely buy is typed arguments rejected before they run, structured results
instead of text, and per-command permission gating so `reap` prompts while
`list` does not; ticket 23 records that, and what would make it worth
revisiting.

So: a skill for the workflow, three slash commands, and a permissions block
that allows the commands which cannot lose anything. `pidly claude` writes
them and `check` compares them, because they are pidly's prose about pidly.
`settings.json` is the exception — it is the project's file and it is JSON,
which this script has no business parsing, so pidly writes it only when there
is none and otherwise prints what to add.

**No hooks.** A hook is enforcement, and in this project enforcement has been
the operator's job. A hook that fires on every tool call is also a strong
thing to install on someone's behalf from a tracker command.

**Both are copies, and copies go stale.** `pidly check` regenerates both and
compares — cheap, since each comes from a single function — so a command that
changes without its documentation is a finding.

That covers the two generated documents and nothing else, and the gap has
been expensive. The same fault has been found three times: the schema told
every project "Four header lines" from the day `desc:` was dropped until it
was noticed while doing 17; this document, the README and *both generated
documents* still said "four header lines, then the body, then project
fields" until later the same day, directly above examples showing the
opposite order; and the schema was the file that could not be fixed by an
upgrade, because `init` correctly refuses to rewrite what the project owns.

The rule that falls out: **pidly's prose belongs in files pidly regenerates
and `check` compares.** Anything explaining the format that lives in a
project-owned file will eventually be wrong with no way to correct it, which
is why 28 moves the schema to a stanza file whose only prose is one `note:`
line per field.

## Not doing

pidly replaces beads (`bd`) for this project's workflow, so it is worth
saying which of its ~100 commands are deliberate non-goals rather than
oversights.

- **A database.** Dolt, SQL, cell-level merge, federation, compaction, gc.
  The whole premise is that the repository is the interface.
- **Issue-tracker integrations.** GitHub, GitLab, Jira, Linear, Notion, ADO.
- **Agent memory.** `remember`/`recall`/`forget`, a kv store, molecules,
  formulas, swarms. That is a different product sharing a binary.
- **More relation types.** `bd` has blocks, relates-to, duplicates,
  supersedes, discovered-from. pidly has `needs` and parentage. Principle 3
  is the reason: every additional relation is another reference to keep
  honest, and the two that exist cover scheduling and decomposition.
- **An assignee separate from the claim.** `bd` distinguishes a durable
  assignee from `in_progress`. pidly has only the claim, which is a live
  process. Saying "this is someone's ticket" while nothing is running is a
  planning concern, and the `handoff` field covers the note that usually
  goes with it.

- **A query language, or statistics.** `pidly field <name>` hands over one
  field across every ticket in a single pass and stops there; the average,
  the tally and the grouping are a shell pipeline over well-formed output.
  Not on purity grounds — every aggregate pidly owned would be one somebody
  wanted computed differently, and the pipeline is already the thing they
  would reach for. The commands are a thin wrapper over the format, not a
  layer on top of it.

Worth noting the direction is not all one way: **`bd` has no claim
liveness.** `bd update --claim` sets an assignee and a status, and if that
agent dies the issue stays claimed until a human notices. Detecting that is
what pidly is named after.

## Deferred

Nothing above is unsettled. These are things consciously not solved yet, with
the trigger that would force each one. Each has a ticket carrying the same
trigger, so an agent reading the tracker rather than this document sees why
not to start it — and the tickets are the copy that gets updated, since this
section is where reasoning goes and the tracker is where work does.

- **Priority** (ticket 34)**.** Decided as a project field. Revisit only if picking among
  unblocked tickets turns out to need a sort that reads every candidate's
  fields often enough to show up — at which point it becomes a fifth header
  line, not a fifth opinion.
- **The schema table** (decided; ticket 28)**.** A markdown table is parseable by `awk` in a pinch, but
  only while the schema stays flat key/value. Enums with per-value behaviour
  would outgrow it and force a real config format, which would cost the
  zero-parser property. That trigger has been pulled: enforcing the `values`
  column starts as a comma-separated set, which a cell holds fine, and ends
  at patterns, which it does not — a regex alternates on `|` and the table
  separates cells on `|`. The collision is the container's, not the regex's.
  The candidate that does not need escaping is the format's own shape applied
  to its own configuration: one field per stanza, `key: value` lines, blank
  line between, read by the same idioms tickets are read with. That is now
  the decision rather than a candidate, and the file loses its extension for
  the reason `info` never had one: `key: value` lines are not markdown, and a
  `.md` suffix invites an editor to reflow them. What it costs is the
  rendered table. Shipped: see **Configurable schema** above for the file and
  what validating a pattern turned out to require.

  Two portability facts constrain the implementation, found on 2026-09-17
  with mawk 1.3.4 20200120 and ugrep 7.8.4 on aarch64 Linux. **`awk` cannot
  evaluate the patterns**: `[0-9]{4}` matches `2026` under `grep -E` and not
  under mawk, which has no interval expressions in a literal `/re/` or a
  dynamic `$0 ~ p`, while gawk does — so a pattern's meaning would depend on
  which `awk` a machine happens to have, and validation goes through
  `grep -Eq` instead, never through one of `check`'s existing `awk` passes.
  And **a permissive `grep` hides dialect errors**: ugrep accepted `\d`
  where GNU `grep -E` treats it as undefined, so a pattern written against
  whichever tool is installed can behave differently on the next machine.
  `check` therefore lints patterns for `\d \w \s \b` and `(?...)` rather
  than trusting what is there. A pattern the local `grep` cannot compile
  exits 2 rather than 1, which is what lets a broken schema be a finding
  instead of a crash. These are facts about the tools, not about this
  checkout: `awk -W version` and `grep --version` say what is in front of
  you.
- **Padded multi-line field values** (ruled out; no ticket)**.** Proposed as a way to keep every
  ticket's lines at fixed positions: a field declares a maximum line count
  and is padded up to it. Two things rule it out. Fields end at the first
  blank line, so blank padding would terminate the field block and every
  ticket would read as truncated — padding would have to be a filler
  character every reader learns to strip. And the padding exists to hold
  positions steady, which is derived data maintained by pidly and falsifiable
  by any hand-edit: `desc:` again, with the line number living in the
  reader rather than in the file. Measured, positions are worth nothing to
  buy — over 2000 tickets, one `awk` pass reading a fixed line is 0.43s and
  the same pass matching a field by name is 0.44s, while a process per ticket
  is 17.4s. The win is the single pass, which needs no fixed offsets.
  If a genuinely multi-line value is ever needed, the shape that survives is
  continuation lines — a leading space continues the previous field, no
  padding and no maximum — which keeps every boundary rule intact. The
  trigger is a field that cannot be one line and does not belong in the body;
  note that `handoff` is deliberately one line, because a multi-line field
  invites an agent to paste its reasoning, and a cap does not prevent that.
- **Labels** (ticket 35)**.** Project fields are single-line `key: value`, so they cannot
  hold a set, and there is no equivalent of `bd`'s label filtering. A
  comma-separated field covers the simple case badly. The trigger is wanting
  to filter across a dimension that is not already a field — until then,
  adding a field is cheaper and reads better.
- **Verifying a remote claim** (the open half is ticket 36)**.** Leases stop a remote claim from wedging a
  ticket, but nothing can confirm a remote agent is alive right now — that
  needs a shared medium updating in real time, which is a server. The
  remaining question is only whether lease durations want tuning per project.
- **A canonical name for a subagent's claim** (ticket 33)**.** Whether a Claude Code
  subagent gets a `CLAUDE_CODE_SESSION_ID` distinct from its parent's was
  never verified — one `echo` from inside a subagent settles it. If it is
  distinct it is the natural `PIDLY_AGENT` value, and the convention gets a
  generated name instead of a hand-written one.
- **Body conventions** (ticket 37)**.** The body is free markdown. Whether acceptance criteria
  deserve structure is open; the trigger is agents guessing wrong about when a
  ticket is done.
