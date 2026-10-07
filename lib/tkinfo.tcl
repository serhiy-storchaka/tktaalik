# The Information window of tktaalik (Repository menu): what "fossil
# info" says about the repository (and the checkout), how much it holds
# (check-ins, tickets, wiki pages, files...), its statistics ("fossil
# dbstat", the hash policy, the login group) and the Fossil running;
# checking its integrity (dbstat --db-check, --db-verify).  Its
# maintenance: rebuild, repack, after a confirmation (a backup offered).

source [file join [file dirname [file normalize [info script]]] fossil.tcl]

namespace eval tkinfo {
    variable repo ""
    variable root ""
    variable verifying ""       ;# the handle of a full verification (fossil::start)
    variable status ""
}

# Open the window (made the first time), for the repository shown.
proc tkinfo::window {} {
    if {[tktaalik::dialogWindow .info Information]} { build }
    setRepository $::tktaalik::repo $::tktaalik::root
    focus .info.text
}

proc tkinfo::build {} {
    wm geometry .info 640x560
    set d .info.text
    text $d -wrap word -width 70 -height 30 -padx 10 -pady 8 -font TkTextFont \
        -state disabled -yscrollcommand {.info.y set}
    ttk::scrollbar .info.y -command [list $d yview]
    set tab [expr {[font measure TkDefaultFont 0] * 16}]
    $d configure -tabs [list $tab]
    $d tag configure title -font TkHeadingFont -spacing1 6 -spacing3 4
    $d tag configure label -foreground gray40
    $d tag configure value -lmargin2 $tab
    ttk::frame .info.b -padding 6
    ttk::button .info.b.check -text "Check integrity" -command tkinfo::check
    ttk::button .info.b.verify -text "Full verification\u2026" -command tkinfo::verify
    ttk::menubutton .info.b.more -text "Maintenance" -menu .info.b.more.m -direction above
    menu .info.b.more.m -tearoff 0
    .info.b.more.m add command -label "Rebuild\u2026" -command tkinfo::rebuild
    .info.b.more.m add command -label "Repack\u2026" -command tkinfo::repack
    .info.b.more.m add separator
    .info.b.more.m add command -label "About Fossil\u2026" -command tkinfo::aboutFossil
    ttk::button .info.b.refresh -text Refresh -command tkinfo::reload
    ttk::button .info.b.close -text Close -command {wm withdraw .info}
    ttk::label .info.b.status -textvariable tkinfo::status -anchor w
    pack .info.b.check .info.b.verify .info.b.more -side left -padx {0 4}
    pack .info.b.close .info.b.refresh -side right -padx {4 0}
    pack .info.b.status -side left -fill x -expand 1 -padx {6 0}
    icons::tooltip .info.b.check "A quick check of the database (fossil dbstat --db-check)"
    icons::tooltip .info.b.verify "Decode and check every artifact (fossil dbstat --db-verify):\ncan take long on a big repository"
    pack .info.b -side bottom -fill x
    pack .info.y -side right -fill y
    pack $d -fill both -expand 1
    bind .info <F5> tkinfo::reload
}

proc tkinfo::setRepository {path newRoot} {
    variable repo $path
    variable root $newRoot
    wm title .info "Information \u2014 [file rootname [file tail $repo]]"
    reload
}

# "fossil info -v": in the checkout (then about it too), else with -R.
# (-v: also the checkouts of the repository and the URLs it was served at.)
proc tkinfo::fossilInfo {} {
    variable repo
    variable root
    fossil::runIn $root $repo info -v
}

# What the repository holds: label -> count.  The tables of the forum and
# of the unversioned files are not in every repository.
proc tkinfo::counts {} {
    variable repo
    set tables [concat {*}[fossil::sql $repo \
        "SELECT name FROM sqlite_schema WHERE type='table'"]]
    set parts {
        Check-ins          "(SELECT count(*) FROM event WHERE type='ci')"
        "Ticket changes"   "(SELECT count(*) FROM event WHERE type='t')"
        "Wiki pages"       "(SELECT count(*) FROM tag WHERE tagname GLOB 'wiki-*')"
        Technotes          "(SELECT count(*) FROM event WHERE type='e')"
        Tags               "(SELECT count(*) FROM tag WHERE tagname GLOB 'sym-*')"
        Files              "(SELECT count(*) FROM filename)"
        Artifacts          "(SELECT count(*) FROM blob)"
        Users              "(SELECT count(*) FROM user)"
    }
    if {"ticket" in $tables} {
        set parts [linsert $parts 2 Tickets "(SELECT count(*) FROM ticket)"]
    }
    if {"forumpost" in $tables} { lappend parts "Forum posts" "(SELECT count(*) FROM forumpost)" }
    if {"unversioned" in $tables} {
        lappend parts "Unversioned files" "(SELECT count(*) FROM unversioned WHERE hash IS NOT NULL)"
    }
    set row [lindex [fossil::sql $repo "SELECT [join [dict values $parts] ,]"] 0]
    set result {}
    foreach label [dict keys $parts] value $row { lappend result $label $value }
    return $result
}

proc tkinfo::reload {} {
    variable repo
    set d .info.text
    $d configure -state normal
    $d delete 1.0 end
    lassign [fossilInfo] code out
    $d insert end "Repository\n" title
    if {$code} {
        $d insert end "fossil info failed: $out\n"
    } else {
        # The checkouts and the URLs (a line each, with when last used):
        # sections of their own.  (In a checkout the others are alt-root
        # lines, with -R check-out lines.)
        set more {alt-root {} access-url {}}
        foreach line [split [string trim $out] \n] {
            if {[regexp {^([^:]+):\s*(.*)$} $line -> key value]} {
                if {$key eq "check-out"} { set key alt-root }
                if {[dict exists $more $key]} {
                    regexp {^(.*?)\s+(\d{4}-\d\d-\d\d)$} $value -> value when
                    dict lappend more $key [list $value [expr {[info exists when] ? $when : ""}]]
                    unset -nocomplain when
                    continue
                }
                $d insert end "$key\t" label "$value\n" value
            } else {
                $d insert end "\t" "" "$line\n" value
            }
        }
    }
    $d insert end "Size\t" label "[format %.1f [expr {[file size $repo] / 1048576.0}]] MB\n" value
    foreach {key title} {alt-root "Checkouts" access-url "Accessed as"} {
        if {$code || ![llength [dict get $more $key]]} continue
        $d insert end "$title\n" title
        foreach item [dict get $more $key] {
            lassign $item value when
            $d insert end "$when\t" label "$value\n" value
        }
    }
    $d insert end "Contents\n" title
    try {
        foreach {label value} [counts] { $d insert end "$label\t" label "$value\n" value }
    } trap {FOSSIL DB} msg {
        $d insert end "Cannot count: $msg\n"
    }
    # Statistics: fossil dbstat (what the lines above do not say).
    lassign [fossil::run dbstat -R $repo] code out
    if {!$code} {
        $d insert end "Statistics\n" title
        set keys {artifact-count Artifacts artifact-sizes "Artifact sizes"
            compression-ratio Compression latest-change "Latest change"
            project-age "Project age" project-id "Project ID" schema-version Schema
            sqlite-version SQLite database-stats Database}
        foreach line [split $out \n] {
            if {[regexp {^([a-z-]+):\s*(.*)$} $line -> key value] && [dict exists $keys $key]} {
                $d insert end "[dict get $keys $key]\t" label "$value\n" value
            }
        }
        lassign [fossil::run hash-policy -R $repo] code policy
        if {!$code} { $d insert end "Hash policy\t" label "[string trim $policy]\n" value }
        lassign [fossil::run login-group -R $repo] code group
        if {!$code} {
            $d insert end "Login group\t" label "[string trim [lindex [split [string trim $group] \n] 0]]\n" value
        }
    }
    $d insert end "Fossil\n" title
    $d insert end "Version\t" label "[tktaalik::fossilVersion]\n" value
    $d configure -state disabled
}

# A quick check of the database: PRAGMA quick_check.
proc tkinfo::check {} {
    variable repo
    variable status
    set status "Checking\u2026"
    update idletasks
    lassign [fossil::run dbstat --db-check --omit-version-info -R $repo] code out
    if {!$code && [regexp -line {^database-check:\s*(.*)$} $out -> result]} {
        set status "Database check: $result"
        if {$result ne "ok"} {
            tk_messageBox -parent .info -icon warning -title Information \
                -message "The database check found problems:" -detail $result
        }
    } else {
        set status "The check failed"
        tk_messageBox -parent .info -icon error -title Information -message "fossil dbstat failed:" \
            -detail [string trim $out]
    }
}

# A full verification (every artifact decoded), in the background.
proc tkinfo::verify {} {
    variable repo
    variable verifying
    variable status
    if {$verifying ne ""} return
    if {![ui::confirm -parent .info -default ok -title Information \
            "Verify every artifact of [file tail $repo]?" \
            "It reads the whole repository and can take minutes on a big one.\
                Nothing is changed."]} return
    set status "Verifying\u2026"
    .info.b.verify state disabled
    set verifying [fossil::start -onDone tkinfo::verified dbstat --db-verify --omit-version-info -R $repo]
}

proc tkinfo::verified {code text stopped msg} {
    variable verifying
    variable status
    set verifying ""
    if {![winfo exists .info]} return
    .info.b.verify state !disabled
    # "N non-phantom blobs (out of M total) checked:  E errors" and the
    # low-level integrity check (the progress before, with carriage
    # returns: not shown).
    set errors ""
    # (The count of the artifacts checked: the non-phantom ones.)
    regexp {(\d+) non-phantom blobs \(out of \d+ total\) checked:\s*(\d+) errors} $text -> checked errors
    set integrity ""
    regexp -line {integrity-check:\s*(.*)$} $text -> integrity
    if {!$code && $errors eq "0" && $integrity eq "ok"} {
        set status "Verified: $checked artifacts, no errors; database ok"
    } else {
        set status "The verification found problems"
        set lines [lmap l [split [string map {\r \n} $text] \n] {
            if {[regexp {^\s*\d+/\d+\s*$} $l] || [string trim $l] eq ""} continue; set l }]
        tk_messageBox -parent .info -icon warning -title Information \
            -message "The verification found problems:" -detail [join [lrange $lines end-20 end] \n]
    }
}

# Maintenance: "fossil rebuild" (its options), "fossil repack" (rebuild
# --compress-only).  No dry run in Fossil: asked, with a backup offered
# first; shown running, not stopped half way.
proc tkinfo::rebuild {} {
    variable repo
    if {[ui::formBusy]} return
    array unset ::repoops::f
    array set ::repoops::f {backup 1 index Keep compress 0 analyze 0 vacuum 0 cluster 0 wal 0}
    if {![repoops::form .repoopsForm "Rebuild repository" "Rebuild the database of\
            [file tail $repo] from its artifacts: after updating Fossil, or when a check found\
            problems.  It can take long on a big repository." {
            {backup "Back up the repository first" check}
            {index "Full-text search index" choice {Keep Add Omit}}
            {compress "Make it as small as possible (--compress)" check}
            {analyze "Analyze it afterwards (--analyze)" check}
            {vacuum "Vacuum it afterwards (--vacuum)" check}
            {cluster "Cluster the unclustered artifacts (--cluster)" check}
            {wal "Write-ahead log journal (--wal)" check}
        } Rebuild\u2026]} return
    set cmd [list fossil rebuild]
    switch -- $::repoops::f(index) { Add { lappend cmd --index } Omit { lappend cmd --noindex } }
    foreach {k o} {compress --compress analyze --analyze vacuum --vacuum cluster --cluster wal --wal} {
        if {$::repoops::f($k)} { lappend cmd $o }
    }
    lappend cmd $repo
    maintain "Rebuild" $cmd $::repoops::f(backup)
}

proc tkinfo::repack {} {
    variable repo
    set answer [tk_messageBox -parent .info -icon question -type yesnocancel -default yes \
        -title Repack -message "Repack [file tail $repo]?" -detail "More delta compression to\
        make it smaller (fossil repack).  It can take long.  Back up the repository first?"]
    if {$answer eq "cancel"} return
    maintain "Repack" [list fossil repack $repo] [expr {$answer eq "yes"}]
}

proc tkinfo::maintain {title cmd backup} {
    variable repo
    if {$backup} {
        repoops::backup
        if {![ui::confirm -parent .info -title $title \
                "$title [file tail $repo] now?" "fossil [join [lrange $cmd 1 end]]"]} return
    } elseif {![ui::confirm -parent .info -title $title \
            "$title [file tail $repo] without a backup?" "fossil [join [lrange $cmd 1 end]]\n\nNothing is pushed."]} {
        return
    }
    repoops::runShown $title $cmd {::apply {{code out} { if {[winfo exists .info]} tkinfo::reload }}} "" "" 0
}

# The Fossil running: its version and how it was built ("fossil
# version -v").
proc tkinfo::aboutFossil {} {
    set w .info.about
    destroy $w
    toplevel $w
    wm title $w "About Fossil"
    wm transient $w .info
    lassign [fossil::run version -v] code out
    text $w.t -height 24 -width 80 -wrap word -font TkFixedFont -yscrollcommand [list $w.y set]
    ttk::scrollbar $w.y -command [list $w.t yview]
    $w.t insert end [string trim $out]
    $w.t configure -state disabled
    ttk::button $w.close -text Close -command [list destroy $w]
    pack $w.close -side bottom -anchor e -padx 8 -pady 6
    pack $w.y -side right -fill y
    pack $w.t -fill both -expand 1
    bind $w <Escape> [list destroy $w]
}
