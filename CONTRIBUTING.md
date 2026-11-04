# Contributing to pidly

Thanks for looking. pidly is small on purpose, and most of what makes a
change acceptable follows from that.

## The rules the code keeps

- **POSIX sh and the POSIX tools, nothing else.** No bashisms, no GNU-only
  flags to `find`, `sed`, `awk`, `sort`, `wc` or `date`. The script has to
  run unchanged on Linux (mawk or gawk) and macOS (BSD userland).
  `tests/portable.sh` catches the common slips; CI runs the suites on
  Ubuntu, under gawk, and on macOS.
- **Every command is something a person could do by hand** with `mkdir`, `mv`
  and an editor, leaving the repository byte-identical. If a change needs
  state the files do not already carry, it is probably a format change, and
  belongs in an issue or a ticket before it becomes a patch.
- **Generated files are generated.** `AGENTS.md`'s pidly block,
  `.pidly/README.md`, `.claude/` and `docs/pidly.1` all come from
  `bin/pidly`. Edit the generator, then regenerate:

  ```sh
  bin/pidly agents
  bin/pidly claude
  bin/pidly man > docs/pidly.1
  ```

## Before you send a change

```sh
./tests/run.sh          # every suite; PIDLY_TEST_RACE=8 if your machine forks poorly
bin/pidly check         # the tracker and the generated files are in step
shellcheck -S warning bin/pidly tests/*.sh    # settings are in .shellcheckrc
```

A bug fix wants a test that failed before it. A new suite is any `tests/*.sh`
other than `run.sh`, `lib.sh` and `config.sh`; `run.sh` finds it without
being told.

## Where the work is tracked

pidly tracks its own work in `.pidly/`, using pidly. `bin/pidly list` shows
what is ready to pick up, and each ticket's `info` explains itself.
`AGENTS.md` and `.pidly/README.md` describe the workflow; `docs/DESIGN.md`
has the reasoning behind the format and the questions still open.

GitHub issues and pull requests are welcome too — you do not need to learn
the tracker to report a bug. A pull request that fixes a ticket can say so
in its commit message by number (`79: ...`), which is the convention the
history follows.

## Licence

By contributing you agree that your contribution is licensed under the MIT
licence in [LICENSE](LICENSE).
