# Ticket schema

Four header lines are structural and always present, in this order:

| line | field | meaning |
|---|---|---|
| 1 | `claim:` | empty, or the pid of the agent holding the ticket |
| 2 | `needs:` | space-separated ticket numbers that must be closed first |
| 3 | `title:` | a human title, not the number |
| 4 | `desc:` | absolute line number of the body's last line |

The body runs from line 5 to `desc`. Everything after `desc` is a project
field from the table below.

| field  | required | values             |
|--------|----------|--------------------|
| effort | no       | S, M, L            |
| area   | no       | format, cli, docs  |
