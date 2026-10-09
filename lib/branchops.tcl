# The Branches tab (lib/tkbranches.tcl): its actions -- releases and their
# changes, update, merge, close, new branches.

# ---------------------------------------------------------------- actions

proc tkbranches::openUrl {path} {
    variable remote
    ui::openServer $remote $path -title Branches
}

proc tkbranches::diffBranch {name} {
    variable repo
    if {$name eq ""} return
    diffview::run "Branch $name" -- -R $repo --branch [fossil::arg $name]
}

proc tkbranches::diffAgainst {name target} {
    variable repo
    if {$name eq "" || $target eq "" || $name eq $target} return
    diffview::run "$name against $target" -- \
        -R $repo --from [fossil::arg $target] --to [fossil::arg $name]
}

proc tkbranches::diffCheckin {uuid} {
    variable repo
    if {$uuid ne ""} {
        diffview::run "Check-in [string range $uuid 0 9]" -- -R $repo --checkin $uuid
    }
}

# ---------------------------------------------------------------- releases

# Releases are the check-ins with the tags core-9-0-3, core-8-7-a1, ...;
# shown as versions: 9.0.3, 8.7a1.

proc tkbranches::version {tag} {
    if {[regexp {^core-([0-9]+)-([0-9]+)-([ab][0-9]+)$} $tag -> major minor pre]} {
        return $major.$minor$pre
    }
    if {[regexp {^core-([0-9]+(?:-[0-9]+)+)$} $tag -> v]} {
        return [string map {- .} $v]
    }
    return ""
}

proc tkbranches::vcompare {a b} {
    if {[catch {package vcompare $a $b} result]} { return [string compare $a $b] }
    return $result
}

# The releases (tags) whose check-ins have $uuid as an ancestor, oldest
# version first.
proc tkbranches::releasesWith {uuid} {
    set rows [sql "WITH RECURSIVE d(rid) AS (
            SELECT rid FROM blob WHERE uuid=[fossil::sqlstr $uuid]
            UNION SELECT plink.cid FROM plink JOIN d ON plink.pid=d.rid)
        SELECT DISTINCT substr(t.tagname,5) FROM tagxref x JOIN tag t USING(tagid)
        WHERE x.rid IN d AND x.tagtype>0 AND t.tagname GLOB 'sym-core-\[0-9\]*'"]
    set tags [lmap row $rows {
        set tag [lindex $row 0]
        if {[version $tag] eq ""} continue
        set tag
    }]
    lsort -command [list ::apply {{a b} {
        tkbranches::vcompare [tkbranches::version $a] [tkbranches::version $b]
    }}] $tags
}

# The first release of each line (8.6, 9.0, ...), as versions.
proc tkbranches::firstReleases {tags} {
    set first {}
    foreach tag $tags {
        set v [version $tag]
        regexp {^[0-9]+\.[0-9]+} $v line
        if {![dict exists $first $line]} { dict set first $line $v }
    }
    dict values $first
}

proc tkbranches::showReleases {uuid} {
    set tags [releasesWith $uuid]
    if {![llength $tags]} {
        tk_messageBox -icon info -title Releases -message "No release has check-in [string range $uuid 0 9] yet."
        return
    }
    tk_messageBox -icon info -title Releases \
        -message "Check-in [string range $uuid 0 9] is in [join [firstReleases $tags] {, }] and later." \
        -detail "All releases with it:\n[join [lmap t $tags { version $t }] {, }]\n\nBy ancestry:\
            a merge counts even if its changes were backed out (a \"null merge\")."
}

# All release tags, newest version first.
proc tkbranches::releaseTags {} {
    set tags [lmap row [sql "SELECT substr(tagname,5) FROM tag WHERE tagname GLOB 'sym-core-\[0-9\]*'
            AND EXISTS(SELECT 1 FROM tagxref x WHERE x.tagid=tag.tagid AND x.tagtype>0)"] {
        set tag [lindex $row 0]
        if {[version $tag] eq ""} continue
        set tag
    }]
    lsort -decreasing -command [list ::apply {{a b} {
        tkbranches::vcompare [tkbranches::version $a] [tkbranches::version $b]
    }}] $tags
}

# Choose two releases: their check-ins in the Timeline, or the diff.
proc tkbranches::compareReleases {} {
    variable answer
    variable fromRelease
    variable toRelease
    set tags [releaseTags]
    if {[llength $tags] < 2} {
        tk_messageBox -icon info -title Releases -message "This repository has no two releases."
        return
    }
    set versions [lmap t $tags { version $t }]
    set toRelease [lindex $versions 0]
    # The previous release of the same line, else the next older one.
    set fromRelease [lindex $versions 1]
    regexp {^[0-9]+\.[0-9]+} $toRelease line
    foreach v [lrange $versions 1 end] {
        if {[string match $line.* $v] || [string match $line\[ab\]* $v]} { set fromRelease $v; break }
    }
    set w .branches.releases
    destroy $w
    toplevel $w
    wm title $w "Changes between releases"
    wm transient $w .
    ttk::frame $w.f -padding 10
    pack $w.f -fill both -expand 1
    ttk::label $w.f.l1 -text "From:"
    ttk::combobox $w.f.from -textvariable tkbranches::fromRelease -values $versions -state readonly -width 12
    ttk::label $w.f.l2 -text "To:"
    ttk::combobox $w.f.to -textvariable tkbranches::toRelease -values $versions -state readonly -width 12
    ttk::frame $w.f.b
    ttk::button $w.f.b.log -text "Check-ins" -default active -command {set tkbranches::answer log}
    ttk::button $w.f.b.diff -text "Diff" -command {set tkbranches::answer diff}
    ttk::button $w.f.b.cancel -text Cancel -command {set tkbranches::answer ""}
    pack $w.f.b.cancel $w.f.b.diff $w.f.b.log -side right -padx {4 0}
    grid $w.f.l1 $w.f.from $w.f.l2 $w.f.to -sticky w -padx {0 6}
    grid $w.f.b - - - -sticky e -pady {10 0}
    bind $w <Escape> {set tkbranches::answer ""}
    wm protocol $w WM_DELETE_WINDOW {set tkbranches::answer ""}
    set answer ""
    vwait ::tkbranches::answer
    destroy $w
    set from [lindex $tags [lsearch -exact $versions $fromRelease]]
    set to [lindex $tags [lsearch -exact $versions $toRelease]]
    switch -- $answer {
        log  { showChanges $from $to }
        diff { diffRelease $from $to }
    }
}

proc tkbranches::showChanges {from to} {
    tktaalik::show timeline
    tktimeline::setQuery "in:$to -in:$from kind:ci"
}

proc tkbranches::diffRelease {from to} {
    variable repo
    diffview::run "[version $from] \u2192 [version $to]" -- -R $repo --from $from --to $to
}

# ------------------------------------------------------------- operations

# Show branch $name (from another tab): in the All view, without a search.
proc tkbranches::showBranch {name} {
    variable view
    variable query
    set t .branches.main.list.t
    if {![$t exists $name]} {
        set view all
        set query ""
        search
        after cancel {tkbranches::search}
    }
    if {[$t exists $name]} {
        $t selection set $name
        $t focus $name
        $t see $name
    }
}

proc tkbranches::commitWindow {} {
    tktaalik::show commit
}

proc tkbranches::showTicket {uuid} {
    if {$uuid eq ""} return
    tktaalik::show tickets
    tktsearch::setQuery id:[string range $uuid 0 9]
}

# A window with the output of a command; with $ok also asks: returns 1 if
# $ok was pressed.  $option is {label variable}: a checkbox.
proc tkbranches::showOutput {title message text {ok ""} {option {}}} {
    variable answer
    set w .branches.output
    destroy $w
    toplevel $w
    wm title $w $title
    wm transient $w .
    ttk::frame $w.f -padding 8
    pack $w.f -fill both -expand 1
    ttk::label $w.f.msg -text $message -wraplength 600 -justify left
    text $w.f.t -width 90 -height 16 -font TkFixedFont -wrap none \
        -yscrollcommand [list $w.f.y set]
    ttk::scrollbar $w.f.y -command [list $w.f.t yview]
    $w.f.t insert end [string trim $text]
    $w.f.t configure -state disabled
    ttk::frame $w.f.b
    grid $w.f.msg - -sticky w -pady {0 6}
    grid $w.f.t $w.f.y -sticky news
    grid $w.f.b - -sticky ew -pady {8 0}
    grid columnconfigure $w.f 0 -weight 1
    grid rowconfigure $w.f 1 -weight 1
    if {[llength $option]} {
        ttk::checkbutton $w.f.b.option -text [lindex $option 0] -variable [lindex $option 1]
        pack $w.f.b.option -side left
    }
    set answer 0
    if {$ok eq ""} {
        ttk::button $w.f.b.close -text Close -default active -command [list destroy $w]
        pack $w.f.b.close -side right
        bind $w <Escape> [list destroy $w]
        return 0
    }
    ttk::button $w.f.b.ok -text $ok -default active \
        -command [list set tkbranches::answer 1]
    ttk::button $w.f.b.cancel -text Cancel -command [list set tkbranches::answer 0]
    pack $w.f.b.cancel $w.f.b.ok -side right -padx {4 0}
    bind $w <Escape> [list set tkbranches::answer 0]
    wm protocol $w WM_DELETE_WINDOW [list set tkbranches::answer 0]
    focus $w.f.b.ok
    vwait ::tkbranches::answer
    destroy $w
    return $answer
}

# Can the checkout be changed?  It needs one, and its changes confirmed.
proc tkbranches::needCheckout {what} {
    variable root
    if {$root ne ""} { return 1 }
    tk_messageBox -icon info -title Branches -message "$what needs a checkout." \
        -detail "Open a checkout (File \u25b8 Open checkout) instead of the repository."
    return 0
}

proc tkbranches::changedFiles {} {
    lassign [inCheckout changes] code out
    expr {$code ? "" : [string trim $out]}
}

# Update the checkout to a branch's last check-in, or to a check-in
# (LABEL: what to call it).
proc tkbranches::updateTo {name {label ""}} {
    variable current
    if {$name eq "" || ![needCheckout "Updating"]} return
    if {$label eq ""} { set label "the last check-in of $name" }
    if {![fossil::argOk $name Update]} return
    set arg [fossil::arg $name]
    lassign [inCheckout update --nosync -n $arg] code out
    set changes [changedFiles]
    set message "Update the checkout to $label?"
    if {$changes ne ""} {
        append message "\n\nThe checkout has uncommitted changes: they are merged into the new\
            files, and can conflict with them."
    }
    if {$code} {
        showOutput "Update" "fossil update failed (dry run):" $out
        return
    }
    if {![showOutput "Update to $name" $message "Dry run:\n$out" Update]} return
    lassign [inCheckout update --nosync $arg] code out
    reload
    showOutput "Update to $name" [expr {$code ? "fossil update failed:" : "Updated to $label."}] $out
}

# Merge $what ({branch NAME}, {checkin UUID}, {cherrypick UUID} or {backout
# UUID}) into the checkout, after a dry run (with -v: what it merges from,
# the baseline and the pivot), with the options of fossil merge: integrate
# (a branch), keep the merge files (-K), force (-f), a baseline, binary
# files.  (--nosync: as update, no pull first.)
# (From another tab: WHERE the checkout, DONE run after the merge instead
# of reloading this tab.)
proc tkbranches::merge {kind what {where ""} {done tkbranches::reload}} {
    variable root
    if {$where eq ""} {
        mergeIn $kind $what $done
        return
    }
    # (The checkout of the caller, for the time of the merge.)
    set saved $root
    set root $where
    try {
        mergeIn $kind $what $done
    } finally {
        set root $saved
    }
}

proc tkbranches::mergeIn {kind what done} {
    variable mergeOpt
    variable current
    variable root
    if {$what eq "" || ![needCheckout "Merging"]} return
    if {![fossil::argOk $what $kind]} return
    # (The branch of the checkout merged into: its own, from any tab.)
    lassign [inCheckout branch current] code out
    set current [expr {$code ? $current : [string trim $out]}]
    array set mergeOpt {integrate 0 keep 0 force 0 baseline "" binary "" answer ""}
    set label [dict get {branch "Merge" checkin "Merge" cherrypick "Cherry-pick" backout "Back out"} $kind]
    set message "$label [expr {$kind eq "branch" ? $what : [string range $what 0 9]}]\
        into the checkout (on $current)?  The files change, nothing is committed."
    if {[changedFiles] ne ""} {
        append message "  The checkout already has uncommitted changes."
    }
    set w .branches.merge
    destroy $w
    toplevel $w
    wm title $w $label
    wm transient $w .
    ttk::frame $w.f -padding 8
    pack $w.f -fill both -expand 1
    ttk::label $w.f.msg -text $message -wraplength 640 -justify left
    text $w.f.t -width 90 -height 14 -font TkFixedFont -wrap none -yscrollcommand [list $w.f.y set]
    ttk::scrollbar $w.f.y -command [list $w.f.t yview]
    ttk::labelframe $w.f.opts -text Options -padding 6
    set o $w.f.opts
    set row 0
    if {$kind eq "branch"} {
        ttk::checkbutton $o.integrate -text "Integrate: close the branch with the commit (--integrate)" \
            -variable tkbranches::mergeOpt(integrate)
        grid $o.integrate - -sticky w
    }
    ttk::checkbutton $o.keep -text "Keep the merge files of conflicts (-K)" -variable tkbranches::mergeOpt(keep)
    ttk::checkbutton $o.force -text "Force, even if there is nothing to merge (-f)" -variable tkbranches::mergeOpt(force)
    ttk::label $o.lb -text "Baseline:"
    ttk::entry $o.baseline -textvariable tkbranches::mergeOpt(baseline) -width 30
    ttk::label $o.lbin -text "Binary files:"
    ttk::entry $o.binary -textvariable tkbranches::mergeOpt(binary) -width 30
    ttk::label $o.hint -foreground gray40 -text "Baseline: merge only the changes since this\
        check-in (--baseline).  Binary files: globs to treat as binary (--binary)."
    grid $o.keep - -sticky w
    grid $o.force - -sticky w
    grid $o.lb $o.baseline -sticky w -pady {4 0}
    grid $o.lbin $o.binary -sticky w
    grid $o.hint - -sticky w
    ttk::frame $w.f.b
    ttk::button $w.f.b.again -text "Dry run again" -command {set tkbranches::mergeOpt(answer) again}
    ttk::button $w.f.b.ok -text $label -default active -command {set tkbranches::mergeOpt(answer) ok}
    ttk::button $w.f.b.cancel -text Cancel -command {set tkbranches::mergeOpt(answer) cancel}
    pack $w.f.b.again -side left
    pack $w.f.b.cancel $w.f.b.ok -side right -padx {4 0}
    grid $w.f.msg - -sticky w -pady {0 6}
    grid $w.f.t $w.f.y -sticky news
    grid $w.f.opts - -sticky ew -pady {6 0}
    grid $w.f.b - -sticky ew -pady {8 0}
    grid columnconfigure $w.f 0 -weight 1
    grid rowconfigure $w.f 1 -weight 1
    bind $w <Escape> {set tkbranches::mergeOpt(answer) cancel}
    wm protocol $w WM_DELETE_WINDOW {set tkbranches::mergeOpt(answer) cancel}
    set arg [fossil::arg $what]
    # (The options of the dry run shown; none yet: they can be none too.)
    set dry ""
    set dryDone 0
    while 1 {
        set opts [mergeOpts $kind]
        if {$opts eq "-"} {
            tk_messageBox -parent $w -icon info -title $label \
                -message "The baseline and the binary files cannot start with \"-\", \"<\", \">\" or \"|\"."
        } elseif {!$dryDone || $dry ne $opts} {
            # The dry run (again, with the options changed).
            lassign [inCheckout merge -n -v {*}$opts $arg] code out
            $w.f.t configure -state normal
            $w.f.t delete 1.0 end
            $w.f.t insert end "fossil merge [join $opts] $what\n\nDry run[expr {$code ? " (failed)" : ""}]:\n[string trim $out]"
            $w.f.t configure -state disabled
            $w.f.b.ok state [expr {$code ? "disabled" : "!disabled"}]
            set dry $opts
            set dryDone 1
        }
        set mergeOpt(answer) ""
        vwait ::tkbranches::mergeOpt(answer)
        if {$mergeOpt(answer) eq "cancel"} { destroy $w; return }
        if {$mergeOpt(answer) eq "ok" && [mergeOpts $kind] eq $dry} break
        # (OK with options changed since the dry run: the dry run first.)
    }
    destroy $w
    lassign [inCheckout merge {*}$dry $arg] code out
    uplevel #0 $done
    if {$code} {
        showOutput $label "fossil merge failed:" $out
    } elseif {$root ne $::tktaalik::root} {
        # (Another checkout: committed there, so shown first.)
        if {[ui::ask -title $label "Merged into the checkout $root." \
                "[string trim $out]\n\nShow that checkout, to review and commit?"]} {
            tktaalik::openPath $root
            tktaalik::show commit
        }
    } elseif {[ui::ask -title $label \
            "Merged into the checkout." "[string trim $out]\n\nOpen the commit window?"]} {
        commitWindow
    }
}

# The options of fossil merge chosen; "-" if a field is not acceptable.
proc tkbranches::mergeOpts {kind} {
    variable mergeOpt
    set opts [list {*}[fossil::nosync merge] {*}[dict get {
        branch {} checkin {} cherrypick --cherrypick backout --backout} $kind]]
    if {$kind eq "branch" && $mergeOpt(integrate)} { lappend opts --integrate }
    if {$mergeOpt(keep)} { lappend opts -K }
    if {$mergeOpt(force)} { lappend opts -f }
    foreach {v opt} {baseline --baseline binary --binary} {
        set value [string trim $mergeOpt($v)]
        if {$value eq ""} continue
        if {[catch {fossil::arg $value}]} { return - }
        lappend opts $opt $value
    }
    return $opts
}

# Writing into the repository: refused while autosync is on, as Fossil
# would push the change.
proc tkbranches::canWrite {} {
    variable repo
    variable me
    lassign [fossil::run settings autosync -R $repo] code out
    set value on
    regexp {autosync\s+\([^)]*\)\s+(\S+)} $out -> value
    if {[string tolower $value] ni {off 0 no false pullonly}} {
        tk_messageBox -icon info -title Branches -message "Autosync is on." \
            -detail "Fossil would push this change.  Turn autosync off\
                (fossil settings autosync off) to change branches here."
        return 0
    }
    if {$me eq ""} {
        tk_messageBox -icon info -title Branches -message "There is no default user." \
            -detail "Set one with \"fossil user default\"."
        return 0
    }
    return 1
}

# Close, reopen, hide or unhide the selected branches that can be.
proc tkbranches::tagBranches {action} {
    variable branches
    variable repo
    variable me
    set key [dict get {close closed reopen closed hide hidden unhide hidden} $action]
    set want [expr {$action in {close hide} ? 0 : 1}]
    set names [lmap name [selectedNames] {
        if {![info exists branches($name)] || [dict get $branches($name) $key] != $want} continue
        set name
    }]
    if {![llength $names]} {
        tk_messageBox -icon info -title Branches \
            -message "No selected branch can be [dict get {close closed reopen reopened hide hidden unhide unhidden} $action]."
        return
    }
    if {![canWrite]} return
    foreach name $names { if {![fossil::argOk $name Branches]} return }
    set args [lmap name $names { fossil::arg $name }]
    set what [expr {[llength $names] == 1 ? "branch [lindex $names 0]" : "[llength $names] branches"}]
    # The dry run: the artifact Fossil would record.
    lassign [fossil::run branch $action -n -v -R $repo {*}$args] code out
    if {$code} {
        showOutput Branches "fossil branch $action failed (dry run):" $out
        return
    }
    if {![showOutput Branches "[string totitle $action] $what, as $me, in [file tail $repo]?\
            It is not pushed." "fossil branch $action [join $names]\n\nDry run:\n$out" \
            [string totitle $action]]} return
    lassign [fossil::run branch $action -R $repo {*}$args] code out
    reload
    if {$code} { showOutput "Branches" "fossil branch $action failed:" $out }
}

proc tkbranches::newBranch {basis {label ""}} {
    variable newName ""
    variable newPrivate 0
    variable newColor ""
    variable answer
    if {$basis eq "" || ![canWrite]} return
    if {$label eq ""} { set label [string range $basis 0 9] }
    set w .branches.newbranch
    destroy $w
    toplevel $w
    wm title $w "New branch"
    wm transient $w .
    ttk::frame $w.f -padding 10
    pack $w.f -fill both -expand 1
    ttk::label $w.f.l -text "Name:"
    ttk::entry $w.f.e -textvariable tkbranches::newName -width 40
    ttk::label $w.f.from -text "From: $label"
    ttk::checkbutton $w.f.private -text "Private (never synced)" -variable tkbranches::newPrivate
    ttk::frame $w.f.color
    ttk::label $w.f.color.l -text "Colour:"
    label $w.f.color.swatch -width 3 -relief sunken -borderwidth 1
    ttk::label $w.f.color.name -text automatic
    ttk::button $w.f.color.choose -text "Choose\u2026" -command [list tkbranches::chooseColor $w]
    ttk::button $w.f.color.auto -text Automatic -command [list tkbranches::setColor $w ""]
    pack $w.f.color.l $w.f.color.swatch $w.f.color.name -side left -padx {0 6}
    pack $w.f.color.auto $w.f.color.choose -side right -padx {4 0}
    setColor $w ""
    ttk::frame $w.f.b
    ttk::button $w.f.b.ok -text Create -default active -command {set tkbranches::answer 1}
    ttk::button $w.f.b.cancel -text Cancel -command {set tkbranches::answer 0}
    pack $w.f.b.cancel $w.f.b.ok -side right -padx {4 0}
    grid $w.f.l $w.f.e -sticky w -pady 2
    grid $w.f.from - -sticky w -pady 2
    grid $w.f.private - -sticky w -pady 2
    grid $w.f.color - -sticky ew -pady 2
    grid $w.f.b - -sticky e -pady {8 0}
    bind $w <Return> {set tkbranches::answer 1}
    bind $w <Escape> {set tkbranches::answer 0}
    wm protocol $w WM_DELETE_WINDOW {set tkbranches::answer 0}
    focus $w.f.e
    while 1 {
        set answer 0
        vwait ::tkbranches::answer
        if {!$answer} break
        set name [string trim $newName]
        if {[set problem [badName $name]] eq ""} break
        tk_messageBox -icon info -parent $w -title "New branch" -message $problem
    }
    destroy $w
    if {!$answer} return
    createBranch $name $basis $newPrivate $newColor
}

# The background colour of a new branch in the timeline ("": Fossil's).
proc tkbranches::setColor {w color} {
    variable newColor $color
    $w.f.color.swatch configure -background \
        [expr {$color eq "" ? [$w cget -background] : $color}]
    $w.f.color.name configure -text [expr {$color eq "" ? "automatic" : $color}]
}

proc tkbranches::chooseColor {w} {
    variable newColor
    set color [tk_chooseColor -parent $w -title "Branch colour" \
        {*}[expr {$newColor eq "" ? "" : [list -initialcolor $newColor]}]]
    if {$color ne ""} { setColor $w $color }
}

proc tkbranches::badName {name} {
    variable branches
    if {$name eq ""} { return "The name is empty." }
    if {[regexp {\s} $name]} { return "The name contains spaces." }
    if {[catch {fossil::arg $name}]} { return "The name cannot start with \"[string index $name 0]\"." }
    if {[info exists branches($name)]} { return "There is already a branch $name." }
    return ""
}

proc tkbranches::createBranch {name basis private {color ""}} {
    variable repo
    variable me
    set opts [fossil::nosync branch]
    if {$private} { lappend opts --private }
    if {$color ne ""} { lappend opts --bgcolor $color }
    if {![ui::confirm -title "New branch" \
            "Create branch $name?" \
            "From [string range $basis 0 9][expr {$private ? ", private" : ""}][expr {$color ne "" ? ", colour $color" : ""}],\
                as $me, in [file tail $repo].  It is not pushed."]} return
    lassign [fossil::run branch new -R $repo [fossil::arg $name] [fossil::arg $basis] {*}$opts] \
        code out
    if {$code} {
        showOutput "New branch" "fossil branch new failed:" $out
        return
    }
    reload
    set t .branches.main.list.t
    if {![$t exists $name]} {
        variable view all
        variable query ""
        search
    }
    if {[$t exists $name]} {
        $t selection set $name
        $t focus $name
        $t see $name
    }
}

proc tkbranches::setTargets {} {
    variable targets
    variable config
    variable repo
    variable answer
    set w .branches.targets
    destroy $w
    toplevel $w
    wm title $w "Merge targets"
    wm transient $w .
    ttk::frame $w.f -padding 10
    pack $w.f -fill both -expand 1
    ttk::label $w.f.l -justify left -text "The branches whose merge state is shown, in order;\
        \nthe first one also decides \"Unmerged\".  One per line:"
    text $w.f.t -width 40 -height 6 -font TkFixedFont
    $w.f.t insert end [join $targets \n]
    ttk::frame $w.f.b
    ttk::button $w.f.b.ok -text OK -default active -command {set tkbranches::answer 1}
    ttk::button $w.f.b.cancel -text Cancel -command {set tkbranches::answer 0}
    pack $w.f.b.cancel $w.f.b.ok -side right -padx {4 0}
    pack $w.f.l -anchor w
    pack $w.f.t -fill both -expand 1 -pady 4
    pack $w.f.b -fill x
    bind $w <Escape> {set tkbranches::answer 0}
    wm protocol $w WM_DELETE_WINDOW {set tkbranches::answer 0}
    set answer 0
    vwait ::tkbranches::answer
    set text [$w.f.t get 1.0 end]
    destroy $w
    if {!$answer} return
    set targets {}
    foreach line [split $text \n] {
        set line [string trim $line]
        if {$line ne "" && $line ni $targets} { lappend targets $line }
    }
    dict set config targets $repo $targets
    setupColumns 1
    reload
}

# ------------------------------------------------------------ finish

# After a branch is merged (TIP 710: reviewed, tested by CI, merged): in
# one go, the core-* tags its check-ins got for the CI cancelled, the
# open tickets it fixes closed, and the branch closed.  Each is a check
# box; Fossil's dry runs and one question before anything is written.

namespace eval tkbranches {
    variable finish             ;# array: the check boxes of the window
}

# The core-* tags (not release tags) given to the branch's check-ins
# themselves: {name hash} each.
proc tkbranches::ciTags {name} {
    variable repo
    set rows [sql "SELECT DISTINCT substr(t.tagname,5), b.uuid FROM tagxref x
        JOIN tag t ON t.tagid=x.tagid JOIN blob b ON b.rid=x.rid
        WHERE x.tagtype=1 AND t.tagname GLOB 'sym-core-*'
        AND x.rid IN (SELECT rid FROM tagxref WHERE tagtype>0 AND value=[fossil::sqlstr $name]
            AND tagid=(SELECT tagid FROM tag WHERE tagname='branch'))
        ORDER BY 1"]
    lmap row $rows {
        # (core-9-0-2, core-8-6-17, core-9-1-b0...: releases.)
        if {[regexp {^core-[0-9]+-[0-9]+-([0-9]+|[ab][0-9]+)(-rc[0-9]*)?$} [lindex $row 0]]} continue
        set row
    }
}

# The open tickets the branch's comments link to: {uuid title type status
# fix} each, fix 1 if a comment names it as fixed ("Fix [id]...").
proc tkbranches::finishTickets {name} {
    variable branches
    if {![llength [dict get $branches($name) tickets]]} { return {} }
    ::tickets::useRepository $::tkbranches::repo
    set comments [split [dict get $branches($name) comments] \x02]
    set result {}
    foreach id [dict get $branches($name) tickets] {
        set row [lindex [::tickets::sql "SELECT tkt_uuid, [join [lmap f {title type status} {
            fossil::outcol "coalesce([::tickets::field $f],'')"
        }] {, }] FROM ticket WHERE tkt_uuid GLOB [fossil::sqlstr $id*]"] 0]
        if {$row eq ""} continue
        lassign $row uuid title type status
        if {[tktsearch::isClosed $status]} continue
        set fix 0
        foreach c $comments {
            set id4 [string range $id 0 3]
            if {[regexp -nocase [string cat {(^|\m)(fix(es|ed)?|close[sd]?|resolve[sd]?)\s+((for|of|bug|ticket)\s+)*\[} $id4] $c]
                    || [regexp -nocase [string cat {^\s*\[} $id4] $c]} {
                set fix 1
            }
        }
        lappend result [list $uuid $title $type $status $fix]
    }
    return $result
}

# Whether Finish has anything to do for branch NAME: not a branch merged
# into (main, the release branches), and still open, or with a CI tag or
# an open ticket it fixes left.
proc tkbranches::finishable {name} {
    variable branches
    variable targets
    if {![info exists branches($name)] || $name in $targets || $name in {trunk main}} { return 0 }
    if {![dict get $branches($name) closed]} { return 1 }
    if {[llength [ciTags $name]]} { return 1 }
    foreach t [finishTickets $name] { if {[lindex $t 4]} { return 1 } }
    return 0
}

proc tkbranches::finish {name} {
    variable branches
    variable targets
    variable finish
    if {![info exists branches($name)] || ![canWrite]} return
    set b $branches($name)
    set tags [ciTags $name]
    set tickets [finishTickets $name]
    set w .branches.finish
    set f [ui::dialog $w "Finish branch $name" -escape [list destroy $w] -help branches#finishing-a-branch]
    array unset finish
    set row 0
    ttk::label $f.intro -justify left -wraplength 560 -text "After the branch is merged: what\
        is still to do, each as checked.  Nothing is pushed."
    grid $f.intro -row [incr row] -sticky w -pady {0 6}
    # Not merged yet into the first target: said, not forbidden.
    set first [lindex $targets 0]
    if {$first ne "" && $first ne $name && [dict get $b merged $first] != 2} {
        ttk::label $f.warn -foreground red3 -wraplength 560 -justify left -text "The last check-in of\
            $name is not merged into [targetHeading $first] yet."
        grid $f.warn -row [incr row] -sticky w -pady {0 6}
    }
    set n 0
    foreach t $tags {
        lassign $t tag hash
        set finish(tag,$n) 1
        set finish(tagof,$n) $t
        ttk::checkbutton $f.t$n -variable tkbranches::finish(tag,$n) \
            -text "Cancel the CI tag $tag on [string range $hash 0 9]"
        grid $f.t$n -row [incr row] -sticky w
        incr n
    }
    set n 0
    foreach t $tickets {
        lassign $t uuid title type status fix
        set finish(tkt,$n) $fix
        set finish(tktof,$n) $t
        set resolution [expr {[string equal -nocase [string trim $type] bug] ? "Fixed" : "Accepted"}]
        set finish(res,$n) $resolution
        ttk::checkbutton $f.k$n -variable tkbranches::finish(tkt,$n) \
            -text "Close ticket [string range $uuid 0 9] as $resolution: $title"
        grid $f.k$n -row [incr row] -sticky w
        if {!$fix} { icons::tooltip $f.k$n "Only mentioned in the branch's comments, not named as fixed" }
        incr n
    }
    if {![dict get $b closed]} {
        set finish(close) 1
        ttk::checkbutton $f.close -variable tkbranches::finish(close) -text "Close the branch $name"
        grid $f.close -row [incr row] -sticky w
    }
    if {![llength $tags] && ![llength $tickets] && [dict get $b closed]} {
        ttk::label $f.none -text "Nothing is left to do: the branch is closed, and it has no CI tags\
            or open tickets." -wraplength 560
        grid $f.none -row [incr row] -sticky w
    }
    ttk::frame $f.b
    ttk::button $f.b.ok -text Finish -default active -command [list tkbranches::finishDone $name]
    ttk::button $f.b.cancel -text Cancel -command [list destroy $w]
    pack $f.b.cancel $f.b.ok -side right -padx {4 0}
    grid $f.b -row [incr row] -sticky ew -pady {10 0}
    focus $f.b.ok
}

proc tkbranches::finishDone {name} {
    variable finish
    variable repo
    variable me
    set w .branches.finish
    if {![winfo exists $w]} return
    # The closed status as the repository spells it (as Close ticket).
    ::tickets::useRepository $repo
    set closed Closed
    set choices [::tickets::choices]
    if {[dict exists $choices status]} {
        set i [lsearch -exact -nocase [dict get $choices status] closed]
        if {$i >= 0} { set closed [lindex [dict get $choices status] $i] }
    }
    # What is checked, with Fossil's dry runs.
    set steps {}
    set dry {}
    foreach key [lsort -dictionary [array names finish tag,*]] {
        if {!$finish($key)} continue
        lassign $finish(tagof,[lindex [split $key ,] 1]) tag hash
        set cmd [list tag cancel [fossil::arg $tag] [fossil::arg $hash]]
        lassign [fossil::run {*}$cmd -R $repo --dry-run] code out
        if {$code} { ui::errorBox -parent $w -title "Finish branch" "fossil tag cancel failed (dry run):" $out; return }
        lappend steps [list fossil $cmd]
        lappend dry "fossil [join $cmd]\n[string trim $out]"
    }
    foreach key [lsort -dictionary [array names finish tkt,*]] {
        if {!$finish($key)} continue
        set n [lindex [split $key ,] 1]
        lassign $finish(tktof,$n) uuid title type status
        lappend steps [list ticket $uuid $status $finish(res,$n)]
        lappend dry "ticket [string range $uuid 0 9]: status $status \u2192 $closed, resolution $finish(res,$n)"
    }
    if {[info exists finish(close)] && $finish(close)} {
        lassign [fossil::run branch close -n -v -R $repo [fossil::arg $name]] code out
        if {$code} { ui::errorBox -parent $w -title "Finish branch" "fossil branch close failed (dry run):" $out; return }
        lappend steps [list fossil [list branch close [fossil::arg $name]]]
        lappend dry "fossil branch close $name\n[string trim $out]"
    }
    if {![llength $steps]} {
        ui::infoBox -parent $w -title "Finish branch" "Nothing is checked."
        return
    }
    if {![showOutput "Finish branch" "Finish $name: [llength $steps] [expr {[llength $steps] == 1 ? "change" : "changes"}],\
            as $me, in [file tail $repo]?  Nothing is pushed." [join $dry \n\n] Finish]} return
    destroy $w
    # The ticket fields as Close ticket writes them.
    set ::tickets::me $me
    set done 0
    foreach step $steps {
        if {[lindex $step 0] eq "fossil"} {
            lassign [fossil::run {*}[lindex $step 1] -R $repo] code out
            if {$code} {
                showOutput "Finish branch" "fossil [lindex $step 1 0] failed\
                    ($done of [llength $steps] done):" $out
                break
            }
        } else {
            lassign $step - uuid status resolution
            set fields [list status $closed]
            if {[::tickets::canWrite resolution]} { dict set fields resolution $resolution }
            set fields [dict merge $fields [tktsearch::closerFields $status $closed]]
            if {[catch {::tickets::writeTicket set $uuid $fields} msg]} {
                showOutput "Finish branch" "The ticket [string range $uuid 0 9] was not closed\
                    ($done of [llength $steps] done):" $msg
                break
            }
        }
        incr done
    }
    reload
}

# ------------------------------------------------------------ backport

# A branch into another checkout of the repository (one on 8.6, while this
# one is on main): its check-ins cherry-picked there, oldest first, or the
# branch merged, with Fossil's dry runs; the checkout shown is not
# touched.  Then that checkout can be shown, to commit there.

namespace eval tkbranches {
    variable bp                 ;# array: the choices of the window
}

# The other checkouts of the repository at the tip of a merge target (the
# ones to backport to): {dir branch changes} each.
proc tkbranches::backportTargets {} {
    variable repo
    variable root
    variable branches
    variable targets
    set tips {}
    foreach t $targets {
        if {![info exists branches($t)]} continue
        dict set tips [lindex [sql "SELECT rid FROM blob\
            WHERE uuid=[fossil::sqlstr [dict get $branches($t) tip]]"] 0 0] $t
    }
    set result {}
    foreach row [sql "SELECT substr(name,7) FROM config WHERE name GLOB 'ckout:*' ORDER BY 1"] {
        set dir [string trimright [lindex $row 0] /]
        if {$dir eq "" || $dir eq [string trimright $root /] || ![file isdirectory $dir]} continue
        if {![file exists $dir/.fslckout] && ![file exists $dir/_FOSSIL_]} continue
        if {[catch {fossil::checkoutSql $dir "SELECT (SELECT value FROM vvar WHERE name='checkout'),
            (SELECT count(*) FROM vfile WHERE chnged OR deleted OR rid=0)"} rows]} continue
        lassign [lindex $rows 0] rid changes
        if {[dict exists $tips $rid]} { lappend result [list $dir [dict get $tips $rid] $changes] }
    }
    return $result
}

# The check-ins of branch NAME, oldest first: {uuid date comment merge} each
# (merge: it merged something in).
proc tkbranches::branchCheckins {name} {
    sql "SELECT b.uuid, strftime('%Y-%m-%d %H:%M', e.mtime),
        [fossil::outcol "coalesce(e.ecomment,e.comment)"],
        EXISTS(SELECT 1 FROM plink WHERE cid=x.rid AND NOT isprim)
        FROM tagxref x JOIN event e ON e.objid=x.rid JOIN blob b ON b.rid=x.rid
        WHERE x.tagtype>0 AND x.value=[fossil::sqlstr $name]
        AND x.tagid=(SELECT tagid FROM tag WHERE tagname='branch') AND e.type='ci'
        ORDER BY e.mtime"
}

proc tkbranches::backport {name} {
    variable branches
    variable bp
    if {![info exists branches($name)]} return
    set b $branches($name)
    set dests [backportTargets]
    variable bpDests $dests
    set checkins [branchCheckins $name]
    array unset bp
    set bp(other) ""
    # By default: a target the branch is not merged into yet.
    set bp(dest) [expr {[llength $dests] ? 0 : "other"}]
    set i 0
    foreach d $dests {
        lassign $d dir branch
        if {[dict exists $b merged $branch] && [dict get $b merged $branch] != 2} { set bp(dest) $i; break }
        incr i
    }
    set w .branches.backport
    set f [ui::dialog $w "Backport $name" -escape [list destroy $w] -help branches#backports]
    ttk::label $f.intro -wraplength 620 -justify left -text "Bring $name into another checkout\
        of [file tail $::tkbranches::repo]; this one stays as it is.  Nothing is committed."
    grid $f.intro - -sticky w -pady {0 6}
    ttk::labelframe $f.to -text "Into the checkout" -padding 6
    grid $f.to - -sticky ew
    set i 0
    foreach d $dests {
        lassign $d dir branch changes
        ttk::radiobutton $f.to.d$i -variable tkbranches::bp(dest) -value $i \
            -text "$dir \u2014 on [targetHeading $branch][expr {$changes ? ", $changes changed files" : ""}]" \
            -command tkbranches::backportHow
        grid $f.to.d$i - -sticky w
        incr i
    }
    ttk::radiobutton $f.to.other -variable tkbranches::bp(dest) -value other -text "Other checkout:" \
        -command tkbranches::backportHow
    ttk::entry $f.to.dir -textvariable tkbranches::bp(other) -width 50
    grid $f.to.other $f.to.dir -sticky w
    grid $f.to.dir -sticky ew
    grid columnconfigure $f.to 1 -weight 1
    ttk::labelframe $f.how -text How -padding 6
    grid $f.how - -sticky ew -pady {6 0}
    ttk::radiobutton $f.how.pick -variable tkbranches::bp(how) -value cherrypick \
        -text "Cherry-pick its check-ins (fossil merge --cherrypick), oldest first:"
    ttk::radiobutton $f.how.merge -variable tkbranches::bp(how) -value merge \
        -text "Merge the branch (fossil merge $name): also what it was based on"
    grid $f.how.pick -sticky w
    set i 0
    foreach c $checkins {
        lassign $c uuid date comment merge
        set bp(ci,$i) [expr {!$merge}]
        set bp(uuid,$i) $uuid
        set text "[string range $uuid 0 9]  $date  [string range [lindex [split $comment \n] 0] 0 70]"
        if {$merge} { set text "(a merge) $text" }
        ttk::checkbutton $f.how.c$i -variable tkbranches::bp(ci,$i) -text $text
        grid $f.how.c$i -sticky w -padx {20 0}
        if {$merge} {
            icons::tooltip $f.how.c$i "It merged something into the branch: cherry-picked, the merged\
                changes would come too"
        }
        incr i
    }
    set bp(count) $i
    grid $f.how.merge -sticky w -pady {4 0}
    set bp(base) [dict get $b base]
    backportHow
    ttk::frame $f.b
    ttk::button $f.b.ok -text Backport\u2026 -default active -command [list tkbranches::backportDone $name]
    ttk::button $f.b.cancel -text Cancel -command [list destroy $w]
    pack $f.b.cancel $f.b.ok -side right -padx {4 0}
    grid $f.b - -sticky e -pady {10 0}
}

# How, by default, for the checkout chosen: merged if it is on the branch
# the branch was made from, else cherry-picked.
proc tkbranches::backportHow {} {
    variable bp
    variable bpDests
    set branch ""
    if {$bp(dest) ne "other"} { set branch [lindex $bpDests $bp(dest) 1] }
    # (main and trunk: the same branch.)
    set same [expr {$branch eq $bp(base) || ($branch in {main trunk} && $bp(base) in {main trunk})}]
    set bp(how) [expr {$branch ne "" && $same ? "merge" : "cherrypick"}]
}

proc tkbranches::backportDone {name} {
    variable bp
    variable bpDests
    variable repo
    set w .branches.backport
    if {![winfo exists $w]} return
    if {$bp(dest) eq "other"} {
        set dir [file normalize [string trim $bp(other)]]
        lassign [fossil::run -dir $dir info] code out
        if {[string trim $bp(other)] eq "" || ![file isdirectory $dir] || $code
                || ![regexp -line {^repository:\s+(.*\S)} $out -> r]
                || [file normalize $r] ne [file normalize $repo]} {
            ui::infoBox -parent $w -title Backport "Not a checkout of [file tail $repo]:" $dir
            return
        }
    } else {
        set dir [lindex $bpDests $bp(dest) 0]
    }
    if {$bp(how) eq "merge"} {
        destroy $w
        merge branch $name $dir
        return
    }
    set picks {}
    for {set i 0} {$i < $bp(count)} {incr i} {
        if {$bp(ci,$i)} { lappend picks $bp(uuid,$i) }
    }
    if {![llength $picks]} {
        ui::infoBox -parent $w -title Backport "No check-in is checked."
        return
    }
    # Dry runs, each on the files as they are now.
    set dry {}
    foreach uuid $picks {
        lassign [fossil::run -dir $dir merge -n --cherrypick $uuid] code out
        if {$code} {
            ui::errorBox -parent $w -title Backport "fossil merge --cherrypick [string range $uuid 0 9] failed\
                (dry run):" $out
            return
        }
        lappend dry "fossil merge --cherrypick [string range $uuid 0 9]\n[string trim $out]"
    }
    if {![showOutput Backport "Cherry-pick [llength $picks] [expr {[llength $picks] == 1 ? "check-in" : "check-ins"}]\
            of $name into $dir?  The files change; nothing is committed.  (Each dry run is on the\
            files as they are now, before the ones above it.)" [join $dry \n\n] Backport]} return
    destroy $w
    set done 0
    foreach uuid $picks {
        lassign [fossil::run -dir $dir merge --cherrypick $uuid] code out
        if {$code} {
            showOutput Backport "fossil merge --cherrypick [string range $uuid 0 9] failed\
                ($done of [llength $picks] done):" $out
            return
        }
        incr done
    }
    if {[ui::ask -title Backport "Cherry-picked into $dir." \
            "[llength $picks] check-ins of $name.\n\nShow that checkout, to review and commit?"]} {
        tktaalik::openPath $dir
        tktaalik::show commit
    }
}
