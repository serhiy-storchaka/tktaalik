# The Stash tab: whether a stash conflicts with the checkout, checked as
# "fossil stash apply" would do it (the details, the files of the diff,
# Apply's confirmation), and compared with what applying it then does.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
set co $W/co
proc co {args} { fossilIn $::co {*}$args }
proc bytes {path} { set f [open $::co/$path rb]; set b [read $f]; close $f; return $b }
proc write {path bytes} { set f [open $::co/$path wb]; puts -nonewline $f $bytes; close $f }
# The first line of a file replaced, or a line added at its end.
proc firstLine {path text} { write $path [regsub {^[^\n]*} [bytes $path] $text] }
proc lastLine {path text} { write $path "[bytes $path]$text\n" }
proc stash {comment} { co stash save -m $comment; lindex [fossil::checkoutSql $::co "SELECT max(stashid) FROM stash"] 0 0 }

# The stashes, each made on the clean checkout.
firstLine README.md "STASHED README"
set s(conflict) [stash "the same line as the checkout"]
lastLine license.terms "stashed end"
set s(merge) [stash "another line than the checkout"]
write new.txt "stashed\n"; co add new.txt
set s(added) [stash "a new file"]
co rm --hard doc/wish.1
set s(deleted) [stash "a deleted file"]
write tests/red.gif "[bytes tests/red.gif]S"
set s(binary) [stash "a binary file"]
lastLine generic/tkFont.c "/* stashed */"
set s(untouched) [stash "a file the checkout does not change"]
puts "stashes: [array get s]"
# The checkout's own changes.
firstLine README.md "LOCAL README"
firstLine license.terms "LOCAL licence"
write new.txt "local\n"
lastLine doc/wish.1 "local"
write tests/red.gif "[bytes tests/red.gif]L"
puts "changes: [co changes]"

start stash $co 1200x800
set t .stash.main.list.t
foreach {name want} {
    conflict {README.md conflict} merge {} added {new.txt overwrite}
    deleted {doc/wish.1 discard} binary {tests/red.gif conflict} untouched {}
} {
    set got [tkstash::conflicts $s($name)]
    set predicted($name) $got
    check "$name: $got" {$got eq $want}
}

# The details: a line saying so; the files marked in the diff.
set d .stash.main.details.text
set p .stash.main.details.diff
proc shown {id} {
    $::t selection set $id; update
    waitUntil {![dict exists $diffview::data($::p) chan]}
    update
}
shown $s(conflict)
check "details: [lindex [split [$d get 1.0 end-1c] \n] end]" {[string match "*1 file conflicts with*" [$d get 1.0 end]] && [$d tag ranges conflict] ne ""}
set red [lmap i [$p.p.files.t tag has conflict] { $p.p.files.t set $i file }]
check "the diff's files: README.md in red ($red)" {$red eq "README.md"}
shown $s(added)
set orange [lmap i [$p.p.files.t tag has warn] { $p.p.files.t set $i file }]
check "overwritten: in orange ($orange), said so" {$orange eq "new.txt" && [string match "*overwrite*" [$d get 1.0 end]]}
shown $s(untouched)
check "untouched: applies without conflicts" {[string match "*without conflicts*" [$d get 1.0 end]] && [$p.p.files.t tag has conflict] eq "" && [$p.p.files.t tag has warn] eq ""}
shown $s(merge)
check "another line: no conflict" {[string match "*without conflicts*" [$d get 1.0 end]]}

# Against the checkout: the checkout's own line shown as removed; the
# conflict marks kept when switched (not only when selected again); the
# setting saved.
proc diffText {} { join [lmap f [dict get $diffview::data($::p) files] { lindex $f 2 }] \n }
proc red {} { lmap i [$::p.p.files.t tag has conflict] { $::p.p.files.t set $i file } }
proc switchDiff {} {
    .stash.main.details.diff.bar.against invoke
    waitUntil {![dict exists $diffview::data($::p) chan]}
    update
}
check "the stash's changes: not the checkout's line" {[string match "*stashed end*" [diffText]] && ![string match "*LOCAL licence*" [diffText]]}
switchDiff
check "against the checkout: [dict get $diffview::data($p) command]" {[dict get $diffview::data($p) command] eq {fossil stash diff} && [string match "*-LOCAL licence*" [diffText]] && [string match "*+stashed end*" [diffText]]}
shown $s(conflict)
switchDiff
check "switched back: README.md in red ([red])" {[dict get $diffview::data($p) command] eq {fossil stash show} && [red] eq "README.md"}
switchDiff
check "switched again: README.md in red ([red])" {[dict get $diffview::data($p) command] eq {fossil stash diff} && [red] eq "README.md"}
tkstash::saveConfig
check "kept in the settings" {[dict get [config::get $tkstash::configFile stash tkstash.conf] against] == 1}
switchDiff

# Apply's confirmation names them; answered No, nothing applied.
set ::answer no
foreach {name file} {conflict README.md deleted doc/wish.1} {
    shown $s($name)
    set ::boxes {}
    tkstash::applyStash
    set box [lindex $::details end]
    check "Apply of $name names $file: [string range $box 0 300]" {[string match "*$file*" $box] && [regexp {Conflicts with|Deleted, with} $box]}
}
check "not applied" {[string match "*LOCAL README*" [bytes README.md]]}

# What applying them then does (undone after each): as checked.
foreach {name file} {conflict README.md merge license.terms binary tests/red.gif} {
    set before [bytes $file]
    set out [co stash apply $s($name)]
    set conflicts [lmap {- f} [regexp -all -inline -line {^CONFLICT (.*)$} $out] { set f }]
    set want [dict keys [dict filter $predicted($name) value conflict]]
    check "applied $name: conflicts [list $conflicts], as checked" {$conflicts eq $want}
    co undo
    check "undone: $file as it was" {[bytes $file] eq $before}
}
set out [co stash apply $s(added)]
check "applied added: new.txt overwritten, as checked" {[bytes new.txt] eq "stashed\n"}
co undo
write new.txt "local\n"
set out [co stash apply $s(deleted)]
check "applied deleted: doc/wish.1 deleted with its change, as checked" {![file exists $co/doc/wish.1]}
co undo
done
