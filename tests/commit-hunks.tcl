# The Commit tab: only the hunks ticked in a file's diff are committed (or
# stashed), the rest stays in the checkout, byte for byte (LF and CR/LF
# files, no line end at the end); the snapshot kept meanwhile is dropped.
# On a scratch copy.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
set co $W/co
proc bytes {path} { set f [open $path rb]; set d [read $f]; close $f; return $d }
proc writeBytes {path data} { set f [open $path wb]; puts -nonewline $f $data; close $f }
# (The stash table is made by the first stash.)
proc stashes {} {
    if {[catch {fossil::checkoutSql $::co "SELECT count(*) FROM stash"} rows]} { return 0 }
    lindex $rows 0 0
}
proc lines {n {sep \n} {change {}} {last 1}} {
    set r ""
    for {set i 1} {$i <= $n} {incr i} {
        append r [expr {[dict exists $change $i] ? [dict get $change $i] : "line $i"}]
        if {$i < $n || $last} { append r $sep }
    }
    return $r
}
# Two files committed: 40 lines with LF; 30 with CR/LF, none at the end.
writeBytes $co/hk-a.txt [lines 40]
writeBytes $co/hk-c.txt [lines 30 \r\n {} 0]
fossilIn $co add hk-a.txt hk-c.txt
fossilIn $co commit --nosync --no-warnings -m "hunks: base" hk-a.txt hk-c.txt
set baseA [bytes $co/hk-a.txt]
set baseC [bytes $co/hk-c.txt]
# Three changes far apart in each; the end of hk-c.txt gets a line end.
set workA [lines 40 \n {1 ONE 20 TWENTY 40 FORTY}]
set workC [lines 30 \r\n {2 TWO 15 FIFTEEN 30 THIRTY}]
writeBytes $co/hk-a.txt $workA
writeBytes $co/hk-c.txt $workC

start commit $co 1300x900
set t .commit.main.files.t
set d .commit.main.diff.text
proc show {path} {
    .commit.main.files.t selection set [list $path]
    .commit.main.files.t focus $path
    update
}
proc boxes {} {
    set r ""
    foreach {key value index} [.commit.main.diff.text dump -text 1.0 end] {
        if {$value in {"☑" "☐" "▣"}} { append r $value }
    }
    return $r
}
show hk-a.txt
check "three hunks, ticked: [boxes]" {[boxes] eq "☑☑☑"}
# Only the middle one.
tkcommit::toggleHunk 0
tkcommit::toggleHunk 2
check "the middle one left: [boxes]" {[boxes] eq "☐☑☐"}
check "greyed: [llength [$d tag ranges off]] ranges" {[llength [$d tag ranges off]] == 4}
check "the file in part in the list: [$t set hk-a.txt check]" {[$t set hk-a.txt check] eq "▣"}
check "status: $tkcommit::status" {[string match "*1 of them in part*" $tkcommit::status]}
show hk-c.txt
tkcommit::toggleHunk 0
check "hk-c.txt: [boxes]" {[boxes] eq "☐☑☑"}
# Space on a hunk: ticks it again, and back.
$d mark set insert [lindex [$d tag ranges hk0] 0]
focus -force $d; update
event generate $d <space>; update
check "Space ticks it: [boxes]" {[boxes] eq "☑☑☑"}
event generate $d <space>; update

# No: nothing happens.
.commit.bottom.msg.text insert end "Part of the changes"
set ::answers [dict create yesno no]
set ::boxes {}
tkcommit::commit
check "asked first: [lindex $::boxes end]" {[string match "Only part of 2 files is committed*" [lindex $::boxes end]]}
check "No: the files as they were" {[bytes $co/hk-a.txt] eq $workA && [bytes $co/hk-c.txt] eq $workC}
check "no stash made" {[stashes] == 0}

# The commit refused by Fossil: the files come back, the snapshot goes.
set ::answers [dict create yesno yes]
rename tkcommit::fossil tkcommit::realFossil
proc tkcommit::fossil {args} {
    if {[lindex $args 0] eq "commit"} {
        set ::seen [list [bytes $::co/hk-a.txt] [bytes $::co/hk-c.txt]]
        return {1 "refused for the test"}
    }
    tkcommit::realFossil {*}$args
}
tkcommit::commit
rename tkcommit::fossil ""
rename tkcommit::realFossil tkcommit::fossil
destroy .commit.log
check "refused: written with the part meanwhile" {[lindex $::seen 0] eq [lines 40 \n {20 TWENTY}]}
check "refused: the files back" {[bytes $co/hk-a.txt] eq $workA && [bytes $co/hk-c.txt] eq $workC}
check "refused: the snapshot dropped" {[stashes] == 0}

# Committed: the middle of hk-a.txt, the last two of hk-c.txt.  (Fossil
# would ask about the CR/LF.)
set tkcommit::noWarnings 1
tkcommit::commit
destroy .commit.log
set tip [fossilIn $co info]
regexp -line {^checkout:\s+(\S+)} $tip -> tip
set got [exec fossil cat -R $W/tk.fossil -r $tip hk-a.txt]
check "committed: hk-a.txt with only its middle change" {$got eq [string trimright [lines 40 \n {20 TWENTY}] \n]}
fossil::inDir $co { fossil::runTo $W/got-c cat -r current ./hk-c.txt }
check "committed: hk-c.txt with CR/LF, its last change, the line end at the end" \
    {[bytes $W/got-c] eq [lines 30 \r\n {15 FIFTEEN 30 THIRTY}]}
check "the files still have all the changes" {[bytes $co/hk-a.txt] eq $workA && [bytes $co/hk-c.txt] eq $workC}
check "the snapshot dropped" {[stashes] == 0}
check "the rest still to commit: [fossilIn $co changes]" \
    {[string match "*EDITED*hk-a.txt*" [fossilIn $co changes]] && [string match "*EDITED*hk-c.txt*" [fossilIn $co changes]]}
check "the comment cleared" {[tkcommit::message] eq ""}

# Stash part: the last change of hk-a.txt stashed, the first stays.
set baseA [lines 40 \n {20 TWENTY}]
show hk-a.txt
check "two hunks now: [boxes]" {[boxes] eq "☑☑"}
tkcommit::toggleHunk 0
foreach p [array names tkcommit::checked] { if {$p ne "hk-a.txt"} { set tkcommit::checked($p) 0 } }
whenOpen .commit.stashpart {set ::ui::f(comment) "the end of hk-a"; set ::ui::done ok}
tkcommit::stashChecked
set comments [concat {*}[fossil::checkoutSql $co "SELECT comment FROM stash"]]
check "stashed: $comments" {$comments eq [list "the end of hk-a"]}
check "the first change stays" {[bytes $co/hk-a.txt] eq [lines 40 \n {1 ONE 20 TWENTY}]}
check "hk-c.txt untouched" {[bytes $co/hk-c.txt] eq $workC}
fossilIn $co stash apply
check "applied: all the changes again" {[bytes $co/hk-a.txt] eq $workA}
check "in the Commit menu" {![catch {.commit.menu.commit index "Stash the checked changes…"}]}

# Splitting a hunk: two changes 4 lines apart are one hunk (their context
# lines meet); split (the mark, or S), each part has its box.
writeBytes $co/hk-s.txt [lines 30]
fossilIn $co add hk-s.txt
fossilIn $co commit --nosync --no-warnings -m "hunks: split base" hk-s.txt
set workS [lines 30 \n {10 TEN 14 FOURTEEN}]
writeBytes $co/hk-s.txt $workS
foreach p [array names tkcommit::checked] { set tkcommit::checked($p) 0 }
tkcommit::refresh; update
set tkcommit::checked(hk-s.txt) 1
show hk-s.txt
check "one hunk, its split mark: [boxes]" {[boxes] eq "\u2611" && [llength [$d tag ranges split]]}
$d mark set insert [lindex [$d tag ranges hk0] 0]
focus -force $d; update
event generate $d <Key-S>; update
check "split (S): the hunk and its two parts: [boxes]" {[boxes] eq "\u2611\u2611\u2611" && ![llength [$d tag ranges split]]}
# Only the second part.
tkcommit::toggleAt [lindex [$d tag ranges hp0.0] 0]
check "the first part off: [boxes]" {[boxes] eq "\u25a3\u2610\u2611"}
check "greyed: only its lines" {[$d get {*}[$d tag ranges off]] eq "\u2610 -line 10\n+TEN\n"}
# The hunk's box: all on, then all off (the file unchecked), then all on.
tkcommit::toggleHunk 0
check "the hunk's box: all on: [boxes]" {[boxes] eq "\u2611\u2611\u2611"}
tkcommit::toggleHunk 0
check "all off: the file unchecked: [boxes]" {[boxes] eq "\u2610\u2610\u2610" && !$tkcommit::checked(hk-s.txt)}
tkcommit::toggleAt [lindex [$d tag ranges hp0.1] 0]
check "the second part alone: [boxes], the file checked" {[boxes] eq "\u25a3\u2610\u2611" && $tkcommit::checked(hk-s.txt)}
.commit.bottom.msg.text insert end "The second part"
set ::answers [dict create yesno yes]
tkcommit::commit
destroy .commit.log
fossil::inDir $co { fossil::runTo $W/got-s cat -r current ./hk-s.txt }
check "committed: only the second change" {[bytes $W/got-s] eq [lines 30 \n {14 FOURTEEN}]}
check "the file still has both" {[bytes $co/hk-s.txt] eq $workS}
show hk-s.txt
check "the rest: one hunk, not split (one change): [boxes]" {[boxes] eq "\u2611" && ![llength [$d tag ranges split]]}
done
