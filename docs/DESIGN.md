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
   machine format that can drift from the source of truth. `desc:` is the one
   deliberate exception, and the ticket-file section explains what bought it.

## Layout

```
.pidly/
  schema.md       # the ticket schema for this project
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

`info` has no extension because the content isn't any established format: four
header lines, a markdown body, then fields. Calling it `.md` would promise a
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

**Reopening cascades upward.** Moving a ticket out of its container's `c/` is
only half the job: if that container is itself closed, a closed tree now holds
live work. So reopening a ticket reopens every closed ancestor between it and
the surface, one `mv` per level.

That isn't a mechanical wart, it's the right answer. If subtask 4 needs redoing
then its parent isn't finished either, and neither is the root above it. The
constraint the filesystem imposes and the constraint the work imposes are the
same one.

Reopening does *not* cascade downward: a reopened parent keeps its finished
children in its `c/`. And a reopened ticket does not reopen tickets that
`needs` it — dependencies constrain when work may *start*, not whether
completed work stays completed.

What's lost by dropping the marker file is the timestamp and one-line
resolution it used to carry. Git records when the move happened and in which
commit, which covers the common case; a project that wants a written resolution
can add it as a schema field.

## Names

**A ticket's name is one number, unique across the whole project, never
zero-padded and never reused.** Parentage is not in the name; it's the path.

The path is readable as lineage because every segment except `c` is a ticket:
`.pidly/1/3/8/` is ticket 8 under 3 under 1. `find .pidly -name 8` locates it
in one command, and the answer shows you its ancestry for free.

**There is no counter file.** The next number is the highest number anywhere in
the tree plus one, closed tickets included. Nothing to read, nothing to write,
nothing that can drift from the directories it describes.

Allocation is the one operation that needs the repository lock (see Claims).
`mkdir` arbitrates only between siblings, so two agents adding children to
*different* parents would otherwise both take the same number and both succeed.
Allocation is rare and the lock is held for microseconds.

Two consequences:

- **Numbers are never reused, so there is no delete.** Finishing a ticket means
  closing it, and a closed ticket stays in the tree inside a `c/`, which is what
  keeps the maximum monotonic. Hard-deleting one would let its number be handed
  out again to a different ticket.
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

Four header lines, then the body, then any project fields.

```
claim:
needs: 1 4
title: Write the pidly shell script
desc:10
A single POSIX shell script providing the ergonomics layer over the format.
Not a runtime dependency: every command must be something a person could
have done by hand with mkdir, mv, and an editor.

Subcommands are broken out as child tickets.
effort: L
area: cli
```

The header is fixed-position on purpose, and the order falls out of how much a
reader needs:

| want | read |
|---|---|
| can I take this? | `sed -n 1,2p` |
| a listing line | `sed -n 3p` |
| the body | `sed -n "5,${desc}p"` |
| project fields | `tail -n +$((desc+1))` |

The first two lines are the status pair and the next two are the content pair.
An agent deciding what to work on needs only `claim:` and `needs:`, so the
scheduling question — *what can I start right now?* — is answered by two lines
per ticket and never touches a body. Add line 3 and you have a full listing.

`desc:` holds the absolute line number of the body's last line, so every one of
those reads is exact — no scanning for a delimiter, and no risk of a body that
happens to contain the delimiter breaking the parse.

Title is a human title, not the number; the number is the directory name and
would be redundant here.

**The cost is real: `desc:` is derived data living inside the file it
describes.** Edit the body by hand and the header starts lying. Nothing detects
that except `pidly check`, and nothing repairs it except rewriting the line.
This is the one place the format knowingly breaks principle 5, bought with the
bounded reads in the table above. It puts weight on `pidly edit` — the command
exists specifically to keep the number honest — and makes the `desc:` check a
required part of CI rather than a nicety.

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

Blocked-ness is computed without opening any file: locate each dependency with
`find .pidly -name <n>` and check whether its path runs through a `c/`.

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

Line 1 is the claim: `claim:` when free, `claim:<pid>` when held.

The pid is the point. An agent that dies mid-task cannot release what it holds,
and a claim with no liveness information is indistinguishable from active work.
A pid is checkable — `kill -0 <pid>` — so a stale claim is detectable rather
than merely suspicious, and `pidly check` reports claims whose holder is gone.

**Claiming is the one operation the format does not make atomic.** Because the
claim lives inside `info`, taking it is read-modify-write, and two agents
can both see `claim:` and both write their pid, with the loser never finding
out. A separate claim file would have made this free (`set -C` fails when the
file exists) at the cost of another file per ticket.

So claim, release and edit take a transient lock. `mkdir` is the atomic
primitive doing the work either way — it just guards the write now instead of
being the write:

```sh
mkdir "$d/.lock" 2>/dev/null || {          # someone is mid-write
  owner=$(cat "$d/.lock/pid" 2>/dev/null)
  kill -0 "$owner" 2>/dev/null && return 1 # live holder: back off
  rm -rf "$d/.lock"                        # dead holder: break it
  mkdir "$d/.lock" 2>/dev/null || return 1
}
echo $$ > "$d/.lock/pid"
# ... read line 1, decide, rewrite line 1 ...
rm -rf "$d/.lock"
```

Three properties matter. The lock is **transient** — held for the microseconds
of a `sed`, so a repository at rest still has exactly one file per ticket. It is
**self-healing**: the holder's pid inside it means an agent that crashes
mid-write doesn't wedge the ticket forever, since the next caller sees a dead
owner and breaks the lock. And that recovery is **the same idiom as stale claim
detection**, so the system has one liveness mechanism rather than two.

The same lock, at `.pidly/.lock`, serializes number allocation.

### Whose pid is it

Because the claim is in a tracked file, claims are committed whether or not
that's wanted, and a pid from another machine will be checked against the local
process table. A bare pid is therefore worse than useless across machines: it
can match an unrelated live local process and report a dead agent as working.

So line 1 is `claim:<pid>@<id>`, and `<id>` identifies the checkout.

`<id>` is **not** the hostname. On the machine this design was written,
`hostname` returns `localhost` — a value shared by an unbounded number of other
machines, which is exactly the collision the field exists to prevent. Instead,
`.pidly/.id` holds a random string generated on first use and is gitignored, so
every checkout has an identity that is unique by construction and never travels
in a commit.

The rule that follows is short: **a claim whose `@<id>` is not the local one is
unverifiable, not stale.** Liveness cannot be checked across machines at all, so
the honest answer is to report the claim as foreign and leave it alone. Without
the id, that case is indistinguishable from a local claim and the tool
confidently gives a wrong answer.

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

`.pidly/schema.md` defines the fields for this project. It's markdown with a
table, because the file has two audiences and a table serves both: a human reads
it as documentation, an agent reads it as a spec, and no one needs a TOML or
JSON parser in bash to use it.

```markdown
# Ticket schema

| field | required | values |
|---|---|---|
| title | yes | free text |
| effort | no | S, M, L |
| area | no | free text |
```

`claim`, `needs`, `title` and `desc` are structural and always present, in that
order. Everything else is schema, lives after the body, and is validated by
`pidly check` rather than by the format — a ticket missing a required field is
still a readable ticket.

**Priority is a project field, not a structural one.** The header earns its
fixed positions by answering *can I start this?* in two lines, and priority
doesn't help with that — it answers *which of these should I pick?*, a sort over
candidates that have already survived the filter. That set is small, so reading
past the body of each one is cheap, and projects that don't want priority pay
nothing for it. Every structural line is a cost every ticket carries forever.

This remains the weakest part of the design: a markdown table is parseable by
`awk` in a pinch, but only while the schema stays flat key/value.

## Why this shape suits agents

The tree is the work breakdown, so it's also the delegation graph. A lead agent
claims `1` by writing its pid to line 1 of `.pidly/1/info`. Each child
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

`pidly` is a POSIX shell script — `new`, `claim`, `release`, `close`, `reopen`,
`edit`, `list`, `tree`, `check`, `reap`. It is not a runtime dependency of the
format; it's an ergonomics layer. The acceptance test for every command is that
a person could have done the same thing with `mkdir`, `mv`, and a text editor,
and the repository would be byte-identical.

Two carve-outs. `edit` exists because `desc:` is derived data that a hand-edit
can falsify. And claiming is the single operation that is *not* safe to do by
hand while other agents are running, because it needs the lock — one function's
worth of shell, and the price of having the claim on line 1 rather than in a
file of its own.

## Deferred

Nothing above is unsettled. These are things consciously not solved yet, with
the trigger that would force each one.

- **Priority.** Decided as a project field. Revisit only if picking among
  unblocked tickets turns out to need a sort that reads every candidate's
  fields often enough to show up — at which point it becomes a fifth header
  line, not a fifth opinion.
- **The schema table.** A markdown table is parseable by `awk` in a pinch, but
  only while the schema stays flat key/value. Enums with per-value behaviour
  would outgrow it and force a real config format, which would cost the
  zero-parser property.
- **Multi-machine claims.** `@<id>` makes a foreign claim *recognizable*, which
  is enough to stop wrong answers. It does not make one *checkable* — that
  would need agents to publish liveness somewhere shared, which is a server,
  which is the thing this project doesn't have. If distributed teams ever need
  it, the answer is probably a heartbeat timestamp rather than a pid.
- **Body conventions.** The body is free markdown. Whether acceptance criteria
  deserve structure is open; the trigger is agents guessing wrong about when a
  ticket is done.
