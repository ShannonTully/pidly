# pidly

A file-based issue tracker that needs no server, no database, and no install.

Everything lives in a `.pidly/` directory at your project root. Every ticket is
a directory; nesting a ticket inside another makes it a subtask. Identity,
parentage, and state are carried by the filesystem, so you can read, navigate,
and edit the whole tracker with `ls`, `cat`, and your editor — and so can an
agent, with `find` and `sed`, on a machine where pidly was never installed.

The name comes from how claiming works: an agent that picks up a ticket writes
its **pid** onto it, so you can tell a live claim from one left behind by an
agent that died. Agents with no local process — cloud sessions, CI jobs —
carry a lease with an expiry instead.

```
.pidly/
  schema          # the project's own fields
  .n/             # every number ever issued, so none is reused
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
extension either, since the content is three header lines, then fields, then a
body, which no renderer understands. `info` can't be mistaken for a ticket number, so
`find .pidly -name info` lists every ticket and `find .pidly -name 8` finds
exactly one.

**State is location.** A ticket is open if it sits directly in its container,
closed if it sits in that container's `c/`. Closing is a move, at every depth.
Nothing else records it, so nothing else can disagree with it.

**Names are one number, never reused.** Parentage is the path, not the name, so
`.pidly/1/3/8/` is ticket 8 under 3 under 1. `find .pidly -name 8` locates it
and shows its ancestry in the same breath. Because the name never changes, a
`8` written in a commit message today still resolves after the ticket is
re-parented or closed.

The next number is the highest ever issued plus one. Nothing holds a counter
to keep current: `.pidly/.n/` has a file per number issued, written once and
never changed, and the highest of those and of the tree is the answer. The
registry is there for merges — two branches that both issue 5 write
`.n/5` with different content, so git stops on a conflict naming the number
instead of quietly merging two tickets 5. It is committed, not ignored.

## The ticket file

```
claim:
needs: 1 4
title: Write the pidly shell script
created: 2026-09-16T21:43:59Z
updated: 2026-09-17T08:02:11Z
effort: L
area: cli

A single POSIX shell script providing the ergonomics layer over the
format. Every command must be something a person could have done by hand.
```

Three fixed header lines, then pidly's `created` and `updated` stamps and
whatever fields your `.pidly/schema` declares, then a blank line, then the
body to the end of the file. Lines 1 and 2 are the status pair: an agent
deciding what to pick up reads those two and nothing else, so *what can I
start right now?* never opens a body. Nothing records where the body starts
or ends, so editing one needs no bookkeeping.

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

Early, but whole. The format is settled and the script implements every
command it is meant to have — `init`, `new`, `claim`, `release`, `status`,
`reap`, `edit`, `set`, `needs`, `fields`, `close`, `reopen`, `reparent`,
`list`, `field`, `show`, `tree`, `check`, `agents`, `claude`, `man`,
`migrate` — each
of them something a person could have done with `mkdir`, `mv` and an editor.
See [docs/DESIGN.md](docs/DESIGN.md) for the layout, the reasoning behind it,
and the questions still open. The work itself is tracked in `.pidly/`, using
pidly.

## Installing

pidly is one POSIX shell script with no build step and no dependencies beyond
the usual coreutils and an optional `git`. Put it on your `PATH`:

```sh
curl -o ~/.local/bin/pidly \
    https://raw.githubusercontent.com/ShannonTully/pidly/main/bin/pidly
chmod +x ~/.local/bin/pidly
pidly --version
```

A Homebrew formula and an AUR PKGBUILD are kept in `packaging/`, ready to
submit but not yet published.

Copying it into a repository that wants it works just as well — the script
carries its own licence line and its own version, so a vendored copy answers
for itself.

Installing is convenience and discoverability, never capability. Nothing in
pidly requires pidly: the tracker is files, every command is something you
could do with `find`, `sed` and `mv`, and both generated documents say how. A
checkout where pidly is not installed is fully usable by hand, and by an agent.

## Getting started

```sh
pidly init            # creates .pidly/, seeds a schema, installs the docs
pidly new "The first thing to do"
```

Re-running `init` refreshes what it generates and leaves `.pidly/schema` alone
once the project owns it, so it is safe after an upgrade. Ignore rules go in
`.pidly/.gitignore` rather than the repo root, so the tracker is
self-contained.

## Telling agents about it

```sh
pidly agents          # writes a section into AGENTS.md, CLAUDE.md, ...
pidly agents -f docs/AGENTS.md
```

This writes two things: a short summary into `AGENTS.md`, between
`<!-- pidly:begin -->` and `<!-- pidly:end -->` so re-running updates it in
place and leaves the rest of the file alone; and `.pidly/README.md`, a fuller
reference the summary points at.

The split is by reading frequency. The summary is in every agent's context,
so it is kept to a budget the tests enforce. The reference is read when a rule
is actually needed. Both explain the format before the commands, so they still
work for an agent in a checkout where pidly isn't installed — and both ship
inside the tracker, since a project using pidly doesn't have this repo's
design document.

For Claude Code, `pidly claude` adds a skill, `/pidly-next`, `/pidly-mine`
and `/pidly-drop`, and a permissions block that allows the read-only
commands. `pidly check` notices when any of these generated files have
drifted from what this version of pidly would write.

## Tests

```sh
./tests/run.sh
PIDLY_TEST_RACE=64 ./tests/run.sh    # hammer the locking harder
```

The concurrency suites fork a process per racer, and how many a machine
tolerates is a property of the machine. `PIDLY_TEST_RACE` sets it: an
exported value wins, then `.env` at the repo root, then the default of 32.
Copy `.env.example` to `.env` and turn it down if your environment cannot
fork widely — `.env` is gitignored, because the limitation belongs to one
machine rather than to the project.

## Reading the tracker

These are the primitives the script wraps. They are also the fallback: in a
checkout where pidly was never installed, this is the whole interface.

```sh
# every open ticket, at any depth, never descending into finished work
find .pidly -type d -name c -prune -o -name info -print

# what can I start right now? — the header and fields, no bodies read
find .pidly -type d -name c -prune -o -name info -print |
  while read -r f; do
    [ -n "$(sed -n '1s/^claim://p' "$f")" ] && continue     # claimed*
    awk '$0 == "" { exit } /^defer: *[^ ]/ { found = 1 } END { exit !found }' \
      "$f" && continue                                       # deferred
    for dep in $(sed -n '2s/^needs://p' "$f"); do
      case "$(find .pidly -type d -name "$dep")" in
        */c/*) ;; *) continue 2 ;;                           # blocked
      esac
    done
    printf '%s\t%s\n' "$(basename "$(dirname "$f")")" \
      "$(sed -n '3s/^title: //p' "$f")"
  done
# * A claim whose lease has expired is free to take, which this loop cannot
#   tell from a live one; `pidly status N` can, and `pidly list` does.

# the body of one ticket, exactly
f=.pidly/2/info; awk 'b { print } !b && $0 == "" { b = 1 }' "$f"

# its project fields
awk 'NR>3 { if ($0 == "") exit; print }' "$f"

# claim it, and ask who holds one
pidly claim 7
pidly status 7

# a cloud agent, which has no pid anyone here can check, leases instead
PIDLY_AGENT=ci-run-4821 PIDLY_LEASE=2h pidly claim 7   # a name you pick

# close a ticket: empty its claim, then move it into its container's c/
sed '1s/.*/claim:/' .pidly/2/info > t && mv t .pidly/2/info
mkdir -p .pidly/c && mv .pidly/2 .pidly/c/
```

Names are unpadded, so `ls` sorts them lexically (`1, 10, 2`). Pipe through
`sort -n` when you want numeric order; `find` itself promises no order at all.

Claiming is the one thing not safe to do by hand while other agents are
running: rewriting a line is read-modify-write, so two agents can both take a
free ticket and the loser never finds out. `pidly claim` serializes it behind a
lock directory. Everything else above is exactly what the script does.

## Releasing

For whoever cuts one. There is nothing to build: a release is a tag and the
script at that tag.

```sh
# 1. bump VERSION in bin/pidly — it is the only place a version is recorded
# 2. the generated documents quote the usage text, so refresh them
pidly agents
pidly man > docs/pidly.1
pidly check                   # must be clean, and says so if they drifted
./tests/run.sh

# 3. tag it, and let the forge build the tarball
git tag -a v0.1.0 -m 'pidly 0.1.0'
git push origin v0.1.0

# 4. the checksum a formula or PKGBUILD will want
curl -sL https://github.com/ShannonTully/pidly/archive/refs/tags/v0.1.0.tar.gz |
    shasum -a 256
```

The recipes in `packaging/` follow the script. With the version bumped in step
1, change it in the formula's `url`, in `pkgver` in the PKGBUILD and in
`.SRCINFO` too (putting `pkgrel` back to 1), then run `./tests/packaging.sh`,
which fails until all of them name the script's VERSION. After step 4, put the
checksum into the formula's `sha256`, the PKGBUILD's `sha256sums` and
`.SRCINFO`. Before that it is `UNRELEASED`, which brew and makepkg both refuse,
so an unreleased recipe cannot be installed by mistake.

Nothing here publishes anything. The formula goes to a `homebrew-pidly` tap
and the PKGBUILD and `.SRCINFO` go to the AUR, and both wait until publishing
is approved. Where `makepkg` is available, `makepkg --printsrcinfo > .SRCINFO`
regenerates `.SRCINFO` rather than you editing it by hand.

Versions are `0.x` until the on-disk schema has been lived with by someone who
did not write it. The tracker itself records no version and never will: that
would be state that can disagree with the files. What a version is for is
letting a person say what they are running, and letting a package name
something — which is why it lives in the script and nowhere else.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the rules the code keeps and the
checks to run, and [CHANGELOG.md](CHANGELOG.md) for what has changed.

## Licence

MIT — see [LICENSE](LICENSE). `bin/pidly` carries an `SPDX-License-Identifier`
line of its own, so a copy vendored into another repository still says what it
is.
