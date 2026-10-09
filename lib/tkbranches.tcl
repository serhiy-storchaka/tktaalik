# The Branches tab of tktaalik: the branches of the repository.
#
# The list shows for each branch whether it is merged into the main
# branches ("targets": main, core-9-0-branch, core-8-6-branch, ...), and
# below it the check-ins, the changed files and the tickets of the
# selected branch.
#
# With a checkout, a branch can be checked out (fossil update --nosync) or
# merged into it (fossil merge, after a dry run); a merge is not committed
# here: the Commit tab does that.  Closing, reopening and hiding branches
# and new branches write control artifacts into the local repository,
# after a confirmation.  Nothing is pushed: these are refused while
# autosync is on.  Settings: ~/.config/tktaalik/branches.conf.

source [file join [file dirname [file normalize [info script]]] config.tcl]
source [file join [file dirname [file normalize [info script]]] fossil.tcl]
source [file join [file dirname [file normalize [info script]]] tablecols.tcl]
source [file join [file dirname [file normalize [info script]]] searchterms.tcl]
source [file join [file dirname [file normalize [info script]]] histops.tcl]

namespace eval tkbranches {
    variable repo ""            ;# the repository file
    variable root ""            ;# the checkout's top directory, or ""
    variable current ""         ;# the branch of the checkout
    variable me ""              ;# the default user
    variable remote ""          ;# the server, for the browser
    variable project ""
    variable targets {}         ;# the branches merges into are shown
    variable branches           ;# array: name -> dict of its fields
    variable view open          ;# open unmerged mine closed all
    variable query ""           ;# the search
    variable history {}         ;# earlier searches, the latest first
    variable terms {}           ;# the parsed search: {neg key alternatives}...
    variable showHidden 0
    variable privateOnly 0
    variable selected ""        ;# the branch in the details
    variable searched ""        ;# the query of the list shown
    variable shown {}           ;# the query, view and options of the list shown
    variable header ""          ;# the line above the details
    variable status ""          ;# the status line
    variable statusTail ""      ;# its part after the number of branches
    variable filesPipe ""       ;# the running "fossil diff --numstat" (fossil::start)
    variable config {}
    variable configFile [config::path branches]

    # The targets if the settings have none for the repository: those of
    # these that it has open.
    variable defaultTargets {main trunk core-9-0-branch core-8-branch core-8-6-branch}

}

# ------------------------------------------------------------- settings

proc tkbranches::loadConfig {} {
    variable configFile
    variable config
    set config [config::get $configFile branches tkbranches.conf]
}

proc tkbranches::getdef {dict key default} {
    expr {[dict exists $dict $key] ? [dict get $dict $key] : $default}
}

proc tkbranches::saveConfig {} {
    variable configFile
    variable config
    variable view
    variable showHidden
    variable query
    variable history
    if {[winfo exists .branches.main.list.t]} {
        dict set config table [tablecols::state .branches.main.list.t]
    }
    dict set config view $view
    dict set config showHidden $showHidden
    dict set config query $query
    dict set config history $history
    config::put $configFile $config {table targets}
}

# ------------------------------------------------------------ repository

proc tkbranches::sql {statement} {
    variable repo
    fossil::sql $repo $statement
}

# Use the repository ($root: its checkout, or "").  Returns 1 on success.
# Where we are (tktaalik::location): the query, view and options of the list,
# the branch.
proc tkbranches::here {} {
    variable shown
    variable selected
    list {*}$shown $selected
}

# Back or Forward to a place of here.
proc tkbranches::goTo {place} {
    variable query
    variable view
    variable showHidden
    variable privateOnly
    lassign $place q v hidden private name
    if {$v ne ""} {
        set showHidden $hidden
        # (The view and Private only are terms of the query; a place
        # without them has them here.)
        if {$v ne "all" && [stripView $q] eq [string trim $q]} { set q [string trim "$q [viewTerms $v]"] }
        if {$private && ![regexp -nocase {(^|\s)is:private(\s|$)} $q]} { set q [string trim "$q is:private"] }
    }
    set query $q
    search
    after cancel {tkbranches::search}
    set t .branches.main.list.t
    if {$name ne "" && [$t exists $name]} {
        $t selection set $name
        $t focus $name
        $t see $name
    }
}

proc tkbranches::setRepository {path newRoot} {
    variable repo
    variable root
    variable me
    variable remote
    variable project
    variable targets
    variable config
    variable defaultTargets
    set old [list $repo $root]
    set repo $path
    set root $newRoot
    # The project, the default user, the remote, and which of the usual
    # targets are open branches (their newest check-in is not closed): in
    # one query, not one fossil process each.
    set usual [join [lmap t $defaultTargets { fossil::sqlstr $t }] ,]
    try {
        set rows [sql "SELECT name, [fossil::outcol value] FROM config
            WHERE name IN ('project-name','default-user','last-sync-url')
            UNION ALL SELECT 'open', [fossil::outcol name] FROM (
             SELECT x.value AS name, x.rid AS rid, max(e.mtime)
             FROM tagxref x JOIN event e ON e.objid=x.rid
             WHERE x.tagid=(SELECT tagid FROM tag WHERE tagname='branch') AND x.tagtype>0
              AND x.value IN ($usual) GROUP BY x.value) AS t
            WHERE NOT EXISTS(SELECT 1 FROM tagxref c WHERE c.rid=t.rid AND c.tagtype>0
             AND c.tagid=(SELECT tagid FROM tag WHERE tagname='closed'))"]
    } trap {FOSSIL DB} msg {
        lassign $old repo root
        tk_messageBox -icon error -title Branches -message "Cannot read the repository:" \
            -detail "$path\n$msg"
        return 0
    }
    set project ""
    set me ""
    set remote ""
    set open {}
    foreach row $rows {
        lassign $row name value
        switch -- $name {
            project-name  { set project $value }
            default-user  { set me $value }
            last-sync-url {
                if {[regexp {^https?://} $value]} {
                    regsub {^(https?://)[^/@]*@} [string trim $value] {\1} remote
                }
            }
            open          { lappend open $value }
        }
    }
    if {$project eq ""} { set project [file rootname [file tail $repo]] }
    if {$me eq ""} {
        # Not set in the repository: Fossil also looks elsewhere (the global
        # settings, the login name).
        lassign [fossil::run user default -R $repo] code out
        set me [expr {$code ? "" : [string trim $out]}]
    }
    # The targets: as set for this repository, else the usual ones.
    if {[dict exists $config targets $repo]} {
        set targets [dict get $config targets $repo]
    } else {
        set targets [lmap b $defaultTargets { if {$b ni $open} continue; set b }]
        if {"main" in $targets && "trunk" in $targets} {
            set targets [lsearch -all -inline -not -exact $targets trunk]
        }
    }
    tktaalik::setTitle branches "Branches \u2014 $project[expr {$root ne "" ? " \u2014 [file tail $root]" : ""}]"
    setupColumns
    reload
    return 1
}

# Run fossil in the checkout.
proc tkbranches::inCheckout {args} {
    variable root
    fossil::run -dir $root {*}$args
}

# A short heading for a target: "9.0" for core-9-0-branch.
proc tkbranches::targetHeading {name} {
    if {[regexp {^core-([0-9]+(?:-[0-9]+)*)-branch$} $name -> v]} {
        return [string map {- .} $v]
    }
    return $name
}

# --------------------------------------------------------------- loading

# One query for all branches.  A check-in's branch is its "branch" tag;
# the last check-in is the tip.  A branch is closed or hidden if its tip
# is.  "Merged into T": its check-ins among the ancestors of T's tip.
# The check-ins of the branches (ci), the newest of each (tip): the start
# of both queries.
proc tkbranches::branchCtes {} {
    return "tg(branch, closed, hidden) AS MATERIALIZED (SELECT
      (SELECT tagid FROM tag WHERE tagname='branch'),
      (SELECT tagid FROM tag WHERE tagname='closed'),
      (SELECT tagid FROM tag WHERE tagname='hidden')),
     ci(rid, name, mtime, user) AS MATERIALIZED (
      SELECT x.rid, x.value, e.mtime, coalesce(e.euser, e.user)
      FROM tagxref x JOIN event e ON e.objid=x.rid, tg
      WHERE x.tagid=tg.branch AND x.tagtype>0 AND e.type='ci'),
     tip(name, rid, mtime, n) AS MATERIALIZED (
      SELECT name, rid, max(mtime), count(*) FROM ci GROUP BY name)"
}

# The merge states of the branches into a target ("Merged into T": its
# check-ins among the ancestors of T's tip): a row per branch merged, 2 for
# its tip, 1 for earlier check-ins only.  The slowest part (a walk of the
# history from T's tip), so a query of its own for each target, all run
# beside the other one.
proc tkbranches::mergeQuery {target} {
    set t [fossil::sqlstr $target]
    return "WITH RECURSIVE [branchCtes],
     anc(rid) AS MATERIALIZED (
      SELECT rid FROM tip WHERE name=$t
      UNION SELECT plink.pid FROM anc JOIN plink ON plink.cid=anc.rid)
    SELECT [fossil::outcol ci.name], 1+max(ci.rid=tip.rid)
    FROM ci JOIN tip USING(name) JOIN anc ON anc.rid=ci.rid
    WHERE ci.name<>$t GROUP BY ci.name"
}

# All branches: one row each, without the merge states (mergeQuery).
proc tkbranches::branchQuery {} {
    return "WITH RECURSIVE [branchCtes],
     first(name, rid, mtime) AS MATERIALIZED (
      SELECT name, rid, min(mtime) FROM ci GROUP BY name),
     users(name, list) AS MATERIALIZED (
      SELECT name, group_concat(user, char(2)) FROM (SELECT DISTINCT name, user FROM ci)
      GROUP BY name),
     leaves(name, n) AS MATERIALIZED (
      SELECT ci.name, count(*) FROM leaf JOIN ci USING(rid), tg
      WHERE NOT EXISTS(SELECT 1 FROM tagxref WHERE rid=leaf.rid AND tagid=tg.closed AND tagtype>0)
      GROUP BY ci.name),
     core(name, state, list) AS MATERIALIZED (
      SELECT name, max(state), group_concat(tagname, char(2)) FROM (
       SELECT DISTINCT ci.name, 1+(ci.rid=tip.rid) AS state, substr(t.tagname,5) AS tagname
       FROM ci JOIN tip USING(name) CROSS JOIN tagxref x ON x.rid=ci.rid AND x.tagtype=1
       CROSS JOIN tag t ON t.tagid=x.tagid
       WHERE t.tagname GLOB 'sym-core-*' AND t.tagname<>'sym-'||ci.name)
      GROUP BY name),
     comments(name, text) AS MATERIALIZED (
      SELECT ci.name, group_concat(coalesce(e.ecomment,e.comment), char(2))
      FROM ci JOIN event e ON e.objid=ci.rid GROUP BY ci.name),
     tickets(name, list) AS MATERIALIZED (
      SELECT name, group_concat(id, char(2)) FROM (
       SELECT DISTINCT ci.name, substr(t.tkt_uuid,1,10) AS id FROM ci
       CROSS JOIN backlink b ON b.srcid=ci.rid AND b.srctype=0
       CROSS JOIN ticket t ON t.tkt_uuid>=b.target AND t.tkt_uuid<b.target||'g')
      GROUP BY name)
    SELECT [fossil::outcol tip.name], strftime('%Y-%m-%d %H:%M',tip.mtime),
     strftime('%Y-%m-%d %H:%M',first.mtime), tip.n,
     [fossil::outcol users.list],
     EXISTS(SELECT 1 FROM tagxref WHERE rid=tip.rid AND tagid=tg.closed AND tagtype>0),
     EXISTS(SELECT 1 FROM tagxref WHERE rid=tip.rid AND tagid=tg.hidden AND tagtype>0),
     EXISTS(SELECT 1 FROM private WHERE rid=tip.rid),
     coalesce([fossil::outcol "(SELECT x.value FROM plink p JOIN tagxref x ON x.rid=p.pid
       AND x.tagid=tg.branch AND x.tagtype>0 WHERE p.cid=first.rid AND p.isprim)"],''),
     coalesce(leaves.n,0), coalesce(core.state,0), coalesce([fossil::outcol core.list],''),
     coalesce(tickets.list,''),
     (SELECT uuid FROM blob WHERE rid=tip.rid),
     [fossil::outcol "(SELECT coalesce(ecomment,comment) FROM event WHERE objid=tip.rid)"],
     coalesce([fossil::outcol comments.text],'')
    FROM tip JOIN first USING(name) JOIN users USING(name)
     LEFT JOIN leaves USING(name) LEFT JOIN core USING(name) LEFT JOIN tickets USING(name)
     LEFT JOIN comments USING(name), tg"
}

# Read all branches, then show them.
proc tkbranches::reload {} {
    variable branches
    variable targets
    variable root
    variable current
    variable repo
    set busy [ui::busyHold]
    # The merge states in other processes, one for each target, beside the
    # rest: mstate(TARGET,BRANCH).
    array set mstate {}
    set chans {}
    try {
        foreach t $targets { lappend chans $t [fossil::sqlStart $repo [mergeQuery $t]] }
        set rows [sql [branchQuery]]
        foreach {t chan} $chans {
            foreach row [fossil::sqlFinish $chan] { set mstate($t,[lindex $row 0]) [lindex $row 1] }
        }
    } trap {FOSSIL DB} msg {
        tk_messageBox -icon error -title Branches -message "Cannot read the branches:" -detail $msg
        set rows {}
    } finally {
        foreach {t chan} $chans {
            if {$chan in [chan names]} { catch {close $chan} }
        }
        ui::busyRelease $busy
    }
    array unset branches
    variable currentMergedOf ""
    foreach row $rows {
        lassign $row name updated created checkins users closed hidden private \
            base forks ci citags tickets tip comment comments
        set merged [lmap t $targets {
            expr {[info exists mstate($t,$name)] ? $mstate($t,$name) : 0}
        }]
        set b [dict create name $name updated $updated created $created checkins $checkins \
            users [split $users \x02] closed $closed hidden $hidden private $private \
            base $base forks $forks ci $ci citags [split $citags \x02] \
            tickets [split $tickets \x02] tip $tip comment $comment]
        # For the search: lower case, all check-in comments.
        dict set b lname [string tolower $name]
        dict set b lusers [string tolower [dict get $b users]]
        dict set b lbase [string tolower $base]
        dict set b comments [string tolower $comments]
        foreach t $targets state $merged { dict set b merged $t $state }
        set branches($name) $b
    }
    set current ""
    if {$root ne ""} {
        lassign [inCheckout branch current] code out
        if {!$code} { set current [string trim $out] }
    }
    # The search again: merged: depends on the targets.
    variable query
    variable terms
    variable searched
    set searched $query
    set error ""
    try {
        set terms [parseSearch $query]
    } trap {TKFOSSIL QUERY} msg {
        set terms {}
        set error $msg
    }
    showList
    updateStatus
    if {$error ne ""} { showError $error }
}

# --------------------------------------------------------------- the list

proc tkbranches::setupColumns {{newTargets 0}} {
    variable targets
    variable config
    set cols {
        name     {heading Branch width 30}
        updated  {heading Updated width 16 dir desc tip "Time of the last check-in"}
        created  {heading Created width 16 dir desc tip "Time of the first check-in"}
        checkins {heading Check-ins width 10 type integer dir desc anchor e}
        users    {heading Users width 20 tip "Users with check-ins on the branch"}
        base     {heading Base width 16 tip "The branch it was made from"}
    }
    set i 0
    foreach t $targets {
        dict set cols m$i [list heading [targetHeading $t] width 6 type integer dir desc \
            anchor center tip "Merged into $t:\n\u2713 the last check-in\n\u25d0 only earlier check-ins"]
        incr i
    }
    dict set cols forks {heading Forks width 6 type integer dir desc anchor center
        tip "Open leaves, if more than one"}
    dict set cols tickets {heading Tickets width 12 type integer dir desc
        tip "Tickets mentioned in the check-in comments"}
    dict set cols ci {heading CI width 5 type integer dir desc anchor center
        tip "A core-* tag (built by CI):\n\u2713 on the last check-in\n\u25d0 only on an earlier one"}
    dict set cols state {heading State width 10}
    dict set cols tip {heading Tip width 11 tip "The last check-in"}
    dict set cols comment {heading "Last comment" width 40 stretch 1}
    set defaults [list updated checkins base \
        {*}[lmap k [dict keys $cols] { if {![string match m* $k]} continue; set k }] \
        forks tickets ci comment]
    # The columns as they are now, else as saved.
    if {[info exists ::tablecols::columns(.branches.main.list.t)]} {
        set table [tablecols::state .branches.main.list.t]
    } else {
        set table [getdef $config table {}]
    }
    set shown [getdef $table shown {}]
    set order [getdef $table order {}]
    if {$newTargets && [llength $shown]} {
        # Show all target columns, together where the first one was.
        set new [lmap k [dict keys $cols] { if {![string match m* $k]} continue; set k }]
        set shown [withTargets $shown $new]
        set order [withTargets $order $new]
    }
    tablecols::setup .branches.main.list.t $cols -fixed name -defaults $defaults \
        -shown $shown -order $order -celltip tkbranches::cellTip \
        -sort [getdef $table sort {updated desc}]
}

# $keys with the target columns replaced by $new, where the first was
# (else after the base).
proc tkbranches::withTargets {keys new} {
    set i [lsearch -glob $keys m*]
    if {$i < 0} { set i [expr {[lsearch -exact $keys base] + 1}] }
    if {$i <= 0} { set i [llength $keys] }
    set rest [lmap k $keys { if {[string match m* $k]} continue; set k }]
    set i [expr {min($i, [llength $rest])}]
    linsert $rest $i {*}$new
}

# Is branch $b shown in view $v?
proc tkbranches::inView {b v} {
    variable me
    variable targets
    if {$v eq "closed"} { return [dict get $b closed] }
    if {$v eq "all"} { return 1 }
    if {[dict get $b closed]} { return 0 }
    switch -- $v {
        unmerged {
            set t [lindex $targets 0]
            expr {$t ne "" && [dict get $b name] ne $t && [dict get $b merged $t] != 2}
        }
        mine { expr {$me ne "" && $me in [dict get $b users]} }
        default { return 1 }
    }
}

proc tkbranches::matches {b} {
    variable terms
    variable showHidden
    variable privateOnly
    if {[dict get $b hidden] && !$showHidden && ![wantsHidden]} { return 0 }
    if {$privateOnly && ![dict get $b private]} { return 0 }
    foreach term $terms {
        lassign $term neg key alts
        if {[termMatches $b $key $alts] == $neg} { return 0 }
    }
    return 1
}

# ----------------------------------------------------------------- search

# The search runs on the loaded branches.  A term is {neg key alternatives},
# the alternatives prepared by parseQuery.

proc tkbranches::parseQuery {query} {
    variable targets
    variable me
    set terms {}
    foreach token [terms::tokenize $query] {
        lassign $token neg key value
        if {$key eq ""} {
            # A word, not split at commas.
            lappend terms [list $neg "" [list [string tolower $value]]]
            continue
        }
        if {$value eq ""} { terms::error "empty value for $key:" }
        set alts [lmap a [split $value ,] {
            set a [string trim $a]
            if {$a eq ""} continue
            set a
        }]
        if {![llength $alts]} { terms::error "empty value for $key:" }
        switch -- $key {
            name - comment - base - ticket {
                set alts [lmap a $alts { string tolower $a }]
            }
            user {
                set alts [lmap a $alts {
                    if {[string tolower $a] eq "@me"} {
                        if {$me eq ""} { terms::error "@me: this repository has no default user" }
                        set a $me
                    }
                    string tolower $a
                }]
            }
            merged {
                # A target by its name or its heading: main, 9.0, core-9-0-branch;
                # @current: the branch of the checkout.
                set alts [lmap a $alts {
                    set found ""
                    if {[string tolower $a] eq "@current"} {
                        variable current
                        if {$current eq ""} { terms::error "merged:@current: there is no checkout" }
                        # (Not a target: what is merged into it, read now.)
                        if {$current in $targets} {
                            set found $current
                        } else {
                            mergedInto $current
                            set found @current
                        }
                    }
                    foreach t [expr {$found eq "" ? $targets : {}}] {
                        if {[string equal -nocase $a $t]
                                || [string equal -nocase $a [targetHeading $t]]} {
                            set found $t
                        }
                    }
                    if {$found eq ""} {
                        terms::error "merged:$a: not a merge target; the targets are\
                            [join [lmap t $targets { targetHeading $t }] {, }]\
                            (File \u25b8 Merge targets)"
                    }
                    set found
                }]
            }
            is - has {
                set known [dict get {
                    is {open closed hidden private current forked leaf}
                    has {tickets ci forks}
                } $key]
                set alts [lmap a $alts {
                    set a [string tolower $a]
                    if {$a ni $known} {
                        terms::error "$key:$a: use $key:[join $known ,$key:]"
                    }
                    set a
                }]
            }
            updated - created { set alts [lmap a $alts { terms::dateSpec $a }] }
            descendant { set alts [lmap a $alts { descendantBranches $a }] }
            checkins { set alts [lmap a $alts { terms::numberSpec $a }] }
            default {
                terms::error "unknown key \"$key:\"; see Help \u25b8 About the list"
            }
        }
        lappend terms [list $neg $key $alts]
    }
    return $terms
}

# merged:@current when the branch of the checkout is not a merge target:
# what is merged into it (as fossil branch list -m), read once for it.
proc tkbranches::mergedInto {branch} {
    variable repo
    variable currentMerged
    variable currentMergedOf
    if {[info exists currentMergedOf] && $currentMergedOf eq "$repo\n$branch"} return
    set currentMerged {}
    foreach row [sql [mergeQuery $branch]] { dict set currentMerged [lindex $row 0] [lindex $row 1] }
    set currentMergedOf $repo\n$branch
}

# descendant:NAME: the branches with check-ins descended from the check-in
# NAME names (a tag or a branch: its newest check-in; or a hash prefix),
# as a dict name -> 1.
proc tkbranches::descendantBranches {name} {
    set rows [sql "SELECT x.rid FROM tagxref x JOIN event e ON e.objid=x.rid
        WHERE x.tagtype>0 AND e.type='ci'
        AND x.tagid=(SELECT tagid FROM tag WHERE tagname=[fossil::sqlstr sym-$name])
        ORDER BY e.mtime DESC LIMIT 1"]
    if {![llength $rows] && [regexp {^[0-9a-fA-F]{4,64}$} $name]} {
        set rows [sql "SELECT rid FROM blob WHERE uuid GLOB [fossil::sqlstr [string tolower $name]*]
            AND rid IN (SELECT objid FROM event WHERE type='ci') LIMIT 2"]
        if {[llength $rows] > 1} { terms::error "descendant:$name: more than one check-in" }
    }
    if {![llength $rows]} { terms::error "descendant:$name: no such check-in, tag or branch" }
    set rid [lindex $rows 0 0]
    set names {}
    foreach row [sql "WITH RECURSIVE d(rid) AS (
          SELECT cid FROM plink WHERE pid=$rid
          UNION SELECT plink.cid FROM d JOIN plink ON plink.pid=d.rid)
        SELECT DISTINCT [fossil::outcol x.value] FROM d JOIN tagxref x ON x.rid=d.rid
        WHERE x.tagtype>0 AND x.tagid=(SELECT tagid FROM tag WHERE tagname='branch')"] {
        dict set names [lindex $row 0] 1
    }
    return $names
}

# Does the search ask for hidden branches?
proc tkbranches::wantsHidden {} {
    variable terms
    foreach term $terms {
        lassign $term neg key alts
        if {!$neg && $key eq "is" && "hidden" in $alts} { return 1 }
    }
    return 0
}

proc tkbranches::termMatches {b key alts} {
    foreach a $alts {
        if {[altMatches $b $key $a]} { return 1 }
    }
    return 0
}

proc tkbranches::altMatches {b key a} {
    variable current
    switch -- $key {
        "" {
            if {[terms::isGlob $a]} { return [string match $a [dict get $b lname]] }
            expr {[string first $a [dict get $b lname]] >= 0
                || [string first $a [dict get $b comments]] >= 0}
        }
        name {
            if {[terms::isGlob $a]} { return [string match $a [dict get $b lname]] }
            expr {[string first $a [dict get $b lname]] >= 0}
        }
        comment { expr {[string first $a [dict get $b comments]] >= 0} }
        user    { expr {$a in [dict get $b lusers]} }
        base {
            if {[terms::isGlob $a]} { return [string match $a [dict get $b lbase]] }
            expr {$a eq [dict get $b lbase]}
        }
        merged  {
            if {$a eq "@current"} {
                variable currentMerged
                variable current
                return [expr {[dict get $b name] eq $current
                    || ([dict exists $currentMerged [dict get $b name]] && [dict get $currentMerged [dict get $b name]] == 2)}]
            }
            expr {[dict get $b name] eq $a || [dict get $b merged $a] == 2}
        }
        ticket {
            foreach id [dict get $b tickets] {
                if {[string match $a* $id]} { return 1 }
            }
            return 0
        }
        is {
            switch -- $a {
                open    { expr {![dict get $b closed]} }
                current { expr {[dict get $b name] eq $current} }
                forked  { expr {[dict get $b forks] > 1} }
                leaf    { expr {[dict get $b forks] > 0} }
                default { dict get $b $a }
            }
        }
        has {
            switch -- $a {
                tickets { expr {[llength [dict get $b tickets]] > 0} }
                ci      { expr {[dict get $b ci] > 0} }
                forks   { expr {[dict get $b forks] > 1} }
            }
        }
        updated - created {
            lassign $a lo hi
            set day [string range [dict get $b $key] 0 9]
            expr {($lo eq "" || [string compare $day $lo] >= 0)
                && ($hi eq "" || [string compare $day $hi] < 0)}
        }
        descendant { dict exists $a [dict get $b name] }
        checkins {
            lassign $a lo hi
            set n [dict get $b checkins]
            expr {($lo eq "" || $n >= $lo) && ($hi eq "" || $n <= $hi)}
        }
    }
}

# Search: parse the query, then show the matching branches.  Errors go to
# the status line, the list stays as it was.  With $remember, the search is
# added to the history.
proc tkbranches::search {{remember 0}} {
    variable query
    variable searched
    set searched $query
    variable terms
    variable history
    after cancel {tkbranches::search}
    try {
        set terms [parseSearch $query]
    } trap {TKFOSSIL QUERY} msg {
        showError $msg
        return
    }
    set q [string trim $query]
    if {$remember && $q ne ""} {
        set history [lrange [linsert [lsearch -all -inline -not -exact $history $q] 0 $q] 0 19]
        .branches.top.q configure -values $history
    }
    showList
}

# The branches with check-ins descended from a check-in: a new search.
proc tkbranches::showDescendants {uuid} {
    variable query
    tktaalik::navigate
    set query descendant:[string range $uuid 0 15]
    search 1
}

proc tkbranches::showError {msg} {
    variable status
    set status "Search: $msg"
    .branches.status configure -foreground red3
}

# Add a term to the search, e.g. from the context menu.
proc tkbranches::addTerm {key value neg} {
    variable query
    tktaalik::navigate
    if {[regexp {[\s,"]} $value]} { set value "\"$value\"" }
    set term [expr {$neg ? "-" : ""}]$key:$value
    if {$term ni [regexp -all -inline {\S+} $query]} {
        set query [string trim "$query $term"]
    }
    search 1
}

# The terms of a search, and its view: the view (the buttons) is terms of
# the query: the first is:open or is:closed; with is:open, -merged:TARGET
# (the first merge target) is Unmerged, else user:@me (or the default user
# by name) is Mine.  They filter as the view, and the buttons count the
# rest.  None: All.
proc tkbranches::parseSearch {query} {
    variable view
    variable me
    variable targets
    set terms [parseQuery $query]
    # Private only: the term is:private (it filters as a term).
    variable privateOnly
    set privateOnly [expr {[findTerm $terms 0 is private] >= 0}]
    set view all
    set i [findTerm $terms 0 is {open closed}]
    if {$i < 0} { return $terms }
    set view [lindex $terms $i 2 0]
    set terms [lreplace $terms $i $i]
    if {$view ne "open"} { return $terms }
    set i [findTerm $terms 1 merged [lrange $targets 0 0]]
    if {$i >= 0} {
        set view unmerged
        return [lreplace $terms $i $i]
    }
    set i [expr {$me eq "" ? -1 : [findTerm $terms 0 user [list [string tolower $me]]]}]
    if {$i >= 0} {
        set view mine
        return [lreplace $terms $i $i]
    }
    return $terms
}

# The index of the first term NEG KEY:VALUE with one value, one of VALUES;
# -1 if none.
proc tkbranches::findTerm {terms neg key values} {
    set i 0
    foreach term $terms {
        lassign $term n k alts
        if {$n == $neg && $k eq $key && [llength $alts] == 1 && [lindex $alts 0] in $values} {
            return $i
        }
        incr i
    }
    return -1
}

# The Open/Unmerged/Mine/Closed/All buttons: the same search with another
# view's terms (is:open, is:open -merged:TARGET, is:open user:@me,
# is:closed; none for All), in place of those of the view shown.
proc tkbranches::setView {} {
    variable query
    variable view
    variable shown
    tktaalik::navigate
    # (The view of the list shown: the button has already changed $view.)
    set rest [stripView $query [lindex $shown 1]]
    set query [string trim "$rest [viewTerms $view]"]
    search
}

# Private only: the term is:private added to the search, or taken out.
proc tkbranches::setPrivate {} {
    variable query
    variable privateOnly
    set on $privateOnly
    tktaalik::navigate
    set words [lmap word [regexp -all -inline {(?:[^\s"]|"[^"]*")+} $query] {
        if {[string equal -nocase $word is:private]} continue
        set word
    }]
    if {$on} { lappend words is:private }
    set query [join $words]
    search
}

# QUERY without the terms of view SHOWN (is:open or is:closed, and the
# -merged:TARGET of Unmerged or the user:@me of Mine), the rest as it was
# typed.  SHOWN "": only is:open and is:closed.
proc tkbranches::stripView {query {shown ""}} {
    variable me
    variable targets
    set target [lindex $targets 0]
    join [lmap word [regexp -all -inline {(?:[^\s"]|"[^"]*")+} $query] {
        if {[regexp -nocase {^is:(open|closed)$} $word]} continue
        if {$shown eq "mine" && ([string equal -nocase $word user:@me]
                || ($me ne "" && [string equal -nocase $word user:$me]))} continue
        if {$shown eq "unmerged" && $target ne ""
                && ([string equal -nocase $word -merged:$target]
                || [string equal -nocase $word -merged:[targetHeading $target]])} continue
        set word
    }]
}

# The terms of view V: "" for All.
proc tkbranches::viewTerms {v} {
    variable targets
    switch -- $v {
        open     { return is:open }
        unmerged {
            set target [lindex $targets 0]
            if {$target eq ""} { return is:open }
            return "is:open -merged:[targetHeading $target]"
        }
        mine     { return "is:open user:@me" }
        closed   { return is:closed }
        default  { return "" }
    }
}

# The tooltip of a merge, CI or forks cell (tablecols -celltip).
proc tkbranches::cellTip {name key} {
    variable branches
    variable targets
    if {![info exists branches($name)]} { return "" }
    set b $branches($name)
    if {[regexp {^m([0-9]+)$} $key -> i]} {
        set target [lindex $targets $i]
        return [lindex [list "Not merged into $target" \
            "Merged into $target earlier; check-ins since" \
            "Merged into $target"] [dict get $b merged $target]]
    }
    switch -- $key {
        ci {
            set tags [join [dict get $b citags] ", "]
            return [lindex [list "" "Tagged earlier: $tags" \
                "The last check-in is tagged: $tags"] [dict get $b ci]]
        }
        forks {
            set n [dict get $b forks]
            return [expr {$n > 1 ? "Forked: $n open leaves" : ""}]
        }
    }
    return ""
}

# A merge or CI state as a cell.
proc tkbranches::mark {state} {
    lindex {"" \u25d0 \u2713} $state
}

proc tkbranches::showList {} {
    variable branches
    variable view
    variable searched
    variable shown
    variable showHidden
    variable privateOnly
    set shown [list $searched $view $showHidden $privateOnly]
    variable targets
    variable current
    variable selected
    set t .branches.main.list.t
    set keep [$t selection]
    if {![llength $keep] && $selected ne ""} { set keep [list $selected] }
    set counts [dict create open 0 unmerged 0 mine 0 closed 0 all 0]
    set rows {}
    foreach name [array names branches] {
        set b $branches($name)
        if {![matches $b]} continue
        foreach v [dict keys $counts] {
            if {[inView $b $v]} { dict incr counts $v }
        }
        if {![inView $b $view]} continue
        set cells [dict create \
            name [expr {$name eq $current ? "\u2605 $name" : $name}] \
            updated [dict get $b updated] created [dict get $b created] \
            checkins [dict get $b checkins] users [join [dict get $b users] ", "] \
            base [dict get $b base] ci [mark [dict get $b ci]] \
            forks [expr {[dict get $b forks] > 1 ? "\u26a0 [dict get $b forks]" : ""}] \
            tickets [join [dict get $b tickets] ", "] \
            state [join [lmap {k label} {closed closed hidden hidden private private} {
                if {![dict get $b $k]} continue; set label }] ", "] \
            tip [string range [dict get $b tip] 0 9] comment [dict get $b comment]]
        set sorts [dict create name $name forks [dict get $b forks] \
            tickets [llength [dict get $b tickets]] ci [dict get $b ci]]
        set i 0
        foreach target $targets {
            dict set cells m$i [mark [dict get $b merged $target]]
            dict set sorts m$i [dict get $b merged $target]
            incr i
        }
        set tags {}
        if {[dict get $b closed] || [dict get $b hidden]} { lappend tags inactive }
        if {$name eq $current} { lappend tags current }
        lappend rows [list $name $cells $sorts $tags]
    }
    tablecols::fill $t $rows
    foreach v [dict keys $counts] {
        .branches.tabs.$v configure -text "[string totitle $v] ([dict get $counts $v])"
    }
    showCount
    set keep [lmap id $keep { if {![$t exists $id]} continue; set id }]
    if {![llength $keep]} { set keep [lrange [$t children {}] 0 0] }
    if {[llength $keep]} {
        $t selection set $keep
        $t focus [lindex $keep 0]
        $t see [lindex $keep 0]
    } else {
        showDetails ""
    }
}

proc tkbranches::updateStatus {} {
    variable status
    variable root
    variable current
    variable repo
    set parts {}
    if {$root ne ""} {
        # The changed files, not the merges ("MERGED_WITH ...").
        lassign [inCheckout changes] code out
        set n 0
        if {!$code} {
            foreach line [split $out \n] {
                if {[regexp {^[A-Z_]+\s+\S} $line]
                        && ![regexp {^(?:MERGED_WITH|CHERRYPICK|BACKOUT|INTEGRATE)\s} $line]} {
                    incr n
                }
            }
        }
        lappend parts "checkout on $current[expr {$n ? ", $n changed files" : ""}]"
    }
    if {![catch {sql "SELECT count(*) FROM unsent"} rows] && [lindex $rows 0 0] > 0} {
        lappend parts "[lindex $rows 0 0] unpushed"
    }
    lappend parts $repo
    variable statusTail [join $parts "  \u00b7  "]
    showCount
}

proc tkbranches::showCount {} {
    variable status
    variable statusTail
    .branches.status configure -foreground ""
    set n [llength [.branches.main.list.t children {}]]
    set status "$n branch[expr {$n == 1 ? "" : "es"}]  \u00b7  $statusTail"
}

# The selected branches, or the one under the context menu.
proc tkbranches::selectedNames {} {
    .branches.main.list.t selection
}

# ---------------------------------------------------------------- details

proc tkbranches::showDetails {name} {
    variable branches
    variable selected
    variable header
    variable targets
    set selected $name
    set c .branches.main.details.nb.checkins.t
    $c delete [$c children {}]
    .branches.main.details.nb.tickets.t delete [.branches.main.details.nb.tickets.t children {}]
    clearFiles
    .branches.main.details.finish state [expr {[finishable $name] ? "!disabled" : "disabled"}]
    if {$name eq "" || ![info exists branches($name)]} {
        set header ""
        return
    }
    set b $branches($name)
    set state [expr {[dict get $b closed] ? "closed" : "open"}]
    foreach k {hidden private} { if {[dict get $b $k]} { append state ", $k" } }
    set parts [list "$name ($state)"]
    if {[dict get $b base] ne ""} {
        lappend parts "from [dict get $b base], [lindex [dict get $b created] 0]"
    }
    set users [dict get $b users]
    if {[llength $users] > 6} {
        set users [list {*}[lrange $users 0 5] "[expr {[llength $users] - 6}] more"]
    }
    lappend parts "[dict get $b checkins] check-ins by [join $users {, }]"
    set merged [lmap t $targets {
        set s [dict get $b merged $t]
        if {$t eq $name} continue
        string cat [targetHeading $t] " " [expr {$s ? [mark $s] : "\u2014"}]
    }]
    if {[llength $merged]} { lappend parts "merged: [join $merged {, }]" }
    if {[llength [dict get $b citags]]} { lappend parts "CI: [join [dict get $b citags] {, }]" }
    if {[dict get $b forks] > 1} { lappend parts "\u26a0 [dict get $b forks] open leaves" }
    set released [firstReleases [releasesWith [dict get $b tip]]]
    lappend parts [expr {[llength $released] ? "released in [join $released {, }]" : "not released"}]
    set header [join $parts "  \u00b7  "]

    # The check-ins, and the branches each was merged into.
    set rows [sql "SELECT strftime('%Y-%m-%d %H:%M',e.mtime), b.uuid, coalesce(e.euser,e.user),
        [fossil::outcol "(SELECT group_concat(DISTINCT x.value) FROM plink p JOIN tagxref x
          ON x.rid=p.cid AND x.tagid=(SELECT tagid FROM tag WHERE tagname='branch')
          AND x.tagtype>0 WHERE p.pid=e.objid AND NOT p.isprim
          AND x.value<>[fossil::sqlstr $name])"],
        [fossil::outcol coalesce(e.ecomment,e.comment)],
        EXISTS(SELECT 1 FROM leaf WHERE rid=e.objid)
        FROM tagxref x JOIN event e ON e.objid=x.rid JOIN blob b ON b.rid=e.objid
        WHERE x.tagid=(SELECT tagid FROM tag WHERE tagname='branch') AND x.tagtype>0
        AND x.value=[fossil::sqlstr $name] AND e.type='ci' ORDER BY e.mtime DESC
        LIMIT 1000"]
    foreach row $rows {
        lassign $row date uuid user into comment leaf
        $c insert {} end -id $uuid -tags [expr {$leaf ? "leaf" : ""}] \
            -values [list $date [string range $uuid 0 9] $user \
                [string map {, {, }} $into] \
                [string map {\n " "} [fossil::lf $comment]]]
    }
    if {[llength $rows]} { $c see [lindex [$c children {}] 0] }
    # (The newest 1000: a main branch can have tens of thousands.)
    set n [dict get $b checkins]
    .branches.main.details.nb tab 0 -text [expr {$n > [llength $rows]
        ? "Check-ins ([llength $rows] of $n)" : "Check-ins ($n)"}]

    # The tickets.
    set k .branches.main.details.nb.tickets.t
    set ids [dict get $b tickets]
    if {[llength $ids]} {
        set rows [sql "SELECT tkt_uuid, [fossil::outcol coalesce(status,'')],
            [fossil::outcol coalesce(type,'')], [fossil::outcol coalesce(title,'')]
            FROM ticket WHERE [join [lmap id $ids {
                string cat "tkt_uuid GLOB " [fossil::sqlstr $id*]
            }] { OR }] ORDER BY tkt_mtime DESC"]
        foreach row $rows {
            lassign $row uuid tstatus type title
            $k insert {} end -id $uuid -values [list [string range $uuid 0 9] $tstatus $type $title]
        }
    }
    .branches.main.details.nb tab 2 -text "Tickets ([llength $ids])"
    if {[.branches.main.details.nb select] eq ".branches.main.details.nb.files"} { loadFiles }
}

# The changed files: "fossil diff --numstat" in the background, as it
# takes long for a big branch.
proc tkbranches::clearFiles {} {
    variable filesPipe
    if {$filesPipe ne ""} {
        fossil::stop $filesPipe
        set filesPipe ""
    }
    set f .branches.main.details.nb.files.t
    $f delete [$f children {}]
    .branches.main.details.nb tab 1 -text Files
}

proc tkbranches::loadFiles {} {
    variable filesPipe
    variable selected
    variable repo
    set f .branches.main.details.nb.files.t
    if {$selected eq "" || $filesPipe ne "" || [llength [$f children {}]]} return
    $f insert {} end -values [list "" "" "Comparing\u2026"]
    set filesPipe [fossil::start -encoding utf-8 -onDone tkbranches::readFiles \
        diff -R $repo --numstat --branch [fossil::arg $selected]]
}

# (A stopped one: for a branch no longer selected.)
proc tkbranches::readFiles {code text stopped msg} {
    variable filesPipe
    if {$stopped} return
    set lines [split $text \n]
    set filesPipe ""
    set f .branches.main.details.nb.files.t
    $f delete [$f children {}]
    set n 0
    set total {}
    foreach line $lines {
        if {[regexp {^\s*([0-9]+)\s+([0-9]+)\s+TOTAL over ([0-9]+) changed files?} $line -> a d n]} {
            set total [list $a $d "Total: $n files"]
        } elseif {[regexp {^\s*([0-9]+)\s+([0-9]+)\s+(.+)$} $line -> a d path]} {
            $f insert {} end -values [list $a $d $path]
        } elseif {[string trim $line] ni {"" "INSERTED DELETED"}
                && ![regexp {^\s*INSERTED\s+DELETED\s*$} $line]} {
            $f insert {} end -tags error -values [list "" "" [string trim $line]]
        }
    }
    if {[llength $total]} { $f insert {} end -tags total -values $total }
    .branches.main.details.nb tab 1 -text "Files ($n)"
}

# ----------------------------------------------------------- context menus

proc tkbranches::branchMenu {x y X Y} {
    variable branches
    variable targets
    set t .branches.main.list.t
    if {[$t identify region $x $y] ni {cell tree}} return
    set name [$t identify item $x $y]
    if {$name eq ""} return
    if {$name ni [$t selection]} { $t selection set $name }
    fillBranchMenu .branches.ctx $name
    # (What a double-click on the branch does.)
    popup::default .branches.ctx "Diff of the branch"
    tk_popup .branches.ctx $X $Y
}

proc tkbranches::fillBranchMenu {m name} {
    variable branches
    variable targets
    variable root
    $m delete 0 end
    set ok [expr {$name ne "" && [info exists branches($name)]}]
    set state [expr {$ok ? "normal" : "disabled"}]
    set co [expr {$ok && $root ne "" ? "normal" : "disabled"}]
    $m add command -label "Update checkout to $name" -state $co \
        -command [list tkbranches::updateTo $name]
    $m add command -label "Merge into checkout\u2026" -state $co \
        -command [list tkbranches::merge branch $name]
    $m add separator
    $m add command -label "Diff of the branch" -state $state \
        -command [list tkbranches::diffBranch $name]
    set first [lindex $targets 0]
    if {$first ne ""} {
        $m add command -label "Diff against $first" \
            -state [expr {$ok && $name ne $first ? "normal" : "disabled"}] \
            -command [list tkbranches::diffAgainst $name $first]
    }
    $m add command -label "Timeline in browser" -state $state \
        -command [list tkbranches::openUrl timeline?r=[fossil::urlquery $name]]
    $m add separator
    set closed [expr {$ok && [dict get $branches($name) closed]}]
    set hidden [expr {$ok && [dict get $branches($name) hidden]}]
    $m add command -label [expr {$closed ? "Reopen" : "Close"}] -state $state \
        -command [list tkbranches::tagBranches [expr {$closed ? "reopen" : "close"}]]
    $m add command -label "Backport to another checkout\u2026" -state $state \
        -command [list tkbranches::backport $name]
    $m add command -label "Finish branch\u2026" -command [list tkbranches::finish $name] \
        -state [expr {$ok && [finishable $name] ? "normal" : "disabled"}]
    $m add command -label [expr {$hidden ? "Unhide" : "Hide"}] -state $state \
        -command [list tkbranches::tagBranches [expr {$hidden ? "unhide" : "hide"}]]
    $m add command -label "New branch from here\u2026" -state $state \
        -command [list tkbranches::newBranch [expr {$ok ? [dict get $branches($name) tip] : ""}] \
            "the last check-in of $name"]
    set private [expr {$ok && [dict get $branches($name) private]}]
    $m add command -label "Make public\u2026" -state [expr {$private ? "normal" : "disabled"}] \
        -command [list histops::publish $::tkbranches::repo $name "the private branch $name" tkbranches::reload]
    $m add separator
    # The common ancestor: of the two branches selected, else with the
    # first merge target.
    set sel [selectedNames]
    set other [expr {[llength $sel] == 2 ? [lindex [lsearch -all -inline -not -exact $sel $name] 0] : $first}]
    $m add command -label [expr {$other eq "" ? "Common ancestor" : "Common ancestor with $other"}] \
        -state [expr {$ok && $other ne "" && $other ne $name ? "normal" : "disabled"}] \
        -command [list histops::showMergeBase $::tkbranches::repo $::tkbranches::root $name $other]
    $m add command -label "Save as archive\u2026" -state $state \
        -command [list histops::archive $::tkbranches::repo [expr {$ok ? [dict get $branches($name) tip] : ""}] \
            "the last check-in of $name"]
    $m add command -label "Export as bundle\u2026" -state $state \
        -command [list histops::exportBundle $::tkbranches::repo $name]
    $m add cascade -label Advanced -menu [advancedMenu $m $name $ok]
    $m add separator
    if {$ok && ![popup::inBar]} {
        set base [dict get $branches($name) base]
        if {$base ne ""} {
            $m add command -label "Search base:$base" \
                -command [list tkbranches::addTerm base $base 0]
        }
        foreach user [lrange [dict get $branches($name) users] 0 2] {
            $m add command -label "Search user:$user" \
                -command [list tkbranches::addTerm user $user 0]
        }
    }
    $m add command -label "Copy name" -state $state -command [list ui::copy $name]
    $m add command -label "Copy last check-in" -state $state \
        -command [list ui::copy [expr {$ok ? [dict get $branches($name) tip] : ""}]]
}

proc tkbranches::checkinMenu {x y X Y} {
    variable root
    set c .branches.main.details.nb.checkins.t
    set uuid [$c identify item $x $y]
    if {$uuid eq ""} return
    $c selection set $uuid
    set m .branches.cictx
    $m delete 0 end
    set co [expr {$root ne "" ? "normal" : "disabled"}]
    $m add command -label "Show in Timeline" -command [list goto::checkin $uuid]
    $m add command -label "Diff of this check-in" -command [list tkbranches::diffCheckin $uuid]
    $m add command -label "Open in browser" -command [list tkbranches::openUrl info/$uuid]
    $m add separator
    $m add command -label "Update checkout to this check-in\u2026" -state $co \
        -command [list tkbranches::updateTo $uuid "check-in [string range $uuid 0 9]"]
    $m add command -label "Merge into checkout\u2026" -state $co \
        -command [list tkbranches::merge checkin $uuid]
    $m add command -label "Cherry-pick into checkout\u2026" -state $co \
        -command [list tkbranches::merge cherrypick $uuid]
    $m add command -label "Back out in checkout\u2026" -state $co \
        -command [list tkbranches::merge backout $uuid]
    $m add command -label "New branch from here\u2026" -command [list tkbranches::newBranch $uuid]
    $m add command -label "Releases with this check-in" -command [list tkbranches::showReleases $uuid]
    $m add command -label "Save as archive\u2026" -command [list histops::archive $::tkbranches::repo $uuid]
    $m add command -label "Show artifact" -command [list histops::showArtifact $::tkbranches::repo $uuid]
    $m add command -label "Branches descended from it" \
        -command [list tkbranches::showDescendants $uuid]
    $m add separator
    $m add command -label "Copy check-in" -command [list ui::copy $uuid]
    popup::default $m "Diff of this check-in"
    tk_popup $m $X $Y
}

# ----------------------------------------------------------------- window

# A treeview with a vertical scrollbar in frame $f.
proc tkbranches::tree {f columns} {
    ttk::frame $f
    ttk::treeview $f.t -columns [dict keys $columns] -show headings \
        -yscrollcommand [list $f.y set]
    ttk::scrollbar $f.y -command [list $f.t yview]
    set char [font measure TkDefaultFont 0]
    dict for {key spec} $columns {
        lassign $spec heading width stretch anchor
        $f.t heading $key -text $heading -anchor w
        $f.t column $key -width [expr {$width * $char}] -stretch [expr {$stretch eq "1"}] \
            -anchor [expr {$anchor eq "" ? "w" : $anchor}]
    }
    grid $f.t $f.y -sticky news
    grid columnconfigure $f 0 -weight 1
    grid rowconfigure $f 0 -weight 1
    return $f.t
}

# Build the tab in the frame .branches, with its menu bar .branches.menu.
# The Advanced submenu of a branch: purging it, switching the checkout to
# it without merging.
proc tkbranches::advancedMenu {m name ok} {
    variable root
    set a $m.advanced
    destroy $a
    menu $a -tearoff 0
    $a add command -label "Switch checkout to $name without merging\u2026" \
        -state [expr {$ok && $root ne "" ? "normal" : "disabled"}] \
        -command [list histops::switchKeep $::tkbranches::repo $::tkbranches::root $name \
            "the last check-in of $name" tkbranches::reload]
    $a add command -label "Purge the branch\u2026" -state [expr {$ok && $root ne "" ? "normal" : "disabled"}] \
        -command [list histops::purgeCheckins $::tkbranches::repo $::tkbranches::root $name \
            "the branch $name" tkbranches::reload]
    return $a
}

proc tkbranches::build {} {
    menu .branches.menu
    .branches.menu add cascade -label File -underline 0 -menu [menu .branches.menu.file]
    tktaalik::fileMenu .branches.menu.file
    .branches.menu.file add command -label "Merge targets\u2026" -underline 0 -command tkbranches::setTargets
    .branches.menu.file add command -label "Changes between releases\u2026" -underline 0 \
        -command tkbranches::compareReleases
    .branches.menu.file add separator
    .branches.menu.file add command -label "Import bundle\u2026" -underline 0 \
        -command {histops::importBundle $tkbranches::repo tkbranches::reload}
    .branches.menu.file add command -label "Remove an imported bundle\u2026" \
        -command {histops::purgeBundle $tkbranches::repo tkbranches::reload}
    .branches.menu.file add command -label "Purge graveyard\u2026" \
        -command {histops::graveyard $tkbranches::repo tkbranches::reload}
    .branches.menu.file add separator
    .branches.menu.file add command -label Refresh -underline 0 -accelerator F5 -command tkbranches::reload
    tktaalik::quitEntry .branches.menu.file
    .branches.menu add cascade -label Branch -underline 0 -menu [menu .branches.menu.branch \
        -postcommand {popup::fill .branches.menu.branch tkbranches::fillBranchMenu $tkbranches::selected}]
    .branches.menu add cascade -label Help -underline 0 -menu [menu .branches.menu.help]
    .branches.menu.help add command -label "Search syntax" -underline 0 \
        -command {help::show branches search-syntax}
    menu .branches.ctx
    menu .branches.cictx

    # The search.
    ttk::frame .branches.top -padding {6 6 6 0}
    ttk::combobox .branches.top.q -textvariable tkbranches::query
    icons::button .branches.top.go search "Search (Return)" {set tktaalik::typing ""; tkbranches::search 1}
    icons::button .branches.top.clear clear "Clear the search (Escape)" \
        {tktaalik::navigate; set tkbranches::query ""; tkbranches::search}
    icons::button .branches.top.help help "Search syntax (the manual)" {help::show branches search-syntax}
    pack .branches.top.help .branches.top.clear .branches.top.go -side right -padx {4 0}
    pack .branches.top.q -fill x -expand 1
    # (Return ends the typing: the next key is a new place for Back.)
    bind .branches.top.q <Return> {set tktaalik::typing ""; tkbranches::search 1}
    bind .branches.top.q <KP_Enter> {set tktaalik::typing ""; tkbranches::search 1}
    bind .branches.top.q <<ComboboxSelected>> {set tktaalik::typing ""; tkbranches::search 1}
    bind .branches.top.q <Escape> {tktaalik::navigate; set tkbranches::query ""; tkbranches::search}
    # Searched while typing, a moment after the last key.
    trace add variable ::tkbranches::query write {::apply {args {
        tktaalik::typing .branches.top.q
        after cancel {tkbranches::search}
        after 300 {tkbranches::search}
    }}}

    # The views.
    ttk::frame .branches.tabs -padding {6 4}
    foreach v {open unmerged mine closed all} {
        ttk::radiobutton .branches.tabs.$v -style Toolbutton -text [string totitle $v] \
            -variable tkbranches::view -value $v -command tkbranches::setView
        pack .branches.tabs.$v -side left -padx {0 4}
    }
    ttk::checkbutton .branches.tabs.hidden -text "Show hidden" -variable tkbranches::showHidden \
        -command {tktaalik::navigate; tkbranches::showList}
    ttk::checkbutton .branches.tabs.private -text "Private only" -variable tkbranches::privateOnly \
        -command tkbranches::setPrivate
    pack .branches.tabs.private .branches.tabs.hidden -side right -padx {6 0}

    # The list and the details.
    ttk::panedwindow .branches.main -orient vertical
    ui::splitByWeights .branches.main
    ttk::frame .branches.main.list
    ttk::treeview .branches.main.list.t -show headings -selectmode extended \
        -yscrollcommand {.branches.main.list.y set} -xscrollcommand {.branches.main.list.x set}
    ttk::scrollbar .branches.main.list.y -command {.branches.main.list.t yview}
    ttk::scrollbar .branches.main.list.x -orient horizontal -command {.branches.main.list.t xview}
    grid .branches.main.list.t .branches.main.list.y -sticky news
    grid .branches.main.list.x -sticky ew
    grid columnconfigure .branches.main.list 0 -weight 1
    grid rowconfigure .branches.main.list 0 -weight 1
    .branches.main.list.t tag configure inactive -foreground gray45
    .branches.main.list.t tag configure current -font TkHeadingFont

    ttk::frame .branches.main.details
    # The header of the branch, and on its right what is done with it.
    ttk::frame .branches.main.details.top
    ttk::label .branches.main.details.header -textvariable tkbranches::header -padding {6 4} \
        -anchor w -wraplength 1000 -justify left
    ttk::style configure Small.TButton -padding {8 0} -width 0
    ttk::button .branches.main.details.finish -text Finish\u2026 -style Small.TButton -state disabled \
        -command {tkbranches::finish $tkbranches::selected}
    icons::tooltip .branches.main.details.finish \
        "After the merge: cancel its CI tags, close its tickets, close the branch"
    pack .branches.main.details.finish -in .branches.main.details.top -side right -padx {4 6}
    pack .branches.main.details.header -in .branches.main.details.top -side left -fill x -expand 1
    bind .branches.main.details.header <Configure> {%W configure -wraplength [expr {max(0, %w - 12)}]}
    ttk::notebook .branches.main.details.nb
    set c [tree .branches.main.details.nb.checkins {
        date {Date 16} hash {Check-in 11} user {User 14} into {"Merged into" 18}
        comment {Comment 50 1}
    }]
    $c tag configure leaf -font TkHeadingFont
    set f [tree .branches.main.details.nb.files {added {Added 7 0 e} deleted {Deleted 7 0 e} file {File 50 1}}]
    $f tag configure total -font TkHeadingFont
    $f tag configure error -foreground red3
    tree .branches.main.details.nb.tickets {id {Ticket 11} status {Status 10} type {Type 10} title {Title 60 1}}
    .branches.main.details.nb add .branches.main.details.nb.checkins -text Check-ins
    .branches.main.details.nb add .branches.main.details.nb.files -text Files
    .branches.main.details.nb add .branches.main.details.nb.tickets -text Tickets
    pack .branches.main.details.top -fill x
    pack .branches.main.details.nb -fill both -expand 1
    .branches.main add .branches.main.list -weight 3
    .branches.main add .branches.main.details -weight 2

    ttk::label .branches.status -textvariable tkbranches::status -padding {6 2} -anchor w

    pack .branches.top -fill x
    pack .branches.tabs -fill x
    pack .branches.status -side bottom -fill x
    pack .branches.main -fill both -expand 1

    # Bindings.
    set t .branches.main.list.t
    bind $t <<TreeviewSelect>> {
        set tkbranches::selected [.branches.main.list.t focus]
        if {$tkbranches::selected ni [.branches.main.list.t selection]} {
            set tkbranches::selected [lindex [.branches.main.list.t selection] 0]
        }
        tkbranches::showDetails $tkbranches::selected
    }
    bind $t <ButtonPress-3> {+tkbranches::branchMenu %x %y %X %Y}
    bind $t <Double-1> {
        if {[.branches.main.list.t identify region %x %y] in {cell tree}} {
            tkbranches::diffBranch [.branches.main.list.t identify item %x %y]
        }
    }
    bind $c <ButtonPress-3> {tkbranches::checkinMenu %x %y %X %Y}
    bind $c <Double-1> {tkbranches::diffCheckin [.branches.main.details.nb.checkins.t identify item %x %y]}
    popup::attach .branches.main.details.nb.tickets.t tkbranches::ticketMenu
    popup::attach .branches.main.details.nb.files.t tkbranches::fileMenu
    bind .branches.main.details.nb.tickets.t <Double-1> {
        tkbranches::showTicket [.branches.main.details.nb.tickets.t identify item %x %y]
    }
    bind .branches.main.details.nb <<NotebookTabChanged>> {
        if {[.branches.main.details.nb select] eq ".branches.main.details.nb.files"} tkbranches::loadFiles
    }
    tktaalik::shortcut branches <F5> tkbranches::reload
    tktaalik::shortcut branches <Control-f> {focus .branches.top.q; .branches.top.q selection range 0 end}

    # The settings.
    variable config
    variable view
    variable showHidden
    loadConfig
    set view [getdef $config view open]
    set showHidden [getdef $config showHidden 0]
    variable history [getdef $config history {}]
    .branches.top.q configure -values $history
    variable query [getdef $config query ""]
    # (Settings of before the view was a term: the view into the query.)
    if {$view ne "all" && [stripView $query] eq [string trim $query]} {
        set query [string trim "$query [viewTerms $view]"]
    }
    after cancel {tkbranches::search}
}

# The tab is shown: read the branches again if the repository or the
# checkout has changed.
proc tkbranches::activate {} {
    variable repo
    if {$repo ne "" && [tktaalik::changed branches]} { reload }
    focus .branches.main.list.t
}

# The context menus of the details: a ticket, a file changed.
proc tkbranches::ticketMenu {m item} {
    $m add command -label "Show the ticket" -command [list tkbranches::showTicket $item]
    $m add command -label "Open in browser" -command [list tkbranches::openUrl tktview/$item]
    popup::separator $m
    popup::copy $m "Copy ticket id" $item
    popup::default $m "Show the ticket"
}

proc tkbranches::fileMenu {m item} {
    variable repo
    set t .branches.main.details.nb.files.t
    set path [$t set $item file]
    if {$path eq "" || [$t tag has error $item] || [$t tag has total $item]} return
    set name [lindex [$t selection] 0]
    set branch [lindex [.branches.main.list.t selection] 0]
    $m add command -label "Diff of this file in the branch" \
        -command [list diffview::run "$path in $branch" -- -R $repo --branch [fossil::arg $branch] [fossil::arg $path]]
    popup::separator $m
    popup::copy $m "Copy path" $path
}

source [file join [file dirname [file normalize [info script]]] branchops.tcl]
