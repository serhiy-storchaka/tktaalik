# The Commit tab, checked again: patches never sync (refused while
# autosync is on), typed values that cannot be passed, the truth of Delete
# unmanaged files (clean-glob, emptied directories), "Check by hashing" in
# the list, "Show unmanaged files" on its own; and several files at once,
# directories, Update, Update files, Merge fork, the three-way view of a
# merged file, Compare two versions, patch headers (scratch copy).
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set co $W/co
# Message boxes: answered yes/ok, recorded.
set ::boxes {}
# The dialogs: answered in turn by {dialog ok script}; the script sees the
# dry run in ::preview.
set ::steps {}
proc respond {args} {
    set ::steps $args
    after cancel pollRespond
    after 20 pollRespond
}
proc pollRespond {} {
    if {![llength $::steps]} return
    lassign [lindex $::steps 0] w ok script
    if {![winfo exists $w] || ![info exists ::tkcommit::answer($w)] || $::tkcommit::answer($w) ne ""} {
        after 20 pollRespond
        return
    }
    set ::steps [lrange $::steps 1 end]
    if {[winfo exists $w.f.p.t]} {
        tkcommit::runPreview $w
        set ::preview [$w.f.p.t get 1.0 end-1c]
    }
    uplevel #0 $script
    if {[winfo exists $w.f.p.t]} { set ::preview [$w.f.p.t get 1.0 end-1c] }
    set ::tkcommit::answer($w) $ok
    after 20 pollRespond
}
proc changes {} {
    set here [pwd]; cd $::co
    catch {exec fossil changes --classify} out
    cd $here
    return $out
}
proc status {path} { tkcommit::loadChanges; expr {[dict exists $tkcommit::files $path] ? [dict get $tkcommit::files $path] : ""} }
proc select {path} {
    .commit.main.files.t selection set [list $path]
    update
}
proc slurp {path} { set f [open $path]; set t [read $f]; close $f; return $t }

proc fossilco {args} { fossilIn $::co {*}$args }
proc write {path text} { set f [open $::co/$path w]; puts -nonewline $f $text; close $f }

start commit $co 1100x800
tktaalik::show commit; update
set t .commit.main.files.t

# --- Bug: a patch is not applied while autosync is on (it would pull).
write README.md "[slurp $co/README.md]patched line\n"
tkcommit::refresh; update
set ::saveTo $W/p.patch
tkcommit::savePatch
fossilco revert
fossilco remote http://127.0.0.1:9/nowhere
fossilco settings autosync on
set ::boxes {}
set ::openFrom $W/p.patch
tkcommit::applyPatch; update
check "autosync on: refused ([lindex $::boxes end])" {[string match "Autosync is on*" [lindex $::boxes end]] && ![string match "*patched line*" [slurp $co/README.md]]}
fossilco settings autosync off
set ::head ""
respond {.commit.patch 1 {set ::head [.commit.patch.f.opts.head cget -text]}}
tkcommit::applyPatch; update
check "autosync off: applied, the header shown ([lindex [split $::head \n] 0])" {[string match "*patched line*" [slurp $co/README.md]] && [string match "BASELINE*" $::head]}
# View a patch: a diff window (fossil patch diff), the header in its title.
tkcommit::viewPatch $W/p.patch; update
set dv [lindex [lsort [lsearch -all -inline -glob [winfo children .] .diffview*]] end]
regexp -line {^BASELINE\s+(\S+)} [tkcommit::patchHeader $W/p.patch] -> base
check "View a patch: its header in the title ([wm title $dv])" {[string match "Patch p.patch*$base*" [wm title $dv]]}
destroy $dv
fossilco revert

# --- Bug: typed values that cannot be passed are refused, named.
set tkcommit::opt(tags) "-x"
check "a tag starting with -: [catch {tkcommit::commitOpts} msg] $msg" {[catch {tkcommit::commitOpts} msg] && [string match "*cannot start with*" $msg]}
set tkcommit::opt(tags) "a<b"
check "a tag with <: refused" {[catch {tkcommit::commitOpts}]}
set tkcommit::opt(tags) ""
set tkcommit::opt(bgcolor) "red;x"
check "a colour: refused" {[catch {tkcommit::commitOpts}]}
set tkcommit::opt(bgcolor) "#00ff00"
set tkcommit::opt(date) "2026-01-02 03:04:05"
set tkcommit::opt(user) "someone"
check "good values: [tkcommit::commitOpts]" {[tkcommit::commitOpts] eq [list --bgcolor=#00ff00 "--date-override=2026-01-02 03:04:05" --user-override=someone]}
tkcommit::resetOpts
set ::boxes {}
respond {.commit.from 1 {set ::tkcommit::revision "|x"}}
tkcommit::compareWith; update
check "Compare with |x: refused ([lindex $::boxes end])" {[string match "Not a version*" [lindex $::boxes end]] && $tkcommit::from eq ""}

# --- Bug: "Check by hashing" in the list too.
set f [open $co/README.md]; set text [read $f]; close $f
set mtime [file mtime $co/README.md]
set f [open $co/README.md w]; puts -nonewline $f [string map {Tk Tq} $text]; close $f
file mtime $co/README.md $mtime
set tkcommit::opt(hash) 0
check "without hashing: not seen (same size and time)" {[status README.md] eq ""}
set tkcommit::opt(hash) 1
check "with hashing: [status README.md]" {[status README.md] eq "EDITED"}
set tkcommit::opt(hash) 0
fossilco revert

# --- Bug: Show unmanaged files uses only Fossil's settings.
write zz-extra.zz "x\n"
set tkcommit::ignoreGlob "*.zz"
set tkcommit::showExtras 1
check "the dialogs' Also ignore does not hide it: [status zz-extra.zz]" {[status zz-extra.zz] eq "EXTRA"}
set tkcommit::showExtras 0
set tkcommit::ignoreGlob ""
file delete $co/zz-extra.zz

# --- Bug: Delete unmanaged files tells what Undo cannot bring back, and
# the directories that become empty.
fossilco settings clean-glob "*.junk"
file mkdir $co/zz-dir/sub
write zz-dir/a.junk "a\n"
write zz-dir/sub/b.txt "b\n"
set ::note ""
set ::listed ""
respond {.commit.clean 1 {set ::tkcommit::emptydirs 1; tkcommit::runPreview .commit.clean}} \
    {.commit.cleanok 0 {set ::note [.commit.cleanok.f.opts.note cget -text]; set ::listed [.commit.cleanok.f.opts.t get 1.0 end]}}
tkcommit::cleanFiles; update
check "clean-glob: no undo ([string range $::note 0 120])" {[string match "*zz-dir/a.junk*clean-glob*" $::note]}
check "emptied directories listed" {[string match "*zz-dir/sub/  (becomes empty*" $::listed] && [string match "*zz-dir/  (becomes empty*" $::listed]}
check "cancelled: nothing deleted" {[file exists $co/zz-dir/a.junk]}
set tkcommit::emptydirs 0
file delete -force $co/zz-dir
fossilco unset clean-glob

# --- Gap: several files at once: Remove (only in Fossil), Revert.
tkcommit::refresh; update
.commit.bottom.opts.unchanged invoke; update
$t selection set [list README.md license.terms]; update
respond {.commit.remove 1 {}}
tkcommit::removeFile; update
check "removed both: [status README.md] [status license.terms]" {[status README.md] eq "DELETED" && [status license.terms] eq "DELETED" && [file exists $co/README.md]}
tkcommit::refresh; update
$t selection set [list README.md license.terms]; update
respond {.commit.revert 1 {}}
tkcommit::revertFiles; update
check "reverted both" {[status README.md] eq "UNCHANGED" && [status license.terms] eq "UNCHANGED"}
# Move several into a directory.
$t selection set [list README.md license.terms]; update
respond {.commit.rename 1 {set ::tkcommit::renameTo zzmoved; tkcommit::runPreview .commit.rename}}
tkcommit::renameFile; update
check "moved both: $::preview" {[file exists $co/zzmoved/README.md] && [file exists $co/zzmoved/license.terms] && [status zzmoved/README.md] eq "RENAMED"}
# Undo for these files: back where they were.
tkcommit::refresh; update
fossilco revert
# Directories: rename, remove (only in Fossil).
tkcommit::refresh; update
respond {.commit.rename 1 {set ::tkcommit::dirName doc; set ::tkcommit::renameTo zzdoc; tkcommit::runPreview .commit.rename}}
tkcommit::renameDir; update
check "directory renamed: [lindex [split $::preview \n] 0]" {[file exists $co/zzdoc/3DBorder.3] && ![file exists $co/doc/3DBorder.3] && [string match "*RENAME*doc/*zzdoc/*" $::preview]}
fossilco revert
file delete -force $co/zzdoc
fossilco revert
respond {.commit.remove 1 {set ::tkcommit::dirName library; set ::tkcommit::onDisk 0}}
tkcommit::removeDir; update
check "directory removed (kept on disk)" {[status library/tk.tcl] eq "DELETED" && [file exists $co/library/tk.tcl]}
fossilco revert

# --- Gap: Update to the newest of the branch; Update files to a version.
set tip [lindex [fossil::checkoutSql $co "SELECT uuid FROM blob WHERE rid=(SELECT value FROM vvar WHERE name='checkout')"] 0 0]
set parent [lindex [fossil::checkoutSql $co "SELECT b.uuid FROM plink p JOIN blob b ON b.rid=p.pid WHERE p.cid=(SELECT value FROM vvar WHERE name='checkout') AND p.isprim"] 0 0]
fossilco update --nosync $parent
tkcommit::refresh; update
respond {.commit.update 1 {set ::tkcommit::setmtime 1; tkcommit::runPreview .commit.update}}
tkcommit::updateCheckout; update
set now [lindex [fossil::checkoutSql $co "SELECT uuid FROM blob WHERE rid=(SELECT value FROM vvar WHERE name='checkout')"] 0 0]
check "updated to the tip (dry run first: [lindex [split $::preview \n] 0])" {$now eq $tip && [string match "*updated-to*" $::preview]}
set tkcommit::setmtime 0
destroy .commit.log
set changed [lindex [fossil::checkoutSql $co "SELECT n.name FROM mlink m JOIN filename n ON n.fnid=m.fnid WHERE m.mid=(SELECT rid FROM blob WHERE uuid='$tip') AND m.pid>0 LIMIT 1"] 0 0]
tkcommit::refresh; update
.commit.bottom.opts.unchanged invoke; update
if {![.commit.bottom.opts.unchanged instate selected]} { .commit.bottom.opts.unchanged invoke; update }
$t selection set [list $changed]; update
respond {.commit.updatefiles 1 "set ::tkcommit::revision [string range $parent 0 11]; tkcommit::runPreview .commit.updatefiles"}
tkcommit::updateFiles; update
check "$changed updated to the version before: [status $changed]" {[status $changed] eq "EDITED"}
fossilco revert

# --- Gap: a fork of the branch merged; the three-way view of a merge.
fossilco settings autosync off
write zzfork.txt "one\ntwo\nthree\n"
fossilco add zzfork.txt
fossilco commit --nosync -m "fork base"
set base [lindex [fossil::checkoutSql $co "SELECT uuid FROM blob WHERE rid=(SELECT value FROM vvar WHERE name='checkout')"] 0 0]
write zzfork.txt "one\nthe second line\nthree\n"
fossilco commit --nosync -m "fork a"
fossilco update --nosync $base
write zzfork.txt "one\nanother second line here\nthree\n"
fossilco commit --nosync --allow-fork -m "fork b"
tkcommit::refresh; update
check "a fork: $tkcommit::forks leaves, Merge fork enabled" {$tkcommit::forks == 2 && [.commit.menu.commit entrycget "Merge fork*" -state] eq "normal"}
respond {.commit.mergefork 1 {tkcommit::runPreview .commit.mergefork}}
tkcommit::mergeFork; update
destroy .commit.log
set st [status zzfork.txt]
check "merged (dry run first): $st, merging $tkcommit::merging, [string range $::preview 0 60]" {$st eq "CONFLICT" && $tkcommit::merging}
# (The merge details: Fossil 2.26 and newer, fossil merge-info.)
if {[fossil::hasCommand merge-info]} {
    tkcommit::mergeInfo; update
    set i [.commit.merge.t search zzfork.txt 1.0]
    # Its context menu: on a file, its three-way view (in bold: the
    # double-click) and its name; on another line, greyed out.
    proc tk_popup {m args} { set ::posted $m }
    proc mergeMenuAt {index} {
        set ::posted ""
        .commit.merge.t see $index; update
        lassign [.commit.merge.t bbox $index] x y
        event generate .commit.merge.t <ButtonPress-3> -x [expr {$x + 2}] -y [expr {$y + 2}] -rootx 10 -rooty 10
        update
        set m $::posted
        list [$m entrycget "Three-way view" -state] [$m entrycget "Copy file name" -state] [$m entrycget 0 -font]
    }
    lassign [mergeMenuAt $i] three copy bold
    check "merge details: the menu of a file: $three $copy, [expr {$bold ne "" ? "bold" : "plain"}]" \
        {$three eq "normal" && $copy eq "normal" && $bold ne "" && $tkcommit::mergeFile eq "zzfork.txt"}
    .commit.merge.ctx invoke "Copy file name"
    check "the name copied: [clipboard get]" {[clipboard get] eq "zzfork.txt"}
    set other [.commit.merge.t search -regexp {^\s*$|^[^A-Z ]} 1.0]
    if {$other eq ""} { set other "end - 1 char" }
    lassign [mergeMenuAt $other] three copy
    check "on a line that is not a file: [list $three $copy]" {$three eq "disabled" && $copy eq "disabled"}
    tkcommit::mergeLine $i
    tkcommit::threeWaySelected; update
    set heads [lmap n {0 1 2 3} {.commit.threeway.f.h$n cget -text}]
    check "three-way view: [join $heads { | }]" {[string match "*baseline*" [lindex $heads 0]] && [string match "*after merge*" [lindex $heads 3]] && [string match "*the second line*" [.commit.threeway.f.t1 get 1.0 end][.commit.threeway.f.t2 get 1.0 end]]}
    destroy .commit.threeway .commit.merge
}
fossilco undo
fossilco revert

# --- Gap: Compare two versions; a directory as From.
set before [llength [lsearch -all -glob [winfo children .] .diffview*]]
respond {.commit.compare 1 "set ::tkcommit::fromVersion [string range $parent 0 11]; set ::tkcommit::toVersion [string range $tip 0 11]"}
tkcommit::compareTwo; update
set dv [lindex [lsort [lsearch -all -inline -glob [winfo children .] .diffview*]] end]
waitUntil {![dict exists $diffview::data($dv) chan]}
check "two versions: [llength [dict get $diffview::data($dv) files]] files" {[llength [lsearch -all -glob [winfo children .] .diffview*]] == $before + 1 && [llength [dict get $diffview::data($dv) files]] > 0}
destroy $dv
file mkdir $W/otherdir
set f [open $W/otherdir/README.md w]; puts $f "elsewhere"; close $f
# (A directory against the whole checkout is slow: the arguments only.)
rename diffview::run diffview::realRun
proc diffview::run {title args} { set ::ran $args }
respond [list .commit.compare 1 "set ::tkcommit::fromVersion $W/otherdir; set ::tkcommit::toVersion {}"]
tkcommit::compareTwo; update
check "from a directory: $::ran" {[string match "*--from=$W/otherdir" $::ran] && [string first --to $::ran] < 0}
rename diffview::run {}
rename diffview::realRun diffview::run
done
