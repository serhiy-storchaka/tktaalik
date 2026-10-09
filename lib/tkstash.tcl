# The Stash tab of tktaalik: the stashes of the checkout.
#
# Lists them with the check-in they were made on, searches them, shows
# their files and diffs, and applies, pops, drops them or goes to them
# ("fossil stash"), after a confirmation.  "Stash changes" saves the
# checkout's changes and reverts them.  All of this is local to the
# checkout: stashes are never synced.  Settings are kept in
# ~/.config/tktaalik/stash.conf.

source [file join [file dirname [file normalize [info script]]] config.tcl]
source [file join [file dirname [file normalize [info script]]] fossil.tcl]
source [file join [file dirname [file normalize [info script]]] tablecols.tcl]
source [file join [file dirname [file normalize [info script]]] searchterms.tcl]
source [file join [file dirname [file normalize [info script]]] diffopts.tcl]

namespace eval tkstash {
    variable searched ""        ;# the query of the list shown
    variable repo ""
    variable root ""            ;# the checkout, or ""
    variable current ""         ;# the check-in the checkout is on
    variable stashes            ;# array: id -> dict of the stash
    variable diffs              ;# array: id -> dict file -> changed lines (lower case)
    variable query ""
    variable history {}
    variable terms {}           ;# the parsed search: {neg key alternatives}...
    variable status ""
    variable message ""         ;# of a new stash
    variable snapshot 0         ;# a new stash keeps the changes in the checkout
    variable saveSkip           ;# array: file -> 1 if not to be stashed
    variable config {}
    variable configFile [config::path stash]

}

# ------------------------------------------------------------- settings

proc tkstash::loadConfig {} {
    variable configFile
    variable config
    set config [config::get $configFile stash tkstash.conf]
}

proc tkstash::saveConfig {} {
    variable configFile
    variable config
    variable query
    variable history
    dict set config table [tablecols::state .stash.main.list.t]
    dict set config query $query
    dict set config history $history
    config::put $configFile $config {table return}
}

proc tkstash::getdef {dict key default} {
    expr {[dict exists $dict $key] ? [dict get $dict $key] : $default}
}

# ----------------------------------------------------------------- data

# Run fossil in the checkout.
proc tkstash::fossil {args} {
    variable root
    fossil::run -dir $root {*}$args
}

# Read the stashes and their files, then show the ones that match.
proc tkstash::reload {} {
    variable root
    variable repo
    variable stashes
    variable diffs
    variable status
    variable current
    if {$root eq ""} return
    try {
        set rows [fossil::checkoutSql $root "SELECT stashid, datetime(ctime), hash,
            [fossil::outcol coalesce(comment,'')] FROM stash ORDER BY stashid DESC"]
        set fileRows [fossil::checkoutSql $root "SELECT stashid, [fossil::outcol newname],
            [fossil::outcol coalesce(origname,newname)], isAdded, isRemoved
            FROM stashfile ORDER BY newname"]
        set current [lindex [fossil::checkoutSql $root "SELECT uuid FROM blob
            WHERE rid=(SELECT value FROM vvar WHERE name='checkout')"] 0 0]
    } trap {FOSSIL DB} msg {
        set status "Cannot read the stashes: $msg"
        return
    }
    set filesOf {}
    foreach row $fileRows {
        lassign $row id new old added removed
        dict lappend filesOf $id [dict create new $new old $old \
            how [expr {$added ? "added" : $removed ? "deleted" : $old ne $new ? "renamed" : "changed"}]]
    }
    # The branches of the check-ins they were made on.
    set hashes [lsort -unique [lmap row $rows { lindex $row 2 }]]
    set branchOf {}
    if {[llength $hashes]} {
        foreach row [fossil::sql $repo "SELECT b.uuid, [fossil::outcol x.value] FROM blob b
                JOIN tagxref x ON x.rid=b.rid AND x.tagtype>0
                AND x.tagid=(SELECT tagid FROM tag WHERE tagname='branch')
                WHERE b.uuid IN ([join [lmap h $hashes { fossil::sqlstr $h }] ,])"] {
            dict set branchOf {*}$row
        }
    }
    array unset stashes
    array unset diffs
    foreach row $rows {
        lassign $row id date hash comment
        set branch [expr {[dict exists $branchOf $hash] ? [dict get $branchOf $hash] : ""}]
        # The files it changes.  Fossil can record every file of the
        # checkout in a stash (after "fossil mv"), most of them unchanged:
        # a file counts if it is added, deleted or renamed, or if its diff
        # has changed lines.
        set diff [stashDiff $id]
        set files [lmap f [expr {[dict exists $filesOf $id] ? [dict get $filesOf $id] : {}}] {
            set new [dict get $f new]
            if {[dict get $f how] eq "changed"
                    && (![dict exists $diff $new] || [dict get $diff $new] eq "")} continue
            set f
        }]
        set stashes($id) [dict create id $id date $date hash $hash comment $comment \
            branch $branch files $files lcomment [string tolower $comment]]
    }
    search
}

# The changed lines of a stash, file by file, in lower case: for diff:.
proc tkstash::stashDiff {id} {
    variable diffs
    if {![info exists diffs($id)]} {
        lassign [fossil stash show $id -i] code out
        set result {}
        if {!$code} {
            foreach f [diffview::parse $out] {
                lassign $f name header lines
                set changed [lmap line $lines {
                    if {![regexp {^[-+]} $line] || [regexp {^(\+\+\+|---) } $line]} continue
                    string range $line 1 end
                }]
                dict set result $name [string tolower [join $changed \n]]
            }
        }
        set diffs($id) $result
    }
    return $diffs($id)
}

# ----------------------------------------------------------------- search

proc tkstash::parseQuery {query} {
    set terms {}
    foreach token [terms::tokenize $query] {
        lassign $token neg key value
        if {$key ne "" && $value eq ""} { terms::error "empty value for $key:" }
        if {$key eq ""} {
            lappend terms [list $neg "" [list [string tolower $value]]]
            continue
        }
        set alts [lmap a [split $value ,] {
            set a [string trim $a]
            if {$a eq ""} continue
            set a
        }]
        if {![llength $alts]} { terms::error "empty value for $key:" }
        switch -- $key {
            comment - file - added - deleted - renamed - diff - branch {
                set alts [lmap a $alts { string tolower $a }]
            }
            on {
                set alts [lmap a $alts {
                    set a [string tolower $a]
                    if {![regexp {^[0-9a-f]{4,64}$} $a]} { terms::error "on:$a: not a check-in hash" }
                    set a
                }]
            }
            date  { set alts [lmap a $alts { terms::dateSpec $a }] }
            files { set alts [lmap a $alts { terms::numberSpec $a }] }
            is {
                foreach a $alts {
                    if {[string tolower $a] ne "current"} { terms::error "is:$a: use is:current" }
                }
                set alts current
            }
            default { terms::error "unknown key \"$key:\"; see Help" }
        }
        lappend terms [list $neg $key $alts]
    }
    return $terms
}

# A name matches a part or a glob pattern.
proc tkstash::nameMatches {pattern name} {
    set name [string tolower $name]
    if {[terms::isGlob $pattern]} { return [string match $pattern $name] }
    expr {[string first $pattern $name] >= 0}
}

# The files of stash $s that term {key alt} matches.
proc tkstash::filesMatching {s key a} {
    set result {}
    foreach f [dict get $s files] {
        set how [dict get $f how]
        set names [lsort -unique [list [dict get $f new] [dict get $f old]]]
        set ok 0
        switch -- $key {
            "" - file { set ok 1 }
            added     { set ok [expr {$how eq "added"}] }
            deleted   { set ok [expr {$how eq "deleted"}] }
            renamed   { set ok [expr {$how eq "renamed"}] }
        }
        if {!$ok} continue
        foreach n $names {
            if {[nameMatches $a $n]} { lappend result [dict get $f new]; break }
        }
    }
    return $result
}

# Does the alternative match?  Sets ::tkstash::hits (the files it matched).
proc tkstash::altMatches {s key a} {
    variable current
    variable hits
    set hits {}
    switch -- $key {
        "" {
            if {![terms::isGlob $a] && [string first $a [dict get $s lcomment]] >= 0} { return 1 }
            set hits [filesMatching $s "" $a]
            return [llength $hits]
        }
        comment { expr {[string first $a [dict get $s lcomment]] >= 0} }
        file - added - deleted - renamed {
            set hits [filesMatching $s $key $a]
            llength $hits
        }
        diff {
            dict for {name text} [stashDiff [dict get $s id]] {
                if {[string first $a $text] >= 0} { lappend hits $name }
            }
            llength $hits
        }
        branch {
            expr {[dict get $s branch] ne "" && ([terms::isGlob $a]
                ? [string match $a [string tolower [dict get $s branch]]]
                : $a eq [string tolower [dict get $s branch]])}
        }
        on   { string match $a* [dict get $s hash] }
        date {
            lassign $a lo hi
            set day [string range [dict get $s date] 0 9]
            expr {($lo eq "" || [string compare $day $lo] >= 0)
                && ($hi eq "" || [string compare $day $hi] < 0)}
        }
        files {
            lassign $a lo hi
            set n [llength [dict get $s files]]
            expr {($lo eq "" || $n >= $lo) && ($hi eq "" || $n <= $hi)}
        }
        is { expr {[dict get $s hash] eq $current} }
    }
}

# Does stash $s match the search?  Returns {1 files-that-matched} or {0 {}}.
proc tkstash::matches {s} {
    variable terms
    variable hits
    set matched {}
    foreach term $terms {
        lassign $term neg key alts
        set ok 0
        foreach a $alts {
            if {[altMatches $s $key $a]} {
                set ok 1
                if {!$neg} { lappend matched {*}$hits }
                break
            }
        }
        if {$ok == $neg} { return {0 {}} }
    }
    list 1 [lsort -unique $matched]
}

proc tkstash::search {{remember 0}} {
    variable query
    variable searched
    set searched $query
    variable terms
    variable history
    after cancel {tkstash::search}
    try {
        set terms [parseQuery $query]
    } trap {TKFOSSIL QUERY} msg {
        showError $msg
        return
    }
    set q [string trim $query]
    if {$remember && $q ne ""} {
        set history [lrange [linsert [lsearch -all -inline -not -exact $history $q] 0 $q] 0 19]
        .stash.top.q configure -values $history
    }
    showList
}

proc tkstash::showError {msg} {
    variable status
    set status "Search: $msg"
    .stash.status configure -foreground red3
}

proc tkstash::showList {} {
    variable stashes
    variable status
    variable root
    variable matchedFiles
    array unset matchedFiles
    set items {}
    foreach id [array names stashes] {
        set s $stashes($id)
        lassign [matches $s] ok files
        if {!$ok} continue
        set matchedFiles($id) $files
        lappend items [list $id [dict create id $id date [dict get $s date] \
            base "[string range [dict get $s hash] 0 9] [dict get $s branch]" \
            files [llength [dict get $s files]] \
            comment [string map {\n " "} [dict get $s comment]]] {} \
            [expr {[llength $files] ? "hit" : ""}]]
    }
    set t .stash.main.list.t
    set keep [$t selection]
    tablecols::fill $t $items
    set keep [lmap id $keep { if {![$t exists $id]} continue; set id }]
    if {![llength $keep]} { set keep [lrange [$t children {}] 0 0] }
    if {[llength $keep]} {
        $t selection set $keep
        $t focus [lindex $keep 0]
        $t see [lindex $keep 0]
        showDetails [lindex $keep 0]
    } else {
        showDetails ""
    }
    set n [array size stashes]
    set shown [llength $items]
    set status [expr {$shown == $n ? "$n stash[expr {$n == 1 ? "" : "es"}]"
        : "$shown of $n stashes"}]
    append status "  \u00b7  checkout $root"
    .stash.status configure -foreground ""
}

# ---------------------------------------------------------------- details

proc tkstash::showDetails {id} {
    variable stashes
    variable current
    variable matchedFiles
    set d .stash.main.details.text
    $d configure -state normal
    $d delete 1.0 end
    if {$id eq "" || ![info exists stashes($id)]} {
        $d configure -state disabled
        return
    }
    set s $stashes($id)
    $d insert end "Stash $id  " title "[dict get $s date]  \u00b7  on [string range [dict get $s hash] 0 9]" meta
    if {[dict get $s branch] ne ""} { $d insert end " ([dict get $s branch])" meta }
    if {[dict get $s hash] eq $current} { $d insert end "  \u00b7  the check-in of the checkout" meta }
    $d insert end \n\n "" [dict get $s comment] comment \n\n ""
    set hits [expr {[info exists matchedFiles($id)] ? $matchedFiles($id) : {}}]
    foreach f [dict get $s files] {
        set how [dict get $f how]
        set new [dict get $f new]
        set tags [list $how]
        set nameTags [expr {$new in $hits ? "hit" : ""}]
        $d insert end [format "%-8s " $how] $tags $new $nameTags
        if {$how eq "renamed"} { $d insert end " (was [dict get $f old])" meta }
        $d insert end \n
    }
    $d configure -state disabled
}

proc tkstash::selected {} {
    lindex [.stash.main.list.t selection] 0
}

# The diff, at the first file the search matched.
proc tkstash::showDiff {{against ""}} {
    variable root
    variable matchedFiles
    set id [selected]
    if {$id eq ""} return
    set first [expr {[info exists matchedFiles($id)] ? [lindex $matchedFiles($id) 0] : ""}]
    if {$against eq ""} {
        diffview::run "Stash $id" -dir $root -command {fossil stash show} -select $first \
            -- $id -i {*}[diffopts::args]
    } else {
        diffview::run "Stash $id against the checkout" -dir $root \
            -command {fossil stash diff} -select $first -- $id -i {*}[diffopts::args]
    }
}

# ---------------------------------------------------------------- actions

proc tkstash::changes {} {
    lassign [fossil changes] code out
    expr {$code ? "" : [string trim $out]}
}

proc tkstash::confirm {title message detail} {
    ui::confirm -title $title $message $detail
}

proc tkstash::done {id what code out} {
    reload
    if {$code} {
        tk_messageBox -icon error -title Stash -message "fossil stash failed:" -detail $out
    } elseif {[ui::ask -title Stash \
            "$what stash $id." "[string trim $out]\n\nShow the Commit tab?"]} {
        tktaalik::show commit
    }
}

# Apply the selected stash; with $drop also drop it.
proc tkstash::applyStash {{drop 0}} {
    set id [selected]
    if {$id eq ""} return
    set what [expr {$drop ? "Apply and drop" : "Apply"}]
    set detail "Its changes are merged into the files of the checkout."
    if {[changes] ne ""} {
        append detail "  The checkout has uncommitted changes: they can conflict."
    }
    if {$drop} {
        append detail "  The stash is then deleted.  (Undo afterwards brings back the\
            stash, not the files as they were: to be able to undo the apply, apply first and\
            drop later.)"
    }
    if {![confirm "Stash" "$what stash $id?" $detail]} return
    lassign [fossil stash apply $id] code out
    if {!$code && $drop} {
        lassign [fossil stash drop $id] code2 out2
        append out \n$out2
        set code $code2
    }
    done $id [expr {$drop ? "Applied and dropped" : "Applied"}] $code $out
}

# Update to the check-in the stash was made on, and apply it there.
proc tkstash::goto {} {
    variable stashes
    variable current
    variable repo
    set id [selected]
    if {$id eq "" || ![info exists stashes($id)]} return
    set s $stashes($id)
    set hash [dict get $s hash]
    set on "[string range $hash 0 9][expr {[dict get $s branch] ne "" ? " on [dict get $s branch]" : ""}]"
    set here [lindex [fossil::sql $repo "SELECT coalesce((SELECT value FROM tagxref
        WHERE rid=(SELECT rid FROM blob WHERE uuid=[fossil::sqlstr $current]) AND tagtype>0
        AND tagid=(SELECT tagid FROM tag WHERE tagname='branch')),'')"] 0 0]
    if {[changes] ne ""} {
        tk_messageBox -icon info -title Stash -message "The checkout has uncommitted changes." \
            -detail "Go to needs a checkout without them, so that Go back can return to it\
                exactly: stash them (Stash changes) or commit them first."
        return
    }
    if {$hash eq $current} {
        set detail "The checkout is already on $on: this is the same as Apply."
    } else {
        set detail "The checkout moves from [string range $current 0 9][expr {$here ne "" ? " on $here" : ""}]\
            to $on, where the stash was made; then the stash is applied there,\
            exactly.  Commits then go to that check-in.\n\nGo back returns to\
            [string range $current 0 9]."
    }
    append detail "\n\nThe stash is kept."
    if {![confirm "Stash" "Go to the check-in of stash $id and apply it?" $detail]} return
    if {$hash ne $current} { setReturn [list $current $here] }
    lassign [fossil stash goto $id] code out
    done $id "Went to the check-in of" $code $out
}

# Where Go back returns to (per checkout, kept over restarts): {hash branch}.
proc tkstash::returnTo {} {
    variable config
    variable root
    if {[dict exists $config return $root]} { return [dict get $config return $root] }
    return ""
}

proc tkstash::setReturn {where} {
    variable config
    variable root
    if {$where eq ""} {
        if {[dict exists $config return $root]} { dict unset config return $root }
    } else {
        dict set config return $root $where
    }
    saveConfig
    updateGoBack
}

proc tkstash::updateGoBack {} {
    if {![winfo exists .stash.bar.back]} return
    lassign [returnTo] hash branch
    if {$hash eq ""} {
        .stash.bar.back state disabled
        icons::tooltip .stash.bar.back "After Go to: return to where the checkout was"
    } else {
        .stash.bar.back state !disabled
        icons::tooltip .stash.bar.back "Return to [string range $hash 0 9][expr {$branch ne "" ? " on $branch" : ""}]"
    }
}

# Back to where the checkout was before Go to: discard the changes (the
# stash still has them) and update.
proc tkstash::goBack {} {
    lassign [returnTo] hash branch
    if {$hash eq ""} return
    set to "[string range $hash 0 9][expr {$branch ne "" ? " on $branch" : ""}]"
    set changes [changes]
    set detail "The changes in the checkout are discarded (fossil revert), then it is\
        updated to $to."
    if {$changes ne ""} {
        append detail "\n\nDiscarded: the applied stash (which keeps them), and anything\
            changed since:\n[join [lrange [split $changes \n] 0 11] \n][expr {
            [llength [split $changes \n]] > 12 ? "\n\u2026" : ""}]"
    }
    if {![confirm "Stash" "Go back to $to?" $detail]} return
    lassign [fossil revert] code out
    if {!$code} {
        lassign [fossil update --nosync $hash] code out2
        append out \n$out2
    }
    if {!$code} { setReturn ""; tkcommit::remember $::tktaalik::root }
    reload
    if {$code} {
        tk_messageBox -icon error -title Stash -message "Going back failed:" -detail $out
    }
}

proc tkstash::drop {} {
    set id [selected]
    if {$id eq ""} return
    if {![confirm "Stash" "Drop stash $id?" "Its changes are lost, unless Commit \u25b8 Undo\
            brings them back right after (Fossil can undo dropping one stash)."]} return
    lassign [fossil stash drop $id] code out
    reload
    if {$code} { tk_messageBox -icon error -title Stash -message "fossil stash drop failed:" -detail $out }
}

# Drop every stash of the checkout (fossil stash drop --all).
proc tkstash::dropAll {} {
    variable stashes
    set n [array size stashes]
    if {!$n} return
    if {![ui::confirm -icon warning -title Stash \
            "Drop all $n stashes?" "Their changes are lost; unlike\
                dropping one stash, this cannot be undone."]} return
    # (Fossil asks again: answered yes, as asked above.)
    variable root
    lassign [fossil::run -dir $root -input "y\n" stash drop --all] code out
    reload
    if {$code} { tk_messageBox -icon error -title Stash -message "fossil stash drop failed:" -detail $out }
}

proc tkstash::saveToggle {path} {
    variable saveSkip
    if {$path eq ""} return
    if {[info exists saveSkip($path)]} { unset saveSkip($path) } else { set saveSkip($path) 1 }
    .stash.save.f.files.t set $path check [expr {[info exists saveSkip($path)] ? "\u2610" : "\u2611"}]
}

# Save the checkout's changes as a stash, and revert them.
proc tkstash::save {} {
    variable message
    variable answer
    variable snapshot
    variable saveSkip
    variable root
    if {[changes] eq ""} {
        tk_messageBox -icon info -title Stash -message "The checkout has no changes."
        return
    }
    lassign [fossil changes --classify] code out
    set changed {}
    foreach line [split $out \n] {
        if {![regexp {^(\S+)\s+(.*\S)} $line -> what path]} continue
        if {$what in {MERGED_WITH CHERRYPICK BACKOUT INTEGRATE}} continue
        regexp {^.*  ->  (.*)$} $path -> path
        lappend changed [list $path $what]
    }
    array unset saveSkip
    set snapshot 0
    set w .stash.save
    destroy $w
    toplevel $w
    wm title $w "Stash changes"
    wm transient $w .
    ttk::frame $w.f -padding 10
    pack $w.f -fill both -expand 1
    ttk::label $w.f.l -text "Stash the changes of the checkout and revert them.  Comment:"
    ttk::entry $w.f.e -textvariable tkstash::message -width 60
    ttk::label $w.f.fl -text "The files (uncheck the ones not to stash):"
    ttk::frame $w.f.files
    ttk::treeview $w.f.files.t -columns {check status path} -show headings -height \
        [expr {min(10, max(3, [llength $changed]))}] -selectmode browse \
        -yscrollcommand [list $w.f.files.y set]
    popup::attach $w.f.files.t tkstash::saveMenu
    ttk::scrollbar $w.f.files.y -command [list $w.f.files.t yview]
    set char [font measure TkDefaultFont 0]
    $w.f.files.t heading status -text Status -anchor w
    $w.f.files.t heading path -text File -anchor w
    $w.f.files.t column check -width [expr {$char * 3}] -stretch 0 -anchor center
    $w.f.files.t column status -width [expr {$char * 10}] -stretch 0
    $w.f.files.t column path -width [expr {$char * 40}] -stretch 1
    foreach item $changed {
        lassign $item path what
        $w.f.files.t insert {} end -id $path -values [list \u2611 $what $path]
    }
    grid $w.f.files.t $w.f.files.y -sticky news
    grid columnconfigure $w.f.files 0 -weight 1
    grid rowconfigure $w.f.files 0 -weight 1
    bind $w.f.files.t <ButtonPress-1> {
        if {[%W identify column %x %y] eq "#1" && [%W identify region %x %y] eq "cell"} {
            tkstash::saveToggle [%W identify item %x %y]
        }
    }
    bind $w.f.files.t <space> {tkstash::saveToggle [lindex [%W selection] 0]}
    ttk::checkbutton $w.f.snap -variable tkstash::snapshot \
        -text "Keep the changes in the checkout too (a snapshot: nothing is reverted)"
    ttk::frame $w.f.b
    ttk::button $w.f.b.ok -text Stash -default active -command {set tkstash::answer 1}
    ttk::button $w.f.b.cancel -text Cancel -command {set tkstash::answer 0}
    pack $w.f.b.cancel $w.f.b.ok -side right -padx {4 0}
    pack $w.f.l -anchor w
    pack $w.f.e -fill x -pady 4
    pack $w.f.fl -anchor w -pady {4 0}
    pack $w.f.files -fill both -expand 1 -pady 2
    pack $w.f.snap -anchor w -pady 4
    pack $w.f.b -fill x
    bind $w.f.e <Return> {set tkstash::answer 1}
    bind $w <Escape> {set tkstash::answer 0}
    wm protocol $w WM_DELETE_WINDOW {set tkstash::answer 0}
    focus $w.f.e
    set answer ""
    vwait ::tkstash::answer
    destroy $w
    if {!$answer} return
    set paths [lmap item $changed {
        if {[info exists saveSkip([lindex $item 0])]} continue
        lindex $item 0
    }]
    if {![llength $paths]} return
    # All files: none named (also what Fossil would not list as a change).
    set args [expr {[llength $paths] == [llength $changed] ? {} : [lmap p $paths { string cat ./ $p }]}]
    set comment [string trim $message]
    if {$comment eq ""} { set comment "(no comment)" }
    # (--comment=: a comment may start with "<", "|" or "-", which exec or
    # fossil would take for something else as a word of its own.)
    lassign [fossil stash [expr {$snapshot ? "snapshot" : "save"}] --comment=$comment {*}$args] code out
    reload
    if {$code} {
        tk_messageBox -icon error -title Stash -message "fossil stash save failed:" -detail $out
    } else {
        set message ""
    }
}

# ----------------------------------------------------------------- window

proc tkstash::build {} {
    variable config
    variable query
    variable history
    menu .stash.menu
    .stash.menu add cascade -label File -underline 0 -menu [menu .stash.menu.file]
    tktaalik::fileMenu .stash.menu.file
    .stash.menu.file add command -label Refresh -underline 0 -accelerator F5 -command tkstash::reload
    tktaalik::quitEntry .stash.menu.file
    .stash.menu add cascade -label Stash -underline 0 -menu [menu .stash.menu.stash]
    foreach {label command} {
        "Show diff"                     tkstash::showDiff
        "Diff against checkout"         {tkstash::showDiff checkout}
        --                              {}
        "Apply\u2026"                        tkstash::applyStash
        "Apply and drop\u2026"               {tkstash::applyStash 1}
        "Go to its check-in and apply\u2026" tkstash::goto
        "Go back\u2026"                      tkstash::goBack
        "Drop\u2026"                         tkstash::drop
        "Drop all\u2026"                     tkstash::dropAll
        --                              {}
        "Diff options"                  >diffopts
        "Stash changes\u2026"                tkstash::save
    } {
        if {$label eq "--"} {
            .stash.menu.stash add separator
        } elseif {[string index $command 0] eq ">"} {
            menu .stash.menu.stash.diffopts
            diffopts::menu .stash.menu.stash.diffopts {}
            .stash.menu.stash add cascade -label $label -menu .stash.menu.stash.diffopts
        } else {
            .stash.menu.stash add command -label $label -command $command
        }
    }
    .stash.menu add cascade -label Help -underline 0 -menu [menu .stash.menu.help]
    .stash.menu.help add command -label "Search syntax" -underline 0 \
        -command {help::show stash search-syntax}

    ttk::label .stash.none -anchor center -justify center \
        -text "Stashes belong to a checkout.\n\nOpen one with File \u25b8 Open checkout."

    # The search.
    ttk::frame .stash.top -padding {6 6 6 0}
    ttk::combobox .stash.top.q -textvariable tkstash::query
    icons::button .stash.top.go search "Search (Return)" {set tktaalik::typing ""; tkstash::search 1}
    icons::button .stash.top.clear clear "Clear the search (Escape)" \
        {tktaalik::navigate; set tkstash::query ""; tkstash::search}
    icons::button .stash.top.help help "Search syntax (the manual)" {help::show stash search-syntax}
    pack .stash.top.help .stash.top.clear .stash.top.go -side right -padx {4 0}
    pack .stash.top.q -fill x -expand 1
    # (Return ends the typing: the next key is a new place for Back.)
    bind .stash.top.q <Return> {set tktaalik::typing ""; tkstash::search 1}
    bind .stash.top.q <KP_Enter> {set tktaalik::typing ""; tkstash::search 1}
    bind .stash.top.q <<ComboboxSelected>> {set tktaalik::typing ""; tkstash::search 1}
    bind .stash.top.q <Escape> {tktaalik::navigate; set tkstash::query ""; tkstash::search}

    ttk::frame .stash.bar -padding {6 4 6 2}
    foreach {name label command} {
        diff  "Show diff"       tkstash::showDiff
        apply "Apply\u2026"          tkstash::applyStash
        pop   "Apply and drop\u2026" {tkstash::applyStash 1}
        goto  "Go to\u2026"          tkstash::goto
        back  "Go back\u2026"        tkstash::goBack
        drop  "Drop\u2026"           tkstash::drop
        save  "Stash changes\u2026"  tkstash::save
    } {
        ttk::button .stash.bar.$name -text $label -command $command
        pack .stash.bar.$name -side left -padx {0 4}
    }
    pack .stash.bar.save -side right
    icons::tooltip .stash.bar.goto "Update to the check-in of the stash and apply it there"

    ttk::panedwindow .stash.main -orient vertical
    ttk::frame .stash.main.list
    set t .stash.main.list.t
    ttk::treeview $t -show headings -selectmode browse -yscrollcommand {.stash.main.list.y set}
    ttk::scrollbar .stash.main.list.y -command [list $t yview]
    grid $t .stash.main.list.y -sticky news
    grid columnconfigure .stash.main.list 0 -weight 1
    grid rowconfigure .stash.main.list 0 -weight 1
    ttk::frame .stash.main.details
    text .stash.main.details.text -wrap word -height 10 -padx 8 -pady 6 -font TkTextFont \
        -state disabled -yscrollcommand {.stash.main.details.y set}
    ttk::scrollbar .stash.main.details.y -command {.stash.main.details.text yview}
    grid .stash.main.details.text .stash.main.details.y -sticky news
    grid columnconfigure .stash.main.details 0 -weight 1
    grid rowconfigure .stash.main.details 0 -weight 1
    set d .stash.main.details.text
    $d tag configure title -font TkHeadingFont
    $d tag configure meta -foreground gray40
    $d tag configure comment -font TkFixedFont
    $d tag configure added -foreground darkgreen
    $d tag configure deleted -foreground darkred
    $d tag configure renamed -foreground #6a3d9a
    $d tag configure changed -foreground gray40
    $d tag configure hit -font TkHeadingFont
    .stash.main add .stash.main.list -weight 2
    .stash.main add .stash.main.details -weight 2
    ttk::label .stash.status -textvariable tkstash::status -padding {6 2} -anchor w

    loadConfig
    set table [getdef $config table {}]
    tablecols::setup $t {
        id      {heading Stash width 7 type integer dir desc anchor e}
        date    {heading Date width 18 dir desc}
        base    {heading "Made on" width 30}
        files   {heading Files width 6 type integer dir desc anchor e}
        comment {heading Comment width 60 stretch 1}
    } -fixed {id comment} -shown [getdef $table shown {}] \
        -order [getdef $table order {}] -sort [getdef $table sort {id desc}]
    $t tag configure hit -font TkHeadingFont

    bind $t <<TreeviewSelect>> {tkstash::showDetails [tkstash::selected]}
    bind $t <Double-1> {
        if {[.stash.main.list.t identify region %x %y] in {cell tree}} tkstash::showDiff
    }
    tktaalik::shortcut stash <F5> tkstash::reload
    tktaalik::shortcut stash <Control-f> {focus .stash.top.q; .stash.top.q selection range 0 end}
    set history [getdef $config history {}]
    .stash.top.q configure -values $history
    set query [getdef $config query ""]
    # Searched while typing, a moment after the last key.
    trace add variable ::tkstash::query write {::apply {args {
        tktaalik::typing .stash.top.q
        after cancel {tkstash::search}
        after 300 {tkstash::search}
    }}}
    showWidgets 0
    popup::attach .stash.main.list.t tkstash::popupMenu
}

proc tkstash::showWidgets {on} {
    pack forget .stash.none .stash.top .stash.bar .stash.main .stash.status
    if {$on} {
        pack .stash.top -fill x
        pack .stash.bar -fill x
        pack .stash.status -side bottom -fill x
        pack .stash.main -fill both -expand 1
    } else {
        pack .stash.none -fill both -expand 1
    }
}

# Where we are (tktaalik::location): the query of the list, the stash.
# (Not to be confused with goto, which is "fossil stash goto".)
proc tkstash::here {} {
    variable searched
    list $searched [selected]
}

# Back or Forward to a place of here.
proc tkstash::goTo {place} {
    variable query
    lassign $place q id
    set query $q
    search
    after cancel {tkstash::search}
    set t .stash.main.list.t
    if {$id ne "" && [$t exists $id]} {
        $t selection set $id
        $t focus $id
        $t see $id
    }
}

proc tkstash::setRepository {path newRoot} {
    variable repo $path
    variable root $newRoot
    showWidgets [expr {$root ne ""}]
    updateGoBack
    tktaalik::setTitle stash [expr {$root eq "" ? "Stash \u2014 no checkout"
        : "Stash \u2014 [file tail $root]"}]
    reload
    after cancel {tkstash::search}
}

proc tkstash::activate {} {
    reload
    after cancel {tkstash::search}
    focus .stash.main.list.t
}

# The context menu of a stash: the Stash menu (the stash selected).
proc tkstash::popupMenu {m item} {
    popup::menuEntries $m .stash.menu.stash
    popup::separator $m
    popup::copy $m "Copy comment" [.stash.main.list.t set $item comment]
    popup::default $m "Show diff"
}

# The context menu of the files to stash: check or uncheck them all.
proc tkstash::saveMenu {m item} {
    variable saveSkip
    $m add command -label [expr {[info exists saveSkip($item)] ? "Check" : "Uncheck"}] \
        -command [list tkstash::saveToggle $item]
    $m add command -label "Check all" -command [list tkstash::saveAll 0]
    $m add command -label "Uncheck all" -command [list tkstash::saveAll 1]
    popup::separator $m
    popup::copy $m "Copy path" $item
}

proc tkstash::saveAll {skip} {
    variable saveSkip
    foreach path [.stash.save.f.files.t children {}] {
        if {[info exists saveSkip($path)] != $skip} { saveToggle $path }
    }
}
