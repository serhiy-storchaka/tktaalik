# The Stash tab of tktaalik: the stashes of the checkout.
#
# Lists them with the check-in they were made on, searches them, shows
# their files and diffs, and applies, pops, drops them or goes to them
# ("fossil stash"), after a confirmation (stashes are made in the Commit
# tab).  All of this is local to the checkout: stashes are never synced.  Settings are kept in
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
    variable diffShown ""       ;# the arguments of the diff in the details
    variable against 0          ;# the details: the diff against the checkout
    variable conflictsOf        ;# array: id -> what applying it would do (conflicts)
    variable query ""
    variable history {}
    variable terms {}           ;# the parsed search: {neg key alternatives}...
    variable status ""
    variable config {}
    variable configFile [config::path stash]

}

# ------------------------------------------------------------- settings

proc tkstash::loadConfig {} {
    variable configFile
    variable config
    set config [config::get $configFile stash tkstash.conf]
    set ::tkstash::against [getdef $config against 0]
}

proc tkstash::saveConfig {} {
    variable configFile
    variable config
    variable query
    variable history
    dict set config table [tablecols::state .stash.main.list.t]
    dict set config query $query
    dict set config history $history
    dict set config against $::tkstash::against
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
    set ::tkstash::diffShown ""
    # (The checkout may have changed: checked again when shown.)
    array unset ::tkstash::conflictsOf
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
    destroy $d.copyhash
    set none [expr {$id eq "" || ![info exists stashes($id)]}]
    foreach b {apply pop goto drop} {
        .stash.main.details.diff.bar.$b state [expr {$none ? "disabled" : "!disabled"}]
    }
    if {$none} {
        $d configure -state disabled
        showStashDiff ""
        return
    }
    set s $stashes($id)
    $d insert end "Stash $id  " title "[dict get $s date]  \u00b7  on [string range [dict get $s hash] 0 9]" meta
    $d window create end -align center -padx 2 -window [icons::copyButton $d.copyhash \
        "Copy the check-in's hash (all of it)" [list ui::copy [dict get $s hash]]]
    if {[dict get $s branch] ne ""} { $d insert end " ([dict get $s branch])" meta }
    if {[dict get $s hash] eq $current} { $d insert end "  \u00b7  the check-in of the checkout" meta }
    if {[dict get $s comment] ne ""} { $d insert end \n "" [dict get $s comment] comment }
    # (Not in the diff: a renamed file is only "CHANGED" there.)
    foreach f [dict get $s files] {
        if {[dict get $f how] eq "renamed"} {
            $d insert end "\nrenamed " renamed [dict get $f old] "" " \u2192 " meta [dict get $f new]
        }
    }
    # Whether it applies to the checkout as it is now.
    set result [checkedConflicts $id]
    if {[dict exists $result ""]} {
        $d insert end "\nWhether it conflicts with the checkout is not known: [dict get $result ""]" meta
    } elseif {![dict size $result]} {
        $d insert end "\nApplies to the checkout without conflicts." clean
    } else {
        # (Each: one file, several files.)
        foreach {how one several tag} {
            conflict
            "1 file conflicts with the changes in the checkout (in red below)"
            "%d files conflict with the changes in the checkout (in red below)" conflict
            overwrite
            "1 added file would overwrite the checkout's own file of its name (in orange)"
            "%d added files would overwrite the checkout's own files of their names (in orange)" warn
            discard
            "1 deleted file would be deleted with the changes the checkout made to it (in orange)"
            "%d deleted files would be deleted with the changes the checkout made to them (in orange)" warn
        } {
            set n [llength [filesThat $result $how]]
            if {$n} { $d insert end \n[format [expr {$n == 1 ? $one : $several}] $n] $tag }
        }
    }
    $d configure -state disabled
    fitHeader
    showStashDiff $id
}

# The header as high as its lines (a long comment: at most 8, scrolled).
proc tkstash::fitHeader {} {
    set d .stash.main.details.text
    # (In pixels, not in lines: the title and the copy button are higher
    # than a line of the text.)
    set pixels [$d count -update -ypixels 1.0 end]
    set max [expr {8 * [font metrics [$d cget -font] -linespace]}]
    set frame [expr {2 * ([$d cget -pady] + [$d cget -borderwidth] + [$d cget -highlightthickness])}]
    grid rowconfigure .stash.main.details 0 -minsize [expr {min($pixels, $max) + $frame}]
}

# The diff of stash ID in the details, at the first file the search
# matched, those in bold: its changes, or with "against" each of its files
# against the checkout's.  Run again only for another stash or other
# options: a search typed only marks other files.
proc tkstash::showStashDiff {id} {
    variable root
    variable matchedFiles
    variable diffShown
    variable against
    set w .stash.main.details.diff
    if {$id eq ""} {
        set diffShown ""
        diffview::clear $w
        return
    }
    variable stashes
    set hits [expr {[info exists matchedFiles($id)] ? $matchedFiles($id) : {}}]
    set args [list $id -i {*}[diffopts::args]]
    if {[list $against $args] eq $diffShown} {
        diffview::mark $w $hits
        markConflicts $id
        return
    }
    set diffShown [list $against $args]
    set command [expr {$against ? {fossil stash diff} : {fossil stash show}}]
    # Only the files it changes (Fossil can record every file of the
    # checkout in a stash, see reload).
    diffview::runIn $w -dir $root -command $command -options 0 \
        -select [lindex $hits 0] -mark $hits \
        -only [lmap f [dict get $stashes($id) files] { dict get $f new }] -- {*}$args
    # (After runIn: it forgets every mark but the search's.)
    markConflicts $id
}

# The files of stash ID that would conflict, in the diff of the details.
proc tkstash::markConflicts {id} {
    set w .stash.main.details.diff
    set result [checkedConflicts $id]
    diffview::mark $w [filesThat $result conflict] conflict
    diffview::mark $w [concat [filesThat $result overwrite] [filesThat $result discard]] warn
}

proc tkstash::selected {} {
    lindex [.stash.main.list.t selection] 0
}

# ---------------------------------------------------------------- conflicts

# What applying stash ID would do to the files of the checkout, decided as
# "fossil stash apply" does (its stash_apply), without applying it: a dict
# file -> how, of the files that do not simply get the stash's version:
#   conflict   the checkout changed it too and the merge of both has
#              conflicts, or cannot be made (a binary file, a symbolic
#              link, the file missing);
#   overwrite  an added file: the checkout has another file of its name;
#   discard    a deleted file: the checkout changed it.
# A file the checkout did not change is not looked at; the others are
# merged by Fossil (3-way-merge), on copies of the stash's versions
# (delta_apply in fossil sql).  Throws FOSSIL DB.
proc tkstash::conflicts {id} {
    variable root
    # (fossil changes first: then vfile knows which files are changed.)
    changes
    set rows [fossil::checkoutSql $root "SELECT [fossil::outcol newname],
        [fossil::outcol coalesce(origname,newname)], isAdded, isRemoved, isLink,
        coalesce((SELECT b.uuid=s.hash AND NOT v.chnged AND NOT v.deleted
            FROM vfile v JOIN blob b ON b.rid=v.rid
            WHERE v.pathname=coalesce(s.origname,s.newname)
            AND v.vid=(SELECT value FROM vvar WHERE name='checkout')), 0)
        FROM stashfile s WHERE stashid=[expr {int($id)}]"]
    set result {}
    set merge {}
    foreach row $rows {
        lassign $row new old added removed link same
        set path [file join $root $old]
        if {$removed} {
            if {!$same && [file exists $path]} { dict set result $new discard }
        } elseif {$added} {
            if {[file exists $path]} { lappend merge $row }
        } elseif {!$same} {
            if {$link || [file type $path] eq "link" || ![file isfile $path]} {
                dict set result $new conflict
            } else {
                lappend merge $row
            }
        }
    }
    if {![llength $merge]} { return $result }
    set dir [fossil::tempDir]
    try {
        # Both versions of each file at once: N.base and N.stash.
        set i 0
        set selects [lmap row $merge {
            lassign $row new
            set base [fossil::sqlstr [file join $dir [incr i].base]]
            set stashed [fossil::sqlstr [file join $dir $i.stash]]
            string cat "SELECT CASE WHEN isAdded THEN 0 ELSE writefile($base, content(hash)) END,
                writefile($stashed, CASE WHEN isAdded THEN delta
                    ELSE delta_apply(content(hash), delta) END)
                FROM stashfile WHERE stashid=[expr {int($id)}] AND newname=[fossil::sqlstr $new]"
        }]
        fossil::checkoutSql $root [join $selects " UNION ALL "]
        set i 0
        foreach row $merge {
            lassign $row new old added
            incr i
            set path [file join $root $old]
            if {$added} {
                if {[ReadBytes $path] ne [ReadBytes [file join $dir $i.stash]]} {
                    dict set result $new overwrite
                }
                continue
            }
            # (No warning and nothing written: a binary file, not merged.)
            lassign [fossil::run 3-way-merge [file join $dir $i.base] $path \
                [file join $dir $i.stash] [file join $dir $i.out]] code out
            if {$code || [string match "*merge conflict*" $out]
                    || ![file exists [file join $dir $i.out]]
                    || ([file size [file join $dir $i.out]] == 0
                        && [file size [file join $dir $i.stash]] > 0)} {
                dict set result $new conflict
            }
        }
    } finally {
        file delete -force $dir
    }
    return $result
}

proc tkstash::ReadBytes {path} {
    set f [open $path rb]
    try { ::read $f } finally { close $f }
}

# The conflicts of stash ID, checked once after each reload: a dict as
# conflicts gives, or one with the key "" (no file's name) and the error.
proc tkstash::checkedConflicts {id} {
    variable conflictsOf
    if {![info exists conflictsOf($id)]} {
        try {
            set conflictsOf($id) [conflicts $id]
        } trap {FOSSIL DB} msg {
            set conflictsOf($id) [list "" $msg]
        }
    }
    return $conflictsOf($id)
}

# The files of a result of conflicts that HOW.
proc tkstash::filesThat {result how} {
    if {[dict exists $result ""]} { return {} }
    lsort [dict keys [dict filter $result value $how]]
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
    # (Checked again: the checkout may have changed since it was shown.)
    variable conflictsOf
    unset -nocomplain conflictsOf($id)
    set result [checkedConflicts $id]
    if {[dict exists $result ""]} {
        if {[changes] ne ""} {
            append detail "  The checkout has uncommitted changes: they can conflict.\
                (Whether they do is not known: [dict get $result ""])"
        }
    } elseif {![dict size $result]} {
        if {[changes] ne ""} {
            append detail "  The checkout has uncommitted changes; they do not conflict with it."
        }
    } else {
        foreach {how text} {
            conflict  "Conflicts with the changes in the checkout: Fossil leaves conflict marks\
                in these files, to resolve before committing:"
            overwrite "Overwritten: the checkout has its own file of the same name, which is lost:"
            discard   "Deleted, with the changes the checkout made to them:"
        } {
            set files [filesThat $result $how]
            if {[llength $files]} {
                append detail "\n\n$text\n[join [lrange $files 0 11] \n][expr {
                    [llength $files] > 12 ? "\n\u2026" : ""}]"
            }
        }
    }
    showDetails $id
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
                exactly: stash them (Stash in the Commit tab) or commit them first."
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
    if {![winfo exists .stash.main.details.diff.bar.back]} return
    lassign [returnTo] hash branch
    if {$hash eq ""} {
        .stash.main.details.diff.bar.back state disabled
        icons::tooltip .stash.main.details.diff.bar.back "After Go to: return to where the checkout was"
    } else {
        .stash.main.details.diff.bar.back state !disabled
        icons::tooltip .stash.main.details.diff.bar.back "Return to [string range $hash 0 9][expr {$branch ne "" ? " on $branch" : ""}]"
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
        "Apply\u2026"                        tkstash::applyStash
        "Apply and drop\u2026"               {tkstash::applyStash 1}
        "Go to its check-in and apply\u2026" tkstash::goto
        "Go back\u2026"                      tkstash::goBack
        "Drop\u2026"                         tkstash::drop
        "Drop all\u2026"                     tkstash::dropAll
        --                              {}
        "Diff options"                  >diffopts
    } {
        if {$label eq "--"} {
            .stash.menu.stash add separator
        } elseif {[string index $command 0] eq ">"} {
            menu .stash.menu.stash.diffopts
            diffopts::menu .stash.menu.stash.diffopts {tkstash::showStashDiff [tkstash::selected]}
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
    complete::attach .stash.top.q tkstash::completion


    ttk::panedwindow .stash.main -orient vertical
    ui::splitByWeights .stash.main
    ttk::frame .stash.main.list
    set t .stash.main.list.t
    ttk::treeview $t -show headings -selectmode browse -yscrollcommand {.stash.main.list.y set}
    ttk::scrollbar .stash.main.list.y -command [list $t yview]
    grid $t .stash.main.list.y -sticky news
    grid columnconfigure .stash.main.list 0 -weight 1
    grid rowconfigure .stash.main.list 0 -weight 1
    ttk::frame .stash.main.details
    # The stash above its diff (the files the search matched in bold).
    text .stash.main.details.text -wrap word -height 1 -padx 8 -pady 6 -font TkTextFont \
        -state disabled -yscrollcommand {.stash.main.details.y set}
    ttk::scrollbar .stash.main.details.y -command {.stash.main.details.text yview}
    diffview::panel .stash.main.details.diff
    # The actions on the stash: in the bar of its diff, instead of a title.
    # (Go back with Go to, whose return it is: enabled by updateGoBack,
    # whichever stash is selected.)
    set b .stash.main.details.diff.bar
    pack forget $b.title
    foreach {name label command} {
        apply "Apply\u2026"          tkstash::applyStash
        pop   "Apply and drop\u2026" {tkstash::applyStash 1}
        goto  "Go to\u2026"          tkstash::goto
        back  "Go back\u2026"        tkstash::goBack
        drop  "Drop\u2026"           tkstash::drop
    } {
        ttk::button $b.$name -text $label -command $command -state disabled
        pack $b.$name -side left -padx {0 4}
    }
    icons::tooltip $b.goto "Update to the check-in of the stash and apply it there"
    ttk::checkbutton $b.against -text "Against the checkout" -variable tkstash::against \
        -command {tkstash::showStashDiff [tkstash::selected]}
    pack $b.against -side left -padx {8 0}
    icons::tooltip $b.against "Each file of the stash compared with the checkout's file\n(fossil stash diff), not with the stash's base.\nThe checkout's own changes show as lines removed:\nApplying merges, it does not replace."
    grid .stash.main.details.text .stash.main.details.y -sticky news
    grid .stash.main.details.diff - -sticky news
    grid columnconfigure .stash.main.details 0 -weight 1
    grid rowconfigure .stash.main.details 1 -weight 1
    bind .stash.main.details.text <Configure> tkstash::fitHeader
    set d .stash.main.details.text
    $d tag configure title -font TkHeadingFont
    $d tag configure meta -foreground gray40
    $d tag configure comment -font TkFixedFont
    $d tag configure renamed -foreground #6a3d9a
    $d tag configure conflict -foreground red3
    $d tag configure warn -foreground darkorange3
    $d tag configure clean -foreground darkgreen
    .stash.main add .stash.main.list -weight 1
    .stash.main add .stash.main.details -weight 3
    ttk::label .stash.status -textvariable tkstash::status -padding {6 2} -anchor w

    loadConfig
    # (The return point of Go to is in the settings.)
    updateGoBack
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
    tktaalik::shortcut stash <F5> tkstash::reload
    tktaalik::shortcut stash <Control-f> {focus .stash.top.q; .stash.top.q selection range 0 end}
    tktaalik::shortcut stash <Control-slash> {focus .stash.top.q; .stash.top.q selection range 0 end}
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
    # (Ctrl+C: the comment; the check-in has its button in the details.)
    popup::copyKey .stash.main.list.t {::apply {{id} { .stash.main.list.t set $id comment }}}
}

proc tkstash::showWidgets {on} {
    pack forget .stash.none .stash.top .stash.main .stash.status
    if {$on} {
        pack .stash.top -fill x
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
}

# The keys of the search, with their values, for the completion of the
# search box (complete::attach).
proc tkstash::completion {} {
    variable repo
    set files [list complete::files $repo]
    dict create \
        comment [list "a part of the comment" ""] \
        date [list "the date it was made" ""] \
        branch [list "made on the branch" [list complete::branches $repo] {complete::icon k-branch}] \
        on [list "made on the check-in" ""] \
        file [list "changes the file" $files complete::fileIcon] \
        added [list "adds the file" $files complete::fileIcon] \
        deleted [list "deletes the file" $files complete::fileIcon] \
        renamed [list "renames the file" $files complete::fileIcon] \
        files [list "the number of files" ""] \
        diff [list "a part of the changed lines" ""] \
        is [list "current" {complete::fixed current}]
}
