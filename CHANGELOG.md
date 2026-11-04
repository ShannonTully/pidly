# Changelog

What changed between released versions of pidly. Numbers in parentheses are
tickets in `.pidly/`; `pidly show N` reads one. Versions stay `0.x` until the
on-disk format has been lived with by someone who did not write it.

## Unreleased

- `pidly man` and `migrate` no longer depend on how a particular awk reads
  backslashes in a `gsub` replacement, so the man page and imports come out
  the same under mawk, gawk and BSD awk (79).
- `init` reports its counts without BSD `wc`'s padding (87).
- A claim's start time is read from after the last `)` in `/proc/PID/stat`,
  so a command name with a space in it no longer shifts it (67), and on
  systems without `/proc` it comes from `ps`, so a recycled pid is caught
  there too (66).
- The tests run in CI on Linux and macOS, under gawk too, with shellcheck;
  `tests/run.sh` finds its suites instead of listing them (68).
- Documentation brought back in line with the tool: every command is listed,
  the README's by-hand idioms are portable and skip deferred tickets, and
  `VISUAL`, `EDITOR`, `TMPDIR` and the exit statuses are documented (70).
- The AUR recipe depends on any `awk`, not specifically gawk (71).

## 0.1.0

The first version: the on-disk format, and a single POSIX shell script that
implements every command — `init`, `new`, `claim`, `release`, `status`,
`reap`, `edit`, `set`, `needs`, `fields`, `close`, `reopen`, `reparent`,
`list`, `field`, `show`, `tree`, `check`, `agents`, `claude`, `man` and
`migrate`.
