# Editing check-ins and their tags (on a scratch copy): "fossil amend"
# from the Timeline (comment, author, date, branch, colours, tags, close,
# hide), adding and cancelling tags from the Timeline and the Tags tab,
# reparent; each after its dry run.  The Tags tab's properties.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set R $W/tk.fossil
set ::boxes {}
start timeline $R 1000x700
tktaalik::show timeline; update
set t .timeline.main.list.t

# Answer the dialogs as they come: STEPS is {condition script} each; a
# script runs once its condition is true (its dialog is up).
set ::shown {}
proc steps {steps} {
    if {![llength $steps]} return
    lassign $steps cond script
    if {![uplevel #0 [list expr $cond]]} {
        after 50 [list steps $steps]
        return
    }
    uplevel #0 $script
    after 50 [list steps [lrange $steps 2 end]]
}
set confirm {[winfo exists .tagwrite.f.t]}
set apply {lappend ::shown [.tagwrite.f.t get 1.0 end]; set tagwrite::answer 1}
set refuse {lappend ::shown [.tagwrite.f.t get 1.0 end]; set tagwrite::answer 0}

# A leaf of a branch of its own (a new one, so that closing it is right).
set tip [lindex [sql "SELECT uuid FROM blob WHERE rid=(SELECT objid FROM event WHERE type='ci' ORDER BY mtime DESC LIMIT 1)"] 0 0]
exec fossil branch new tktaalik-amend $tip -R $R {*}[fossil::nosync branch] 2>@1
set rid [lindex [sql "SELECT x.rid FROM tagxref x JOIN tag t ON t.tagid=x.tagid WHERE t.tagname='sym-tktaalik-amend' AND x.tagtype>0 ORDER BY x.mtime DESC LIMIT 1"] 0 0]
set uuid [lindex [sql "SELECT uuid FROM blob WHERE rid=$rid"] 0 0]
set tktimeline::query hash:[string range $uuid 0 11]; tktimeline::search; after cancel tktimeline::search
check "the branch's check-in shown" {[$t exists $rid]}

# Edit: a new comment (starting with "-"), author, date, colours, a tag,
# close, hide.
steps [list {[winfo exists .tagwrite.f.m]} {
    .tagwrite.f.m delete 1.0 end
    .tagwrite.f.m insert end "-- amended by tktaalik\nsecond line"
    set tagwrite::f(user) tester
    set tagwrite::f(date) "2026-10-01 12:00:00"
    set tagwrite::f(bgcolor) "#ffeedd"
    set tagwrite::f(branchcolor) "#ddeeff"
    set tagwrite::f(addTags) "tk-one tk-two"
    set tagwrite::f(close) 1
    set tagwrite::f(hide) 1
    set tagwrite::answer 1
} {[llength $::boxes]} {
    # (Both colours: refused, Fossil would set only the branch colour.)
    set tagwrite::f(bgcolor) [dict get $tagwrite::f(original) bgcolor]
    set tagwrite::answer 1
} $confirm $apply]
set ::boxes {}
tktimeline::editCheckin $rid
update
check "both colours refused: [lindex $::boxes 0]" {[string match "Change one of the colours*" [lindex $::boxes 0]]}
set art [lindex $::shown end]
check "dry run shown: comment, user, date, tags" {[string match "*T +comment *" $art] && [string match "*+user*tester*" $art] && [string match "*T +date *" $art] && [string match "*+sym-tk-one*" $art] && [string match "*+closed*" $art] && [string match "*hidden*" $art] && ![string match "*#ffeedd*" $art] && [string match "*bgcolor*#ddeeff*" $art]}
set row [lindex [sql "SELECT [fossil::outcol coalesce(ecomment,comment)], coalesce(euser,user), strftime('%Y-%m-%d %H:%M:%S', mtime), bgcolor FROM event WHERE objid=$rid"] 0]
check "amended: [lrange $row 1 end]" {[lindex $row 0] eq "-- amended by tktaalik\nsecond line" && [lindex $row 1] eq "tester" && [lindex $row 2] eq "2026-10-01 12:00:00"}
set tags [lmap r [tktimeline::checkinTags $rid] {lindex $r 0}]
check "tags: $tags" {"tk-one" in $tags && "tk-two" in $tags && "closed" in $tags && "hidden" in $tags}
check "the list shows it again" {[$t exists $rid] && [string match "-- amended*" [$t set $rid comment]]}

# Nothing changed: no command.
set ::boxes {}
steps {{[winfo exists .tagwrite.f.m]} {set tagwrite::answer 1}}
tktimeline::editCheckin $rid
check "nothing changed: said so" {[lindex $::boxes end] eq "Nothing is changed."}

# A bad date: said so, and the dialog stays.
set ::boxes {}
steps {{[winfo exists .tagwrite.f.m]} {set tagwrite::f(date) "yesterday"; set tagwrite::answer 1}
    {[llength $::boxes]} {set tagwrite::answer 0}}
tktimeline::editCheckin $rid
check "bad date: [lindex $::boxes 0]" {[string match "The date*" [lindex $::boxes 0]]}

# Rename the branch from here; cancel a tag with amend.
set ::shown {}
steps [list {[winfo exists .tagwrite.f.m]} {
    set tagwrite::f(branch) tktaalik-renamed
    set tagwrite::f(cancel,tk-two) 1
    set tagwrite::answer 1
} $confirm $apply]
tktimeline::editCheckin $rid
set tags [tktimeline::checkinTags $rid]
check "renamed, tk-two cancelled: [lmap r $tags {lindex $r 0}]" {[lsearch -index 0 $tags tk-two] < 0 && [lsearch -index 0 -inline $tags branch] ne "" && [lindex [lsearch -index 0 -inline $tags branch] 1] eq "tktaalik-renamed"}

# Add a tag with a value from the Timeline, then cancel it (refused once).
set ::shown {}
steps [list {[winfo exists .tagwrite.f.n]} {
    set tagwrite::f(name) tk-valued; set tagwrite::f(value) "some value"; set tagwrite::answer 1
} $confirm $apply]
tktimeline::addTag $rid
set tags [tktimeline::checkinTags $rid]
check "tag add: tk-valued = [lindex [lsearch -index 0 -inline $tags tk-valued] 1]" {[lindex [lsearch -index 0 -inline $tags tk-valued] 1] eq "some value"}
steps [list $confirm $refuse]
tktimeline::cancelTag $rid tk-valued 0
check "cancel refused: still there" {[lsearch -index 0 [tktimeline::checkinTags $rid] tk-valued] >= 0 && [string match "*-sym-tk-valued*" [lindex $::shown end]]}
steps [list $confirm $apply]
tktimeline::cancelTag $rid tk-valued 0
check "cancelled" {[lsearch -index 0 [tktimeline::checkinTags $rid] tk-valued] < 0}

# A propagating tag, a raw one (a property).
steps [list {[winfo exists .tagwrite.f.n]} {
    set tagwrite::f(name) tk-prop; set tagwrite::f(propagate) 1; set tagwrite::answer 1
} $confirm $apply]
tktimeline::addTag $rid
check "propagating: tagtype 2" {[lindex [sql "SELECT tagtype FROM tagxref WHERE rid=$rid AND tagid=(SELECT tagid FROM tag WHERE tagname='sym-tk-prop')"] 0 0] == 2}
steps [list {[winfo exists .tagwrite.f.n]} {
    set tagwrite::f(name) tk-raw; set tagwrite::f(raw) 1; set tagwrite::answer 1
} $confirm $apply]
tktimeline::addTag $rid
check "raw: tk-raw, not sym-tk-raw" {[lindex [sql "SELECT count(*) FROM tag WHERE tagname='tk-raw'"] 0 0] == 1 && [lindex [sql "SELECT count(*) FROM tag WHERE tagname='sym-tk-raw'"] 0 0] == 0}
# Bad names: refused in the dialog.
set ::boxes {}
steps {{[winfo exists .tagwrite.f.n]} {set tagwrite::f(name) "wiki-x"; set tagwrite::answer 1}
    {[llength $::boxes]} {set tagwrite::f(name) "two words"; set tagwrite::answer 1}
    {[llength $::boxes] > 1} {set tagwrite::answer 0}}
tktimeline::addTag $rid
check "bad names: $::boxes" {[string match "*Fossil's own*" [lindex $::boxes 0]] && [string match "*spaces*" [lindex $::boxes 1]]}

# Reparent: the dry run, refused: nothing changed.
set parent [lindex [sql "SELECT uuid FROM blob WHERE rid=(SELECT pid FROM plink WHERE cid=$rid AND isprim)"] 0 0]
set ::shown {}
steps [list {[winfo exists .tagwrite.f.p]} [list set tagwrite::f(parents) $parent] \
    {[winfo exists .tagwrite.f.p]} {set tagwrite::answer 1} $confirm $refuse]
tktimeline::reparent $rid
check "reparent: dry run shows the parent tag, not applied" {[string match "*T +parent*$parent*" [lindex $::shown end]] && [lindex [sql "SELECT count(*) FROM tagxref WHERE rid=$rid AND tagid=(SELECT tagid FROM tag WHERE tagname='parent')"] 0 0] == 0}

# The Tags tab: properties, add a tag, cancel it where it is on two.
tktaalik::show tags; update
set g .tags.main.list.t
.tags.top.properties invoke; update
check "properties: tk-raw, closed, bgcolor" {[$g exists " tk-raw"] && [$g exists " closed"] && [$g exists " bgcolor"] && [$g set " tk-raw" kind] eq "Property"}
$g selection set [list " bgcolor"]; update
check "property history: values" {[string match "*= #ddeeff*" [.tags.main.details.text get 1.0 end]]}
.tags.top.properties invoke; update
set other [lindex [sql "SELECT uuid FROM blob WHERE rid=(SELECT pid FROM plink WHERE cid=$rid AND isprim)"] 0 0]
foreach target [list $uuid $other] {
    steps [list {[winfo exists .tagwrite.f.n]} [list ::apply {{target} {
        set tagwrite::f(name) tk-twice; set tagwrite::f(checkin) $target; set tagwrite::answer 1
    }} $target] $confirm $apply]
    tktags::addTag
}
check "tag on two check-ins: [$g set tk-twice count]" {[$g exists tk-twice] && [$g set tk-twice count] == 2 && [$g selection] eq "tk-twice"}
steps [list {[winfo exists .tagwrite.f.c]} {
    set tktags::choice [lindex [.tagwrite.f.c cget -values] 1]; set tagwrite::answer 1
} $confirm $apply]
tktags::cancelTag
# (The chooser: the newest tagged first; the second is the first tagged.)
check "cancelled on the first tagged: on [$g set tk-twice hash] now" {[$g set tk-twice count] == 1 && [$g set tk-twice hash] eq [string range $other 0 9]}
check "history: on one, cancelled on the other" {[regexp -all "added to [string range $other 0 9]" [.tags.main.details.text get 1.0 end]] == 1 && [regexp -all "cancelled on [string range $uuid 0 9]" [.tags.main.details.text get 1.0 end]] == 1}
done
