# The Commit tab of tktaalik, for a checkout.
#
# Lists the changed files with checkboxes, shows the diff of the selected
# one, and commits the checked files with the given message.  It never
# syncs: "fossil commit" gets --nosync (pushing stays a separate step), and
# --no-prompt, so that a question from Fossil (CR/LF line endings, binary
# content, a fork, ...) cancels the commit and is shown instead of waiting
# for an answer on the terminal.

source [file join [file dirname [file normalize [info script]]] fossil.tcl]
source [file join [file dirname [file normalize [info script]]] commitops.tcl]

namespace eval tkcommit {
    variable root ""            ;# the checkout's top directory
    variable files {}           ;# path -> status, in Fossil's order
    variable checked            ;# array: path -> 1 if to be committed
    variable merging 0          ;# a merge is in progress: all or nothing
    variable showExtras 0       ;# also list unmanaged files
    variable extrasDot 0        ;#   with the dot files (extras --dotfiles)
    variable branch ""          ;# a new branch for the check-in
    variable noWarnings 0       ;# --no-warnings --no-verify-comment
    variable info ""            ;# the line at the top
    variable status ""          ;# the status line
    variable current ""         ;# the file whose diff is shown
    variable forks 0            ;# open leaves of the checkout's branch

    # Statuses that "fossil commit" does not take; listed unchecked.
    variable uncommittable {EXTRA MISSING UNCHANGED}
}

# ---------------------------------------------------------------- Fossil

# Run fossil in the checkout; return {exit-code output}.  The arguments
# must not look like exec redirections: file names get a "./" in front.
proc tkcommit::fossil {args} {
    variable root
    fossil::run -dir $root {*}$args
}

proc tkcommit::filearg {path} {
    return ./$path
}

# The changed (and with showExtras also the unmanaged) files.
proc tkcommit::loadChanges {} {
    variable files
    variable checked
    variable merging
    variable showExtras
    variable showUnchanged
    variable uncommittable
    variable status
    variable mergedWith

    # (With "Check by hashing": as the commit will see them.)
    set opts [expr {$showUnchanged ? "--all" : ""}]
    if {$::tkcommit::opt(hash)} { lappend opts --hash }
    lassign [fossil changes --classify {*}$opts] code out
    # --all leaves out the merge in progress: asked for on its own.
    # (--merge is a filter: with it only the merge is listed.)
    if {!$code && $showUnchanged} {
        lassign [fossil changes --classify --merge] mcode mout
        if {!$mcode} { append out \n $mout }
    }
    if {$code} {
        set status [string trim $out]
        return 0
    }
    set old [array get checked]
    set oldFiles $files
    set files {}
    set merging 0
    set mergedWith {}
    foreach line [split $out \n] {
        if {![regexp {^(\S+)\s+(.*\S)} $line -> what path]} continue
        if {$what in {MERGED_WITH CHERRYPICK BACKOUT INTEGRATE}} {
            set merging 1
            lappend mergedWith [list $what $path]
            continue
        }
        # A rename is "old  ->  new"; the new name is committed.
        regexp {^.*  ->  (.*)$} $path -> path
        dict set files $path $what
    }
    if {$showExtras} {
        # (Only Fossil's settings, ignore-glob and dotfiles: not the
        # fields of the dialogs.)
        lassign [fossil extras {*}[expr {$::tkcommit::extrasDot ? "--dotfiles" : ""}]] code out
        if {!$code} {
            foreach path [split $out \n] {
                if {$path ne "" && ![dict exists $files $path]} {
                    dict set files $path EXTRA
                }
            }
        }
    }
    # Keep earlier choices while the status is the same; otherwise check the
    # files that can be committed.
    array unset checked
    dict for {path what} $files {
        if {[dict exists $old $path] && [dict exists $oldFiles $path]
                && [dict get $oldFiles $path] eq $what} {
            set checked($path) [dict get $old $path]
        } else {
            set checked($path) [expr {$what ni $uncommittable}]
        }
        if {$merging} { set checked($path) [expr {$what ni $uncommittable}] }
    }
    return 1
}

proc tkcommit::loadInfo {} {
    variable info
    variable forks
    lassign [fossil info] code out
    set hash ""
    regexp -line {^checkout:\s+([0-9a-f]{10})} $out -> hash
    lassign [fossil branch current] code branch
    set sync [autosyncSetting]
    if {$sync eq ""} { set sync "default (on)" }
    set forks [forkCount [string trim $branch]]
    set info "[file tail [string trimright $::tkcommit::root /]]  \u00b7  branch [string trim $branch]"
    append info "  \u00b7  check-in $hash  \u00b7  autosync $sync (never used here)"
    if {$::tkcommit::from ne ""} { append info "  \u00b7  diffs against $::tkcommit::from" }
    if {$forks > 1} { append info "  \u00b7  the branch has $forks leaves (Commit \u25b8 Merge fork\u2026)" }
}

# How many open leaves the branch has: more than one is a fork.
proc tkcommit::forkCount {branch} {
    variable root
    if {$branch eq ""} { return 0 }
    if {[catch {fossil::checkoutSql $root "SELECT count(*) FROM leaf l
            WHERE EXISTS (SELECT 1 FROM tagxref x WHERE x.rid=l.rid AND x.tagtype>0
                AND x.tagid=(SELECT tagid FROM tag WHERE tagname='branch')
                AND x.value=[fossil::sqlstr $branch])
            AND NOT EXISTS (SELECT 1 FROM tagxref c WHERE c.rid=l.rid AND c.tagtype>0
                AND c.tagid=(SELECT tagid FROM tag WHERE tagname='closed'))"} rows]} {
        return 0
    }
    lindex $rows 0 0
}

# The autosync setting as it is (local, global or versioned), "" if not
# set (then it is on).
proc tkcommit::autosyncSetting {} {
    variable root
    fossil::autosyncSetting -dir $root
}

# The value of autosync for COMMAND (update, commit, merge, open): the
# setting is a list of VALUE and COMMAND=VALUE entries, the plain VALUE
# for the commands not named ("on,commit=off", "pullonly update=off").
proc tkcommit::autosyncFor {command} {
    fossil::autosyncValue [autosyncSetting] $command
}

# Whether autosync is on for the "update" that commands like "patch apply"
# run themselves, without a --nosync: they are refused then.
proc tkcommit::autosyncOn {} {
    expr {[string tolower [autosyncFor update]] ni {off 0 no false}}
}

# --------------------------------------------------------------- the list

proc tkcommit::refresh {} {
    variable files
    variable current
    variable merging
    variable forks
    loadInfo
    # Merge fork: only when the branch has more than one leaf.
    .commit.menu.commit entryconfigure "Merge fork*" -state [expr {$forks > 1 ? "normal" : "disabled"}]
    if {![loadChanges]} return
    set t .commit.main.files.t
    set selected [lindex [$t selection] 0]
    $t delete [$t children {}]
    dict for {path what} $files {
        $t insert {} end -id $path -values [list [mark $path] $what $path] \
            -tags [string tolower $what]
    }
    if {[$t exists $selected]} {
        $t selection set $selected
    } elseif {[llength [$t children {}]]} {
        $t selection set [lindex [$t children {}] 0]
    } else {
        showDiff ""
    }
    variable mergedWith
    set with [join [lmap m $mergedWith {
        lassign $m what hash
        set what [dict get {MERGED_WITH merge CHERRYPICK cherry-pick BACKOUT "back-out"
            INTEGRATE "integrating merge"} $what]
        string cat "$what of " [string range $hash 0 9]
    }] ", "]
    .commit.bottom.note configure -text [expr {$merging
        ? "A merge is in progress ($with): Fossil commits all changed files." : ""}]
    if {$merging} {
        pack .commit.bottom.buttons.merge -side left -padx {0 4} -before .commit.bottom.buttons.sbs
    } else {
        pack forget .commit.bottom.buttons.merge
    }
    updateStatus
}

proc tkcommit::mark {path} {
    variable checked
    expr {$checked($path) ? "\u2611" : "\u2610"}
}

proc tkcommit::toggle {path} {
    variable checked
    variable merging
    variable files
    if {$path eq "" || $merging} return
    set checked($path) [expr {!$checked($path)}]
    .commit.main.files.t set $path check [mark $path]
    updateStatus
}

# Space: the selected files all checked, or all unchecked.
proc tkcommit::toggleSelected {} {
    variable checked
    variable merging
    set paths [.commit.main.files.t selection]
    if {![llength $paths] || $merging} return
    set to [expr {!$checked([lindex $paths 0])}]
    foreach path $paths {
        set checked($path) $to
        .commit.main.files.t set $path check [mark $path]
    }
    updateStatus
}

# The files selected in the list (several with Shift and Control).
proc tkcommit::selectedFiles {} {
    .commit.main.files.t selection
}

proc tkcommit::updateStatus {} {
    variable files
    variable status
    set n [llength [toCommit]]
    set total [dict size $files]
    set status "$n of $total [expr {$total == 1 ? "file" : "files"}] checked"
}

# The checked files that can be committed.
proc tkcommit::toCommit {} {
    variable files
    variable checked
    variable uncommittable
    set result {}
    dict for {path what} $files {
        if {$checked($path) && $what ni $uncommittable} { lappend result $path }
    }
    return $result
}

# ----------------------------------------------------------------- the diff

# The diff of the file in focus (the last one clicked); the status line
# counts the files selected.
proc tkcommit::selectionChanged {} {
    set t .commit.main.files.t
    set focus [$t focus]
    set selected [$t selection]
    if {$focus eq "" || $focus ni $selected} { set focus [lindex $selected 0] }
    showDiff $focus
    if {[llength $selected] > 1} {
        set ::tkcommit::status "[llength $selected] files selected"
    } else {
        updateStatus
    }
}

proc tkcommit::showDiff {path} {
    variable files
    variable current
    variable root
    set current $path
    set d .commit.main.diff.text
    $d configure -state normal
    $d delete 1.0 end
    if {$path ne ""} {
        set what [dict get $files $path]
        if {$what eq "EXTRA"} {
            # Not in Fossil yet: the start of the file.
            if {[catch {
                set f [open [file join $root $path]]
                fconfigure $f -encoding utf-8
                set text [read $f 100000]
                close $f
            } msg]} {
                set text $msg
            }
            $d insert end "Unmanaged file\n" heading $text
        } elseif {$what eq "UNCHANGED"} {
            $d insert end "Unchanged" heading
        } elseif {$what eq "MISSING"} {
            $d insert end "Missing: the file is not on disk.  Remove it with\
                \"fossil rm\" or restore it with Revert." heading
        } else {
            lassign [fossil diff -i -N {*}[diffArgs] [filearg $path]] code out
            foreach line [split $out \n] {
                switch -glob -- $line {
                    "+++ *" - "--- *" - "Index: *" - "=====*" { set tag meta }
                    "@@*"   { set tag hunk }
                    "+*"    { set tag added }
                    "-*"    { set tag removed }
                    default { set tag "" }
                }
                $d insert end $line\n $tag
            }
        }
    }
    $d configure -state disabled
}

proc tkcommit::sideBySide {} {
    variable current
    variable files
    variable root
    if {$current eq "" || [dict get $files $current] in {EXTRA MISSING UNCHANGED}} return
    diffview::run $current -dir $root -mode sidebyside -- -N {*}[diffArgs] [filearg $current]
}

# All changes of the checkout.
proc tkcommit::diffAll {} {
    variable root
    diffview::run "Changes in [file tail $root]" -dir $root -- -N {*}[diffArgs]
}

# ---------------------------------------------------------------- actions

# Add the checked unmanaged files, or the selected one.  Files of the
# ignore-glob setting and names Windows reserves only when confirmed.
proc tkcommit::addFiles {} {
    variable current
    variable files
    variable checked
    set paths [dict keys [dict filter $files script {path what} {
        expr {$what eq "EXTRA" && $checked($path)}
    }]]
    if {![llength $paths]} {
        set paths [lmap p [selectedFiles] {
            if {![dict exists $files $p] || [dict get $files $p] ne "EXTRA"} continue
            set p
        }]
    }
    if {![llength $paths] && $current ne "" && [dict exists $files $current]
            && [dict get $files $current] eq "EXTRA"} {
        set paths [list $current]
    }
    if {![llength $paths]} {
        bell
        return
    }
    set args [lmap p $paths { filearg $p }]
    lassign [fossil add {*}$args] code out
    set opts {}
    if {[regexp {matches "([^"]*)"} $out -> glob]} {
        if {[ui::ask -default no -title Add \
                "Some files match the $glob setting: add them anyway?" \
                [string trim $out]]} {
            lappend opts -f
        }
    }
    if {[string match "*--allow-reserved*" $out]} {
        if {[ui::ask -icon warning -default no -title Add \
                "Windows reserves some of these names: add them anyway?" \
                "Such files cannot be checked out on Windows.\n\n[string trim $out]"]} {
            lappend opts --allow-reserved
        }
    }
    if {[llength $opts]} {
        lassign [fossil add {*}$opts {*}$args] code out
    }
    if {$code} { showLog "fossil add" $out }
    refresh
}

proc tkcommit::revertFile {} {
    revertFiles
}

proc tkcommit::message {} {
    string trim [.commit.bottom.msg.text get 1.0 end]
}

# Commit (or with $dryRun only check) the checked files.
proc tkcommit::commit {{dryRun 0}} {
    variable merging
    variable branch
    variable noWarnings
    variable files
    set msg [message]
    if {$msg eq ""} {
        tk_messageBox -icon info -title Commit -message "Enter a check-in comment."
        focus .commit.bottom.msg.text
        return
    }
    set paths [toCommit]
    # (No files with "Allow no changes" only if nothing changed: without
    # files Fossil commits all changes.)
    set committable [dict filter $files script {k v} { expr {$v ni $::tkcommit::uncommittable} }]
    if {![llength $paths] && !($::tkcommit::opt(allowEmpty) && ![dict size $committable])} {
        tk_messageBox -icon info -title Commit -message "No files are checked."
        return
    }
    set branch [string trim $branch]
    if {$branch ne "" && ![regexp {^[^-<>|\s][^\s]*$} $branch]} {
        tk_messageBox -icon error -title Commit -message "Not a branch name: $branch"
        return
    }

    # The message in a file: no quoting or redirection issues.
    set f [file tempfile tmp]
    fconfigure $f -encoding utf-8
    puts -nonewline $f $msg
    close $f
    set args [list commit --nosync --no-prompt -M $tmp]
    if {$dryRun} { lappend args --dry-run }
    # (As --branch=NAME: a name cannot be taken for a redirection.)
    if {$branch ne ""} { lappend args --branch=$branch }
    if {$noWarnings} { lappend args --no-warnings --no-verify-comment }
    if {[catch {commitOpts} opts]} {
        tk_messageBox -icon error -title Commit -message $opts
        return
    }
    lappend args {*}$opts
    # During a merge Fossil commits everything; otherwise only these.
    if {!$merging} {
        foreach path $paths { lappend args [filearg $path] }
    }
    . configure -cursor watch
    update idletasks
    lassign [fossil {*}$args] code out
    . configure -cursor ""
    file delete $tmp

    if {$dryRun} {
        showLog [expr {$code ? "Dry run failed" : "Dry run"}] $out
        return
    }
    if {$code || ![regexp -line {^New_Version:\s+([0-9a-f]+)} $out -> hash]} {
        showLog "Commit failed" $out
        return
    }
    .commit.bottom.msg.text delete 1.0 end
    set branch ""
    resetOpts
    refresh
    set ::tkcommit::status "Committed [string range $hash 0 9]"
    showLog "Committed [string range $hash 0 9]" $out
}

proc tkcommit::showLog {title text} {
    set w .commit.log
    if {![winfo exists $w]} {
        toplevel $w
        text $w.t -width 90 -height 20 -font TkFixedFont -wrap none \
            -yscrollcommand [list $w.y set]
        ttk::scrollbar $w.y -command [list $w.t yview]
        ttk::button $w.close -text Close -command [list destroy $w]
        grid $w.t $w.y -sticky news
        grid $w.close - -pady 4
        grid columnconfigure $w 0 -weight 1
        grid rowconfigure $w 0 -weight 1
        bind $w <Escape> [list destroy $w]
    }
    wm title $w $title
    $w.t configure -state normal
    $w.t delete 1.0 end
    $w.t insert end [string trim $text]
    $w.t configure -state disabled
    raise $w
}

# ----------------------------------------------------------------- window

# Build the tab in the frame .commit, with its menu bar .commit.menu.
proc tkcommit::build {} {
    set char [font measure TkDefaultFont 0]

    menu .commit.menu
    .commit.menu add cascade -label File -underline 0 -menu [menu .commit.menu.file]
    tktaalik::fileMenu .commit.menu.file
    .commit.menu.file add command -label Refresh -underline 0 -accelerator F5 \
        -command tkcommit::refresh
    tktaalik::quitEntry .commit.menu.file
    .commit.menu add cascade -label Commit -underline 0 -menu [menu .commit.menu.commit]
    menu .commit.menu.commit.diffopts
    diffopts::menu .commit.menu.commit.diffopts tkcommit::refresh
    foreach {label command accel} {
        "Side-by-side diff"             tkcommit::sideBySide    ""
        "Diff of all changes"           tkcommit::diffAll       ""
        "Compare with version\u2026"        tkcommit::compareWith   ""
        "Compare two versions\u2026"        tkcommit::compareTwo    ""
        "Diff since before the last undoable command" tkcommit::diffUndo ""
        "Diff options"                  >diffopts               ""
        --                              {}                      ""
        "Add"                           tkcommit::addFiles      ""
        "Rename or move\u2026"              tkcommit::renameFile    ""
        "Remove\u2026"                      tkcommit::removeFile    ""
        "Rename or move a directory\u2026"  tkcommit::renameDir     ""
        "Remove a directory\u2026"          tkcommit::removeDir     ""
        "Add new and remove missing\u2026"  tkcommit::addRemove     ""
        "Reset adds and removes\u2026"      tkcommit::resetAdds     ""
        "Reset adds\u2026"                  {tkcommit::resetAdds add} ""
        "Reset removes\u2026"               {tkcommit::resetAdds rm} ""
        "Delete unmanaged files\u2026"      tkcommit::cleanFiles    ""
        --                              {}                      ""
        "Update\u2026"                      tkcommit::updateCheckout ""
        "Update files to a version\u2026"   tkcommit::updateFiles   ""
        "Merge fork\u2026"                  tkcommit::mergeFork     ""
        "Switch the version, keep the files\u2026" tkcommit::switchKeep ""
        "Set the times of files\u2026"      tkcommit::touchFiles    ""
        --                              {}                      ""
        "Revert\u2026"                      tkcommit::revertFiles   ""
        "Revert all\u2026"                  {tkcommit::revertFiles 1} ""
        "Undo\u2026"                        tkcommit::undo          ""
        "Redo\u2026"                        {tkcommit::undo redo}   ""
        "Merge details"                 tkcommit::mergeInfo     ""
        --                              {}                      ""
        "Save changes as a patch\u2026"     tkcommit::savePatch     ""
        "Apply a patch\u2026"               tkcommit::applyPatch    ""
        "View a patch\u2026"                tkcommit::viewPatch     ""
        --                              {}                      ""
        "Dry run"                       {tkcommit::commit 1}    ""
        "Commit"                        tkcommit::commit        Ctrl+Return
    } {
        if {$label eq "--"} {
            .commit.menu.commit add separator
        } elseif {[string index $command 0] eq ">"} {
            .commit.menu.commit add cascade -label $label -menu .commit.menu.commit.[string range $command 1 end]
        } else {
            .commit.menu.commit add command -label $label -command $command -accelerator $accel
        }
    }

    # The menu of a file.
    menu .commit.ctx -tearoff 0
    foreach {label command} {
        "Side-by-side diff"     tkcommit::sideBySide
        "Add"                   tkcommit::addFiles
        "Rename or move\u2026"      tkcommit::renameFile
        "Remove\u2026"              tkcommit::removeFile
        "Revert\u2026"              tkcommit::revertFiles
        "Update to a version\u2026" tkcommit::updateFiles
        "Undo for these files\u2026" tkcommit::undoFile
        "Redo for these files\u2026" {tkcommit::undoFile redo}
        "Copy names"            {ui::copy [join [tkcommit::selectedFiles] \n]}
    } {
        .commit.ctx add command -label $label -command $command
    }

    # Instead of the rest without a checkout.
    ttk::label .commit.none -anchor center -justify center -text "Committing needs a checkout.\n\nOpen one with File \u25b8 Open checkout."

    ttk::label .commit.info -textvariable tkcommit::info -padding {6 4} -anchor w

    # The files and the diff of the selected one.
    ttk::panedwindow .commit.main -orient horizontal
    ttk::frame .commit.main.files
    ttk::treeview .commit.main.files.t -columns {check status path} -show headings \
        -selectmode extended -yscrollcommand {.commit.main.files.y set}
    ttk::scrollbar .commit.main.files.y -command {.commit.main.files.t yview}
    .commit.main.files.t heading check -text ""
    .commit.main.files.t heading status -text Status -anchor w
    .commit.main.files.t heading path -text File -anchor w
    .commit.main.files.t column check -width [expr {$char * 3}] -stretch 0 -anchor center
    .commit.main.files.t column status -width [expr {$char * 10}] -stretch 0
    .commit.main.files.t column path -width [expr {$char * 30}] -stretch 1
    foreach {tag colour} {missing red3 extra gray45 conflict red3} {
        .commit.main.files.t tag configure $tag -foreground $colour
    }
    grid .commit.main.files.t .commit.main.files.y -sticky news
    grid columnconfigure .commit.main.files 0 -weight 1
    grid rowconfigure .commit.main.files 0 -weight 1

    ttk::frame .commit.main.diff
    text .commit.main.diff.text -font TkFixedFont -wrap none -state disabled \
        -width 80 -yscrollcommand {.commit.main.diff.y set} -xscrollcommand {.commit.main.diff.x set}
    ttk::scrollbar .commit.main.diff.y -command {.commit.main.diff.text yview}
    ttk::scrollbar .commit.main.diff.x -orient horizontal -command {.commit.main.diff.text xview}
    grid .commit.main.diff.text .commit.main.diff.y -sticky news
    grid .commit.main.diff.x -sticky ew
    grid columnconfigure .commit.main.diff 0 -weight 1
    grid rowconfigure .commit.main.diff 0 -weight 1
    set d .commit.main.diff.text
    $d tag configure added -foreground darkgreen -background #e6ffec
    $d tag configure removed -foreground darkred -background #ffebe9
    $d tag configure hunk -foreground blue4
    $d tag configure meta -foreground gray45
    $d tag configure heading -font TkHeadingFont
    # The selection over the colours: tags made later are above it.
    $d tag raise sel
    .commit.main add .commit.main.files -weight 1
    .commit.main add .commit.main.diff -weight 2

    # The message, the options and the buttons.
    ttk::frame .commit.bottom -padding 6
    ttk::label .commit.bottom.label -text "Check-in comment:"
    ttk::frame .commit.bottom.msg
    text .commit.bottom.msg.text -height 5 -wrap word -undo 1 -font TkTextFont \
        -yscrollcommand {.commit.bottom.msg.y set}
    ttk::scrollbar .commit.bottom.msg.y -command {.commit.bottom.msg.text yview}
    pack .commit.bottom.msg.y -side right -fill y
    pack .commit.bottom.msg.text -fill both -expand 1
    ttk::frame .commit.bottom.opts
    ttk::label .commit.bottom.opts.bl -text "New branch:"
    ttk::entry .commit.bottom.opts.branch -textvariable tkcommit::branch -width 20
    ttk::checkbutton .commit.bottom.opts.extras -text "Show unmanaged files" \
        -variable tkcommit::showExtras -command tkcommit::refresh
    icons::tooltip .commit.bottom.opts.extras "The files Fossil does not manage, as \"fossil extras\"\
        lists them:\nnot those of the ignore-glob setting, nor dot files unless the dotfiles\
        setting is on"
    ttk::checkbutton .commit.bottom.opts.dot -text "with dot files" \
        -variable tkcommit::extrasDot -command tkcommit::refresh
    icons::tooltip .commit.bottom.opts.dot "Unmanaged files whose names begin with a dot too\
        (\"fossil extras --dotfiles\")"
    ttk::checkbutton .commit.bottom.opts.unchanged -text "Show unchanged files" \
        -variable tkcommit::showUnchanged -command tkcommit::refresh
    ttk::checkbutton .commit.bottom.opts.warn -text "Ignore warnings" \
        -variable tkcommit::noWarnings
    icons::tooltip .commit.bottom.opts.warn "No warnings about the files' contents, no check of the comment"
    ttk::button .commit.bottom.opts.more -text "More options" -style Toolbutton -command tkcommit::toggleMore
    pack .commit.bottom.opts.bl .commit.bottom.opts.branch -side left
    pack .commit.bottom.opts.extras -side left -padx {12 0}
    pack .commit.bottom.opts.dot .commit.bottom.opts.unchanged .commit.bottom.opts.warn \
        .commit.bottom.opts.more -side left -padx {12 0}
    buildMore .commit.bottom.more
    ttk::label .commit.bottom.note -foreground red3
    ttk::frame .commit.bottom.buttons
    foreach {name label command} {
        refresh  Refresh              tkcommit::refresh
        sbs      "Side-by-side diff"  tkcommit::sideBySide
        add      Add                  tkcommit::addFiles
        merge    "Merge details"      tkcommit::mergeInfo
        revert   Revert\u2026              tkcommit::revertFiles
        dry      "Dry run"            {tkcommit::commit 1}
        commit   Commit               tkcommit::commit
    } {
        ttk::button .commit.bottom.buttons.$name -text $label -command $command
        pack .commit.bottom.buttons.$name -side left -padx {0 4}
    }
    .commit.bottom.buttons.commit configure -default active
    pack forget .commit.bottom.buttons.merge
    grid .commit.bottom.label -row 0 -sticky w
    grid .commit.bottom.msg -row 1 -sticky news
    grid .commit.bottom.opts -row 2 -sticky w -pady 4
    # (Row 3: More options.)
    grid .commit.bottom.note -row 4 -sticky w
    grid .commit.bottom.buttons -row 5 -sticky e
    grid columnconfigure .commit.bottom 0 -weight 1
    grid rowconfigure .commit.bottom 1 -weight 1

    ttk::label .commit.status -textvariable tkcommit::status -padding {6 2} -anchor w

    showWidgets 1

    # Bindings.
    set t .commit.main.files.t
    bind $t <<TreeviewSelect>> {tkcommit::selectionChanged}
    bind $t <ButtonPress-1> {
        if {[.commit.main.files.t identify column %x %y] eq "#1"
                && [.commit.main.files.t identify region %x %y] eq "cell"} {
            tkcommit::toggle [.commit.main.files.t identify item %x %y]
        }
    }
    bind $t <space> {tkcommit::toggleSelected; break}
    bind $t <Double-1> tkcommit::sideBySide
    bind $t <Button-3> {
        set item [.commit.main.files.t identify item %x %y]
        if {$item ne ""} {
            # (A selected file: the menu is for all of them.)
            if {$item ni [.commit.main.files.t selection]} {
                .commit.main.files.t selection set [list $item]
            }
            .commit.main.files.t focus $item
            update idletasks
            tk_popup .commit.ctx %X %Y
        }
    }
    tktaalik::shortcut commit <Control-Return> tkcommit::commit
    tktaalik::shortcut commit <F5> tkcommit::refresh
}

# The files and the commit message, or the note that a checkout is needed.
proc tkcommit::showWidgets {on} {
    pack forget .commit.none .commit.info .commit.status .commit.bottom .commit.main
    if {$on} {
        pack .commit.info -fill x
        pack .commit.status -side bottom -fill x
        pack .commit.bottom -side bottom -fill x
        pack .commit.main -fill both -expand 1
    } else {
        pack .commit.none -fill both -expand 1
    }
}

# Use the checkout $root (the current directory), or none ("").
proc tkcommit::setRepository {repo newRoot} {
    variable root $newRoot
    showWidgets [expr {$root ne ""}]
    if {$root eq ""} {
        tktaalik::setTitle commit "Commit \u2014 no checkout"
        return
    }
    tktaalik::setTitle commit "Commit \u2014 [file tail [string trimright $root /]]"
    refresh
}

# The tab is shown: the files may have changed.
proc tkcommit::activate {} {
    variable root
    if {$root eq ""} return
    refresh
    focus .commit.bottom.msg.text
}
