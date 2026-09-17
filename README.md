# pidly

A file-based issue tracker that needs no server, no database, and no install.

Everything lives in a `.pidly/` directory at your project root. Every ticket is
a directory; nesting a ticket inside another makes it a subtask. Identity,
parentage, and state are carried by the filesystem, so you can read, navigate,
and edit the whole tracker with `ls`, `cat`, and your editor — and so can an
agent, with `find` and `sed`, on a machine where pidly was never installed.

The name comes from how claiming works: an agent that picks up a ticket writes
its **pid** onto it, so you can tell a live claim from one left behind by an
agent that died.

```
.pidly/
  schema.md
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
```

What's known about a ticket lives in the file `info` inside its directory. Not
`ticket` — the *directory* is the ticket, and it carries the identity, the
position, the children and the state; the file just holds the information. No
extension either, since the content is four header lines, a body, then fields,
which no renderer understands. `info` can't be mistaken for a ticket number, so
`find .pidly -name info` lists every ticket and `find .pidly -name 8` finds
exactly one.

**State is location.** A ticket is open if it sits directly in its container,
closed if it sits in that container's `c/`. Closing is a move, at every depth.
Nothing else records it, so nothing else can disagree with it.

**Names are one number, never reused.** Parentage is the path, not the name, so
`.pidly/1/3/8/` is ticket 8 under 3 under 1. `find .pidly -name 8` locates it
and shows its ancestry in the same breath. Because the name never changes, a
`8` written in a commit message today still resolves after the ticket is
re-parented or closed. There's no counter file — the next number is the highest
in the tree plus one.

## The ticket file

```
claim:
needs: 1 4
title: Write the pidly shell script
desc:7
A single POSIX shell script providing the ergonomics layer over the
format. Every command must be something a person could have done by hand.
effort: L
area: cli
```

Four fixed header lines, then the body, then your own fields. Lines 1 and 2 are
the status pair: an agent deciding what to pick up reads those two and nothing
else, so *what can I start right now?* never opens a body. `desc:` is the
absolute line number where the body ends, so the body and the project fields
are each one exact read when they're actually wanted.

`needs:` lists ticket numbers that must be closed first. It references numbers
rather than paths because numbers are permanent and paths aren't — a `needs: 7`
still resolves after 7 has been closed and re-parented.

## Why

Issue trackers either want a server or want a database file you can't read.
Neither survives being handed to someone else — or to someone else's agent —
as a folder. pidly's constraint is that the repository is the interface: if the
tooling vanished, nothing would be lost, because there was never anything but
files.

## Status

Early. The design is settled enough to build against — see
[docs/DESIGN.md](docs/DESIGN.md) for the layout, the reasoning behind it, and
the questions still open. The work itself is tracked in `.pidly/`, using pidly.

## Reading the tracker

Until the `pidly` script exists, these are the primitives it will wrap:

```sh
# every open ticket, at any depth, never descending into finished work
find .pidly -type d -name c -prune -o -name info -print

# what can I start right now? — two lines per ticket, no bodies read
find .pidly -type d -name c -prune -o -name info -print | sort -V |
  while read -r f; do
    [ -n "$(sed -n '1s/^claim://p' "$f")" ] && continue     # already claimed
    for dep in $(sed -n '2s/^needs://p' "$f"); do
      case "$(find .pidly -type d -name "$dep")" in
        */c/*) ;; *) continue 2 ;;
      esac
    done
    printf '%s\t%s\n' "$(basename "$(dirname "$f")")" \
      "$(sed -n '3s/^title: //p' "$f")"
  done

# the body of one ticket, exactly
f=.pidly/2/info; n=$(sed -n '4s/^desc://p' "$f"); sed -n "5,${n}p" "$f"

# its custom fields
tail -n +$((n+1)) "$f"

# claim it (pidly takes a lock around this; by hand, just don't race)
sed -i "1s/.*/claim:$$@$(cat .pidly/.id)/" .pidly/2/info

# is a claim still alive? (only answerable for claims from this checkout)
c=$(sed -n '1s/^claim://p' .pidly/2/info)
[ "${c#*@}" = "$(cat .pidly/.id)" ] &&
  { kill -0 "${c%@*}" 2>/dev/null && echo live || echo dead; } ||
  echo "foreign claim — cannot check"

# close a ticket: move it into its container's c/
mkdir -p .pidly/c && mv .pidly/2 .pidly/c/
```

Names are unpadded, so `ls` sorts them lexically (`1, 10, 2`). Use `ls -v` or
`sort -V` when you want numeric order.

Claiming is the one thing not safe to do by hand while other agents are
running: rewriting a line is read-modify-write, so two agents can both take a
free ticket and the loser never finds out. `pidly claim` serializes it behind a
lock directory. Everything else above is exactly what the script does.
