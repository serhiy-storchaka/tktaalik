# The Timeline tab of tktaalik: everything that happened in the
# repository, newest first: check-ins, ticket changes, tag changes (closed
# and hidden branches, release tags), wiki, forum and technote edits.
#
# Views: All; Last pull (what the last "fossil pull" brought); Outgoing
# (what a push would send: the events among the unsent artifacts).  The
# search is turned into SQL (lib/searchterms.tcl for the syntax), and the
# newest matches are shown, more on request.  Settings are kept in
# ~/.config/tktaalik/timeline.conf.
#
# Changes, in the local repository only (nothing is pushed): a check-in
# edited ("fossil amend"), tags added and cancelled, reparenting
# (lib/tagwrite.tcl); a pull ("fossil pull", never push or sync).  In a
# checkout, bisect ("fossil bisect": the checkout or any check-in marked
# good, bad or skipped; status, log, chart; bisect run).

source [file join [file dirname [file normalize [info script]]] config.tcl]
source [file join [file dirname [file normalize [info script]]] fossil.tcl]
source [file join [file dirname [file normalize [info script]]] tablecols.tcl]
source [file join [file dirname [file normalize [info script]]] searchterms.tcl]
source [file join [file dirname [file normalize [info script]]] tagwrite.tcl]
source [file join [file dirname [file normalize [info script]]] histops.tcl]

namespace eval tktimeline {
    variable repo ""
    variable me ""
    variable remote ""
    variable query ""           ;# the search
    variable history {}
    variable view all           ;# all lastpull outgoing private
    variable limit 1000         ;# rows shown; More doubles it
    variable searched {}        ;# the query and view of the list shown
    variable status ""
    variable rows               ;# array: rid -> dict of the row
    variable config {}
    variable configFile [config::path timeline]
    variable kinds {ci check-in t ticket g tag w wiki f forum e technote}
    variable root ""            ;# the checkout, or ""
    variable current ""         ;# the rid of the checkout's check-in
    variable bisect {}          ;# rid -> good, bad or skip
    variable bisectAll 0        ;# the bisect status of all check-ins
    variable bisectOpt          ;# array: the bisect options
    variable bisectChan ""      ;# "fossil bisect run" running
    variable pullOpt            ;# array: the pull options
    variable pullChan ""        ;# "fossil pull" running
    variable pullCmd {}         ;# the last pull command

}

# ------------------------------------------------------------- settings

proc tktimeline::loadConfig {} {
    variable configFile
    variable config
    set config [config::get $configFile timeline tktimeline.conf]
}

proc tktimeline::saveConfig {} {
    variable configFile
    variable config
    variable query
    variable history
    variable view
    dict set config table [tablecols::state .timeline.main.list.t]
    dict set config query $query
    dict set config history $history
    dict set config view $view
    config::put $configFile $config table
}

proc tktimeline::getdef {dict key default} {
    expr {[dict exists $dict $key] ? [dict get $dict $key] : $default}
}

proc tktimeline::sql {statement} {
    variable repo
    fossil::sql $repo $statement
}

# ----------------------------------------------------------------- search

# SQL for a LIKE pattern matching $text anywhere.
proc tktimeline::like {text} {
    fossil::sqlstr %[string map {\\ \\\\ % \\% _ \\_} $text]%
}

# The check-in a name means, as SQL: a tag or a branch name (its newest
# check-in), a hash prefix, or "current" (the checkout's).
proc tktimeline::checkin {name} {
    variable current
    if {[string tolower $name] eq "current"} {
        if {$current eq ""} { terms::error "current: there is no checkout" }
        return $current
    }
    # (A subquery: ORDER BY cannot come before the UNION.)
    set start "(SELECT rid FROM tagxref WHERE tagtype>0
        AND tagid=(SELECT tagid FROM tag WHERE tagname=[fossil::sqlstr sym-$name])
        ORDER BY mtime DESC LIMIT 1)"
    if {[regexp {^[0-9a-f]{4,64}$} $name]} {
        # A hash prefix of one check-in (several: say so, as Branches does).
        variable repo
        set n [lindex [fossil::sql $repo "SELECT count(*) FROM blob b JOIN event e\
            ON e.objid=b.rid AND e.type='ci' WHERE b.uuid GLOB [fossil::sqlstr $name*]"] 0 0]
        if {$n > 1 && ![llength [fossil::sql $repo "SELECT 1 FROM tag WHERE tagname=[fossil::sqlstr sym-$name]"]]} {
            terms::error "$name: $n check-ins start with it"
        }
        set start "coalesce($start,
            (SELECT b.rid FROM blob b JOIN event e ON e.objid=b.rid AND e.type='ci'
             WHERE b.uuid GLOB [fossil::sqlstr $name*] LIMIT 1))"
    }
    return $start
}

# The check-ins that a name means, and their ancestors.
proc tktimeline::ancestors {name} {
    return "(WITH RECURSIVE anc(rid) AS (SELECT [checkin $name]
        UNION SELECT plink.pid FROM plink JOIN anc ON plink.cid=anc.rid)
        SELECT rid FROM anc)"
}

# And its descendants.
proc tktimeline::descendants {name} {
    return "(WITH RECURSIVE des(rid) AS (SELECT [checkin $name]
        UNION SELECT plink.cid FROM plink JOIN des ON plink.pid=des.rid)
        SELECT rid FROM des)"
}

# The search as an SQL condition on event e, blob b.
proc tktimeline::where {query} {
    variable kinds
    variable me
    set conds {}
    foreach token [terms::tokenize $query] {
        lassign $token neg key value
        if {$key ne "" && $value eq ""} { terms::error "empty value for $key:" }
        if {$key eq ""} {
            set alts [list $value]
        } else {
            set alts [lmap a [split $value ,] {
                set a [string trim $a]
                if {$a eq ""} continue
                set a
            }]
        }
        set ors [lmap a $alts {
            switch -- $key {
                "" - comment {
                    string cat "lower(coalesce(e.ecomment,e.comment)) LIKE " \
                        [like [string tolower $a]] " ESCAPE '\\'"
                }
                user {
                    if {[string tolower $a] eq "@me"} {
                        if {$me eq ""} { terms::error "@me: this repository has no default user" }
                        set a $me
                    }
                    string cat "lower(coalesce(e.euser,e.user))=" [fossil::sqlstr [string tolower $a]]
                }
                kind {
                    set a [string tolower $a]
                    if {$a eq "checkin"} { set a ci }
                    set type ""
                    dict for {t label} $kinds {
                        if {$a eq $t || $a eq $label} { set type $t }
                    }
                    if {$type eq ""} {
                        terms::error "kind:$a: use kind:[join [dict values $kinds] ,kind:]"
                    }
                    string cat "e.type='" $type "'"
                }
                branch {
                    if {[string tolower $a] eq "@current"} {
                        variable current
                        if {$current eq ""} { terms::error "branch:@current: there is no checkout" }
                        set a [lindex [sql "SELECT value FROM tagxref WHERE rid=$current AND tagtype>0
                            AND tagid=(SELECT tagid FROM tag WHERE tagname='branch')"] 0 0]
                    }
                    set op [expr {[terms::isGlob $a] ? "GLOB" : "="}]
                    string cat "e.type='ci' AND EXISTS(SELECT 1 FROM tagxref x WHERE x.rid=e.objid" \
                        " AND x.tagid=(SELECT tagid FROM tag WHERE tagname='branch')" \
                        " AND x.tagtype>0 AND x.value $op " [fossil::sqlstr $a] ")"
                }
                tag {
                    # Every check-in with the tag, given or propagated to it
                    # (as fossil tag find); a glob is allowed.
                    set op [expr {[terms::isGlob $a] ? "GLOB" : "="}]
                    string cat "EXISTS(SELECT 1 FROM tagxref x JOIN tag t ON t.tagid=x.tagid" \
                        " WHERE x.rid=e.objid AND x.tagtype>0 AND t.tagname $op " [fossil::sqlstr sym-$a] ")"
                }
                ticket {
                    set a [string tolower $a]
                    if {![regexp {^[0-9a-f]{4,64}$} $a]} { terms::error "ticket:$a: not a ticket id" }
                    string cat "((e.type='t' AND (SELECT tagname FROM tag WHERE tagid=e.tagid) GLOB " \
                        [fossil::sqlstr tkt-$a*] ") OR (e.type='ci' AND EXISTS(SELECT 1 FROM backlink" \
                        " bl WHERE bl.srctype=0 AND bl.srcid=e.objid AND (bl.target GLOB " \
                        [fossil::sqlstr $a*] " OR " [fossil::sqlstr $a] " GLOB bl.target||'*'))))"
                }
                hash {
                    set a [string tolower $a]
                    if {![regexp {^[0-9a-f]{1,64}$} $a]} { terms::error "hash:$a: not a hash" }
                    string cat "b.uuid GLOB " [fossil::sqlstr $a*]
                }
                date {
                    lassign [terms::dateSpec $a] lo hi
                    set c {}
                    if {$lo ne ""} { lappend c "e.mtime>=julianday('$lo')" }
                    if {$hi ne ""} { lappend c "e.mtime<julianday('$hi')" }
                    expr {[llength $c] ? [join $c " AND "] : "1"}
                }
                pull {
                    if {![regexp {^[0-9]+$} $a] || $a < 1} { terms::error "pull:$a: use pull:1, pull:2, ..." }
                    string cat "b.rcvid IN (SELECT rcvid FROM rcvfrom WHERE ipaddr IS NOT NULL" \
                        " AND rcvid IN (SELECT rcvid FROM blob JOIN event ON objid=rid)" \
                        " ORDER BY rcvid DESC LIMIT $a)"
                }
                in {
                    string cat "e.type='ci' AND e.objid IN " [ancestors $a]
                }
                desc {
                    string cat "e.type='ci' AND e.objid IN " [descendants $a]
                }
                after {
                    string cat "e.mtime>(SELECT mtime FROM event WHERE objid=" [checkin $a] ")"
                }
                before {
                    string cat "e.mtime<(SELECT mtime FROM event WHERE objid=" [checkin $a] ")"
                }
                path {
                    # A file, or the files in a directory; or a glob.
                    set a [string trim $a /]
                    if {[terms::isGlob $a]} {
                        set match "f.name GLOB [fossil::sqlstr $a]"
                    } else {
                        set match "(f.name=[fossil::sqlstr $a] OR substr(f.name,1,[string length $a/])=[fossil::sqlstr $a/])"
                    }
                    string cat "e.type='ci' AND EXISTS(SELECT 1 FROM mlink m JOIN filename f" \
                        " ON f.fnid=m.fnid WHERE m.mid=e.objid AND " $match ")"
                }
                is {
                    switch -- [string tolower $a] {
                        unsent  { string cat "e.objid IN (SELECT rid FROM unsent)" }
                        private { string cat "e.objid IN (SELECT rid FROM private)" }
                        leaf    { string cat "e.objid IN (SELECT rid FROM leaf)" }
                        open - closed {
                            # Leaves, open or closed (as fossil leaves, -c).
                            string cat "e.objid IN (SELECT rid FROM leaf) AND " \
                                [expr {[string tolower $a] eq "open" ? "NOT " : ""}] \
                                "EXISTS(SELECT 1 FROM tagxref WHERE rid=e.objid AND tagtype>0" \
                                " AND tagid=(SELECT tagid FROM tag WHERE tagname='closed'))"
                        }
                        merge   { string cat "(SELECT count(*) FROM plink WHERE cid=e.objid)>1" }
                        current { string cat "e.objid=" [checkin current] }
                        default { terms::error "is:$a: use is:unsent, is:private, is:leaf, is:open, is:closed, is:merge or is:current" }
                    }
                }
                default {
                    terms::error "unknown key \"$key:\"; see Help \u25b8 About the timeline"
                }
            }
        }]
        if {![llength $ors]} { terms::error "empty value for $key:" }
        set cond "([join $ors { OR }])"
        lappend conds [expr {$neg ? "NOT $cond" : $cond}]
    }
    expr {[llength $conds] ? [join $conds " AND "] : "1"}
}

# The views (the All, Last pull, Outgoing and Private buttons) are terms of
# the query: none, pull:1, is:unsent, is:private.  The first one in the
# query is the view; it filters as the view, and the buttons count the
# rest of the search.  Returns {view rest-of-query}.
proc tktimeline::splitView {query} {
    set words [regexp -all -inline {(?:[^\s"]|"[^"]*")+} $query]
    set i 0
    foreach word $words {
        foreach {v term} {lastpull pull:1 outgoing is:unsent private is:private} {
            if {[string equal -nocase $word $term]} {
                return [list $v [join [lreplace $words $i $i]]]
            }
        }
        incr i
    }
    list all [join $words]
}

proc tktimeline::viewTerm {v} {
    dict get {all "" lastpull pull:1 outgoing is:unsent private is:private} $v
}

# A view button: the same search with its term, in place of the view's.
proc tktimeline::setView {} {
    variable query
    variable view
    set new $view
    tktaalik::navigate
    set query [string trim "[lindex [splitView $query] 1] [viewTerm $new]"]
    search
}

# The condition of a view.
proc tktimeline::viewCondition {view} {
    switch -- $view {
        lastpull { return "b.rcvid=(SELECT rcvid FROM rcvfrom WHERE ipaddr IS NOT NULL
            AND rcvid IN (SELECT rcvid FROM blob JOIN event ON objid=rid)
            ORDER BY rcvid DESC LIMIT 1)" }
        outgoing { return "e.objid IN (SELECT rid FROM unsent)" }
        private  { return "e.objid IN (SELECT rid FROM private)" }
        default  { return 1 }
    }
}

# A comment as text.  Check-in comments are as written; the comments
# Fossil makes for the other events have links [target|label], and those
# of ticket changes HTML.
proc tktimeline::plain {type text} {
    if {$type eq "ci"} { return $text }
    set text [regsub -all {\[[^]|\[]*\|([^]\[]*)\]} $text {\1}]
    if {$type ne "t"} { return $text }
    set text [regsub -all {<[^<>]*>} $text ""]
    string map {&lt; < &gt; > &quot; \" &#39; ' &amp; &} $text
}

proc tktimeline::search {{remember 0}} {
    # (Tags may have changed: describe again.)
    histops::forget
    variable query
    variable history
    variable view
    variable searched
    # (The view is a term of the query: see splitView.)
    lassign [splitView $query] view rest
    set searched [list $query $view]
    variable limit
    variable status
    variable rows
    variable kinds
    after cancel {tktimeline::search}
    checkoutState
    try {
        set where [where $rest]
    } trap {TKFOSSIL QUERY} msg {
        showError $msg
        return
    }
    set q [string trim $query]
    if {$remember && $q ne ""} {
        set history [lrange [linsert [lsearch -all -inline -not -exact $history $q] 0 $q] 0 29]
        .timeline.top.q configure -values $history
    }
    set busy [ui::busyHold]
    try {
        set counts {}
        foreach v {all lastpull outgoing private} {
            dict set counts $v [lindex [sql "SELECT count(*) FROM event e JOIN blob b ON b.rid=e.objid
                WHERE ($where) AND [viewCondition $v]"] 0 0]
        }
        set result [sql "SELECT e.objid, e.type, strftime('%Y-%m-%d %H:%M', e.mtime),
            [fossil::outcol coalesce(e.euser,e.user)],
            [fossil::outcol coalesce(e.ecomment,e.comment)], b.uuid,
            coalesce([fossil::outcol "(SELECT value FROM tagxref WHERE rid=e.objid AND tagtype>0
                AND tagid=(SELECT tagid FROM tag WHERE tagname='branch'))"],''),
            coalesce((SELECT substr(tagname,5) FROM tag WHERE tagid=e.tagid AND tagname GLOB 'tkt-*'),''),
            e.objid IN (SELECT rid FROM unsent), e.objid IN (SELECT rid FROM private)
            FROM event e JOIN blob b ON b.rid=e.objid
            WHERE ($where) AND [viewCondition $view]
            ORDER BY e.mtime DESC LIMIT $limit"]
        set lastPull [lindex [sql "SELECT datetime(mtime) FROM rcvfrom WHERE ipaddr IS NOT NULL
            AND rcvid IN (SELECT rcvid FROM blob JOIN event ON objid=rid)
            ORDER BY rcvid DESC LIMIT 1"] 0 0]
        set unsent [lindex [sql "SELECT count(*) FROM unsent"] 0 0]
        set private [lindex [sql "SELECT count(*) FROM private"] 0 0]
    } trap {FOSSIL DB} msg {
        showError "Database error: $msg"
        return
    } finally {
        ui::busyRelease $busy
    }
    foreach v {all lastpull outgoing private} {
        .timeline.tabs.$v configure -text "[dict get {all All lastpull "Last pull" outgoing Outgoing
            private Private} $v] ([dict get $counts $v])"
    }
    array unset rows
    set items {}
    # Tk 9 shows the kind as an icon (the word in a tooltip); Tk 8.6 cannot.
    set t .timeline.main.list.t
    set cellImages [expr {![catch {$t tag cell has {}}]}]
    set iconCells {}
    foreach row $result {
        lassign $row rid type date user comment uuid branch ticket unsentRow privateRow
        set comment [fossil::lf [plain $type $comment]]
        set rows($rid) [dict create type $type date $date user $user comment $comment \
            uuid $uuid branch $branch ticket $ticket unsent $unsentRow private $privateRow]
        set kind [dict get $kinds $type]
        set cells [dict create date $date kind $kind user $user \
            branch $branch ticket [string range $ticket 0 9] hash [string range $uuid 0 9] \
            comment [string map {\n " "} $comment]]
        if {$cellImages} {
            dict set cells kind ""
            dict lappend iconCells [kindIcon $type] [list $rid kind]
        }
        set tags {}
        if {$unsentRow} { lappend tags unsent }
        if {$privateRow} { lappend tags private }
        variable bisect
        if {[dict exists $bisect $rid]} { lappend tags bisect-[dict get $bisect $rid] }
        variable current
        if {$rid eq $current} { lappend tags current }
        lappend items [list $rid $cells [dict create kind $kind] $tags]
    }
    set keep [$t selection]
    tablecols::fill $t $items
    dict for {icon cells} $iconCells {
        $t tag configure icon:$icon -image [icons::get $icon row] -imageanchor center
        $t tag cell add icon:$icon $cells
    }
    set keep [lmap id $keep { if {![$t exists $id]} continue; set id }]
    if {![llength $keep]} { set keep [lrange [$t children {}] 0 0] }
    if {[llength $keep]} {
        $t selection set $keep
        $t focus [lindex $keep 0]
        $t see [lindex $keep 0]
    } else {
        showDetails ""
    }
    set total [dict get $counts $view]
    set status [expr {$total > [llength $result]
        ? "[llength $result] newest of $total" : "$total events"}]
    if {$lastPull ne ""} { append status "  \u00b7  last pull $lastPull" }
    if {$unsent > 0} { append status "  \u00b7  $unsent unpushed artifacts" }
    if {$private > 0} { append status "  \u00b7  $private private artifacts" }
    variable bisect
    if {[dict size $bisect]} { append status "  \u00b7  [bisectSummary]" }
    variable repo
    append status "  \u00b7  $repo"
    .timeline.status configure -foreground ""
    if {$total > [llength $result]} {
        pack .timeline.more -in .timeline.bottom -side right
    } else {
        pack forget .timeline.more
    }
}

# The checkout's check-in and its bisect (good, bad and skipped ones).
proc tktimeline::checkoutState {} {
    variable root
    variable current ""
    variable bisect {}
    if {$root eq ""} return
    try {
        set rows [fossil::checkoutSql $root "SELECT name, value FROM vvar
            WHERE name IN ('checkout', 'bisect-log')"]
    } trap {FOSSIL DB} msg {
        return
    }
    foreach row $rows {
        lassign $row name value
        if {$name eq "checkout"} {
            set current $value
            continue
        }
        # "-RID": bad, "sRID": skipped, "RID": good; the last one counts.
        foreach entry $value {
            if {[regexp {^-(\d+)$} $entry -> rid]} {
                dict set bisect $rid bad
            } elseif {[regexp {^s(\d+)$} $entry -> rid]} {
                dict set bisect $rid skip
            } elseif {[regexp {^\d+$} $entry]} {
                dict set bisect $entry good
            }
        }
    }
}

# How far the bisect is: how many good, bad, skipped, how many check-ins
# are left between the newest good and the oldest bad.
proc tktimeline::bisectSummary {} {
    variable bisect
    set n [dict create good 0 bad 0 skip 0]
    dict for {rid how} $bisect { dict incr n $how }
    set text "bisect: [dict get $n good] good, [dict get $n bad] bad"
    if {[dict get $n skip]} { append text ", [dict get $n skip] skipped" }
    lassign [bisectRun bisect ls] code out
    if {!$code} {
        set left [regexp -all -line {^\d{4}-\d\d-\d\d } $out]
        if {[regexp {(\d+) other check-ins omitted} $out -> more]} { incr left $more }
        append text ", $left in between"
    }
    return $text
}

proc tktimeline::more {} {
    variable limit
    set limit [expr {$limit * 2}]
    search
}

proc tktimeline::showError {msg} {
    variable status
    set status "Search: $msg"
    .timeline.status configure -foreground red3
}

proc tktimeline::addTerm {key value neg} {
    variable query
    tktaalik::navigate
    if {[regexp {[\s,"]} $value]} { set value "\"$value\"" }
    set term [expr {$neg ? "-" : ""}]$key:$value
    if {$term ni [regexp -all -inline {\S+} $query]} {
        set query [string trim "$query $term"]
    }
    search 1
}

# ---------------------------------------------------------------- details

proc tktimeline::showDetails {rid} {
    variable rows
    variable kinds
    set d .timeline.main.details.text
    $d configure -state normal
    $d delete 1.0 end
    foreach b [winfo children .timeline.main.details.buttons] { destroy $b }
    if {$rid eq "" || ![info exists rows($rid)]} {
        $d configure -state disabled
        return
    }
    set r $rows($rid)
    set type [dict get $r type]
    set uuid [dict get $r uuid]
    $d image create end -image [icons::get [kindIcon $type] row] -align center -padx 2
    $d insert end " [string totitle [dict get $kinds $type]]  " title \
        "[dict get $r date] by [dict get $r user]  \u00b7  [string range $uuid 0 9]" meta
    if {[dict get $r branch] ne ""} { $d insert end "  \u00b7  branch [dict get $r branch]" meta }
    if {[dict get $r unsent]} { $d insert end "  \u00b7  not pushed" unsent }
    if {[dict get $r private]} { $d insert end "  \u00b7  private: never pushed" private }
    $d insert end \n\n "" [dict get $r comment] comment \n\n ""

    set buttons {}
    switch -- $type {
        ci {
            # Its tags (inherited ones in grey), then its files.
            set tags [checkinTags $rid]
            if {[llength $tags]} {
                $d insert end "Tags: " label
                foreach tag $tags {
                    lassign $tag name value raw inherited
                    $d insert end $name[expr {$value ne "" ? "=$value" : ""}] \
                        [expr {$inherited ? "meta" : ""}] "  " ""
                }
                $d insert end \n\n
            }
            # Where it is: its parents and children (merges too), its state;
            # the nearest tag before it (and release, as describe --match).
            relations $d $rid
            set desc [describe $uuid]
            variable config
            set match [getdef $config describeMatch core-*]
            set release [expr {$match ne "*" ? [describe $uuid $match] : ""}]
            if {$desc ne ""} {
                $d insert end "Describe: " label $desc
                if {$release ne "" && $release ne $desc} { $d insert end "   (from $match: $release)" meta }
                $d insert end \n\n
            }
            # The files of the check-in.
            set files [sql "SELECT [fossil::outcol f.name],
                CASE WHEN m.pid=0 THEN 'added' WHEN m.fid=0 THEN 'deleted' ELSE 'changed' END
                FROM mlink m JOIN filename f ON f.fnid=m.fnid
                WHERE m.mid=$rid AND NOT m.isaux ORDER BY f.name"]
            $d insert end "[llength $files] file[expr {[llength $files] == 1 ? "" : "s"}]\n" label
            foreach row $files {
                lassign $row name how
                $d insert end [format "%-8s " $how] $how $name\n
            }
            lappend buttons Diff [list tktimeline::diff $uuid] \
                "Show branch" [list tktimeline::showBranch [dict get $r branch]]
        }
        t {
            # The fields of the change: the J cards of the artifact.
            foreach {field value} [ticketFields $uuid] {
                $d insert end "$field: " label
                $d insert end [expr {[string first \n $value] >= 0 ? "\n$value\n" : "$value\n"}]
            }
            lappend buttons "Show ticket" [list tktimeline::showTicket [dict get $r ticket]]
        }
        w - e - f {
            # The page, technote or post, in its tab (as Go to shows it).
            set script [goto::nameTarget $uuid artifact]
            if {$script ne ""} {
                lappend buttons [expr {$type eq "f" ? "Show in Forum" : "Show in Wiki"}] $script
            }
        }
        g {
            set tags [sql "SELECT [fossil::outcol t.tagname], x.tagtype, coalesce([fossil::outcol x.value],''),
                (SELECT substr(uuid,1,10) FROM blob WHERE rid=x.rid)
                FROM tagxref x JOIN tag t USING(tagid) WHERE x.srcid=$rid ORDER BY 1"]
            foreach row $tags {
                lassign $row name tagtype value target
                set what [lindex {cancel add propagate} $tagtype]
                $d insert end "$what " label "$name[expr {$value ne "" ? " = $value" : ""}]" "" \
                    "  on $target\n" meta
            }
        }
    }
    lappend buttons "Open in browser" [list tktimeline::openUrl info/$uuid]
    set i 0
    foreach {label command} $buttons {
        ttk::button .timeline.main.details.buttons.b[incr i] -text $label -command $command
        pack .timeline.main.details.buttons.b$i -side left -padx {0 4}
    }
    $d configure -state disabled
}

# The fields a ticket change sets: {field value ...}; "+field" appends.
proc tktimeline::ticketFields {uuid} {
    variable repo
    lassign [fossil::run artifact -R $repo $uuid] code out
    if {$code} { return [list error $out] }
    set fields {}
    foreach line [split $out \n] {
        if {[regexp {^J (\S+)(?: (.*))?$} $line -> field value]} {
            lappend fields $field [fossil::lf [string map {\\s " " \\n \n \\t \t \\r \r \\\\ \\} $value]]
        }
    }
    return $fields
}

proc tktimeline::diff {uuid} {
    variable repo
    diffview::run "Check-in [string range $uuid 0 9]" -- -R $repo --checkin $uuid
}

proc tktimeline::showTicket {id} {
    if {$id eq ""} return
    tktaalik::show tickets
    tktsearch::setQuery id:[string range $id 0 9]
}

proc tktimeline::showBranch {name} {
    if {$name eq ""} return
    tktaalik::show branches
    tkbranches::showBranch $name
}

proc tktimeline::openUrl {path} {
    variable remote
    ui::openServer $remote $path -title Timeline
}

proc tktimeline::contextMenu {x y X Y} {
    variable rows
    variable kinds
    set t .timeline.main.list.t
    if {[$t identify region $x $y] ni {cell tree}} return
    set rid [$t identify item $x $y]
    if {$rid eq "" || ![info exists rows($rid)]} return
    $t selection set $rid
    set r $rows($rid)
    set m .timeline.ctx
    $m delete 0 end
    if {[dict get $r type] eq "ci"} {
        $m add command -label "Diff" -command [list tktimeline::diff [dict get $r uuid]]
        $m add command -label "Show branch [dict get $r branch]" \
            -command [list tktimeline::showBranch [dict get $r branch]]
        $m add separator
        $m add command -label "Edit check-in\u2026" -command [list tktimeline::editCheckin $rid]
        $m add command -label "Add tag\u2026" -command [list tktimeline::addTag $rid]
        # Its own tags can be cancelled here; a propagating one also from
        # a check-in it reached: then it stops there ("from here on").
        destroy $m.cancel
        menu $m.cancel
        foreach tag [checkinTags $rid] {
            lassign $tag name value raw inherited propagating branch
            # (Not the branch name, nor the raw tags a branch propagates,
            # its colour...: Branches, Edit check-in.)
            if {$branch || ($raw && $propagating)} continue
            if {$inherited && !$propagating} continue
            set label "$name[expr {$value ne "" ? " = $value" : ""}]"
            if {$inherited} { append label " (from here on)" }
            $m.cancel add command -label $label\u2026 \
                -command [list tktimeline::cancelTag $rid $name $raw]
        }
        $m add cascade -label "Cancel tag" -menu $m.cancel \
            -state [expr {[$m.cancel index end] eq "none" ? "disabled" : "normal"}]
        destroy $m.bisect
        menu $m.bisect
        foreach {sub label} {good "Good" bad "Bad" skip "Skip"} {
            $m.bisect add command -label $label -command [list tktimeline::bisect $sub [dict get $r uuid]]
        }
        variable root
        $m add cascade -label Bisect -menu $m.bisect -state [expr {$root eq "" ? "disabled" : "normal"}]
        destroy $m.advanced
        menu $m.advanced
        $m.advanced add command -label "Reparent\u2026" -command [list tktimeline::reparent $rid]
        $m.advanced add command -label "Switch checkout here without merging\u2026" \
            -state [expr {$root eq "" ? "disabled" : "normal"}] \
            -command [list histops::switchKeep $::tktimeline::repo $root [dict get $r uuid] \
                "check-in [string range [dict get $r uuid] 0 9]" tktimeline::changedHere]
        $m.advanced add command -label "Purge this check-in and its descendants\u2026" \
            -state [expr {$root eq "" ? "disabled" : "normal"}] \
            -command [list histops::purgeCheckins $::tktimeline::repo $root [dict get $r uuid] \
                "check-in [string range [dict get $r uuid] 0 9]" tktimeline::changedHere]
        $m.advanced add command -label "Purge graveyard\u2026" \
            -command [list histops::graveyard $::tktimeline::repo tktimeline::changedHere]
        $m add cascade -label Advanced -menu $m.advanced
        $m add separator
        $m add command -label "Update checkout to this check-in\u2026" -command [list tktimeline::updateTo $rid] \
            -state [expr {$root eq "" ? "disabled" : "normal"}]
        # Merges into the checkout (as in Branches: dry run first, no pull).
        foreach {kind label} {checkin "Merge into checkout\u2026" cherrypick "Cherry-pick into checkout\u2026"
                backout "Back out in checkout\u2026"} {
            $m add command -label $label -command [list tktimeline::merge $kind $rid] \
                -state [expr {$root eq "" ? "disabled" : "normal"}]
        }
        $m add command -label "Save as archive\u2026" -command [list tktimeline::archive $rid]
    }
    if {[dict get $r private]} {
        $m add command -label "Make public\u2026" -command [list tktimeline::publish $rid]
    }
    if {[dict get $r ticket] ne ""} {
        $m add command -label "Show ticket" -command [list tktimeline::showTicket [dict get $r ticket]]
    }
    if {[dict get $r type] in {w e f}} {
        set script [goto::nameTarget [dict get $r uuid] artifact]
        $m add command -label [expr {[dict get $r type] eq "f" ? "Show in Forum" : "Show in Wiki"}] \
            -command $script -state [expr {$script eq "" ? "disabled" : "normal"}]
    }
    $m add command -label "Open in browser" -command [list tktimeline::openUrl info/[dict get $r uuid]]
    $m add separator
    $m add command -label "Search user:[dict get $r user]" \
        -command [list tktimeline::addTerm user [dict get $r user] 0]
    $m add command -label "Exclude user:[dict get $r user]" \
        -command [list tktimeline::addTerm user [dict get $r user] 1]
    if {[dict get $r branch] ne ""} {
        $m add command -label "Search branch:[dict get $r branch]" \
            -command [list tktimeline::addTerm branch [dict get $r branch] 0]
    }
    $m add command -label "Search kind:[dict get $kinds [dict get $r type]]" \
        -command [list tktimeline::addTerm kind [dict get $kinds [dict get $r type]] 0]
    $m add separator
    $m add command -label "Copy hash" -command [list ui::copy [dict get $r uuid]]
    $m add command -label "Copy comment" -command [list ui::copy [dict get $r comment]]
    $m add command -label "Show artifact" \
        -command [list histops::showArtifact $::tktimeline::repo [dict get $r uuid]]
    $m add command -label "Save artifact\u2026" -command [list tktimeline::saveArtifact $rid]
    tk_popup $m $X $Y
}

proc tktimeline::activateRow {rid} {
    variable rows
    if {$rid eq "" || ![info exists rows($rid)]} return
    set r $rows($rid)
    switch -- [dict get $r type] {
        ci { diff [dict get $r uuid] }
        t  { showTicket [dict get $r ticket] }
        w - e - f {
            # A wiki page, technote or forum post: in its tab.
            set script [goto::nameTarget [dict get $r uuid] artifact]
            if {$script ne ""} { uplevel #0 $script }
        }
    }
}

# ---------------------------------------------------------------- changes

# After a change of the repository: the list again, the same row.
proc tktimeline::changedHere {} {
    search
    after cancel {tktimeline::search}
    # (The same row selected: no event to show its details again.)
    showDetails [lindex [.timeline.main.list.t selection] 0]
}

proc tktimeline::rowUuid {rid} {
    variable rows
    dict get $rows($rid) uuid
}

proc tktimeline::editCheckin {rid} {
    variable repo
    tagwrite::amend $repo $rid tktimeline::changedHere
}

proc tktimeline::addTag {rid} {
    variable repo
    tagwrite::addTag $repo [rowUuid $rid] "" tktimeline::changedHere
}

proc tktimeline::cancelTag {rid name raw} {
    variable repo
    tagwrite::cancelTag $repo $name [rowUuid $rid] $raw tktimeline::changedHere
}

proc tktimeline::reparent {rid} {
    variable repo
    tagwrite::reparent $repo [rowUuid $rid] tktimeline::changedHere
}

# The tags on a check-in (as "fossil tag list CHECKIN"): {name value raw
# inherited propagating branch} each, its own first; branch: the name of
# a branch, now or before (the sym- tag a branch propagates).
proc tktimeline::checkinTags {rid} {
    variable repo
    set rows [fossil::sql $repo "SELECT [fossil::outcol t.tagname], coalesce([fossil::outcol x.value],''),
        x.tagtype, x.origid<>x.rid,
        t.tagname GLOB 'sym-*' AND EXISTS (SELECT 1 FROM tagxref b
            WHERE b.tagid=(SELECT tagid FROM tag WHERE tagname='branch') AND b.value=substr(t.tagname,5))
        FROM tagxref x JOIN tag t ON t.tagid=x.tagid
        WHERE x.rid=$rid AND x.tagtype>0 ORDER BY x.origid<>x.rid, t.tagname"]
    lmap row $rows {
        lassign $row name value type inherited branch
        set raw [expr {![string match sym-* $name]}]
        if {!$raw} { set name [string range $name 4 end] }
        list $name $value $raw $inherited [expr {$type == 2}] $branch
    }
}

# Save the artifact of an event (its manifest or control artifact) in a
# file ("fossil artifact HASH FILE").
# The parents, merged-from, children, merged-into check-ins of a check-in,
# and whether it is a leaf and closed, in the details D; each a link.
proc tktimeline::relations {d rid} {
    set links 0
    # (Cherry-picks and back-outs: the cherrypick table, as Fossil's /info.)
    set picks [llength [sql "SELECT 1 FROM sqlite_schema WHERE name='cherrypick'"]]
    foreach {label query} {
        Parent       "SELECT p.pid FROM plink p WHERE p.cid=$rid AND p.isprim"
        "Merged from" "SELECT p.pid FROM plink p WHERE p.cid=$rid AND NOT p.isprim"
        "Cherry-picked from" "SELECT parentid FROM cherrypick WHERE childid=$rid AND NOT isExclude"
        "Backs out"  "SELECT parentid FROM cherrypick WHERE childid=$rid AND isExclude"
        Child        "SELECT p.cid FROM plink p WHERE p.pid=$rid AND p.isprim"
        "Merged into" "SELECT p.cid FROM plink p WHERE p.pid=$rid AND NOT p.isprim"
        "Cherry-picked into" "SELECT childid FROM cherrypick WHERE parentid=$rid AND NOT isExclude"
        "Backed out by" "SELECT childid FROM cherrypick WHERE parentid=$rid AND isExclude"
    } {
        if {!$picks && [string match *cherrypick* $query]} continue
        set rows [sql "SELECT b.uuid, strftime('%Y-%m-%d %H:%M', e.mtime),
            [fossil::outcol "coalesce(e.euser,e.user,'')"],
            [fossil::outcol "coalesce((SELECT value FROM tagxref WHERE rid=e.objid AND tagtype>0
                AND tagid=(SELECT tagid FROM tag WHERE tagname='branch')),'')"]
            FROM blob b JOIN event e ON e.objid=b.rid WHERE b.rid IN ([subst $query]) ORDER BY e.mtime"]
        if {![llength $rows]} continue
        set n [llength $rows]
        if {$n > 1 && $label in {Parent Child}} { set label [dict get {Parent Parents Child Children} $label] }
        $d insert end "$label: " label
        set first 1
        foreach row $rows {
            lassign $row uuid date user branch
            if {!$first} { $d insert end ",  " }
            set first 0
            set tag rel[incr links]
            $d insert end [string range $uuid 0 9] [list link $tag]
            $d insert end " $date $user[expr {$branch ne "" ? " ($branch)" : ""}]" meta
            $d tag bind $tag <1> [list goto::checkin $uuid]
        }
        $d insert end \n
    }
    set leaf [llength [sql "SELECT 1 FROM leaf WHERE rid=$rid"]]
    set closed [llength [sql "SELECT 1 FROM tagxref WHERE rid=$rid AND tagtype>0
        AND tagid=(SELECT tagid FROM tag WHERE tagname='closed')"]]
    if {$leaf || $closed} {
        $d insert end "State: " label [join [concat [expr {$leaf ? "leaf" : {}}] \
            [expr {$closed ? "closed" : ($leaf ? "open" : {})}]] ", "] "" \n
    }
    $d insert end \n
}

# The check-in shown in the details as an archive (histops::archive).
proc tktimeline::archive {rid} {
    variable repo
    histops::archive $repo [rowUuid $rid]
}

# Make a private check-in public (and its files, tags).
proc tktimeline::publish {rid} {
    variable repo
    set uuid [rowUuid $rid]
    histops::publish $repo $uuid "check-in [string range $uuid 0 9]" tktimeline::changedHere
}

# Merge a check-in into the checkout (KIND checkin, cherrypick or backout),
# in the dialog of the Branches tab: the dry run first, its options.
proc tktimeline::merge {kind rid} {
    variable root
    if {$root eq ""} { bell; return }
    tkbranches::merge $kind [rowUuid $rid] $root tktimeline::changedHere
}

# Update the checkout to a check-in (as Branches does): the dry run first;
# never a pull (--nosync).
proc tktimeline::updateTo {rid} {
    variable root
    set uuid [rowUuid $rid]
    if {$root eq ""} return
    lassign [inCheckout update --nosync -n $uuid] code out
    if {$code} {
        tk_messageBox -icon error -title Update -message "fossil update failed (dry run):" -detail $out
        return
    }
    lassign [inCheckout changes] - changes
    set message "Update the checkout to [string range $uuid 0 9]?"
    if {[string trim $changes] ne ""} {
        append message "  Its uncommitted changes are merged into the new files, and can conflict."
    }
    if {![tagwrite::confirm Update $message "Dry run:\n$out" \
            -note "The files of the checkout change; nothing is committed, pulled or pushed."]} return
    lassign [inCheckout update --nosync $uuid] code out
    if {$code} {
        tk_messageBox -icon error -title Update -message "fossil update failed:" -detail $out
    }
    search
}

proc tktimeline::saveArtifact {rid} {
    variable repo
    set uuid [rowUuid $rid]
    set file [tk_getSaveFile -parent . -title "Save artifact" \
        -initialfile [string range $uuid 0 15].txt]
    if {$file eq ""} return
    lassign [fossil::run artifact -R $repo $uuid $file] code out
    if {$code} {
        tk_messageBox -icon error -title "Save artifact" -message "fossil artifact failed:" \
            -detail [string trim $out]
    }
}

# The tags the details also describe a check-in from (as fossil describe
# --match GLOB): asked, kept in the settings (describeMatch).
proc tktimeline::describeMatch {} {
    variable config
    variable matchAnswer
    set matchAnswer [getdef $config describeMatch core-*]
    set w [tagwrite::dialog .tagwrite "Describe from tags matching"]
    ttk::label $w.l -wraplength 460 -justify left -text "Besides the nearest tag, the details of\
        a check-in describe it from the nearest tag matching this pattern (fossil describe\
        --match), e.g. core-* for the Tcl/Tk releases; * or empty: none."
    ttk::entry $w.e -textvariable tktimeline::matchAnswer -width 30
    grid $w.l -sticky w -pady {0 6}
    grid $w.e -sticky w
    focus $w.e
    bind .tagwrite <Return> {set tagwrite::answer 1}
    if {![tagwrite::wait .tagwrite OK]} return
    set value [string trim $matchAnswer]
    if {$value eq ""} { set value * }
    dict set config describeMatch $value
    saveConfig
    showDetails [lindex [.timeline.main.list.t selection] 0]
}

# A check-in described from the nearest tag before it, as "fossil
# describe" (histops::describe: also without a checkout).
proc tktimeline::describe {uuid {match *}} {
    variable repo
    set rid [lindex [sql "SELECT rid FROM blob WHERE uuid=[fossil::sqlstr $uuid]"] 0 0]
    if {$rid eq ""} { return "" }
    histops::describe $repo $rid $match
}

proc tktimeline::inCheckout {args} {
    variable root
    fossil::run -dir $root {*}$args
}

# ----------------------------------------------------------------- window

proc tktimeline::build {} {
    variable config
    variable query
    variable history
    variable view
    menu .timeline.menu
    .timeline.menu add cascade -label File -underline 0 -menu [menu .timeline.menu.file]
    tktaalik::fileMenu .timeline.menu.file
    .timeline.menu.file add command -label "Pull\u2026" -underline 0 -command tktimeline::pull
    .timeline.menu.file add command -label "Describe from tags matching\u2026" -underline 0 \
        -command tktimeline::describeMatch
    .timeline.menu.file add command -label Refresh -underline 0 -accelerator F5 \
        -command tktimeline::search
    tktaalik::quitEntry .timeline.menu.file
    # Bisect (in the checkout): the checkout is marked good or bad.
    set m .timeline.menu.bisect
    .timeline.menu add cascade -label Bisect -underline 1 -menu [menu $m \
        -postcommand [list tktimeline::bisectMenu $m]]
    $m add command -label "Checkout is good" -underline 12 -command {tktimeline::bisect good}
    $m add command -label "Checkout is bad" -underline 12 -command {tktimeline::bisect bad}
    $m add command -label "Skip the checkout" -underline 0 -command {tktimeline::bisect skip}
    $m add command -label "Next" -underline 0 -command {tktimeline::bisect next}
    $m add command -label "Undo" -underline 0 -command {tktimeline::bisect undo}
    $m add command -label "Reset\u2026" -underline 0 -command {tktimeline::bisect reset}
    $m add separator
    $m add command -label "Status" -underline 1 -command {tktimeline::bisectInfo status}
    $m add command -label "Log" -underline 0 -command {tktimeline::bisectInfo log}
    $m add command -label "Chart" -underline 0 -command {tktimeline::bisectInfo chart}
    $m add command -label "Run a command\u2026" -underline 4 -command tktimeline::bisectCommand
    $m add separator
    $m add checkbutton -label "Next after each mark (auto-next)" -variable tktimeline::bisectOpt(auto-next) \
        -command {tktimeline::setBisectOption auto-next}
    $m add checkbutton -label "Primary parents only (direct-only)" -variable tktimeline::bisectOpt(direct-only) \
        -command {tktimeline::setBisectOption direct-only}
    $m add checkbutton -label "Linear scan (linear)" -variable tktimeline::bisectOpt(linear) \
        -command {tktimeline::setBisectOption linear}
    $m add cascade -label "After next, show" -menu [menu $m.display]
    foreach v {chart log status none} {
        $m.display add radiobutton -label $v -value $v -variable tktimeline::bisectOpt(display) \
            -command {tktimeline::setBisectOption display}
    }
    .timeline.menu add cascade -label Help -underline 0 -menu [menu .timeline.menu.help]
    .timeline.menu.help add command -label "Search syntax" -underline 0 \
        -command {help::show timeline search-syntax}
    menu .timeline.ctx

    ttk::frame .timeline.top -padding {6 6 6 0}
    ttk::combobox .timeline.top.q -textvariable tktimeline::query
    icons::button .timeline.top.go search "Search (Return)" {set tktaalik::typing ""; tktimeline::search 1}
    icons::button .timeline.top.clear clear "Clear the search (Escape)" \
        {tktaalik::navigate; set tktimeline::query ""; tktimeline::search}
    icons::button .timeline.top.help help "Search syntax (the manual)" {help::show timeline search-syntax}
    pack .timeline.top.help .timeline.top.clear .timeline.top.go -side right -padx {4 0}
    pack .timeline.top.q -fill x -expand 1
    ttk::frame .timeline.tabs -padding {6 4}
    foreach {v label} {all All lastpull "Last pull" outgoing Outgoing private Private} {
        ttk::radiobutton .timeline.tabs.$v -style Toolbutton -text $label \
            -variable tktimeline::view -value $v -command tktimeline::setView
        pack .timeline.tabs.$v -side left -padx {0 4}
    }

    ttk::panedwindow .timeline.main -orient vertical
    ttk::frame .timeline.main.list
    set t .timeline.main.list.t
    ttk::treeview $t -show headings -selectmode browse \
        -yscrollcommand {.timeline.main.list.y set} -xscrollcommand {.timeline.main.list.x set}
    ttk::scrollbar .timeline.main.list.y -command [list $t yview]
    ttk::scrollbar .timeline.main.list.x -orient horizontal -command [list $t xview]
    grid $t .timeline.main.list.y -sticky news
    grid .timeline.main.list.x -sticky ew
    grid columnconfigure .timeline.main.list 0 -weight 1
    grid rowconfigure .timeline.main.list 0 -weight 1
    $t tag configure unsent -foreground #a05000
    $t tag configure private -foreground #6a3d9a \
        -font [linsert [font actual TkDefaultFont] end -slant italic]
    $t tag configure current -font [linsert [font actual TkDefaultFont] end -weight bold]
    $t tag configure bisect-good -background #d8f0d8
    $t tag configure bisect-bad -background #f6d6d6
    $t tag configure bisect-skip -background #e4e4e4

    ttk::frame .timeline.main.details
    ttk::frame .timeline.main.details.buttons -padding {4 4 4 0}
    text .timeline.main.details.text -wrap word -height 10 -padx 8 -pady 6 -font TkTextFont \
        -state disabled -yscrollcommand {.timeline.main.details.y set}
    ttk::scrollbar .timeline.main.details.y -command {.timeline.main.details.text yview}
    grid .timeline.main.details.buttons - -sticky w
    grid .timeline.main.details.text .timeline.main.details.y -sticky news
    grid columnconfigure .timeline.main.details 0 -weight 1
    grid rowconfigure .timeline.main.details 1 -weight 1
    set d .timeline.main.details.text
    set size [font actual TkHeadingFont -size]
    $d tag configure title -font [linsert [font actual TkHeadingFont] end -size [expr {round($size * 1.2)}]]
    $d tag configure meta -foreground gray40
    $d tag configure label -foreground gray40
    $d tag configure unsent -foreground #a05000
    $d tag configure private -foreground #6a3d9a
    $d tag configure comment -font TkFixedFont
    # The check-ins related to the one shown (relations): links.
    $d tag configure link -foreground #0b57d0
    $d tag bind link <Enter> [list $d configure -cursor hand2]
    $d tag bind link <Leave> [list $d configure -cursor ""]
    $d tag configure added -foreground darkgreen
    $d tag configure deleted -foreground darkred
    $d tag configure changed -foreground gray40
    .timeline.main add .timeline.main.list -weight 3
    .timeline.main add .timeline.main.details -weight 2

    ttk::frame .timeline.bottom
    ttk::label .timeline.status -textvariable tktimeline::status -padding {6 2} -anchor w
    ttk::button .timeline.more -text "More" -command tktimeline::more
    pack .timeline.status -in .timeline.bottom -side left -fill x -expand 1

    pack .timeline.top -fill x
    pack .timeline.tabs -fill x
    pack .timeline.bottom -side bottom -fill x
    pack .timeline.main -fill both -expand 1

    # (Return ends the typing: the next key is a new place for Back.)
    bind .timeline.top.q <Return> {set tktaalik::typing ""; tktimeline::search 1}
    bind .timeline.top.q <KP_Enter> {set tktaalik::typing ""; tktimeline::search 1}
    bind .timeline.top.q <<ComboboxSelected>> {set tktaalik::typing ""; tktimeline::search 1}
    bind .timeline.top.q <Escape> {tktaalik::navigate; set tktimeline::query ""; tktimeline::search}
    bind $t <<TreeviewSelect>> {tktimeline::showDetails [lindex [.timeline.main.list.t selection] 0]}
    bind $t <Double-1> {
        if {[.timeline.main.list.t identify region %x %y] in {cell tree}} {
            tktimeline::activateRow [.timeline.main.list.t identify item %x %y]
        }
    }
    bind $t <Return> {tktimeline::activateRow [lindex [.timeline.main.list.t selection] 0]}
    bind $t <ButtonPress-3> {+tktimeline::contextMenu %x %y %X %Y}
    tktaalik::shortcut timeline <F5> tktimeline::search
    tktaalik::shortcut timeline <Control-f> {focus .timeline.top.q; .timeline.top.q selection range 0 end}

    loadConfig
    set table [getdef $config table {}]
    set kind {heading Kind width 9}
    if {![catch {$t tag cell has {}}]} {
        # Icons (Tk 9): as wide as the heading.
        dict set kind pixels [expr {max([icons::rowSize], [font measure TkDefaultFont "Kind \u25bc"]) + 12}]
        dict set kind anchor center
    }
    dict set kind tip "Check-in, ticket change, tag change,\nwiki, forum or technote edit"
    tablecols::setup $t [dict create \
        date    {heading Date width 16 dir desc} \
        kind    $kind \
        user    {heading User width 14} \
        branch  {heading Branch width 20} \
        ticket  {heading Ticket width 11} \
        hash    {heading Hash width 11} \
        comment {heading Comment width 60 stretch 1} \
    ] -fixed {date comment} -defaults {date kind user branch comment} \
        -celltip tktimeline::cellTip \
        -shown [getdef $table shown {}] \
        -order [getdef $table order {date kind user branch ticket hash comment}] \
        -sort [getdef $table sort {date desc}]
    set history [getdef $config history {}]
    .timeline.top.q configure -values $history
    set view [getdef $config view all]
    set query [getdef $config query ""]
    # (Settings of before the view was a term: the view into the query.)
    if {$view ne "all" && [lindex [splitView $query] 0] eq "all"} {
        set query [string trim "$query [viewTerm $view]"]
    }
    # Searched while typing, a moment after the last key.
    trace add variable ::tktimeline::query write {::apply {args {
        tktaalik::typing .timeline.top.q
        after cancel {tktimeline::search}
        after 300 {tktimeline::search}
    }}}
}

# The icon of an event type (lib/icons.tcl).
proc tktimeline::kindIcon {type} {
    dict get {ci k-checkin t k-ticket g k-tag w k-wiki f k-forum e k-technote} $type
}

# The tooltip of a kind cell: the kind; of a check-in's hash: its
# description (tablecols -celltip).
proc tktimeline::cellTip {rid key} {
    variable rows
    variable kinds
    if {![info exists rows($rid)]} { return "" }
    # A check-in's hash: where it is from the nearest tag ("fossil describe").
    if {$key eq "hash" && [dict get $rows($rid) type] eq "ci"} {
        return [describe [dict get $rows($rid) uuid]]
    }
    if {$key ne "kind"} { return "" }
    # Not when it shows the word (Tk 8.6).
    if {[.timeline.main.list.t set $rid kind] ne ""} { return "" }
    string totitle [dict get $kinds [dict get $rows($rid) type]]
}

# Where we are (tktaalik::location): the query and view of the list, the row.
proc tktimeline::here {} {
    variable searched
    list {*}$searched [lindex [.timeline.main.list.t selection] 0]
}

# Back or Forward to a place of here.
proc tktimeline::goTo {place} {
    variable query
    variable view
    lassign $place q v rid
    # (A place of before the view was a term: the view into the query.)
    if {$v ni {"" all} && [lindex [splitView $q] 0] eq "all"} {
        set q [string trim "$q [viewTerm $v]"]
    }
    set query $q
    search
    after cancel {tktimeline::search}
    set t .timeline.main.list.t
    if {$rid ne "" && [$t exists $rid]} {
        $t selection set $rid
        $t focus $rid
        $t see $rid
    }
}

proc tktimeline::setRepository {path newRoot} {
    variable repo $path
    variable root $newRoot
    variable me
    variable remote
    variable limit 1000
    lassign [fossil::run user default -R $repo] code me
    if {$code} { set me "" }
    set remote ""
    lassign [fossil::run remote -R $repo] code url
    if {!$code && [regexp {^https?://} $url]} {
        regsub {^(https?://)[^/@]*@} [string trim $url] {\1} remote
    }
    set project [lindex [sql "SELECT value FROM config WHERE name='project-name'"] 0 0]
    if {$project eq ""} { set project [file rootname [file tail $repo]] }
    tktaalik::setTitle timeline "Timeline \u2014 $project"
    search
    after cancel {tktimeline::search}
}

# Search for $q (from another tab): the All view unless it has a view term.
proc tktimeline::setQuery {q} {
    variable query
    set query $q
    search 1
    after cancel {tktimeline::search}
}

proc tktimeline::activate {} {
    if {[tktaalik::changed timeline]} { search }
    focus .timeline.main.list.t
}

source [file join [file dirname [file normalize [info script]]] bisect.tcl]
source [file join [file dirname [file normalize [info script]]] pull.tcl]
