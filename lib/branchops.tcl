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
    set dry ""
    while 1 {
        set opts [mergeOpts $kind]
        if {$opts eq "-"} {
            tk_messageBox -parent $w -icon info -title $label \
                -message "The baseline and the binary files cannot start with \"-\", \"<\", \">\" or \"|\"."
        } elseif {$dry ne $opts} {
            # The dry run (again, with the options changed).
            lassign [inCheckout merge -n -v {*}$opts $arg] code out
            $w.f.t configure -state normal
            $w.f.t delete 1.0 end
            $w.f.t insert end "fossil merge [join $opts] $what\n\nDry run[expr {$code ? " (failed)" : ""}]:\n[string trim $out]"
            $w.f.t configure -state disabled
            $w.f.b.ok state [expr {$code ? "disabled" : "!disabled"}]
            set dry $opts
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
    } elseif {[ui::ask -title $label \
            "Merged into the checkout." "[string trim $out]\n\nOpen the commit window?"]} {
        commitWindow
    }
}

# The options of fossil merge chosen; "-" if a field is not acceptable.
proc tkbranches::mergeOpts {kind} {
    variable mergeOpt
    set opts [list --nosync {*}[dict get {
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
    set opts [list --nosync]
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
