# The Commit tab after the re-audit: autosync read per command, values and
# patterns that cannot become redirections, the patterns typed added to the
# settings', empty directories kept when unchecked, the three-way view as
# Fossil's, Compare from a directory of the checkout, Undo for files,
# Revert all with nothing to revert; resetting adds or removes alone, the
# patch viewer, dot files, setting file times, switching the version with
# the files kept, --allckouts (scratch copy).
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
# Calls of fossil recorded (with what they return).
rename tkcommit::fossil tkcommit::realFossil
set ::calls {}
proc tkcommit::fossil {args} { lappend ::calls $args; tkcommit::realFossil {*}$args }
proc called {pattern} { lsearch -all -inline -glob $::calls $pattern }

# --- Bug 14: Revert all with nothing to revert.
fossilco revert
tkcommit::refresh; update
set ::boxes {}
tkcommit::revertFiles 1; update
check "Revert all, no changes: [lindex $::boxes end]" {[string match "*no changes to revert*" [lindex $::boxes end]] && ![winfo exists .commit.revert]}

# --- Bug 1: autosync read per command.
foreach {value on} {"on,commit=off" 1 "off,update=on" 1 "pullonly update=off" 0 "off" 0 "on" 1} {
    fossilco settings autosync $value
    check "autosync \"$value\": on for update = [tkcommit::autosyncOn]" {[tkcommit::autosyncOn] == $on}
}
fossilco unset autosync
check "autosync unset: on" {[tkcommit::autosyncOn] == 1}
fossilco settings autosync off

# --- Bug 2: a version that would be a redirection is refused, nothing run.
write README.md "[slurp $co/README.md]edited\n"
tkcommit::refresh; update
set before [slurp $co/README.md]
set tkcommit::revision "2>"
set tkcommit::updating {README.md}
set out [tkcommit::updateFilesPreview]
check "version 2>: refused ($out), file kept" {[string match "Not a version*" $out] && [slurp $co/README.md] eq $before}
set tkcommit::revision "&"
check "version &: refused" {[string match "Not a version*" [tkcommit::updateFilesPreview]]}

# --- Bug 9: Update files does not pass the Update dialog's --setmtime.
set tkcommit::setmtime 1
set tkcommit::revision trunk
set ::calls {}
tkcommit::updateFilesPreview
check "no hidden --setmtime: [called {update*}]" {[llength [called {update*}]] && ![llength [called {*--setmtime*}]]}
set tkcommit::setmtime 0
fossilco revert

# --- Bugs 3, 5: the patterns typed are added to the settings', as one word.
# (Tk's checkout has a versioned ignore-glob: it is used, as by Fossil.)
set igfile $co/.fossil-settings/ignore-glob
set igbefore [slurp $igfile]
set f [open $igfile a]; puts $f {*.log}; close $f
fossilco settings keep-glob {*.keep}
write a.log x
write b.keep x
write c.tmp x
set tkcommit::ignoreGlob {*.tmp}
set opts [tkcommit::globOpts 0]
check "--ignore: the setting's and the typed: [string range $opts 0 30]..." {[string match "--ignore=*,\\*.log,\\*.tmp" $opts] && [llength $opts] == 1}
set ::calls {}
set out [tkcommit::cleanPreview]
set listed [lmap i $tkcommit::cleanList { lindex $i 0 }]
check "clean -n with Also ignore: a.log and b.keep still protected ($listed)" {"a.log" ni $listed && "b.keep" ni $listed && "c.tmp" ni $listed}
set tkcommit::ignoreGlob ""
set tkcommit::keepGlob {2>zz}
set opts [tkcommit::cleanOpts]
check "--keep as one word: $opts" {"--keep=*.keep,2>zz" in $opts}
tkcommit::cleanPreview
check "no file made by a redirection" {![file exists $co/zz] && ![file exists $co/--keep]}
set tkcommit::keepGlob ""
set f [open $igfile w]; puts -nonewline $f $igbefore; close $f
fossilco unset keep-glob

# --- Bug 4: an unchecked empty directory is kept.
file mkdir $co/e1 $co/e2
set tkcommit::emptydirs 1
set tkcommit::cleanSkip(e2) 1
respond [list .commit.clean 1 {
    set tkcommit::emptydirs 1
    set tkcommit::cleanSkip(e2) 1
    tkcommit::cleanPreview
    set ::listedDirs [lmap i $tkcommit::cleanList { if {[lindex $i 1] eq "file"} continue; lindex $i 0 }]
}] [list .commit.cleanok 1 {}]
array unset tkcommit::cleanSkip
after 50 {set tkcommit::cleanSkip(e2) 1}
tkcommit::cleanFiles; update
check "e1 deleted, e2 (unchecked) kept: listed $::listedDirs" {![file exists $co/e1] && [file isdirectory $co/e2] && ![file exists $co/c.tmp]}
check "no --emptydirs passed with the names" {![llength [called {clean --force*--emptydirs*}]]}
set tkcommit::emptydirs 0
file delete $co/e2 $co/a.log $co/b.keep

# --- --allckouts in the options.
set tkcommit::allckouts 1
check "clean --allckouts" {"--allckouts" in [tkcommit::cleanOpts]}
set tkcommit::allckouts 0

# --- Bug 8: the new branch passed as --branch=NAME.
write README.md "[slurp $co/README.md]branch\n"
tkcommit::refresh; update
.commit.bottom.msg.text insert end "test"
set tkcommit::branch "2>yy"
set ::calls {}
tkcommit::commit 1; update
check "--branch=2>yy, no file yy" {[llength [called {commit*--branch=2>yy*}]] && ![file exists $co/yy]}
set tkcommit::branch ""
.commit.bottom.msg.text delete 1.0 end
catch {destroy .commit.log}

# --- Bug 11: Compare from a directory named relative to the checkout.
file mkdir $co/cmpdir
set ::runArgs {}
rename diffview::run diffview::realRun
proc diffview::run {title args} { set ::runArgs $args }
respond [list .commit.compare 1 {set tkcommit::fromVersion cmpdir; set tkcommit::toVersion ""}]
tkcommit::compareTwo; update
check "from the checkout's directory: [lsearch -inline -glob $::runArgs --from=*]" {[lsearch -inline -glob $::runArgs --from=*] eq "--from=[file normalize $co/cmpdir]"}
file delete $co/cmpdir

# --- View a patch: through a diff window running "fossil patch diff -f".
set ::saveTo $W/v.patch
tkcommit::savePatch
set ::openFrom $W/v.patch
tkcommit::viewPatch; update
check "patch diff in a diff window: [lrange $::runArgs 0 3]" {[lsearch -exact $::runArgs -command] >= 0 && [lindex $::runArgs [expr {[lsearch -exact $::runArgs -command] + 1}]] eq {fossil patch diff -f}}
rename diffview::run {}
rename diffview::realRun diffview::run
fossilco revert

# --- Bug 13: Undo for files says that only they are undone.
write README.md "[slurp $co/README.md]for undo\n"
fossilco revert README.md
tkcommit::refresh; update
set ::details {}
set ::answer cancel
tkcommit::undo undo {README.md}
check "undo for a file: says only it" {[string match "Only these files:*README.md*" [lindex $::details end]]}
set ::answer ok

# --- Reset adds or removes alone.
write new1.txt n
fossilco add new1.txt
fossilco rm --soft changes.md
respond [list .commit.reset 1 {}]
tkcommit::resetAdds add; update
set c [changes]
check "Reset adds: new1.txt no longer added, the remove kept" {![string match "*ADDED*new1.txt*" $c] && [string match "*DELETED*changes.md*" $c]}
respond [list .commit.reset 1 {}]
tkcommit::resetAdds rm; update
check "Reset removes: changes.md back" {![string match "*DELETED*changes.md*" [changes]]}
file delete $co/new1.txt

# --- Dot files among the unmanaged files.
write .dotfile x
set tkcommit::showExtras 1
set tkcommit::extrasDot 0
tkcommit::refresh; update
set without [dict exists $tkcommit::files .dotfile]
set tkcommit::extrasDot 1
tkcommit::refresh; update
check "with dot files: .dotfile listed (not before: $without)" {!$without && [dict exists $tkcommit::files .dotfile]}
set tkcommit::showExtras 0
set tkcommit::extrasDot 0
file delete $co/.dotfile

# --- Setting file times (touch, dry run first).
file mtime $co/README.md [clock scan 2001-01-01 -gmt 1]
.commit.main.files.t selection set {}
tkcommit::refresh; update
respond [list .commit.touch 1 {set tkcommit::touchTo checkin}]
tkcommit::touchFiles; update
check "touch: dry run shown ([string range $::preview 0 60])" {[string length $::preview] > 0}
check "README.md has its check-in's time" {[file mtime $co/README.md] > [clock scan 2002-01-01 -gmt 1]}

# --- Switch the version, keep the files (checkout --keep).
set parent [fossilco info]
regexp -line {^parent:\s+([0-9a-f]{10})} $parent -> par
set before [slurp $co/README.md]
respond [list .commit.switch 1 [list set tkcommit::revision $par]]
tkcommit::switchKeep; update
check "switched to $par, files kept" {[string match "*checkout:*$par*" [fossilco info]] && [slurp $co/README.md] eq $before}
fossilco update --nosync trunk
fossilco revert

# Without "fossil merge-info" (Fossil 2.25 and older): the merge details
# and the three-way view say what they need, and the rest is skipped.
if {![fossil::hasCommand merge-info]} {
    set ::boxes {}
    tkcommit::mergeInfo; update
    check "no merge-info: Merge details say why: [lindex $::boxes end]" {
        [string match "*2.26*" [lindex $::boxes end]] && ![winfo exists .commit.merge]}
    lassign [tkcommit::mergeRows README.md 3] st rows
    check "no merge-info: the three-way view says why" {$st eq "error" && [string match "*2.26*" $rows]}
    done
}

# --- Bug 6: the three-way view as Fossil's own.
fossilco merge {*}[fossil::nosync merge] core-9-0-branch
tkcommit::mergeInfo; update
set mi [.commit.merge.t get 1.0 end]
set files {}
foreach line [split $mi \n] { if {[regexp {^MERGE\s+(\S+)$} $line -> f]} { lappend files $f } }
set file [lindex $files 0]
lassign [tkcommit::mergeRows $file 3] st rows
set names [lindex [lsearch -inline -index 0 $rows names] 1]
check "rows: [llength $rows], names [join $names /]" {$st eq "ok" && [string match "*(after merge)" [lindex $names 3]]}
# The merge details: a status line chosen, an ERROR line not.
set w .commit.merge.t
$w configure -state normal
$w insert end "ERROR  (cannot find some file)\n"
$w configure -state disabled
set tkcommit::mergeFile ""
tkcommit::mergeLine [$w search ERROR 1.0]
check "an ERROR line is not a file" {$tkcommit::mergeFile eq ""}
tkcommit::mergeLine [$w search $file 1.0]
check "a MERGE line: $tkcommit::mergeFile" {$tkcommit::mergeFile eq $file}
tkcommit::threeWay $file; update
check "the three-way window" {[winfo exists .commit.threeway] && [.commit.threeway.f.h3 cget -text] ne ""}
# A two-way view: a diff window of two versions.
set before [llength [lsearch -all -glob [winfo children .] .diffview*]]
tkcommit::twoWay $file 0 2; update
check "two-way: a diff window" {[llength [lsearch -all -glob [winfo children .] .diffview*]] == $before + 1}
destroy .commit.threeway .commit.merge
fossilco undo
# A line taken from the merged-in version: its text in the result too.  On
# a merge of its own (whether the repository's has one depends on it).
set f [open $co/README.md a]; puts $f "a merged-in line"; close $f
fossilco commit --nosync -m "A line to merge" --branch zz-mergein
fossilco update --nosync main
fossilco merge {*}[fossil::nosync merge] zz-mergein
lassign [tkcommit::mergeRows README.md 3] st rows
set ok 0
foreach row $rows {
    lassign $row kind cells
    if {$kind ne "line"} continue
    lassign [lindex $cells 2] t2 tag2
    lassign [lindex $cells 3] t3 tag3
    if {$tag3 eq "add" && $t3 eq "a merged-in line" && $t2 eq $t3} { set ok 1 }
}
check "a merged-in line shown with its text in the result" {$st eq "ok" && $ok}
set dots [llength [lmap row $rows { if {[lindex $row 0] ne "line"} continue; lassign [lindex [lindex $row 1] 0] t g; if {$g ne "none"} continue; set g }]]
check "\"no line here\" cells empty in the baseline ($dots)" {$dots > 0}
fossilco undo
done
