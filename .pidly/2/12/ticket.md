claim:
needs: 8
title: pidly reap, and checkout identity
desc:13
Generate .pidly/.id on first use: a random string identifying this
checkout, gitignored so it never travels in a commit. Hostname is not
usable for this — it is routinely "localhost", which is precisely the
collision the field exists to prevent.

reap clears claims that are both local (the @id matches this checkout) and
dead (kill -0 fails). It never touches a foreign claim, because the
information needed to judge one does not exist on this machine. check
reports both cases and modifies nothing.
effort: M
area: cli
