# Operations on the history shared by the Timeline, Branches and Tags tabs:
# a check-in as an archive (fossil zip/tarball/sqlar), an artifact as it
# is (fossil artifact), the common ancestor of two check-ins (fossil
# merge-base), making private check-ins public (fossil publish), bundles
# (fossil bundle export/import/purge), purging check-ins and the graveyard
# (fossil purge), switching the checkout without merging (fossil checkout
# --keep), and the description of a check-in from its nearest tag (as
# fossil describe, without a checkout).  Only the archives and bundles
# written to files; publish, import, purge and the checkout change things
# after a confirmation that shows Fossil's dry run where it has one;
# nothing is pushed.

source [file join [file dirname [file normalize [info script]]] fossil.tcl]
source [file join [file dirname [file normalize [info script]]] tagwrite.tcl]

namespace eval histops {
    variable archive          ;# array: the fields of the archive dialog
    variable bundle           ;# array: the fields of the bundle dialogs
    variable describeCache {} ;# repo,rid,match -> description
    variable digits {}        ;# repo -> the hash-digits setting
}

# Forget the descriptions: after a change of the tags, a pull...
proc histops::forget {} {
    variable describeCache {}
    variable digits {}
}

# Run fossil in the checkout ROOT if there is one, else with -R REPO.
proc histops::run {repo root args} {
    fossil::runIn $root $repo {*}$args
}

# A text in a window of its own (Close; Copy all).
proc histops::textWindow {w title text} {
    destroy $w
    toplevel $w
    wm title $w $title
    ttk::frame $w.f -padding 8
    text $w.f.t -width 100 -height 30 -font TkFixedFont -wrap none \
        -yscrollcommand [list $w.f.y set] -xscrollcommand [list $w.f.x set]
    ttk::scrollbar $w.f.y -command [list $w.f.t yview]
    ttk::scrollbar $w.f.x -orient horizontal -command [list $w.f.t xview]
    $w.f.t insert end $text
    $w.f.t configure -state disabled
    ttk::frame $w.f.b
    ttk::button $w.f.b.copy -text "Copy all" -command [list apply {{t} {
        ui::copy [$t get 1.0 end-1c] }} $w.f.t]
    ttk::button $w.f.b.close -text Close -command [list destroy $w]
    pack $w.f.b.close $w.f.b.copy -side right -padx {4 0}
    grid $w.f.t $w.f.y -sticky news
    grid $w.f.x -sticky ew
    grid $w.f.b - -sticky ew -pady {6 0}
    grid columnconfigure $w.f 0 -weight 1
    grid rowconfigure $w.f 0 -weight 1
    pack $w.f -fill both -expand 1
    bind $w <Escape> [list destroy $w]
    return $w
}

# ---------------------------------------------------------------- artifact

# The artifact (manifest, control artifact...) as Fossil stores it.
proc histops::showArtifact {repo uuid} {
    lassign [fossil::run artifact [fossil::arg $uuid] -R $repo] code out
    if {$code} {
        tk_messageBox -icon error -title Artifact -message "fossil artifact failed:" -detail $out
        return
    }
    textWindow .artifact "Artifact [string range $uuid 0 9]" $out
}

# ---------------------------------------------------------------- archive

# Save a check-in (CHECKIN, a hash or a name; LABEL for the title) as an
# archive: ZIP, tarball (.tar.gz) or SQL archive, with a top directory
# (--name) and the files chosen (--include, --exclude).  Only a file is
# written, where the user chooses.
proc histops::archive {repo checkin {label ""}} {
    variable archive
    if {![fossil::argOk $checkin Archive]} return
    if {$label eq ""} { set label [string range $checkin 0 9] }
    set project [lindex [fossil::sql $repo "SELECT coalesce((SELECT value FROM config\
        WHERE name='project-name'),'')"] 0 0]
    regsub -all {[^A-Za-z0-9._-]+} $project - project
    set short [expr {[regexp {^[0-9a-f]{10,}$} $checkin] ? [string range $checkin 0 9] : $checkin}]
    if {![info exists archive(format)]} { set archive(format) zip }
    set archive(name) [string trim "$project-$short" -]
    set archive(include) ""
    set archive(exclude) ""
    set archive(count) ""
    set archive(repo) $repo
    set archive(checkin) $checkin
    set w [tagwrite::dialog .tagwrite "Save $label as an archive"]
    ttk::label $w.lf -text "Format:"
    ttk::frame $w.fmt
    foreach {v text} {zip "ZIP (.zip)" tarball "Tarball (.tar.gz)" sqlar "SQL archive (.sqlar)"} {
        ttk::radiobutton $w.fmt.$v -text $text -value $v -variable histops::archive(format)
        pack $w.fmt.$v -side left -padx {0 8}
    }
    ttk::label $w.ln -text "Top folder:"
    ttk::entry $w.name -textvariable histops::archive(name) -width 40
    ttk::label $w.li -text "Only files:"
    ttk::entry $w.include -textvariable histops::archive(include) -width 40
    ttk::label $w.lx -text "Except files:"
    ttk::entry $w.exclude -textvariable histops::archive(exclude) -width 40
    ttk::label $w.hint -foreground gray40 -text "Globs, comma-separated: generic/*,doc/*.n"
    ttk::label $w.count -textvariable histops::archive(count) -foreground gray40
    grid $w.lf $w.fmt -sticky w -pady 2
    grid $w.ln $w.name -sticky ew -pady 2
    grid $w.li $w.include -sticky ew -pady 2
    grid $w.lx $w.exclude -sticky ew -pady 2
    grid x $w.hint -sticky w
    grid x $w.count -sticky w -pady {6 0}
    grid columnconfigure $w 1 -weight 1
    foreach v {include exclude} {
        trace add variable ::histops::archive($v) write {after cancel histops::countFiles; after 300 histops::countFiles; list}
    }
    bind $w <Destroy> {
        foreach v {include exclude} { trace remove variable ::histops::archive($v) write {after cancel histops::countFiles; after 300 histops::countFiles; list} }
    }
    countFiles
    if {![tagwrite::wait .tagwrite "Save\u2026" histops::archiveProblem]} return
    set ext [dict get {zip .zip tarball .tar.gz sqlar .sqlar} $archive(format)]
    set file [tk_getSaveFile -title "Save the archive" -initialfile [string trim $archive(name)]$ext]
    if {$file eq ""} return
    . configure -cursor watch
    update idletasks
    lassign [fossil::run $archive(format) [fossil::arg $checkin] $file -R $repo {*}[archiveOpts]] code out
    . configure -cursor ""
    if {$code} {
        tk_messageBox -icon error -title Archive -message "fossil $archive(format) failed:" -detail $out
    } else {
        tk_messageBox -icon info -title Archive -message "Saved [file tail $file]" \
            -detail "[format %.1f [expr {[file size $file] / 1024.0}]] KB, in [file dirname $file]."
    }
}

proc histops::archiveOpts {} {
    variable archive
    set opts {}
    foreach {v opt} {name --name include --include exclude --exclude} {
        set value [string trim $archive($v)]
        # (As --option=VALUE: fossil.exe on Windows would expand a
        # pattern of its own word into the files it matches.)
        if {$value ne ""} { lappend opts $opt=[fossil::arg $value] }
    }
    return $opts
}

proc histops::archiveProblem {} {
    variable archive
    foreach v {name include exclude} {
        set value [string trim $archive($v)]
        if {$value ne "" && [catch {fossil::arg $value}]} {
            return "These fields cannot start with \"-\", \"<\", \">\" or \"|\"."
        }
    }
    return ""
}

# How many files the archive gets (zip --list into nothing).
proc histops::countFiles {} {
    variable archive
    if {![winfo exists .tagwrite]} return
    if {[archiveProblem] ne ""} { set archive(count) ""; return }
    lassign [fossil::run zip [fossil::arg $archive(checkin)] "" --list -R $archive(repo) \
        {*}[lmap o [archiveOpts] {set o}]] code out
    if {$code} {
        set archive(count) [string trim $out]
    } else {
        set n [llength [lmap l [split [string trim $out] \n] { if {[string trim $l] eq ""} continue; set l }]]
        set archive(count) "$n files"
    }
}

# ---------------------------------------------------------------- merge-base

# The common ancestor of A and B (hashes or names), the pivot a merge of B
# into A would use: "fossil merge-base" in a checkout (Fossil wants one),
# else the newest check-in that is an ancestor of both (through merges
# too, unless IGNORE).  Its hash, or "" with the reason in ERRVAR.
proc histops::mergeBase {repo root a b {ignore 0} {errVar ""}} {
    if {$errVar ne ""} { upvar 1 $errVar err }
    set err ""
    if {$root ne ""} {
        set opts [expr {$ignore ? "--ignore-merges" : ""}]
        lassign [run $repo $root merge-base {*}$opts [fossil::arg $a] [fossil::arg $b]] code out
        set out [string trim $out]
        if {!$code && [regexp {([0-9a-f]{40,64})} $out -> uuid]} { return $uuid }
        if {!$code && [regexp {^[0-9a-f]{4,}$} $out]} {
            return [lindex [fossil::sql $repo "SELECT uuid FROM blob WHERE uuid GLOB '$out*'"] 0 0]
        }
        set err $out
        return ""
    }
    set rids {}
    foreach name [list $a $b] {
        set rid [checkinRid $repo $name]
        if {$rid eq ""} { set err "$name: not a check-in here"; return "" }
        lappend rids $rid
    }
    lassign $rids ra rb
    set join [expr {$ignore ? "AND p.isprim" : ""}]
    set row [fossil::sql $repo "WITH RECURSIVE
        a(rid) AS (SELECT $ra UNION SELECT p.pid FROM plink p JOIN a ON p.cid=a.rid $join),
        b(rid) AS (SELECT $rb UNION SELECT p.pid FROM plink p JOIN b ON p.cid=b.rid $join)
        SELECT bl.uuid FROM a JOIN b USING(rid) JOIN event e ON e.objid=a.rid
        JOIN blob bl ON bl.rid=a.rid ORDER BY e.mtime DESC LIMIT 1"]
    if {![llength $row]} { set err "They have no common ancestor."; return "" }
    lindex $row 0 0
}

# The check-in a name is: a hash prefix, a branch or a tag (its newest).
proc histops::checkinRid {repo name} {
    set q [fossil::sqlstr $name]
    set row [fossil::sql $repo "SELECT x.rid FROM tagxref x JOIN event e ON e.objid=x.rid
        WHERE x.tagtype>0 AND e.type='ci' AND x.tagid=(SELECT tagid FROM tag WHERE tagname='sym-'||$q)
        ORDER BY e.mtime DESC LIMIT 1"]
    if {[llength $row]} { return [lindex $row 0 0] }
    if {[regexp {^[0-9a-fA-F]{4,64}$} $name]} {
        set rows [fossil::sql $repo "SELECT b.rid FROM blob b JOIN event e ON e.objid=b.rid
            AND e.type='ci' WHERE b.uuid GLOB [fossil::sqlstr [string tolower $name]*] LIMIT 2"]
        if {[llength $rows] == 1} { return [lindex $rows 0 0] }
    }
    return ""
}

# The common ancestor shown: its check-in, with going to it and diffs.
proc histops::showMergeBase {repo root a b {ignore 0}} {
    foreach name [list $a $b] { if {![fossil::argOk $name "Common ancestor"]} return }
    set uuid [mergeBase $repo $root $a $b $ignore err]
    if {$uuid eq ""} {
        tk_messageBox -icon info -title "Common ancestor" -message "No common ancestor of $a and $b." \
            -detail $err
        return
    }
    set row [lindex [fossil::sql $repo "SELECT strftime('%Y-%m-%d %H:%M', e.mtime),\
        [fossil::outcol "coalesce(e.euser,e.user,'')"], [fossil::outcol "coalesce(e.ecomment,e.comment,'')"]\
        FROM event e JOIN blob b ON b.rid=e.objid WHERE b.uuid=[fossil::sqlstr $uuid]"] 0]
    lassign $row date user comment
    set w [tagwrite::dialog .tagwrite "Common ancestor"]
    ttk::label $w.msg -justify left -wraplength 560 -text "The common ancestor of $a and $b\
        (the pivot of a merge of one into the other):\n\n[string range $uuid 0 15]  $date  $user\n[fossil::oneLine $comment]"
    pack $w.msg -anchor w
    # (Along the first parents only: the branch lines, not their merges.)
    variable ignoreMerges $ignore
    ttk::checkbutton $w.ignore -text "Ignore merges (--ignore-merges)" -variable histops::ignoreMerges \
        -command [list ::apply {{repo root a b} {
            after idle [list histops::showMergeBase $repo $root $a $b $::histops::ignoreMerges]
        }} $repo $root $a $b]
    pack $w.ignore -anchor w -pady {6 0}
    foreach {b2 text cmd} [list \
            show "Show in Timeline" [list goto::checkin $uuid] \
            diffa "Diff to $a" [list diffview::run "[string range $uuid 0 9] \u2192 $a" -- -R $repo --from $uuid --to [fossil::arg $a]] \
            diffb "Diff to $b" [list diffview::run "[string range $uuid 0 9] \u2192 $b" -- -R $repo --from $uuid --to [fossil::arg $b]]] {
        ttk::button .tagwrite.b.$b2 -text $text -command "[list destroy .tagwrite]; $cmd"
        pack .tagwrite.b.$b2 -side left -padx {0 4}
    }
    ttk::button .tagwrite.b.close -text Close -command {destroy .tagwrite}
    pack .tagwrite.b.close -side right
    bind .tagwrite <Escape> {destroy .tagwrite}
    wm protocol .tagwrite WM_DELETE_WINDOW {destroy .tagwrite}
}

# ---------------------------------------------------------------- publish

# Make private check-ins public (fossil publish): WHAT a branch (all its
# check-ins) or a check-in.  Nothing is pushed: they go out at the next
# push or sync of the repository.  DONE when done.
proc histops::publish {repo what label {done ""}} {
    if {![fossil::argOk $what "Make public"]} { return 0 }
    # The dry run (--test): what would become public.
    lassign [fossil::run publish --test [fossil::arg $what] -R $repo] code out
    if {$code} {
        tk_messageBox -icon error -title "Make public" -message "fossil publish failed (dry run):" -detail $out
        return 0
    }
    if {![tagwrite::confirm "Make public" "Make $label public?  The private check-ins (and their\
            files and tags) become public in [file tail $repo]; they go to the server with the\
            next push or sync.  This cannot be undone (except by purging them)." \
            "fossil publish [string range $what 0 39]\n\nDry run (what becomes public):\n$out" \
            -note "Nothing is pushed now."]} { return 0 }
    lassign [fossil::run publish [fossil::arg $what] -R $repo] code out
    if {$code} {
        tk_messageBox -icon error -title "Make public" -message "fossil publish failed:" -detail $out
        return 0
    }
    if {$done ne ""} { uplevel #0 $done }
    return 1
}

# ---------------------------------------------------------------- bundles

# Export check-ins as a bundle file (fossil bundle export): a branch, the
# check-ins between two, or one check-in; self-contained or not.  The
# repository is not changed.
proc histops::exportBundle {repo {branch ""}} {
    variable bundle
    set bundle(how) [expr {$branch ne "" ? "branch" : "checkin"}]
    set bundle(branch) $branch
    set bundle(from) ""
    set bundle(to) ""
    set bundle(checkin) ""
    set bundle(standalone) 0
    set w [tagwrite::dialog .tagwrite "Export a bundle"]
    ttk::label $w.l -text "Check-ins to put in the bundle (it can be imported into another\
        repository with Import bundle):" -wraplength 520 -justify left
    ttk::radiobutton $w.rb -text "The branch:" -value branch -variable histops::bundle(how)
    ttk::entry $w.branch -textvariable histops::bundle(branch) -width 30
    ttk::radiobutton $w.rr -text "From:" -value range -variable histops::bundle(how)
    ttk::frame $w.range
    ttk::entry $w.range.from -textvariable histops::bundle(from) -width 20
    ttk::label $w.range.l -text " to: "
    ttk::entry $w.range.to -textvariable histops::bundle(to) -width 20
    pack $w.range.from $w.range.l $w.range.to -side left
    ttk::radiobutton $w.rc -text "The check-in:" -value checkin -variable histops::bundle(how)
    ttk::entry $w.checkin -textvariable histops::bundle(checkin) -width 30
    ttk::checkbutton $w.sa -variable histops::bundle(standalone) \
        -text "Self-contained (no deltas against artifacts not in it; larger)"
    grid $w.l - -sticky w -pady {0 6}
    grid $w.rb $w.branch -sticky w -pady 2
    grid $w.rr $w.range -sticky w -pady 2
    grid $w.rc $w.checkin -sticky w -pady 2
    grid $w.sa - -sticky w -pady {6 0}
    if {![tagwrite::wait .tagwrite "Save\u2026" histops::bundleProblem]} return
    set name [expr {$bundle(how) eq "branch" ? $bundle(branch) : "bundle"}]
    set file [tk_getSaveFile -title "Save the bundle" -initialfile [regsub -all {[^A-Za-z0-9._-]} $name -].bundle]
    if {$file eq ""} return
    # (A bundle file that exists is added to: replaced instead, as asked.)
    file delete $file
    set opts [switch -- $bundle(how) {
        branch  { list --branch [fossil::arg $bundle(branch)] }
        range   { list --from [fossil::arg $bundle(from)] --to [fossil::arg $bundle(to)] }
        checkin { list --checkin [fossil::arg $bundle(checkin)] }
    }]
    if {$bundle(standalone)} { lappend opts --standalone }
    lassign [fossil::run bundle export $file {*}$opts -R $repo] code out
    if {$code || ![file exists $file]} {
        tk_messageBox -icon error -title "Export a bundle" -message "fossil bundle export failed:" -detail $out
        return
    }
    lassign [fossil::run bundle ls $file -R $repo] code list
    set n [artifactCount $list]
    tk_messageBox -icon info -title "Export a bundle" -message "Saved [file tail $file]" \
        -detail "$n artifacts, [format %.1f [expr {[file size $file] / 1024.0}]] KB."
}

# How many artifacts a listing of fossil has ("HASH what" lines; not the
# header of "bundle ls": mtime, project-code, dashes).
proc histops::artifactCount {text} {
    llength [regexp -all -inline -line {^\s*[0-9a-f]{8,}\s} $text]
}

proc histops::bundleProblem {} {
    variable bundle
    set fields [dict get {branch branch range {from to} checkin checkin} $bundle(how)]
    foreach v $fields {
        set value [string trim $bundle($v)]
        if {$value eq ""} { return "Fill in the [dict get {branch branch from From to To checkin check-in} $v]." }
        if {[catch {fossil::arg $value}]} { return "$value: not a name of a check-in or branch." }
    }
    return ""
}

# A bundle file to work with: its contents (fossil bundle ls), or "".
proc histops::chooseBundle {repo title} {
    set file [tk_getOpenFile -title $title -filetypes {{Bundles .bundle} {All *}}]
    if {$file eq ""} { return "" }
    lassign [fossil::run bundle ls $file -R $repo] code out
    if {$code} {
        tk_messageBox -icon error -title $title -message "Not a bundle: [file tail $file]" -detail $out
        return ""
    }
    list $file $out
}

# Import a bundle (fossil bundle import): its check-ins private, unless
# made public too; after showing what it has.  DONE when done.
proc histops::importBundle {repo {done ""}} {
    variable bundle
    lassign [chooseBundle $repo "Import a bundle"] file list
    if {$file eq ""} return
    set bundle(publish) 0
    set bundle(force) 0
    set w [tagwrite::dialog .tagwrite "Import [file tail $file]"]
    ttk::label $w.msg -justify left -wraplength 600 -text "Import these artifacts into\
        [file tail $repo]?  They come in private (they do not go to the server) unless made\
        public.  Remove an imported bundle undoes it."
    text $w.t -width 90 -height 14 -font TkFixedFont -wrap none -yscrollcommand [list $w.y set]
    ttk::scrollbar $w.y -command [list $w.t yview]
    $w.t insert end [string trim $list]
    $w.t configure -state disabled
    ttk::checkbutton $w.pub -text "Make them public too (--publish): they go out with the next push" \
        -variable histops::bundle(publish)
    ttk::checkbutton $w.force -variable histops::bundle(force) -text "Even from another project\
        (--force): its check-ins then mix with this project's, which is rarely wanted"
    grid $w.msg - -sticky w -pady {0 6}
    grid $w.t $w.y -sticky news
    grid $w.pub - -sticky w -pady {6 0}
    grid $w.force - -sticky w
    grid columnconfigure $w 0 -weight 1
    grid rowconfigure $w 1 -weight 1
    if {![tagwrite::wait .tagwrite Import]} return
    set opts {}
    if {$bundle(publish)} { lappend opts --publish }
    if {$bundle(force)} {
        if {![ui::confirm -icon warning -title "Import a bundle" \
                "Import a bundle of another project?" "Its check-ins come into\
                [file tail $repo] although they belong to another project.  Remove an imported\
                bundle takes them out again."]} return
        lappend opts --force
    }
    lassign [fossil::run bundle import $file {*}$opts -R $repo] code out
    if {$code} {
        tk_messageBox -icon error -title "Import a bundle" -message "fossil bundle import failed:" -detail $out
        return
    }
    if {$done ne ""} { uplevel #0 $done }
    tk_messageBox -icon info -title "Import a bundle" -message "Imported [file tail $file]." -detail [string trim $out]
}

# Remove what a bundle brought (fossil bundle purge), after its dry run
# (--test: what would go).  Not into the graveyard: importing the bundle
# again undoes it (it has them all).
proc histops::purgeBundle {repo {done ""}} {
    lassign [chooseBundle $repo "Remove an imported bundle"] file list
    if {$file eq ""} return
    lassign [fossil::run bundle purge $file --test -R $repo] code out
    if {$code} {
        tk_messageBox -icon error -title "Remove an imported bundle" \
            -message "fossil bundle purge failed (dry run):" -detail $out
        return
    }
    if {![tagwrite::confirm "Remove an imported bundle" "Remove from [file tail $repo] what\
            [file tail $file] brought ([artifactCount $list] artifacts in it)?  They do not go to the\
            purge graveyard: importing the bundle again brings them back, so keep the file." \
            "fossil bundle purge [file tail $file]\n\nDry run:\n$out"]} return
    lassign [fossil::run bundle purge $file -R $repo] code out
    if {$code} {
        tk_messageBox -icon error -title "Remove an imported bundle" -message "fossil bundle purge failed:" -detail $out
        return
    }
    if {$done ne ""} { uplevel #0 $done }
    tk_messageBox -icon info -title "Remove an imported bundle" -message "Removed." -detail [string trim $out]
}

# ---------------------------------------------------------------- purge

# Purge check-ins (fossil purge checkins: WHAT and its descendants; a
# branch: its check-ins) into the graveyard, after the dry run
# (--explain).  Purge graveyard brings them back, until obliterated.
# (In the checkout ROOT: fossil purge checkins needs one, to keep its
# check-in.)
proc histops::purgeCheckins {repo root what label {done ""}} {
    if {$root eq ""} {
        tk_messageBox -icon info -title Purge -message "Purging check-ins needs a checkout." \
            -detail "fossil purge checkins works only in a checkout of the repository."
        return 0
    }
    if {![fossil::argOk $what Purge]} { return 0 }
    lassign [run $repo $root purge checkins [fossil::arg $what] --explain] code out
    if {$code} {
        tk_messageBox -icon error -title Purge -message "fossil purge failed (dry run):" -detail $out
        return 0
    }
    if {![tagwrite::confirm Purge "Purge $label and its descendants from [file tail $repo]?\
            They leave the history: the timeline, branches, tags.  They go to the graveyard,\
            from where Purge graveyard can bring them back, until obliterated.  Fossil warns that\
            purging can leave a repository in an odd state: make a backup first if in doubt." \
            "fossil purge checkins $what\n\nDry run (what would go):\n$out" \
            -note "Only the local repository is changed: nothing is pushed, and check-ins\
                pushed before stay on the server."]} { return 0 }
    lassign [run $repo $root purge checkins [fossil::arg $what]] code out
    if {$code} {
        tk_messageBox -icon error -title Purge -message "fossil purge failed:" -detail $out
        return 0
    }
    if {$done ne ""} { uplevel #0 $done }
    tk_messageBox -icon info -title Purge -message "Purged." -detail [string trim $out]
    return 1
}

# The graveyard of the purges (fossil purge list -l): each purge with its
# artifacts; Undo one (purge undo), Obliterate one (purge obliterate: its
# artifacts are then gone for good).  DONE after a change.
proc histops::graveyard {repo {done ""}} {
    set w .graveyard
    destroy $w
    toplevel $w
    wm title $w "Purge graveyard \u2014 [file rootname [file tail $repo]]"
    ttk::frame $w.f -padding 8
    pack $w.f -fill both -expand 1
    ttk::label $w.f.l -wraplength 600 -justify left -text "What was purged from the repository,\
        newest first.  Undo brings a purge back; Obliterate removes it for good."
    ttk::treeview $w.f.t -columns {what size} -show {tree headings} -selectmode browse \
        -yscrollcommand [list $w.f.y set]
    ttk::scrollbar $w.f.y -command [list $w.f.t yview]
    $w.f.t heading #0 -text Purge -anchor w
    $w.f.t heading what -text Artifact -anchor w
    $w.f.t heading size -text Size -anchor e
    $w.f.t column #0 -width 220 -stretch 0
    $w.f.t column what -width 420
    $w.f.t column size -width 80 -anchor e -stretch 0
    ttk::frame $w.f.b
    ttk::button $w.f.b.undo -text "Undo\u2026" -command [list histops::graveUndo $repo $done]
    ttk::button $w.f.b.obl -text "Obliterate\u2026" -command [list histops::graveObliterate $repo]
    ttk::button $w.f.b.close -text Close -command [list destroy $w]
    pack $w.f.b.undo $w.f.b.obl -side left -padx {0 4}
    pack $w.f.b.close -side right
    grid $w.f.l - -sticky w -pady {0 6}
    grid $w.f.t $w.f.y -sticky news
    grid $w.f.b - -sticky ew -pady {6 0}
    grid columnconfigure $w.f 0 -weight 1
    grid rowconfigure $w.f 1 -weight 1
    bind $w <Escape> [list destroy $w]
    wm geometry $w 760x420
    graveFill $repo
}

proc histops::graveFill {repo} {
    set t .graveyard.f.t
    $t delete [$t children {}]
    lassign [fossil::run purge list -l -R $repo] code out
    if {$code} {
        $t insert {} end -id none -text "fossil purge list failed" -values [list [string trim $out] ""]
        set out ""
    }
    set event ""
    foreach line [split $out \n] {
        if {[regexp {^\s*(\d+) on (.*)$} $line -> id date]} {
            set event p$id
            $t insert {} 0 -id $event -text "$id  [string trim $date]" -open 0
        } elseif {$event ne "" && [regexp {^\s+\d+\s+([0-9a-f]+)\s+(\d+)\s+(.*)$} $line -> hash size what]} {
            $t insert $event end -text "" -values [list "$hash  [string trim $what]" $size]
        }
    }
    set empty [expr {![llength [lsearch -all -inline -glob [$t children {}] p*]]}]
    if {$empty && ![$t exists none]} { $t insert {} end -id none -text "(empty)" }
    foreach b {undo obl} { .graveyard.f.b.$b state [expr {$empty ? "disabled" : "!disabled"}] }
    if {!$empty} { $t selection set [list [lindex [$t children {}] 0]] }
}

# The purge selected (or of the artifact selected): its number, or "".
proc histops::graveSelected {} {
    set t .graveyard.f.t
    set i [lindex [$t selection] 0]
    if {$i ne "" && [$t parent $i] ne ""} { set i [$t parent $i] }
    if {![regexp {^p(\d+)$} $i -> id]} { return "" }
    return $id
}

proc histops::graveUndo {repo done} {
    set id [graveSelected]
    if {$id eq ""} return
    if {![ui::confirm -parent .graveyard \
            -title "Purge graveyard" "Bring purge $id back into [file tail $repo]?" \
            "fossil purge undo $id: its artifacts come back.  Only the local repository\
                changes; nothing is pushed."]} return
    lassign [fossil::run purge undo $id -R $repo] code out
    if {$code} {
        tk_messageBox -parent .graveyard -icon error -title "Purge graveyard" \
            -message "fossil purge undo failed:" -detail $out
    } elseif {$done ne ""} {
        uplevel #0 $done
    }
    graveFill $repo
}

proc histops::graveObliterate {repo} {
    set id [graveSelected]
    if {$id eq ""} return
    if {![ui::confirm -parent .graveyard -icon warning \
            -title "Purge graveyard" "Obliterate purge $id?" \
            "fossil purge obliterate $id: its artifacts are removed for good, and the\
                purge cannot be undone any more.  This cannot be undone."]} return
    lassign [fossil::run purge obliterate $id --force -R $repo] code out
    if {$code} {
        tk_messageBox -parent .graveyard -icon error -title "Purge graveyard" \
            -message "fossil purge obliterate failed:" -detail $out
    }
    graveFill $repo
}

# ---------------------------------------------------------------- checkout --keep

# Switch the checkout (ROOT) to TARGET without changing its files (fossil
# checkout --keep): the checkout is then at TARGET, and where the files
# differ from it they are changes.  Fossil has no dry run for this.
proc histops::switchKeep {repo root target label {done ""}} {
    if {$root eq "" || ![fossil::argOk $target "Switch without merging"]} { return 0 }
    lassign [run $repo $root changes] code changes
    if {$code} { set changes "" }
    set detail "fossil checkout --keep: the files of the checkout stay as they are; only the\
        version it is at changes.  Where they differ from $label, they show as changes, which a\
        commit would record.  Fossil has no dry run for this, and Undo does not take it back\
        (switch back the same way to the version before)."
    if {[string trim $changes] ne ""} {
        append detail "\n\nThe checkout has uncommitted changes: they stay (--force)."
    }
    if {![ui::confirm -icon warning -title "Switch without merging" \
            "Switch the checkout to $label without changing its files?" $detail]} {
        return 0
    }
    set opts [list --keep]
    if {[string trim $changes] ne ""} { lappend opts --force }
    lassign [run $repo $root checkout {*}$opts [fossil::arg $target]] code out
    if {$code} {
        tk_messageBox -icon error -title "Switch without merging" -message "fossil checkout failed:" -detail $out
        return 0
    }
    if {$done ne ""} { uplevel #0 $done }
    return 1
}

# ---------------------------------------------------------------- describe

# A check-in (RID) described from the nearest tag before it, as "fossil
# describe" does (also without a checkout): TAG if it is on the check-in,
# else TAG-N-HASH, N check-ins after it along the first parents; only tags
# on a single check-in, matching MATCH.  "" if none.
proc histops::describe {repo rid {match *}} {
    variable describeCache
    set key $repo,$rid,$match
    if {[dict exists $describeCache $key]} { return [dict get $describeCache $key] }
    set m [fossil::sqlstr $match]
    set row [lindex [fossil::sql $repo "WITH RECURSIVE
        single(rid, tagname) AS MATERIALIZED (
            SELECT min(x.rid), substr(t.tagname,5) FROM tag t JOIN tagxref x ON x.tagid=t.tagid
            WHERE x.tagtype=1 AND t.tagname GLOB 'sym-'||$m GROUP BY t.tagname HAVING count(*)=1),
        anc(rid, mtime, tagname, n) AS (
            SELECT e.objid, e.mtime, s.tagname, 0 FROM event e LEFT JOIN single s ON s.rid=e.objid
            WHERE e.objid=$rid
            UNION ALL
            SELECT p.pid, e.mtime, s.tagname, anc.n+1 FROM anc JOIN plink p ON p.cid=anc.rid AND p.isprim
            JOIN event e ON e.objid=p.pid LEFT JOIN single s ON s.rid=p.pid
            WHERE anc.tagname IS NULL ORDER BY 2 DESC LIMIT 100000)
        SELECT [fossil::outcol tagname], n, (SELECT uuid FROM blob WHERE rid=$rid)
        FROM anc WHERE tagname IS NOT NULL ORDER BY n LIMIT 1"] 0]
    set text ""
    if {$row ne ""} {
        lassign $row tag n uuid
        set text [expr {$n == 0 ? $tag : "$tag-$n-[string range $uuid 0 [hashDigits $repo]-1]"}]
    }
    dict set describeCache $key $text
    return $text
}

# How many digits of a hash Fossil shows (the hash-digits setting, 6 to 64;
# 10 if not set), as describe uses.
proc histops::hashDigits {repo} {
    variable digits
    if {![dict exists $digits $repo]} {
        lassign [fossil::run settings hash-digits --value -R $repo] code out
        set n [string trim $out]
        if {$code || ![string is integer -strict $n]} { set n 10 }
        dict set digits $repo [expr {max(6, min(64, $n))}]
    }
    dict get $digits $repo
}
