# The Tags tab after the history re-audit (on a scratch copy): amended
# authors and comments in the list and the history, Save as archive by
# the tag's check-in hash, names fossil cannot take (cancel, amend
# --cancel).  Nothing is pushed.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set R $W/tk.fossil
set ::boxes {}
set ::archived {}
proc histops::archive {args} { lappend ::archived $args }
start tags $R 1000x700
tktaalik::show tags; update

# An amended check-in of a tag: its new author and comment.
set uuid [lindex [fossil::sql $R "SELECT b.uuid FROM tagxref x JOIN blob b ON b.rid=x.rid WHERE x.tagtype>0 AND x.tagid=(SELECT tagid FROM tag WHERE tagname='sym-core-9-0-2')"] 0 0]
exec fossil amend $uuid --author zzauthor --comment "zz amended comment" -R $R
tktags::reload; update
set g $tktags::tags(core-9-0-2)
check "list: [dict get $g user], [dict get $g comment]" {[dict get $g user] eq "zzauthor" && [dict get $g comment] eq "zz amended comment"}
tktags::showDetails core-9-0-2
check "history: the amended comment" {[string match "*zz amended comment*" [.tags.main.details.text get 1.0 end]]}

# Save as archive: the check-in by its hash, the name as its label.
set tktags::selected core-9-0-2
tktags::archive
check "archive: $::archived" {[lindex $::archived 0] eq [list $R $uuid core-9-0-2]}

# Names fossil cannot take: cancel said so; amend --cancel leaves them out.
set ::boxes {}
check "cancel -x: refused" {![tagwrite::cancelTag $R -x $uuid]}
check "  said so: $::boxes" {[lindex $::boxes 0] eq "This name cannot be passed to fossil:"}
array set tagwrite::f [list original {user u date d branch b bgcolor {} branchcolor {} comment c} \
    user u date d branch b bgcolor {} branchcolor {} addTags {} close 0 hide 0 noverify 0 \
    comment c cancel,-bad 1 cancel,>x 1 cancel,good 1]
check "amend: only --cancel good: [tagwrite::amendOptions]" {[tagwrite::amendOptions] eq {--cancel good}}
done
