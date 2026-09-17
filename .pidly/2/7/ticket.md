claim:
needs: 1
title: pidly new
desc:14
Allocate the next number, create the directory under the target parent, and
write the four header lines with the schema's required fields stubbed below
the body.

The next number is the highest number anywhere in the tree plus one, closed
tickets included, so there is no counter file. Allocation must hold the
repository lock: mkdir only arbitrates between siblings, and two agents
adding children to different parents would otherwise both take the same
number. Numbers are never reused, which is why there is no delete
operation.
effort: M
area: cli
