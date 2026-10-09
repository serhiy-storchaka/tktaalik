# The Commit tab's actions besides committing: rename, remove, add, add
# and remove all, reset, delete unmanaged files, revert (to a version),
# undo and redo, diff options, patches, merge details, commit options
# (scratch copy).
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

start commit $co 1100x800
tktaalik::show commit; update
set t .commit.main.files.t
check "no changes yet: [llength [$t children {}]] files" {[llength [$t children {}]] == 0}

# Unchanged files listed when wanted.
.commit.bottom.opts.unchanged invoke; update
check "Show unchanged files: [llength [$t children {}]]" {[llength [$t children {}]] > 500 && [$t set changes.md status] eq "UNCHANGED"}
check "unchanged: not checked" {$tkcommit::checked(changes.md) == 0 && [llength [tkcommit::toCommit]] == 0}

# Rename (on disk too), with its dry run.
select changes.md
respond {.commit.rename 1 {set ::tkcommit::renameTo doc/changes-renamed.md; tkcommit::runPreview .commit.rename}}
tkcommit::renameFile
check "rename dry run: $::preview" {[string match "*RENAME changes.md doc/changes-renamed.md*" $::preview]}
check "renamed on disk" {[file exists $co/doc/changes-renamed.md] && ![file exists $co/changes.md]}
check "renamed in Fossil: [status doc/changes-renamed.md]" {[status doc/changes-renamed.md] eq "RENAMED"}
# Only in Fossil.
select license.terms
respond {.commit.rename 1 {set ::tkcommit::renameTo license2.terms; set ::tkcommit::onDisk 0}}
tkcommit::renameFile
check "renamed only in Fossil (the new name missing on disk): [status license2.terms]" {[file exists $co/license.terms] && ![file exists $co/license2.terms] && [status license2.terms] in {RENAMED MISSING}}
tkcommit::fossil revert
file delete $co/doc/changes-renamed.md
.commit.bottom.opts.unchanged invoke; update

# Remove: a missing file, and one kept on disk (forget).
file delete $co/README.md
tkcommit::refresh; update
check "missing: [status README.md]" {[status README.md] eq "MISSING"}
select README.md
respond {.commit.remove 1 {}}
tkcommit::removeFile
check "remove dry run: $::preview" {[string match "*DELETED README.md*" $::preview]}
check "removed: [status README.md]" {[status README.md] eq "DELETED"}

# Add: the ignore-glob asked about; reset.
set f [open $co/new1.txt w]; puts $f new; close $f
file mkdir $co/sub
set f [open $co/sub/new2.txt w]; puts $f new; close $f
set f [open $co/.hidden w]; puts $f new; close $f
set f [open $co/x.o w]; puts $f obj; close $f
.commit.bottom.opts.extras invoke; update
check "extras: [lsort [lmap i [$t children {}] {if {[$t set $i status] eq "EXTRA"} {set i} else continue}]]" {[$t exists new1.txt] && [$t exists sub/new2.txt] && ![$t exists x.o]}
select new1.txt
tkcommit::addFiles; update
check "added: [status new1.txt]" {[status new1.txt] eq "ADDED"}
# x.o is not listed (ignore-glob); added by name it asks.
set tkcommit::current x.o
dict set tkcommit::files x.o EXTRA
set tkcommit::checked(x.o) 0
set ::boxes {}
tkcommit::addFiles; update
check "ignore-glob asked: $::boxes" {[string match "*ignore-glob*anyway*" $::boxes] && [status x.o] eq "ADDED"}
respond {.commit.reset 1 {}}
tkcommit::resetAdds
check "reset dry run: [string map {\n |} $::preview]" {[string match "*new1.txt*" $::preview] && [string match "*x.o*" $::preview]}
check "reset: no longer added, README no longer removed: [status README.md]" {[status new1.txt] eq "EXTRA" && [status x.o] eq "" && [status README.md] ne "DELETED"}
file delete $co/README.md

# Add new and remove missing; dot files only when wanted.
respond {.commit.addremove 1 {}}
tkcommit::addRemove
check "addremove dry run: [string map {\n |} $::preview]" {[string match "*ADDED  new1.txt*" $::preview] && [string match "*ADDED  sub/new2.txt*" $::preview] && [string match "*DELETED  README.md*" $::preview] && ![string match "*.hidden*" $::preview]}
check "addremove done" {[status new1.txt] eq "ADDED" && [status sub/new2.txt] eq "ADDED" && [status README.md] eq "DELETED" && [status .hidden] eq ""}
respond {.commit.addremove 0 {set ::tkcommit::dotfiles 1; tkcommit::runPreview .commit.addremove}}
tkcommit::addRemove
check "with dot files: in the dry run" {[string match "*ADDED  .hidden*" $::preview]}
check "cancelled: not added" {[status .hidden] ne "ADDED"}
set tkcommit::dotfiles 0
respond {.commit.reset 1 {}}
tkcommit::resetAdds

# Delete unmanaged files: the ones checked, after naming them.
respond {.commit.clean 1 {tkcommit::cleanToggle new1.txt}} \
    {.commit.cleanok 1 {set ::named [.commit.cleanok.f.opts.t get 1.0 end-1c]; set ::note [.commit.cleanok.f.opts.note cget -text]}}
tkcommit::cleanFiles
check "clean: named [list $::named]" {$::named eq "sub/new2.txt"}
check "clean: undo noted" {[string match "Undo brings them back*" $::note]}
check "clean: deleted only the checked" {![file exists $co/sub/new2.txt] && [file exists $co/new1.txt] && [file exists $co/.hidden] && [file exists $co/x.o]}
# Empty directories and dot files as options.
respond {.commit.clean 0 {set ::tkcommit::emptydirs 1; set ::tkcommit::dotfiles 1; tkcommit::runPreview .commit.clean; set ::listed [.commit.clean.f.opts.list.t children {}]}}
tkcommit::cleanFiles
check "clean options: $::listed" {"sub" in $::listed && ".hidden" in $::listed && "new1.txt" in $::listed}
set tkcommit::emptydirs 0; set tkcommit::dotfiles 0
check "cancelled: nothing deleted" {[file isdirectory $co/sub] && [file exists $co/.hidden]}

# Revert, undo, redo.
tkcommit::fossil revert
set orig [slurp $co/win/README]
set f [open $co/win/README a]; puts $f "a local change"; close $f
tkcommit::refresh; update
select win/README
respond {.commit.revert 1 {}}
tkcommit::revertFiles
check "reverted" {[slurp $co/win/README] eq $orig}
set ::boxes {}
tkcommit::undo
check "undo: asked with its dry run ($::boxes)" {[string match "Undo?*" $::boxes]}
check "undone: the change is back" {[string match "*a local change*" [slurp $co/win/README]]}
tkcommit::undo redo
check "redone: reverted again" {[slurp $co/win/README] eq $orig}
set ::boxes {}
tkcommit::undo redo
check "nothing to redo: said so ($::boxes)" {[string match "Nothing to redo*" [lindex $::boxes end]]}
# Revert to another version.
set old [lindex [fossil::sql $W/tk.fossil "SELECT b.uuid FROM blob b JOIN mlink m ON m.mid=b.rid
    JOIN filename n ON n.fnid=m.fnid WHERE n.name='win/README' ORDER BY b.rid LIMIT 1"] 0 0]
set f [open $co/win/README a]; puts $f "x"; close $f
tkcommit::refresh; update
select win/README
respond [list .commit.revert 1 [list set ::tkcommit::revision $old]]
tkcommit::revertFiles
set here [pwd]; cd $co
set expected [exec fossil cat -r $old win/README]
cd $here
check "reverted to [string range $old 0 9]" {[string trimright [slurp $co/win/README] \n] eq [string trimright $expected \n] && $expected ne [string trimright $orig \n]}
respond {.commit.revert 1 {set ::revertList [.commit.revert.f.opts.t get 1.0 end-1c]}}
tkcommit::revertFiles 1
check "revert all: listed, done ($::revertList)" {[string match *win/README* $::revertList] && [status win/README] eq ""}

# Diff options.
set f [open $co/win/README w]; puts -nonewline $f [string map {"\n" " \n"} $orig]; close $f
tkcommit::refresh; update
select win/README
set d .commit.main.diff.text
check "a diff of white space" {[llength [$d search -all -regexp {^\+} 1.0 end]] > 1}
set diffopts::ignoreTrailing 1
tkcommit::refresh; update
check "ignored with -Z: [llength [$d search -all -regexp {^\+[^+]} 1.0 end]] lines" {[llength [$d search -all -regexp {^\+[^+]} 1.0 end]] == 0}
set diffopts::ignoreTrailing 0
check "diff options: [diffopts::args]" {[diffopts::args] eq ""}
set diffopts::context 0; set diffopts::ignoreSpace 1
check "diff options: [diffopts::args]" {[diffopts::args] eq "-w -c 0"}
set diffopts::context ""; set diffopts::ignoreSpace 0
respond {.commit.from 1 {set ::tkcommit::revision core-9-0-branch}}
tkcommit::compareWith; update
check "compare with: $tkcommit::info" {[string match "*diffs against core-9-0-branch" $tkcommit::info] && [tkcommit::diffArgs] eq "--from=core-9-0-branch"}
set tkcommit::from ""
tkcommit::refresh

# Patches: saved, reverted, applied again, viewed.
set ::saveTo $T(tmp)/changes.patch
tkcommit::savePatch
check "patch saved" {[file size $::saveTo] > 0}
tkcommit::fossil revert
tkcommit::refresh
check "reverted: [status win/README]" {[status win/README] eq ""}
set ::openFrom $::saveTo
respond {.commit.patch 1 {}}
tkcommit::applyPatch
check "patch dry run: $::preview" {[string match "*fossil update*" $::preview]}
check "patch applied: [status win/README]" {[status win/README] eq "EDITED"}
# Over changes: only with discarding them.
respond {.commit.patch 0 {set ::refused $::preview; set ::tkcommit::discard 1; tkcommit::runPreview .commit.patch}}
tkcommit::applyPatch
check "over changes: refused, then with -f: [string range $::preview 0 60]" {[string match "*unsaved changes*" $::refused] && ![string match "*unsaved changes*" $::preview]}
tkcommit::viewPatch $::saveTo
check "patch viewed" {[llength [lsearch -all -inline [winfo children .] .diffview*]] > 0}
tkcommit::fossil revert

# A merge: the note, the details.  (Of a branch of its own: the
# repository's branches may all be merged already.)
set f [open $co/README.md a]; puts $f "a line to merge"; close $f
tkcommit::fossil commit --nosync -m "A line to merge" --branch zz-opsmerge
tkcommit::fossil update --nosync main
lassign [tkcommit::fossil merge zz-opsmerge] code out
tkcommit::refresh; update
check "merging: [.commit.bottom.note cget -text]" {$tkcommit::merging && [string match "*merge of *" [.commit.bottom.note cget -text]] && [winfo ismapped .commit.bottom.buttons.merge]}
if {[fossil::hasCommand merge-info]} {
    tkcommit::mergeInfo
    check "merge details shown" {[winfo exists .commit.merge] && [.commit.merge.t get 1.0 end-1c] ne ""}
    set tkcommit::allMerge 1; tkcommit::mergeInfo
    check "all files of the merge: more lines" {[llength [split [.commit.merge.t get 1.0 end-1c] \n]] >= 1}
    destroy .commit.merge
} else {
    # (Fossil 2.25 and older: no merge-info.)
    tkcommit::mergeInfo
    check "no merge-info: said, no window" {[string match "*2.26*" [lindex $::boxes end]] && ![winfo exists .commit.merge]}
}
tkcommit::fossil revert
tkcommit::refresh; update
check "no merge: no button" {!$tkcommit::merging && ![winfo ismapped .commit.bottom.buttons.merge]}

# Commit options: tags, a colour, the user; cleared after the commit.
set f [open $co/win/README a]; puts $f "committed"; close $f
tkcommit::refresh; update
set tkcommit::opt(tags) "t-one, t-two"
set tkcommit::opt(bgcolor) "#ffcc00"
set tkcommit::opt(hash) 1
check "commit options: [tkcommit::commitOpts]" {[tkcommit::commitOpts] eq "--tag=t-one --tag=t-two --hash --bgcolor=#ffcc00"}
.commit.bottom.msg.text insert end "With options"
tkcommit::commit
set tags [fossil::sql $W/tk.fossil "SELECT tagname FROM tag JOIN tagxref USING(tagid)
    WHERE rid=(SELECT objid FROM event WHERE type='ci' ORDER BY mtime DESC LIMIT 1) ORDER BY tagname"]
check "committed with the tags: [join $tags]" {"sym-t-one" in [join $tags] && "sym-t-two" in [join $tags] && "bgcolor" in [join $tags]}
check "one-shot cleared, kept kept" {$tkcommit::opt(tags) eq "" && $tkcommit::opt(bgcolor) eq "" && $tkcommit::opt(hash) == 1}
# Allow no changes: a check-in without files.
set n [lindex [fossil::sql $W/tk.fossil "SELECT count(*) FROM event WHERE type='ci'"] 0 0]
set tkcommit::opt(allowEmpty) 1
.commit.bottom.msg.text insert end "Empty"
tkcommit::commit
check "an empty check-in" {[lindex [fossil::sql $W/tk.fossil "SELECT count(*) FROM event WHERE type='ci'"] 0 0] == $n + 1}
# The More options shown and hidden; the file menu.
tkcommit::toggleMore; update
check "more options shown" {[winfo ismapped .commit.bottom.more]}
tkcommit::toggleMore; update
check "file menu: [.commit.ctx index end] entries" {[.commit.ctx index end] == 8}
done
