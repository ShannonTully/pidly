# Editing files in place, portably. Sourced by the suites that fabricate a
# damaged ticket to see what pidly says about it.
#
# GNU sed takes -i with no argument and BSD sed requires one, so there is no
# spelling of `sed -i` that runs on both. A temp file and a mv is what the
# script itself does for the same reason, and it works everywhere.

# sedi 'SCRIPT' FILE — sed -i, with the file as the last argument as usual.
sedi() {
	for _li_f in "$@"; do :; done          # the last argument is the file
	sed "$@" > "$_li_f.sedi" && mv "$_li_f.sedi" "$_li_f"
}

# insert_after LINE FILE TEXT... — put each TEXT on its own line after line
# LINE. POSIX sed's a command wants a backslash and a real newline, and the
# one-line "3a text" form is GNU only.
insert_after() {
	_li_n=$1 _li_t=$2; shift 2
	{ head -n "$_li_n" "$_li_t"
	  printf '%s\n' "$@"
	  sed -n "$((_li_n + 1)),\$p" "$_li_t"
	} > "$_li_t.ins" && mv "$_li_t.ins" "$_li_t"
}

# delete_stanza NAME FILE — drop a schema stanza whole: its field: line and
# everything up to the blank line that closes it. sed's addr,+N is GNU only.
delete_stanza() {
	awk -v n="$1" '
		$1 == "field:" && $2 == n { drop = 1; next }
		drop && $0 == "" { drop = 0; next }
		drop { next }
		{ print }' "$2" > "$2.stz" && mv "$2.stz" "$2"
}
