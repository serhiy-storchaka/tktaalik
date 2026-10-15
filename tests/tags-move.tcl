# Moving a tag to the newest check-in of its branch (Tags tab): which tags
# can move, the dialog, both dry runs in one question; the tag on the tip
# with its value, cancelled on the old check-in unless kept.  On a scratch
# copy; nothing is pushed.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set R $W/tk.fossil
set ::confirms {}
proc tagwrite::confirm {title message text args} { lappend ::confirms [list $message $text]; return 1 }
# The newest check-ins of main: the tip, and two older ones.
set main [lmap r [fossil::sql $R "SELECT b.uuid FROM tagxref x JOIN event e ON e.objid=x.rid
    JOIN blob b ON b.rid=x.rid WHERE x.tagid=(SELECT tagid FROM tag WHERE tagname='branch')
    AND x.tagtype>0 AND x.value='main' ORDER BY e.mtime DESC LIMIT 4"] { lindex $r 0 }]
lassign $main tip c1 c2 c3
exec fossil tag add qmoved $c1 v1 -R $R
exec fossil tag add qkept $c2 -R $R
exec fossil tag add qontip $tip -R $R
exec fossil tag add qtwo $c2 -R $R
exec fossil tag add qtwo $c3 -R $R
exec fossil tag add --propagate qprop $c3 -R $R
start tags $R 1000x700
tktaalik::show tags; update
set t .tags.main.list.t
proc select {name} { $::t selection set [list $name]; update }
proc tagOn {name uuid} {
    lindex [fossil::sql $::R "SELECT x.tagtype, [fossil::outcol "coalesce(x.value,'')"] FROM tagxref x
        JOIN blob b ON b.rid=x.rid WHERE b.uuid='$uuid' AND x.origid=x.rid
        AND x.tagid=(SELECT tagid FROM tag WHERE tagname='sym-$name')"] 0
}

# Which can move.
select qmoved
check "qmoved: Move enabled" {[.tags.b.move instate !disabled]}
set m [menu .tagmenu -tearoff 0]
tktags::popupMenu $m qmoved
check "menu: Move to the tip of main" {![catch {$m index "Move to the tip of main…"}]}
destroy $m
foreach {name why} {qontip "already on" qtwo "on 2 check-ins" qprop "propagates"} {
    select $name
    check "$name: Move disabled ([tktags::unmovable $name])" {[.tags.b.move instate disabled] && [string match *$why* [tktags::unmovable $name]]}
}
.tags.top.branches invoke; update
select main
check "a branch name: Move disabled" {[.tags.b.move instate disabled] && [tktags::unmovable main] eq "a branch name"}
.tags.top.branches invoke; update

# Move qmoved: the dialog shows where, with the value; both dry runs asked.
select qmoved
whenOpen .tagwrite {
    set ::dialogText [.tagwrite.f.l cget -text]
    set ::dialogValue $tagwrite::f(value)
    set ::dialogHelp [help::context .tagwrite.f.v]
    set tagwrite::answer 1
}
tktags::moveTag; update
check "dialog: from $c1, to the tip of main: [list $::dialogText]" {[string match "*[string range $c1 0 9]*the tip of main, [string range $tip 0 9]*" $::dialogText]}
check "dialog: the value v1" {$::dialogValue eq "v1"}
set f [open [file join [file dirname [info script]] .. docs tags.md]]
fconfigure $f -encoding utf-8
set doc [read $f]
close $f
set slugs [lmap l [split $doc \n] {
    if {![regexp {^#+ (.*)} $l -> h]} continue
    help::slug $h
}]
check "dialog: F1 is $::dialogHelp" {$::dialogHelp eq "tags#move" && "move" in $slugs}
lassign [lindex $::confirms end] message text
check "asked: $message" {$message eq "Move qmoved to the tip of main?" && [string match "*fossil tag add qmoved $tip v1*fossil tag cancel qmoved $c1*" $text]}
check "on the tip, with v1: [tagOn qmoved $tip]" {[tagOn qmoved $tip] eq {1 v1}}
check "cancelled on the old one: [tagOn qmoved $c1]" {[lindex [tagOn qmoved $c1] 0] eq "0"}
check "the name is the tip's" {[string match "*[string range $tip 0 15]*" [exec fossil info qmoved -R $R]]}
check "still selected, now not movable" {[$t selection] eq "qmoved" && [.tags.b.move instate disabled]}
set d [.tags.main.details.text get 1.0 end]
check "history: added to the tip, cancelled on the old one" {[string match "*added to [string range $tip 0 9]*" $d] && [string match "*cancelled on [string range $c1 0 9]*" $d]}

# Keep it on the old one too.
select qkept
whenOpen .tagwrite { set tagwrite::f(keep) 1; set tagwrite::answer 1 }
tktags::moveTag; update
lassign [lindex $::confirms end] message text
check "kept: asked to add only: $message" {$message eq "Add qkept to the tip of main as well?" && ![string match "*cancel*" $text]}
check "kept: on both" {[lindex [tagOn qkept $tip] 0] eq "1" && [lindex [tagOn qkept $c2] 0] eq "1"}

# Cancelled in the dialog: nothing changes.
exec fossil tag add qstays $c1 -R $R
tktags::reload; update
select qstays
set n [llength $::confirms]
whenOpen .tagwrite { set tagwrite::answer 0 }
tktags::moveTag; update
check "cancelled: not asked, not moved" {[llength $::confirms] == $n && [tagOn qstays $tip] eq ""}
done
