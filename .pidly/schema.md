# Ticket schema

Every ticket is a directory; its content is the file `info` inside it.
Three header lines are structural and always present, in this order:

| line | field | meaning |
|---|---|---|
| 1 | `claim:` | empty, or who holds the ticket |
| 2 | `needs:` | space-separated ticket numbers that must be closed first |
| 3 | `title:` | a human title, not the number |

Lines 4 onward are project fields from the table below, ending at the first
blank line. Everything after that blank line is the body, which runs to the
end of the file.

| field   | required | values                        |
|---------|----------|-------------------------------|
| created | no       | ISO-8601 UTC; pidly new writes it |
| updated | no       | ISO-8601 UTC; every pidly write bumps it |
| effort  | no       | S, M, L                       |
| area    | no       | format, cli, docs             |
| handoff | no       | one line: where the last agent got to |
