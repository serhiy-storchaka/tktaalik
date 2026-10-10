# The Commit tab's actions on the checkout besides committing: rename,
# remove (files, several, directories), add and remove all, delete
# unmanaged files, revert, undo and redo, update (the checkout, some files),
# merging a fork, the state of a merge and a three-way view of a merged
# file, patches, comparing versions; and the options of a commit.  Each
# change is shown first (Fossil's dry run, where it has one) in the dialog
# that asks for it.  Sourced by tkcommit.tcl.

source [file join [file dirname [file normalize [info script]]] diffopts.tcl]

namespace eval tkcommit {
    variable answer             ;# array: dialog -> 1 (OK), 0, "" (open)
    variable previewScript      ;# array: dialog -> script giving the dry run
    variable mergedWith {}      ;# what the merge in progress brings: {what hash}...
    variable from ""            ;# diff against this version, not the check-in
    variable showUnchanged 0    ;# also list the unchanged files

    # The options of a commit: one-shot (cleared after it) and kept.
    variable once {tags "" close 0 integrate 0 private 0 bgcolor "" branchcolor ""
        date "" user "" allowFork 0 allowEmpty 0 allowConflict 0 allowOlder 0
        overrideLock 0}
    variable opt
    array set opt $once
    array set opt {ignoreOversize 0 ignoreSkew 0 hash 0 nosign 0 noVerify 0}
    variable moreShown 0

    # The dialogs' fields.
    variable renameTo ""
    variable onDisk 1
    variable dotfiles 0
    variable ignoreGlob ""
    variable cleanGlob ""
    variable keepGlob ""
    variable emptydirs 0
    variable dirsonly 0
    variable temp 0
    variable verily 0
    variable allckouts 0        ;# clean --allckouts
    variable cleanList {}       ;# the files "clean -n" lists: {path kind}...
    variable cleanSkip          ;# array: path -> 1 if unchecked
    variable revision ""
    variable discard 0
    variable allMerge 0
    variable renameFrom ""      ;# the file or directory renamed
    variable dirName ""         ;# the directory of the directory dialogs
    variable latest 0           ;# update --latest
    variable setmtime 0         ;# update --setmtime
    variable keepMerge 0        ;# update/merge -K
    variable fromVersion ""     ;# Compare two versions: from
    variable toVersion ""       ;#   and to ("" the files of the checkout)
}

# ---------------------------------------------------------------- dialogs

# A dialog W asking for an action: MESSAGE, a frame $w.f.opts for the
# fields, the dry run of PREVIEW (a script returning its output; "" for
# none) shown below and run again after each change, and OK (its label)
# and Cancel.  Shown with waitDialog.
proc tkcommit::dialog {w title message ok {preview ""}} {
    variable answer
    variable previewScript
    ui::dialog $w $title -escape [list set tkcommit::answer($w) 0] \
        -close [list set tkcommit::answer($w) 0]
    ttk::label $w.f.msg -text $message -wraplength 640 -justify left
    ttk::frame $w.f.opts
    grid $w.f.msg -sticky w
    grid $w.f.opts -sticky we -pady {6 0}
    set previewScript($w) $preview
    if {$preview ne ""} {
        ttk::label $w.f.pl -text "What it does (dry run):" -foreground gray35
        ttk::frame $w.f.p
        text $w.f.p.t -width 90 -height 12 -font TkFixedFont -wrap none -state disabled \
            -yscrollcommand [list $w.f.p.y set]
        ttk::scrollbar $w.f.p.y -command [list $w.f.p.t yview]
        grid $w.f.p.t $w.f.p.y -sticky news
        grid columnconfigure $w.f.p 0 -weight 1
        grid rowconfigure $w.f.p 0 -weight 1
        grid $w.f.pl -sticky w -pady {8 2}
        grid $w.f.p -sticky news
        grid rowconfigure $w.f 3 -weight 1
    }
    grid columnconfigure $w.f 0 -weight 1
    ttk::frame $w.f.b
    ui::buttons $w.f.b $ok [list set tkcommit::answer($w) 1] [list set tkcommit::answer($w) 0]
    grid $w.f.b -sticky e -pady {8 0}
    set answer($w) ""
    return $w
}

# Show the dialog W until it is answered: 1 for OK.
proc tkcommit::waitDialog {w} {
    variable answer
    variable previewScript
    if {$previewScript($w) ne ""} { runPreview $w }
    if {$answer($w) eq ""} { vwait tkcommit::answer($w) }
    set result $answer($w)
    destroy $w
    unset answer($w) previewScript($w)
    return $result
}

# The dry run again, a moment after the last change.
proc tkcommit::preview {w} {
    ui::later [list tkcommit::runPreview $w]
}

proc tkcommit::runPreview {w} {
    variable previewScript
    if {![winfo exists $w.f.p.t]} return
    ui::setText $w.f.p.t [string trim [uplevel #0 $previewScript($w)]]
}

# A checkbutton and a labelled entry in a dialog's fields; changes run the
# dry run again.
proc tkcommit::checkField {w name label var} {
    ttk::checkbutton $w.f.opts.$name -text $label -variable $var \
        -command [list tkcommit::preview $w]
    grid $w.f.opts.$name - -sticky w
}

proc tkcommit::field {w name label var {width 40}} {
    ttk::label $w.f.opts.${name}l -text $label
    ttk::entry $w.f.opts.$name -textvariable $var -width $width
    bind $w.f.opts.$name <KeyRelease> [list tkcommit::preview $w]
    grid $w.f.opts.${name}l $w.f.opts.$name -sticky w -pady 1
}

# The output of fossil, or why it failed.
proc tkcommit::dryRun {args} {
    lassign [fossil {*}$args] code out
    expr {$code ? "Fossil refuses:\n$out" : $out}
}

# The globs of the unmanaged files: --dotfiles, --ignore, --clean.  The
# patterns typed are added to the setting's (Fossil's --ignore, --clean,
# --keep replace the ignore-glob, clean-glob, keep-glob settings), and
# passed as --option=VALUE (no word of their own: not taken for a
# redirection).
proc tkcommit::globOpts {{clean 1}} {
    variable dotfiles
    variable ignoreGlob
    variable cleanGlob
    set result {}
    if {$dotfiles} { lappend result --dotfiles }
    lappend result {*}[globOpt --ignore ignore-glob $ignoreGlob]
    if {$clean} { lappend result {*}[globOpt --clean clean-glob $cleanGlob] }
    return $result
}

# OPTION=the patterns of SETTING and the ones TYPED (comma-separated); none
# if nothing is typed (then the setting applies by itself).
proc tkcommit::globOpt {option setting typed} {
    set more [lmap g [split $typed ", \n\t"] { if {$g eq ""} continue; set g }]
    if {![llength $more]} { return {} }
    list $option=[join [concat [settingGlobs $setting] $more] ,]
}

# The selected file, if it is managed (Fossil knows it).
proc tkcommit::managed {} {
    variable current
    variable files
    if {$current eq "" || ![dict exists $files $current]
            || [dict get $files $current] eq "EXTRA"} {
        bell
        return ""
    }
    return $current
}

# The selected files that are managed (or the one shown); none: a bell.
proc tkcommit::managedFiles {} {
    variable files
    variable current
    set paths [lmap p [selectedFiles] {
        if {![dict exists $files $p] || [dict get $files $p] eq "EXTRA"} continue
        set p
    }]
    if {![llength $paths] && $current ne "" && [dict exists $files $current]
            && [dict get $files $current] ne "EXTRA"} {
        set paths [list $current]
    }
    if {![llength $paths]} { bell }
    return $paths
}

proc tkcommit::finish {code out what} {
    refresh
    if {$code} { showLog "$what failed" $out }
    return [expr {!$code}]
}

# ------------------------------------------------------- rename, remove

# Rename or move the selected file (fossil mv); on disk too, unless not
# wanted.
proc tkcommit::renameFile {} {
    variable renameTo
    variable renameFrom
    variable onDisk
    set paths [managedFiles]
    if {![llength $paths]} return
    if {[llength $paths] > 1} {
        moveFiles $paths
        return
    }
    set path [lindex $paths 0]
    set renameFrom $path
    set renameTo $path
    set onDisk 1
    set w [dialog .commit.rename "Rename or move" \
        "Rename or move $path: its new name, or a directory to move it into." Rename \
        {tkcommit::renamePreview}]
    field $w to "New name:" tkcommit::renameTo 50
    checkField $w disk "Also rename the file on disk (otherwise Fossil only records the new name)" \
        tkcommit::onDisk
    after idle [list ui::focusIfThere $w.f.opts.to]
    if {![waitDialog $w]} return
    set to [string trim $renameTo]
    if {$to eq "" || $to eq $path} return
    lassign [fossil mv [expr {$onDisk ? "--hard" : "--soft"}] [filearg $path] [filearg $to]] code out
    if {[finish $code $out "fossil mv"]} {
        set ::tkcommit::status "Renamed $path to $to"
        if {[.commit.main.files.t exists $to]} { .commit.main.files.t selection set [list $to] }
    }
}

proc tkcommit::renamePreview {} {
    variable renameFrom
    variable renameTo
    variable onDisk
    set to [string trim $renameTo]
    if {$to eq "" || $to eq $renameFrom} { return "(the same name)" }
    dryRun mv -n [expr {$onDisk ? "--hard" : "--soft"}] [filearg $renameFrom] [filearg $to]
}

# Move several files into a directory: each to DIR/NAME ("fossil mv" takes
# several files only into a directory that exists).
proc tkcommit::moveFiles {paths} {
    variable renameTo
    variable onDisk
    variable moving $paths
    set renameTo [file dirname [lindex $paths 0]]
    if {$renameTo eq "."} { set renameTo "" }
    set onDisk 1
    set w [dialog .commit.rename "Move files" "Move these [llength $paths] files into a\
        directory (of the checkout):\n[join $paths {, }]" Move \
        {tkcommit::movePreview}]
    field $w to "Into the directory:" tkcommit::renameTo 50
    checkField $w disk "Also move the files on disk (otherwise Fossil only records the new names)" \
        tkcommit::onDisk
    after idle [list ui::focusIfThere $w.f.opts.to]
    if {![waitDialog $w]} return
    set to [string trim $renameTo /]
    if {$to eq ""} return
    set code 0
    set out ""
    foreach p $paths {
        lassign [fossil mv [expr {$onDisk ? "--hard" : "--soft"}] [filearg $p] [filearg $to/[file tail $p]]] c o
        append out $o\n
        if {$c} {
            set code $c
            break
        }
    }
    if {[finish $code $out "fossil mv"]} { set ::tkcommit::status "Moved [llength $paths] files to $to" }
}

proc tkcommit::movePreview {} {
    variable moving
    variable renameTo
    variable onDisk
    set to [string trim $renameTo /]
    if {$to eq ""} { return "(the directory is missing)" }
    join [lmap p $moving {
        dryRun mv -n [expr {$onDisk ? "--hard" : "--soft"}] [filearg $p] [filearg $to/[file tail $p]]
    }] \n
}

# A directory of the checkout: the one of the selected file to start with.
proc tkcommit::currentDir {} {
    variable current
    set dir [expr {$current eq "" ? "" : [file dirname $current]}]
    expr {$dir eq "." ? "" : $dir}
}

# Rename or move a directory with all its files (fossil mv DIR NEW).
proc tkcommit::renameDir {} {
    variable dirName
    variable renameTo
    variable onDisk
    set dirName [currentDir]
    set renameTo $dirName
    set onDisk 1
    set w [dialog .commit.rename "Rename or move a directory" "Rename or move a directory\
        of the checkout with all its files." Rename {tkcommit::dirRenamePreview}]
    field $w dir "Directory:" tkcommit::dirName 50
    field $w to "New name:" tkcommit::renameTo 50
    checkField $w disk "Also rename it on disk (otherwise Fossil only records the new names)" \
        tkcommit::onDisk
    after idle [list ui::focusIfThere $w.f.opts.to]
    if {![waitDialog $w]} return
    set dir [string trim $dirName /]
    set to [string trim $renameTo /]
    if {$dir eq "" || $to eq "" || $to eq $dir} return
    lassign [fossil mv [expr {$onDisk ? "--hard" : "--soft"}] [filearg $dir] [filearg $to]] code out
    if {[finish $code $out "fossil mv"]} { set ::tkcommit::status "Renamed $dir to $to" }
}

proc tkcommit::dirRenamePreview {} {
    variable dirName
    variable renameTo
    variable onDisk
    set dir [string trim $dirName /]
    set to [string trim $renameTo /]
    if {$dir eq "" || $to eq "" || $to eq $dir} { return "(the same name)" }
    dryRun mv -n [expr {$onDisk ? "--hard" : "--soft"}] [filearg $dir] [filearg $to]
}

# Remove a directory's files from the repository (fossil rm DIR).
proc tkcommit::removeDir {} {
    variable dirName
    variable onDisk
    set dirName [currentDir]
    set onDisk 0
    set w [dialog .commit.remove "Remove a directory" "Remove the files of a directory\
        from the repository: from the next commit on, Fossil no longer has them." Remove \
        {tkcommit::dirRemovePreview}]
    field $w dir "Directory:" tkcommit::dirName 50
    checkField $w disk "Also delete the files on disk" tkcommit::onDisk
    after idle [list ui::focusIfThere $w.f.opts.dir]
    if {![waitDialog $w]} return
    set dir [string trim $dirName /]
    if {$dir eq ""} return
    lassign [fossil rm [expr {$onDisk ? "--hard" : "--soft"}] [filearg $dir]] code out
    if {[finish $code $out "fossil rm"]} { set ::tkcommit::status "Removed $dir" }
}

proc tkcommit::dirRemovePreview {} {
    variable dirName
    variable onDisk
    set dir [string trim $dirName /]
    if {$dir eq ""} { return "(the directory is missing)" }
    dryRun rm -n [expr {$onDisk ? "--hard" : "--soft"}] [filearg $dir]
}

# Remove the selected file from the repository (fossil rm); from the disk
# only if wanted (otherwise it is forgotten: fossil forget).
proc tkcommit::removeFile {} {
    variable onDisk
    variable removing
    set paths [managedFiles]
    if {![llength $paths]} return
    set removing $paths
    set what [expr {[llength $paths] == 1 ? [lindex $paths 0] : "these [llength $paths] files"}]
    set onDisk 0
    set w [dialog .commit.remove "Remove" "Remove $what from the repository: from the next\
        commit on, Fossil no longer has [expr {[llength $paths] == 1 ? "it" : "them"}].  (An\
        added file is only no longer added.)" \
        Remove {tkcommit::dryRun rm -n [expr {$tkcommit::onDisk ? "--hard" : "--soft"}]\
            {*}[lmap p $tkcommit::removing { tkcommit::filearg $p }]}]
    checkField $w disk "Also delete the [expr {[llength $paths] == 1 ? "file" : "files"}] on disk" tkcommit::onDisk
    if {![waitDialog $w]} return
    lassign [fossil rm [expr {$onDisk ? "--hard" : "--soft"}] {*}[lmap p $paths { filearg $p }]] code out
    if {[finish $code $out "fossil rm"]} { set ::tkcommit::status "Removed $what" }
}

# Add all unmanaged files and remove all missing ones (fossil addremove).
proc tkcommit::addRemove {} {
    set w [dialog .commit.addremove "Add new and remove missing" "Add all unmanaged\
        files (except those of the ignore-glob setting) and remove the missing ones from\
        the repository: they are committed with the next commit." "Add and remove" \
        {tkcommit::dryRun addremove -n {*}[tkcommit::globOpts]}]
    globFields $w
    if {![waitDialog $w]} return
    lassign [fossil addremove {*}[globOpts]] code out
    if {[finish $code $out "fossil addremove"]} {
        set ::tkcommit::status [lindex [split [string trim $out] \n] end]
    }
}

proc tkcommit::globFields {w {clean 1}} {
    checkField $w dot "Include files whose names begin with a dot" tkcommit::dotfiles
    field $w ignore "Also ignore:" tkcommit::ignoreGlob
    if {$clean} { field $w clean "And these:" tkcommit::cleanGlob }
    ttk::label $w.f.opts.globs -foreground gray35 -text "Comma-separated glob patterns,\
        added to those of the ignore-glob (and clean-glob) settings."
    grid $w.f.opts.globs - -sticky w
}

# Undo the adds and removes not committed yet (addremove --reset); with
# WHICH add or rm only the adds (add --reset) or the removes (rm --reset).
proc tkcommit::resetAdds {{which addremove}} {
    set title [dict get {addremove "Reset adds and removes" add "Reset adds" rm "Reset removes"} $which]
    set message [dict get {
        addremove "Files added are no longer added, files removed no longer removed"
        add "Files added are no longer added"
        rm "Files removed are no longer removed"} $which]
    set w [dialog .commit.reset $title "$message (the files on disk stay as they are)." \
        Reset [list tkcommit::dryRun $which --reset -n -v]]
    if {![waitDialog $w]} return
    lassign [fossil $which --reset -v] code out
    if {[finish $code $out "fossil $which --reset"]} { set ::tkcommit::status $title }
}

# ---------------------------------------------------------------- clean

# The options of "fossil clean" chosen.
proc tkcommit::cleanOpts {} {
    variable emptydirs
    variable dirsonly
    variable temp
    variable verily
    variable keepGlob
    set result [globOpts 0]
    if {$emptydirs} { lappend result --emptydirs }
    if {$dirsonly} { lappend result --dirsonly }
    if {$temp} { lappend result --temp }
    if {$verily} { lappend result -x }
    if {$::tkcommit::allckouts} { lappend result --allckouts }
    lappend result {*}[globOpt --keep keep-glob $keepGlob]
    return $result
}

# What "clean -n" would delete: {path kind}..., in the dialog's list.
proc tkcommit::cleanPreview {} {
    variable cleanList
    variable cleanSkip
    lassign [fossil clean -n {*}[cleanOpts]] code out
    set cleanList {}
    foreach line [split $out \n] {
        if {[regexp {^Removed unmanaged (file|directory): (.*)$} $line -> kind path]} {
            lappend cleanList [list $path $kind]
        }
    }
    set t .commit.clean.f.opts.list.t
    if {[winfo exists $t]} {
        $t delete [$t children {}]
        foreach item $cleanList {
            lassign $item path kind
            $t insert {} end -id $path -values [list [expr {[info exists cleanSkip($path)]
                ? "\u2610" : "\u2611"}] $path $kind]
        }
    }
    set n [llength [cleanChosen]]
    expr {$code ? "Fossil refuses:\n$out" : "[llength $cleanList] found, $n checked to delete."}
}

proc tkcommit::cleanChosen {} {
    variable cleanList
    variable cleanSkip
    lmap item $cleanList {
        if {[info exists cleanSkip([lindex $item 0])]} continue
        set item
    }
}

proc tkcommit::cleanToggle {path} {
    variable cleanSkip
    if {$path eq ""} return
    if {[info exists cleanSkip($path)]} { unset cleanSkip($path) } else { set cleanSkip($path) 1 }
    tkcommit::runPreview .commit.clean
}

# Delete unmanaged files (fossil clean): the ones checked in the list of its
# dry run, after a confirmation that names each.
proc tkcommit::cleanFiles {} {
    variable cleanSkip
    variable root
    array unset cleanSkip
    set w [dialog .commit.clean "Delete unmanaged files" "Delete files that Fossil does\
        not manage (except those of the ignore-glob and keep-glob settings).  Uncheck\
        the ones to keep." "Delete\u2026" tkcommit::cleanPreview]
    checkField $w dot "Include files whose names begin with a dot" tkcommit::dotfiles
    checkField $w empty "Also delete empty directories" tkcommit::emptydirs
    checkField $w dirs "Only empty directories" tkcommit::dirsonly
    checkField $w temp "Only Fossil's temporary files (of merges and conflicts)" tkcommit::temp
    checkField $w verily "Everything not managed: ignore the ignore-glob and keep-glob\
        settings; nothing can be undone" tkcommit::verily
    checkField $w allck "Also in checkouts nested in this one (--allckouts): their own\
        settings are not taken into account" tkcommit::allckouts
    field $w ignore "Also ignore:" tkcommit::ignoreGlob
    field $w keep "Also keep:" tkcommit::keepGlob
    set f $w.f.opts.list
    ttk::frame $f
    ttk::treeview $f.t -columns {check path kind} -show headings -height 10 \
        -selectmode browse -yscrollcommand [list $f.y set]
    popup::attach $f.t tkcommit::cleanMenu
    ttk::scrollbar $f.y -command [list $f.t yview]
    set char [font measure TkDefaultFont 0]
    $f.t heading path -text File -anchor w
    $f.t heading kind -text Kind -anchor w
    $f.t column check -width [expr {$char * 3}] -stretch 0 -anchor center
    $f.t column path -width [expr {$char * 60}] -stretch 1
    $f.t column kind -width [expr {$char * 10}] -stretch 0
    grid $f.t $f.y -sticky news
    grid columnconfigure $f 0 -weight 1
    grid $f - -sticky news -pady {6 0}
    bind $f.t <ButtonPress-1> {
        if {[%W identify column %x %y] eq "#1" && [%W identify region %x %y] eq "cell"} {
            tkcommit::cleanToggle [%W identify item %x %y]
        }
    }
    bind $f.t <space> {tkcommit::cleanToggle [lindex [%W selection] 0]}
    # (Its dry run is only a count: the list is above.)
    $w.f.p.t configure -height 2
    if {![waitDialog $w]} return
    set chosen [cleanChosen]
    if {![llength $chosen]} return
    # Which ones Undo cannot bring back.
    set big {}
    foreach item $chosen {
        lassign $item path kind
        if {$kind eq "file" && ![catch {file size [file join $root $path]} size]
                && $size >= 10 * 1024 * 1024} {
            lappend big $path
        }
    }
    # Files of the clean-glob setting: Fossil deletes them without undo.
    set globs [cleanGlobs]
    set noUndo {}
    foreach item $chosen {
        lassign $item path kind
        if {$kind ne "file" || $path in $big} continue
        foreach g $globs {
            if {[string match $g $path] || [string match $g [file tail $path]]} {
                lappend noUndo $path
                break
            }
        }
    }
    # Directories that "--emptydirs" removes as well: emptied by this.
    set emptied [expr {$::tkcommit::emptydirs ? [emptiedDirs $chosen] : {}}]
    set n [expr {[llength $chosen] + [llength $emptied]}]
    set w [dialog .commit.cleanok "Delete unmanaged files" "Delete these\
        $n files and directories?" Delete {}]
    if {$::tkcommit::verily} {
        set note "Nothing can be brought back: undo is off with \"everything not managed\"."
    } else {
        set lost [concat $big $noUndo]
        set note "Undo brings them back"
        if {[llength $lost]} {
            append note ", except: [join $lost {, }]"
            set why {}
            if {[llength $big]} { lappend why "files of 10 MiB or more" }
            if {[llength $noUndo]} { lappend why "files of the clean-glob setting ([join $globs {, }])" }
            append note " ([join $why {; }]: Fossil deletes them without undo)"
        }
        append note .
    }
    ttk::label $w.f.opts.note -text $note -wraplength 640 -foreground red3
    text $w.f.opts.t -width 80 -height [expr {min(20, $n)}] -font TkFixedFont
    $w.f.opts.t insert end [join [lmap item $chosen { lindex $item 0 }] \n]
    foreach dir $emptied { $w.f.opts.t insert end "\n$dir/  (becomes empty: deleted too)" }
    $w.f.opts.t configure -state disabled
    grid $w.f.opts.note -sticky w
    grid $w.f.opts.t -sticky news
    $w.f.b.ok configure -default normal
    $w.f.b.cancel configure -default active
    after idle [list ui::focusIfThere $w.f.b.cancel]
    if {![waitDialog $w]} return
    # The files with "fossil clean" (undoable); without --emptydirs and
    # --dirsonly, which scan the whole tree whatever is named: the empty
    # directories chosen (and those emptied) are removed here, each only if
    # empty.
    set opts [lmap o [cleanOpts] { if {$o in {--emptydirs --dirsonly}} continue; set o }]
    set paths [lmap item $chosen { if {[lindex $item 1] ne "file"} continue; lindex $item 0 }]
    set dirs [lmap item $chosen { if {[lindex $item 1] eq "file"} continue; lindex $item 0 }]
    set code 0
    set out ""
    if {[llength $paths]} {
        lassign [fossil clean --force {*}$opts {*}[lmap p $paths { filearg $p }]] code out
    }
    if {!$code} {
        foreach dir [lsort -decreasing -command {::apply {{a b} {
                expr {[llength [file split $a]] - [llength [file split $b]]}
            }}} [concat $dirs $emptied]] {
            set full [file join $root $dir]
            if {[file isdirectory $full] && [llength [lmap e [glob -nocomplain -tails -directory $full * .*] {
                    if {$e in {. ..}} continue; set e }]] == 0} {
                if {[catch {file delete $full} msg]} {
                    append out "\nCannot delete $dir: $msg"
                    set code 1
                } else {
                    append out "\nRemoved empty directory: $dir"
                }
            }
        }
    }
    if {[finish $code $out "fossil clean"]} {
        set ::tkcommit::status "Deleted [llength $chosen] unmanaged files and directories"
    }
}

# The patterns of the clean-glob setting (the versioned file first).
proc tkcommit::cleanGlobs {} {
    settingGlobs clean-glob
}

# The patterns of a glob setting (ignore-glob, clean-glob, keep-glob): the
# versioned file .fossil-settings/NAME first, else the setting.
proc tkcommit::settingGlobs {name} {
    variable root
    set file [file join $root .fossil-settings $name]
    set value ""
    if {[file exists $file]} {
        catch {
            set f [open $file]
            set value [read $f]
            close $f
        }
    } else {
        lassign [fossil settings $name --exact] code out
        foreach line [split $out \n] {
            if {[regexp {^(\S+)\s+(?:\([^)]*\)\s+)?(.*)$} $line -> n v] && $n eq $name} { set value $v }
        }
    }
    lmap g [split $value ", \n\t\r"] { if {$g eq ""} continue; set g }
}

# The directories that become empty when the files and directories CHOSEN
# ({path kind}...) are deleted, the deepest first: "clean --emptydirs"
# deletes them too.
proc tkcommit::emptiedDirs {chosen} {
    variable root
    set gone {}
    foreach item $chosen { dict set gone [lindex $item 0] 1 }
    set candidates {}
    foreach item $chosen {
        set dir [file dirname [lindex $item 0]]
        while {$dir ne "." && $dir ne "/" && $dir ne ""} {
            dict set candidates $dir 1
            set dir [file dirname $dir]
        }
    }
    set dirs [lsort -decreasing -command {::apply {{a b} {
        expr {[llength [file split $a]] - [llength [file split $b]]}
    }}} [dict keys $candidates]]
    set emptied {}
    foreach dir $dirs {
        if {[dict exists $gone $dir]} continue
        set empty 1
        foreach entry [glob -nocomplain -tails -directory [file join $root $dir] * .*] {
            if {$entry in {. ..}} continue
            if {![dict exists $gone $dir/$entry]} {
                set empty 0
                break
            }
        }
        if {$empty} {
            lappend emptied $dir
            dict set gone $dir 1
        }
    }
    return $emptied
}

# ------------------------------------------------------- revert, undo

# Revert the selected file, or with $all every change, to the check-in of
# the checkout or to another version (fossil revert -r).
proc tkcommit::revertFiles {{all 0}} {
    variable revision
    variable files
    if {$all} {
        set paths {}
        set what "all changes of the checkout"
        set list [join [dict keys [dict filter $files script {k v} { expr {$v ni {EXTRA UNCHANGED}} }]] \n]
        if {$list eq ""} {
            tk_messageBox -icon info -title Revert -message "The checkout has no changes to revert."
            return
        }
    } else {
        set paths [managedFiles]
        if {![llength $paths]} return
        set what [expr {[llength $paths] == 1 ? [lindex $paths 0] : "these [llength $paths] files"}]
        set list [expr {[llength $paths] == 1 ? "" : [join $paths \n]}]
    }
    set revision ""
    set w [dialog .commit.revert "Revert" "Revert $what: the changes are lost\
        (Undo can bring them back until the next update or commit)." Revert {}]
    field $w rev "To the version:" tkcommit::revision 30
    ttk::label $w.f.opts.revnote -foreground gray35 -text "Empty: the check-in of the\
        checkout; otherwise a check-in, branch or tag (only for the files named)."
    grid $w.f.opts.revnote - -sticky w
    if {$list ne ""} {
        if {$all} { $w.f.opts.rev state disabled }
        text $w.f.opts.t -width 80 -height [expr {min(16, [llength [split $list \n]] + 1)}] \
            -font TkFixedFont
        $w.f.opts.t insert end $list
        $w.f.opts.t configure -state disabled
        grid $w.f.opts.t - -sticky news -pady {6 0}
    }
    if {![waitDialog $w]} return
    set args {}
    set rev [string trim $revision]
    if {$rev ne ""} {
        set bad [fossil::valueProblem Version $rev version]
        if {$bad ne ""} {
            tk_messageBox -icon error -title Revert -message $bad
            return
        }
        lappend args --revision=$rev
    }
    lassign [fossil revert {*}$args {*}[lmap p $paths { filearg $p }]] code out
    if {[finish $code $out "fossil revert"]} { set ::tkcommit::status "Reverted $what" }
}

# Undo (or redo) the last update, merge, revert, stash or clean; with a
# file, only for it.
proc tkcommit::undo {{which undo} {paths ""}} {
    set files [lmap p $paths { filearg $p }]
    set path [expr {[llength $paths] == 1 ? [lindex $paths 0] : [llength $paths] ? "[llength $paths] files" : ""}]
    lassign [fossil $which -n {*}$files] code out
    set Which [string totitle $which]
    # (With only an undo, "redo -n" describes the undo, and the other way.)
    if {$code || ![regexp "^An? $which is available" [string trim $out]]} {
        tk_messageBox -icon info -title $Which -message "Nothing to [string tolower $which]." \
            -detail [string trim $out]
        return
    }
    # (With files: Fossil's dry run still lists the whole undo.)
    set detail [string trim $out]
    if {[llength $paths]} {
        set detail "Only these files:\n[join $paths \n]\n\nThe whole $which (Fossil's dry run\
            lists all of it):\n$detail"
    }
    if {![ui::confirm -title $Which \
            "$Which[expr {$path eq "" ? "" : " for $path"}]?" \
            $detail]} return
    lassign [fossil $which {*}$files] code out
    if {[finish $code $out "fossil $which"]} { set ::tkcommit::status "[string trim $out]" }
}

# Undo (or redo) for the selected files only.
proc tkcommit::undoFile {{which undo}} {
    set paths [managedFiles]
    if {[llength $paths]} { undo $which $paths }
}

# All changes against the state before the last undoable command.
proc tkcommit::diffUndo {} {
    variable root
    diffview::run "Changes since before the last undoable command" -dir $root \
        -- -N --undo {*}[diffopts::args]
}

# The version the diffs are against (fossil diff --from).
proc tkcommit::compareWith {} {
    variable from
    variable revision
    set revision $from
    set w [dialog .commit.from "Compare with" "Show the changes of the files against\
        another version: a check-in, branch or tag.  Empty: the check-in of the\
        checkout." OK {}]
    field $w rev "Version:" tkcommit::revision 30
    after idle [list ui::focusIfThere $w.f.opts.rev]
    if {![waitDialog $w]} return
    set v [string trim $revision]
    set bad [expr {$v eq "" ? "" : [fossil::valueProblem Version $v version]}]
    if {$bad ne ""} {
        tk_messageBox -icon error -title "Compare with" -message $bad
        return
    }
    set from $v
    refresh
}

# The options of "fossil diff" for the diffs of the checkout.
proc tkcommit::diffArgs {} {
    variable from
    set result [diffopts::args]
    if {$from ne ""} { lappend result --from=$from }
    return $result
}

# ---------------------------------------------------------------- merge

# What the last merge did (fossil merge-info): with $allMerge every file.
proc tkcommit::mergeInfo {} {
    if {![mergeInfoOk]} return
    set w .commit.merge
    if {![winfo exists $w]} {
        toplevel $w
        wm title $w "Merge details"
        ttk::frame $w.bar -padding 4
        ttk::checkbutton $w.bar.all -text "All files the merge changed" \
            -variable tkcommit::allMerge -command tkcommit::mergeInfo
        ttk::button $w.bar.three -text "Three-way view" -command tkcommit::threeWaySelected
        ttk::button $w.bar.close -text Close -command [list destroy $w]
        pack $w.bar.all -side left
        pack $w.bar.close $w.bar.three -side right -padx {4 0}
        icons::tooltip $w.bar.three "The file of the line clicked: its baseline, local,\
            merged-in and merged versions side by side (double-click a line too)"
        text $w.t -width 90 -height 24 -font TkFixedFont -wrap none \
            -yscrollcommand [list $w.y set]
        ttk::scrollbar $w.y -command [list $w.t yview]
        $w.t tag configure conflict -foreground red3
        $w.t tag configure current -background gray90
        bind $w.t <1> {tkcommit::mergeLine [%W index @%x,%y]}
        bind $w.t <Double-1> {tkcommit::mergeLine [%W index @%x,%y]; tkcommit::threeWaySelected}
        bind $w.t <ButtonPress-3> {tkcommit::mergeMenu %x %y %X %Y}
        if {[tk windowingsystem] eq "aqua"} {
            bind $w.t <ButtonPress-2> {tkcommit::mergeMenu %x %y %X %Y}
            bind $w.t <Control-ButtonPress-1> {tkcommit::mergeMenu %x %y %X %Y}
        }
        grid $w.bar - -sticky we
        grid $w.t $w.y -sticky news
        grid columnconfigure $w 0 -weight 1
        grid rowconfigure $w 1 -weight 1
        bind $w <Escape> [list destroy $w]
    }
    lassign [fossil merge-info {*}[expr {$::tkcommit::allMerge ? "-a" : ""}]] code out
    $w.t configure -state normal
    $w.t delete 1.0 end
    foreach line [split [string trim $out] \n] {
        $w.t insert end $line\n [expr {[regexp {^\s*(CONFLICT|ERROR)} $line] ? "conflict" : ""}]
    }
    $w.t configure -state disabled
    raise $w
}

# 1 if this Fossil can tell what the last merge did, else said and 0.
proc tkcommit::mergeInfoOk {} {
    if {[fossil::hasCommand merge-info]} { return 1 }
    ui::infoBox -title "Merge details" "Merge details need Fossil 2.26 or newer." \
        "They come from \"fossil merge-info\", which [fossil::exe] does not have."
    return 0
}

# ---------------------------------------------------------------- update

# The update options of the dialogs: --latest, --setmtime, -K.
proc tkcommit::updateOpts {{latestToo 1}} {
    variable latest
    variable setmtime
    variable keepMerge
    set result {}
    if {$latestToo && $latest} { lappend result --latest }
    if {$setmtime} { lappend result --setmtime }
    if {$keepMerge} { lappend result -K }
    return $result
}

# Update the checkout to the newest check-in of its branch (fossil update,
# no pull), or of the branch TARGET, after its dry run.
proc tkcommit::updateCheckout {{target ""}} {
    variable latest 0
    variable updateTo $target
    # The check-in moved to another branch since (tkcommit::branchMoved):
    # the update would follow it there; to the old branch instead?
    set moved [expr {$target eq "" ? [branchMoved] : {}}]
    if {[llength $moved]} {
        lassign $moved to from user date
        if {$from ne "" && ![catch {fossil::arg $from}]} {
            switch [ui::askCancel -title Update -icon warning -default yes \
                    "The check-in of the checkout was moved to $to." \
                    "It was moved from $from by $user on $date (a tag change, as \"fossil\
                    amend --branch\" makes), and an update follows the branch of the\
                    check-in: along $to.\n\nUpdate to the newest check-in of $from instead\
                    (Yes), or along $to (No)?"] {
                yes { set updateTo $from }
                no {}
                default return
            }
        }
    }
    set what [expr {$updateTo eq "" ? "the newest check-in of its branch" : "the newest check-in of $updateTo"}]
    set w [dialog .commit.update "Update" "Update the checkout to $what (nothing is\
        pulled first).  Uncommitted changes are merged into the new version." Update \
        {tkcommit::dryRun update --nosync -n {*}[tkcommit::updateOpts] {*}$::tkcommit::updateTo}]
    checkField $w latest "To the newest check-in of any branch (--latest)" tkcommit::latest
    checkField $w mtime "Set the times of the files to their check-ins' (--setmtime)" tkcommit::setmtime
    checkField $w keep "On a merge conflict, keep the files of the three versions (-K)" tkcommit::keepMerge
    if {![waitDialog $w]} return
    lassign [fossil update --nosync {*}[updateOpts] {*}$updateTo] code out
    if {!$code} { remember }
    if {[finish $code $out "fossil update"]} {
        set ::tkcommit::status [lindex [split [string trim $out] \n] 0]
        showLog Updated $out
    }
}

# Update only the selected files to a version (fossil update VERSION FILE...).
proc tkcommit::updateFiles {} {
    variable revision
    variable updating
    set paths [managedFiles]
    if {![llength $paths]} return
    set updating $paths
    set revision ""
    set what [expr {[llength $paths] == 1 ? [lindex $paths 0] : "these [llength $paths] files"}]
    set w [dialog .commit.updatefiles "Update files to a version" "Update $what to how\
        [expr {[llength $paths] == 1 ? "it is" : "they are"}] in another version: a check-in,\
        branch or tag.  Their changes are merged into it; the rest of the checkout stays." \
        Update {tkcommit::updateFilesPreview}]
    field $w rev "Version:" tkcommit::revision 30
    checkField $w keep "On a merge conflict, keep the files of the three versions (-K)" tkcommit::keepMerge
    after idle [list ui::focusIfThere $w.f.opts.rev]
    if {![waitDialog $w]} return
    set v [string trim $revision]
    if {$v eq ""} return
    set bad [fossil::valueProblem Version $v version]
    if {$bad ne ""} {
        tk_messageBox -icon error -title Update -message $bad
        return
    }
    lassign [fossil update --nosync {*}[expr {$::tkcommit::keepMerge ? "-K" : ""}] $v \
        {*}[lmap p $paths { filearg $p }]] code out
    if {[finish $code $out "fossil update"]} { set ::tkcommit::status "Updated $what to $v" }
}

proc tkcommit::updateFilesPreview {} {
    variable revision
    variable updating
    set v [string trim $revision]
    if {$v eq ""} { return "(no version)" }
    if {[fossil::valueProblem Version $v version] ne ""} { return [fossil::valueProblem Version $v version] }
    dryRun update --nosync -n {*}[expr {$::tkcommit::keepMerge ? "-K" : ""}] $v \
        {*}[lmap p $updating { filearg $p }]
}

# Merge a fork of the checkout's branch into it (fossil merge, no
# version), after its dry run.
proc tkcommit::mergeFork {} {
    variable forks
    set w [dialog .commit.mergefork "Merge fork" "The branch has $forks leaves: merge the\
        other one into the checkout (nothing is pulled first).  Then commit to join them." \
        Merge {tkcommit::dryRun merge {*}[fossil::nosync merge] -n -v {*}[expr {$tkcommit::keepMerge ? "-K" : ""}]}]
    checkField $w keep "On a merge conflict, keep the files of the three versions (-K)" tkcommit::keepMerge
    if {![waitDialog $w]} return
    lassign [fossil merge {*}[fossil::nosync merge] {*}[expr {$::tkcommit::keepMerge ? "-K" : ""}]] code out
    if {[finish $code $out "fossil merge"]} {
        set ::tkcommit::status "Merged the fork: commit to join the leaves"
        showLog "Merged the fork" $out
    }
}

# ----------------------------------------------------------- compare

# The diff between two versions: check-ins, branches, tags, or a directory
# as the first; the second empty: the files of the checkout.
proc tkcommit::compareTwo {} {
    variable fromVersion
    variable toVersion
    variable root
    set w [dialog .commit.compare "Compare two versions" "The changes from one version to\
        another: a check-in, branch or tag.  From can also be a directory (a tree of files\
        elsewhere); To empty: the files of the checkout as they are." Compare {}]
    field $w from "From:" tkcommit::fromVersion 40
    ttk::button $w.f.opts.dir -text "Directory\u2026" -command {
        set d [tk_chooseDirectory -parent .commit.compare -title "Compare from the directory"]
        if {$d ne ""} { set tkcommit::fromVersion $d }
    }
    grid $w.f.opts.dir -row [dict get [grid info $w.f.opts.from] -row] -column 2 -padx {4 0}
    field $w to "To:" tkcommit::toVersion 40
    after idle [list ui::focusIfThere $w.f.opts.from]
    if {![waitDialog $w]} return
    set from [string trim $fromVersion]
    set to [string trim $toVersion]
    if {$from eq ""} return
    foreach {label v} [list From $from To $to] {
        set bad [expr {$v eq "" ? "" : [fossil::valueProblem $label $v version]}]
        if {$bad ne ""} {
            tk_messageBox -icon error -title "Compare two versions" -message $bad
            return
        }
    }
    # (A directory: as the diff sees it, from the checkout.)
    set dir [file join $root $from]
    if {[file isdirectory $dir]} { set from [file normalize $dir] }
    set args [list --from=$from]
    if {$to ne ""} { lappend args --to=$to }
    diffview::run "[file tail $from] \u2192 [expr {$to eq "" ? "the checkout" : $to}]" -dir $root \
        -- -N {*}[diffopts::args] {*}$args
}

# The file of a line of the merge details, as chosen.
proc tkcommit::mergeLine {index} {
    variable mergeFile
    set t .commit.merge.t
    set line [$t get "$index linestart" "$index lineend"]
    $t tag remove current 1.0 end
    # ("STATUS  path"; not ERROR lines nor Fossil's notes.)
    if {[regexp {^\s*([A-Z_]+)\s+(\S.*)$} $line -> what path] && $what ne "ERROR"} {
        regexp {^.*\s->\s(.*)$} $path -> path
        set mergeFile [string trim $path]
        $t tag add current "$index linestart" "$index lineend + 1 char"
    }
}

# The context menu of a line of the merge details (a file): its three-way
# view, its name.
proc tkcommit::mergeMenu {x y X Y} {
    variable mergeFile
    set mergeFile ""
    mergeLine [.commit.merge.t index @$x,$y]
    set m .commit.merge.ctx
    destroy $m
    menu $m -tearoff 0
    $m add command -label "Three-way view" -command tkcommit::threeWaySelected \
        -state [expr {$mergeFile eq "" ? "disabled" : "normal"}]
    $m add separator
    popup::copy $m "Copy file name" $mergeFile
    popup::default $m "Three-way view"
    tk_popup $m $X $Y
}

proc tkcommit::threeWaySelected {} {
    variable mergeFile
    if {![info exists mergeFile] || $mergeFile eq ""} {
        bell
        return
    }
    threeWay $mergeFile
}

# A merged file in four columns ("fossil merge-info --tcl FILE"): the
# baseline, the checkout's version, the one merged in, and the result; the
# lines changed, added and removed marked, as Fossil's own --tk view does.
proc tkcommit::threeWay {path} {
    set rows [mergeRows $path 3]
    if {[lindex $rows 0] eq "error"} {
        tk_messageBox -icon info -title "Three-way view" -message "No three-way view of $path." \
            -detail [lindex $rows 1]
        return
    }
    set rows [lindex $rows 1]
    set w .commit.threeway
    destroy $w
    toplevel $w
    wm title $w "Three ways: $path"
    wm geometry $w 1200x600
    ttk::frame $w.bar -padding 4
    foreach {b label pair} {d12 "Baseline \u2192 local" {0 1} d13 "Baseline \u2192 merged in" {0 2}
            d23 "Local \u2192 merged in" {1 2}} {
        ttk::button $w.bar.$b -text $label -command [list tkcommit::twoWay $path {*}$pair]
        pack $w.bar.$b -side left -padx {0 4}
    }
    ttk::button $w.bar.close -text Close -command [list destroy $w]
    pack $w.bar.close -side right
    pack $w.bar -fill x
    ttk::frame $w.f
    foreach i {0 1 2 3} {
        ttk::label $w.f.h$i -font TkHeadingFont -anchor w
        text $w.f.t$i -font TkFixedFont -wrap none -width 30 -state normal \
            -yscrollcommand [list tkcommit::threeWayScroll $w $i]
        $w.f.t$i tag configure chng -background #fff3c4
        $w.f.t$i tag configure add -background #e6ffec
        $w.f.t$i tag configure rm -background #ffebe9
        $w.f.t$i tag configure skip -foreground gray50 -background gray95
        $w.f.t$i tag configure none -background gray94
        grid $w.f.h$i -row 0 -column $i -sticky we
        grid $w.f.t$i -row 1 -column $i -sticky news
        grid columnconfigure $w.f $i -weight 1
    }
    ttk::scrollbar $w.f.y -command [list tkcommit::threeWayYview $w]
    grid $w.f.y -row 1 -column 4 -sticky ns
    grid rowconfigure $w.f 1 -weight 1
    pack $w.f -fill both -expand 1
    bind $w <Escape> [list destroy $w]
    foreach row $rows {
        lassign $row kind cells
        switch -- $kind {
            names {
                foreach i {0 1 2 3} { $w.f.h$i configure -text [lindex $cells $i] }
            }
            skip {
                foreach i {0 1 2 3} {
                    set n [lindex $cells $i]
                    $w.f.t$i insert end [expr {$n > 0 ? "\u2026 $n lines \u2026" : ""}]\n skip
                }
            }
            line {
                foreach i {0 1 2 3} {
                    lassign [lindex $cells $i] text tag
                    $w.f.t$i insert end $text\n $tag
                }
            }
        }
    }
    foreach i {0 1 2 3} { $w.f.t$i configure -state disabled }
}

# The rows of "fossil merge-info --tcl=FILE -c CONTEXT": {error message},
# or {ok ROWS} with each row {names {4 names}}, {skip {4 counts}} or
# {line {{text tag} x4}} (tag: chng, add, rm, none or "").  The output is a
# Tcl list of 4 cells per row; a cell's first character says what it is:
# N a name, S lines left out (in the first cell: "S a b c d"), "." no line
# here, 1/2/3 the text of that column, X a line removed, else (T) a line.
proc tkcommit::mergeRows {path context} {
    if {![fossil::hasCommand merge-info]} {
        return [list error "This Fossil has no \"fossil merge-info\" (it is new in Fossil 2.26)."]
    }
    lassign [fossil merge-info --tcl=$path -c $context] code out
    set out [string trim $out]
    if {$code || [string match ERROR* $out] || [catch {llength $out} n] || $n % 4} {
        return [list error $out]
    }
    set rows {}
    foreach {a b c d} $out {
        set cells [list $a $b $c $d]
        set keys [lmap x $cells { string index $x 0 }]
        # (The text as bytes of UTF-8, in Tcl's escapes.)
        set texts [lmap x $cells { encoding convertfrom utf-8 [string range $x 1 end] }]
        if {[lindex $keys 0] eq "S"} {
            scan [lindex $texts 0] "%d %d %d %d" na nb nc nd
            lappend rows [list skip [list $na $nb $nc $nd]]
            continue
        }
        if {"N" in $keys} {
            lappend rows [list names $texts]
            continue
        }
        set line {}
        foreach i {0 1 2 3} {
            set key [lindex $keys $i]
            set key4 [lindex $keys 3]
            if {$key eq "."} {
                lappend line [list "" none]
            } elseif {$key in {1 2 3}} {
                # The text of that column.
                set tag [dict get {1 "" 2 chng 3 add} $key]
                if {$i == 1 && $key4 eq "2"} { set tag chng }
                lappend line [list [lindex $texts [expr {$key - 1}]] $tag]
            } elseif {$key eq "X"} {
                lappend line [list [lindex $texts $i] rm]
            } else {
                set tag ""
                if {$i == 1 && $key4 eq "2"} { set tag chng }
                if {$i == 2 && $key4 eq "3"} { set tag add }
                lappend line [list [lindex $texts $i] $tag]
            }
        }
        lappend rows [list line $line]
    }
    list ok $rows
}

# Two of the merge's versions of a file, whole, compared: 0 the baseline,
# 1 the checkout's, 2 the one merged in (fossil xdiff of the two).
proc tkcommit::twoWay {path from to} {
    lassign [mergeRows $path -1] status rows
    if {$status ne "ok"} {
        tk_messageBox -icon info -title "Two-way view" -message "No view of $path." -detail $rows
        return
    }
    set texts {{} {} {}}
    set names {baseline local merge-in}
    foreach row $rows {
        lassign $row kind cells
        if {$kind ne "line"} continue
        foreach i {0 1 2} {
            lassign [lindex $cells $i] text tag
            if {$tag ne "none"} { lset texts $i [concat [lindex $texts $i] [list $text]] }
        }
    }
    set files {}
    foreach i [list $from $to] {
        set f [file tempfile name]
        fconfigure $f -encoding utf-8
        puts $f [join [lindex $texts $i] \n]
        close $f
        lappend files $name
    }
    lassign [fossil xdiff -i {*}$files] code out
    file delete {*}$files
    # (The temporary names as the versions.)
    set out [string map [list [lindex $files 0] "[lindex $names $from]/$path" \
        [lindex $files 1] "[lindex $names $to]/$path"] $out]
    diffview::show "$path: [lindex $names $from] \u2192 [lindex $names $to]" $out
}

proc tkcommit::threeWayYview {w args} {
    foreach i {0 1 2 3} { $w.f.t$i yview {*}$args }
}

proc tkcommit::threeWayScroll {w i first last} {
    $w.f.y set $first $last
    foreach j {0 1 2 3} {
        if {$j != $i} { $w.f.t$j yview moveto $first }
    }
}

# --------------------------------------------------------------- patches

# Save all changes of the checkout as a Fossil patch file.
proc tkcommit::savePatch {} {
    variable files
    variable root
    if {![dict size [dict filter $files script {k v} { expr {$v ni {EXTRA UNCHANGED}} }]]} {
        tk_messageBox -icon info -title Patch -message "The checkout has no changes."
        return
    }
    set file [tk_getSaveFile -title "Save the changes as a patch" -parent . \
        -initialfile [file tail [string trimright $root /]].patch -defaultextension .patch \
        -filetypes {{"Fossil patches" .patch} {"All files" *}}]
    if {$file eq ""} return
    # (The file dialog asked before replacing a file.)
    lassign [fossil patch create -f [file normalize $file]] code out
    if {[finish $code $out "fossil patch create"]} { set ::tkcommit::status "Saved the changes in $file" }
}

proc tkcommit::choosePatch {title} {
    tk_getOpenFile -title $title -parent . -filetypes {{"Fossil patches" .patch} {"All files" *}}
}

# Apply a patch file to the checkout, after its dry run; over uncommitted
# changes only if they may be discarded.
proc tkcommit::applyPatch {{file ""}} {
    variable discard
    variable files
    if {$file eq ""} { set file [choosePatch "Apply a patch"] }
    if {$file eq ""} return
    set file [file normalize $file]
    # "fossil patch apply" updates the checkout to the patch's baseline
    # with a plain "fossil update": with autosync on that pulls (there is
    # no --nosync for it).
    if {[autosyncOn]} {
        tk_messageBox -icon info -title "Apply a patch" -message "Autosync is on: applying a\
            patch would pull from the remote first." -detail "Fossil updates the checkout to\
            the patch's baseline with a sync.  Turn the autosync setting off (Repository\
            \u25b8 Settings) to apply patches here.\n\n[patchHeader $file]"
        return
    }
    set discard 0
    set changed [dict size [dict filter $files script {k v} { expr {$v ni {EXTRA UNCHANGED}} }]]
    set w [dialog .commit.patch "Apply a patch" "Apply the patch [file tail $file] to the\
        checkout: it updates it to the patch's check-in and makes its changes." Apply \
        [list apply {{file} {
            tkcommit::dryRun patch apply -n {*}[expr {$tkcommit::discard ? "-f" : ""}] $file
        }} $file]]
    checkField $w discard "Discard the uncommitted changes of the checkout first (they are lost)" \
        tkcommit::discard
    if {!$changed} { $w.f.opts.discard state disabled }
    # The patch's header: its baseline, who made it, where and when.
    ttk::label $w.f.opts.head -text [patchHeader $file] -font TkFixedFont -justify left
    grid $w.f.opts.head - -sticky w -pady {6 0}
    if {![waitDialog $w]} return
    lassign [fossil patch apply -v {*}[expr {$discard ? "-f" : ""}] $file] code out
    if {[finish $code $out "fossil patch apply"]} {
        set ::tkcommit::status "Applied [file tail $file]"
        showLog "Applied [file tail $file]" $out
    }
}

# The header of a patch file ("fossil patch view -v"): its baseline, user,
# host, time, checkout; not its file list.
proc tkcommit::patchHeader {file} {
    lassign [fossil patch view -v $file] code out
    if {$code} { return [string trim $out] }
    join [lmap line [split [string trim $out] \n] {
        if {![regexp {^(BASELINE|PROJECT-NAME|TIMESTAMP|USER|HOSTNAME|CHECKOUT)\s} $line]} continue
        set line
    }] \n
}

# The diff of a patch file, in a diff window (its options and External
# diff work there); its header in the title.
proc tkcommit::viewPatch {{file ""}} {
    variable root
    if {$file eq ""} { set file [choosePatch "View a patch"] }
    if {$file eq ""} return
    set file [file normalize $file]
    set head [patchHeader $file]
    set who {}
    foreach key {USER TIMESTAMP BASELINE} {
        if {[regexp -line "^$key\\s+(.*)\$" $head -> v]} { lappend who [string trim $v] }
    }
    # (-f: also when the repository lacks the patch's baseline.)
    diffview::run "Patch [file tail $file] \u2014 [join $who {, }]" -dir $root \
        -command {fossil patch diff -f} -- -i -N {*}[diffopts::args] $file
}

# ------------------------------------------------------ commit options

# The options of "fossil commit" from the More options fields; an error
# names a value that cannot be passed.  (As --option=VALUE: a value cannot
# be taken for an option or a redirection.)
proc tkcommit::commitOpts {} {
    variable opt
    set result {}
    foreach tag [split $opt(tags) ", "] {
        if {$tag eq ""} continue
        set bad [fossil::valueProblem Tag $tag tag]
        if {$bad ne ""} { error $bad }
        lappend result --tag=$tag
    }
    foreach {key flag} {close --close integrate --integrate private --private
            allowFork --allow-fork allowEmpty --allow-empty allowConflict --allow-conflict
            allowOlder --allow-older overrideLock --override-lock ignoreOversize
            --ignore-oversize ignoreSkew --ignore-clock-skew hash --hash nosign --nosign
            noVerify --no-verify} {
        if {$opt($key)} { lappend result $flag }
    }
    foreach {key flag label kind} {bgcolor --bgcolor "Check-in colour" color
            branchcolor --branchcolor "Branch colour" color date --date-override Date date
            user --user-override "As user" name} {
        set value [string trim $opt($key)]
        if {$value eq ""} continue
        set bad [fossil::valueProblem $label $value $kind]
        if {$bad ne ""} { error $bad }
        lappend result $flag=$value
    }
    return $result
}

# After a commit: the one-shot options cleared.
proc tkcommit::resetOpts {} {
    variable once
    variable opt
    array set opt $once
}

proc tkcommit::chooseColor {key} {
    variable opt
    set c [tk_chooseColor -parent . -title "Colour" \
        {*}[expr {[string trim $opt($key)] ne "" ? [list -initialcolor $opt($key)] : ""}]]
    if {$c ne ""} { set opt($key) $c }
}

proc tkcommit::toggleMore {} {
    variable moreShown
    set moreShown [expr {!$moreShown}]
    .commit.bottom.opts.more configure -text [expr {$moreShown ? "Fewer options" : "More options"}]
    if {$moreShown} {
        grid .commit.bottom.more -row 3 -sticky w -pady {0 4}
    } else {
        grid forget .commit.bottom.more
    }
}

proc tkcommit::buildMore {f} {
    ttk::frame $f
    set row 0
    foreach {key label} {tags "Tags:" branchcolor "Branch colour:" bgcolor "Check-in colour:"
            date "Date:" user "As user:"} {
        ttk::label $f.${key}l -text $label
        ttk::entry $f.$key -textvariable tkcommit::opt($key) -width 22
        grid $f.${key}l -row [expr {$row / 3}] -column [expr {$row % 3 * 3}] -sticky w -padx {0 4}
        grid $f.$key -row [expr {$row / 3}] -column [expr {$row % 3 * 3 + 1}] -sticky w
        if {$key in {branchcolor bgcolor}} {
            ttk::button $f.${key}c -text \u2026 -width 2 -command [list tkcommit::chooseColor $key]
            grid $f.${key}c -row [expr {$row / 3}] -column [expr {$row % 3 * 3 + 2}] -sticky w -padx {2 12}
        }
        incr row
    }
    icons::tooltip $f.tags "Tags of the new check-in, separated by spaces or commas"
    icons::tooltip $f.date "The time of the check-in instead of now (YYYY-MM-DD HH:MM:SS, UTC)"
    icons::tooltip $f.user "Record this user as the one who made the check-in"
    icons::tooltip $f.branchcolor "The colour of the new branch"
    icons::tooltip $f.bgcolor "The colour of this check-in only"
    set row 2
    set col 0
    foreach {key label tip} {
        close "Close the branch" "Close the branch committed to: no more check-ins on it"
        integrate "Close merged branches" "Close the branches merged in (--integrate)"
        private "Private" "Never sync the check-in, and make its descendants private"
        nosign "Don't sign" "Do not sign the check-in with gpg"
        allowFork "Allow a fork" "Commit although it forks the branch"
        allowEmpty "Allow no changes" "Commit although no file changed (with the close option, to close a branch)"
        allowConflict "Allow conflicts" "Commit although files have unresolved merge conflicts"
        allowOlder "Allow older" "Commit although it is older than its parent"
        ignoreOversize "Allow big files" "No warning about oversized files"
        ignoreSkew "Ignore clock skew" "Commit although the clock differs from the server's"
        overrideLock "Override a lock" "Commit although the parent is locked by another checkout"
        hash "Check by hashing" "Find changed files by their hashes, not their times"
        noVerify "Skip hooks" "Do not run the before-commit hooks"
    } {
        ttk::checkbutton $f.$key -text $label -variable tkcommit::opt($key)
        icons::tooltip $f.$key $tip
        grid $f.$key -row $row -column $col -columnspan 3 -sticky w -padx {0 12}
        if {[incr col 3] > 6} {
            set col 0
            incr row
        }
    }
    return $f
}


# The context menu of the files to delete: check or uncheck them all.
proc tkcommit::cleanMenu {m item} {
    variable cleanSkip
    set t .commit.clean.f.opts.list.t
    $m add command -label [expr {[info exists cleanSkip($item)] ? "Check" : "Uncheck"}] \
        -command [list tkcommit::cleanToggle $item]
    $m add command -label "Check all" -command [list tkcommit::cleanAll 0]
    $m add command -label "Uncheck all" -command [list tkcommit::cleanAll 1]
    popup::separator $m
    popup::copy $m "Copy path" $item
}

proc tkcommit::cleanAll {skip} {
    variable cleanSkip
    foreach path [.commit.clean.f.opts.list.t children {}] {
        if {[info exists cleanSkip($path)] != $skip} { cleanToggle $path }
    }
}

# ------------------------------------------------- times, switch version

# Set the times of the selected files, or of all managed files (fossil
# touch): to now, their check-ins' or the checkout's time; after its dry
# run.
proc tkcommit::touchFiles {} {
    variable touchTo
    variable touching
    set touching [lmap p [selectedFiles] {
        if {![dict exists $::tkcommit::files $p] || [dict get $::tkcommit::files $p] eq "EXTRA"} continue
        set p
    }]
    set touchTo now
    set what [expr {[llength $touching] ? "the [llength $touching] files selected" : "all managed files"}]
    set w [dialog .commit.touch "Set the times of files" "Set the modification times of\
        $what (the files are not changed; build tools may see them as new or old)." \
        "Set times" {tkcommit::dryRun touch -n -v {*}[tkcommit::touchOpts]}]
    foreach {value label} {now "Now" checkin "The time of the check-in that last changed each"
            checkout "The time of the checked-out version"} {
        ttk::radiobutton $w.f.opts.$value -text $label -value $value -variable tkcommit::touchTo \
            -command [list tkcommit::preview $w]
        grid $w.f.opts.$value - -sticky w
    }
    if {![waitDialog $w]} return
    lassign [fossil touch {*}[touchOpts]] code out
    if {[finish $code $out "fossil touch"]} { set ::tkcommit::status "Set the times of $what" }
}

proc tkcommit::touchOpts {} {
    variable touchTo
    variable touching
    list [dict get {now --now checkin --checkin checkout --checkout} $touchTo] \
        {*}[lmap p $touching { filearg $p }]
}

# Change the version of the checkout without touching the files (fossil
# checkout --keep): the files stay as they are, and differ then from the
# new version as changes.  Fossil has no dry run for it: the question says
# what it does.
proc tkcommit::switchKeep {} {
    variable revision
    set revision ""
    set w [dialog .commit.switch "Switch the version, keep the files" "Make the checkout a\
        checkout of another version without changing any file on disk: the files stay as they\
        are, and what differs from the new version shows as changes (for example to commit\
        files from elsewhere onto that version).  Fossil has no dry run for this; it refuses\
        when files are edited (commit or revert them first).  Undo cannot take it back:\
        switch again to the version now." Switch {}]
    field $w rev "Version:" tkcommit::revision 30
    ttk::label $w.f.opts.now -foreground gray35 -text "Now: [lindex [split $::tkcommit::info \u00b7] 2]"
    grid $w.f.opts.now - -sticky w
    after idle [list ui::focusIfThere $w.f.opts.rev]
    if {![waitDialog $w]} return
    set v [string trim $revision]
    if {$v eq ""} return
    set bad [fossil::valueProblem Version $v version]
    if {$bad ne ""} {
        tk_messageBox -icon error -title "Switch the version" -message $bad
        return
    }
    lassign [fossil checkout --keep $v] code out
    if {[finish $code $out "fossil checkout --keep"]} { set ::tkcommit::status "The checkout is now of $v (files kept)" }
}
