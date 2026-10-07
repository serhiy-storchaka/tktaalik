# The ticket search of the Tickets tab: the query language and its SQL.
#
# SQL runs through "fossil sql --readonly" (the SQLite shell built into
# Fossil), so no sqlite3 Tcl package is needed.  Query values go into SQL as
# quoted literals; callers remove control characters from them first, so no
# line of the shell input can start with a "." (a shell command).
#
# Call useRepository with the repository file and set tickets::me to the
# user for "@me", then use buildQuery, orderBy and sql.

package require Tcl 8.6-

namespace eval tickets {
    variable states {open closed pending deleted}

    # Ticket tables differ: Fossil's default has no subsystem, submitter,
    # assignee, closer, closedate or is_private, which the Tcl/Tk trackers
    # add.  The "all" tables below describe everything; configure keeps what
    # the repository's ticket table supports (useRepository).

    # Query key -> ticket column.  Several GitHub names are aliases.
    variable allFields {
        type type  kind type
        state status  status status
        resolution resolution  reason resolution
        subsystem subsystem  label subsystem  component subsystem
        priority priority
        severity severity
        foundin foundin  version foundin
        author submitter  submitter submitter
        assignee assignee
        closer closer
        tip tip_number
    }
    variable allDateFields {created tkt_ctime  updated tkt_mtime  closed closedate}

    # Table columns, in display order:
    #   key {heading  SQL expression  sort expression  default direction
    #        ticket fields it needs}
    # The counts come from other tables: remarks in ticketchng, check-ins
    # whose comments mention the ticket (backlink; any prefix of the ticket
    # id, found through the index on target), and attachments (the latest
    # version of each, not deleted ones).
    variable severityRank {CASE lower(severity) WHEN 'critical' THEN 5
        WHEN 'severe' THEN 4 WHEN 'major' THEN 3 WHEN 'important' THEN 3
        WHEN 'minor' THEN 2 WHEN 'cosmetic' THEN 1 ELSE 0 END}
    variable allColumns [::apply {{severityRank} {
      set long [dict create \
        STATUS {lower(status)||char(1)||lower(coalesce(resolution,''))} \
        PRIORITY {CAST(priority AS INTEGER)} SEVERITY $severityRank]
      set long [dict merge $long {
        COMMENTS {(SELECT count(*) FROM ticketchng c
            WHERE c.tkt_id=ticket.tkt_id AND c.icomment<>'')}
        CHECKINS {(SELECT count(DISTINCT b.srcid) FROM backlink b
            WHERE b.srctype=0 AND b.target BETWEEN substr(ticket.tkt_uuid,1,4)
            AND ticket.tkt_uuid AND ticket.tkt_uuid GLOB b.target||'*')}
        ATTACHMENTS {(SELECT count(*) FROM attachment a
            WHERE a.target=ticket.tkt_uuid AND a.isLatest AND a.src<>'')}
      }]
      set columns {}
      foreach {key heading expr sort dir needs} {
        tip        TIP          tip_number       {CAST(tip_number AS INTEGER)} desc tip_number
        type       Type         type             lower(type)       asc   type
        state      Status       status           STATUS            asc   status
        subsystem  Subsystem    subsystem        lower(subsystem)  asc   subsystem
        priority   Priority     priority         PRIORITY          desc  priority
        severity   Severity     severity         SEVERITY          desc  severity
        version    {Found in}   foundin          lower(foundin)    asc   foundin
        assignee   Assignee     assignee         lower(assignee)   asc   assignee
        author     Submitter    submitter        lower(submitter)  asc   submitter
        closer     Closer       closer           lower(closer)     asc   closer
        created    Created      date(tkt_ctime)  tkt_ctime         desc  {}
        updated    Updated      date(tkt_mtime)  tkt_mtime         desc  {}
        closed     Closed       date(closedate)  closedate         desc  closedate
        comments   Comments     COMMENTS         COMMENTS          desc  {}
        checkins   Check-ins    CHECKINS         CHECKINS          desc  {}
        attachments Attachments ATTACHMENTS      ATTACHMENTS       desc  {}
    } {
        dict set columns $key [dict create heading $heading \
            expr [string map $long $expr] sort [string map $long $sort] dir $dir \
            needs $needs]
      }
      return $columns
    }} $severityRank]
    # Columns with counts, blank for 0.  comments:, checkins: and
    # attachments: filter them.
    variable counts {comments checkins attachments}
    variable countKeys {comments comments  comment comments  checkins checkins  checkin checkins
        attachments attachments  attachment attachments}
    # Status also shows (and sorts by) the resolution.
    variable allExtra {state resolution}
    # Names accepted by sort= and cols= (for cols=, resolution means the
    # Status column that shows it).
    variable allAliases {
        status state  kind type  label subsystem  component subsystem
        reason resolution  foundin version  submitter author  tip_number tip
    }
    variable allDefaultColumns {tip type state subsystem priority severity version assignee updated}
    variable me ""                      ;# the logged-in user, for "@me"
    variable sortkey updated            ;# the sort= parameter
    variable sortdir desc
    # The columns and the sort order asked for; shown, sortkey and sortdir
    # are the parts the repository supports.
    variable wanted $allDefaultColumns
    variable wantedSort {updated desc}
    variable repo ""

    # What configure derives: fields, dateFields, columns, extra, sorts,
    # aliases, defaultColumns, shown (the cols= parameter), have (the ticket
    # fields), people (submitter, assignee, closer as present).
}

# Keep the parts of the tables that the ticket fields $have support.
proc tickets::configure {have} {
    variable allFields
    variable allDateFields
    variable allColumns
    variable allExtra
    variable allAliases
    variable allDefaultColumns
    variable severityRank
    variable fields {}
    variable dateFields {}
    variable columns {}
    variable extra {}
    variable sorts {}
    variable aliases {}
    variable defaultColumns
    variable shown
    variable sortkey
    variable sortdir
    variable people
    set ::tickets::have $have

    dict for {key col} $allFields {
        if {$col in $have} { dict set fields $key $col }
    }
    dict for {key col} $allDateFields {
        if {$col in $have} { dict set dateFields $key $col }
    }
    dict for {key col} $allColumns {
        if {[llength [lmap f [dict get $col needs] {if {$f in $have} continue; set f}]]} continue
        # Without the resolution, sort by the status.
        if {$key eq "state" && "resolution" ni $have} { dict set col sort lower(status) }
        dict set columns $key $col
    }
    dict for {key x} $allExtra {
        if {[dict exists $columns $key] && $x in $have} { dict set extra $key $x }
    }
    # The repository's own fields (custom ticket setups): searched by their
    # name (field:value), a column each (not shown at first), shown and
    # edited in the details.
    variable custom [customFields $have]
    foreach col $custom {
        if {![dict exists $fields $col]} { dict set fields $col $col }
        if {![dict exists $columns $col]} {
            dict set columns $col [dict create heading [fieldLabel $col] expr $col \
                sort lower($col) dir asc needs $col]
        }
    }
    # Sort keys: the columns, Status followed by the resolution alone, then
    # title and id.
    set alone [dict create \
        resolution {heading Resolution sort lower(resolution) dir asc}]
    dict for {key col} $columns {
        dict set sorts $key $col
        if {[dict exists $extra $key]} {
            set x [dict get $extra $key]
            dict set sorts $x [dict get $alone $x]
        }
    }
    set sorts [dict merge $sorts {
        title {heading Title     sort lower(title) dir asc}
        id    {heading {Ticket id} sort tkt_uuid   dir asc}
    }]
    dict for {alias key} $allAliases {
        if {[dict exists $sorts $key]} { dict set aliases $alias $key }
    }
    foreach key [dict keys $sorts] { dict set aliases $key $key }
    set defaultColumns [lmap key $allDefaultColumns {
        if {![dict exists $columns $key]} continue
        set key
    }]
    set shown [lmap key $::tickets::wanted {
        if {![dict exists $columns $key]} continue
        set key
    }]
    if {![llength $shown]} { set shown $defaultColumns }
    lassign $::tickets::wantedSort sortkey sortdir
    if {![dict exists $sorts $sortkey]} {
        set sortkey updated
        set sortdir desc
    }
    set people [lmap col {submitter assignee closer} {
        if {$col ni $have} continue
        set col
    }]
}

# The fields of the ticket table that the application does not know: the
# repository's own (not Fossil's tkt_* columns, the description and the
# private contact).
proc tickets::customFields {have} {
    set known {type status resolution subsystem priority severity foundin title comment
        cmimetype mimetype submitter assignee closer closedate is_private tip_number
        private_contact username login icomment}
    lmap col $have {
        if {[string match tkt_* $col] || $col in $known} continue
        set col
    }
}

# A field's name as a label: "fix_version" -> "Fix version".
proc tickets::fieldLabel {col} {
    string totitle [string map {_ " "} $col] 0 0
}

# Use the repository file $repository: read which fields its tickets have.
proc tickets::useRepository {repository} {
    variable repo $repository
    configure [lmap row [sql "SELECT name FROM pragma_table_info('ticket')"] {
        lindex $row 0
    }]
}

# A ticket field for SELECT: the field, or '' if the tickets have none.
proc tickets::field {name} {
    variable have
    expr {$name in $have ? $name : "''"}
}

proc tickets::getdef {dict key default} {
    if {[dict exists $dict $key]} { dict get $dict $key } else { return $default }
}

# Run one SQL statement; return its rows as lists of values (NULL is "").
proc tickets::sql {statement} {
    variable repo
    fossil::sql $repo $statement
}

proc tickets::queryError {msg} {
    throw {TICKETS QUERY} $msg
}

# ------------------------------------------------------------ query parsing

# Split the query into {neg key value quoted} terms:
#   -?  (name:)?  ("quoted text" | non-space characters)
proc tickets::tokenize {query} {
    set re {(-?)(?:([A-Za-z_]+):)?("[^"]*"?|\S+)}
    lmap {- neg key value} [regexp -all -inline $re $query] {
        set quoted [regexp {^"([^"]*)"?$} $value -> value]
        list [expr {$neg eq "-"}] [string tolower $key] $value $quoted
    }
}

proc tickets::termText {neg key value {quoted 0}} {
    if {$quoted || [regexp {\s} $value]} { set value "\"$value\"" }
    string cat [expr {$neg ? "-" : ""}] [expr {$key ne "" ? "$key:" : ""}] $value
}

# The state of a ticket by its status: open, pending, closed or deleted.
# Fossil's own ticket setup has more statuses: Verified and Review are
# open, Deferred pending, Fixed and Tested closed.  Others are themselves.
proc tickets::stateExpr {} {
    set s "lower(trim(coalesce(status,'')))"
    return "(CASE $s WHEN 'verified' THEN 'open' WHEN 'review' THEN 'open'\
        WHEN 'deferred' THEN 'pending' WHEN 'fixed' THEN 'closed'\
        WHEN 'tested' THEN 'closed' ELSE $s END)"
}

proc tickets::isState {key value} {
    variable states
    expr {$key in {state status} || ($key eq "is" && [string tolower $value] in $states)}
}

# The query without state terms (for the Open/Pending/Closed tabs), and
# the single state it selects ("" if none or several).
proc tickets::stripState {query} {
    join [lmap t [tokenize $query] {
        if {[isState {*}[lrange $t 1 2]]} continue
        termText {*}$t
    }]
}

proc tickets::queryState {query} {
    variable states
    set found [lmap t [tokenize $query] {
        lassign $t neg key value
        set value [string tolower $value]
        if {$neg || ![isState $key $value] || $value ni $states} continue
        set value
    }]
    expr {[llength $found] == 1 ? [lindex $found 0] : ""}
}

proc tickets::addTerm {query key value} {
    set term [termText 0 $key $value]
    if {$term in [regexp -all -inline {\S+} $query]} { return $query }
    string trim "$query $term"
}

# SQL true when column $col matches $pattern case-insensitively: the whole
# value, the value without its "NN. " numbering and brackets
# ("18. [text]" -> "text"), that number, or either word of "5 Medium".
# A "*" or "?" in the pattern makes it a glob.
proc tickets::match {col pattern} {
    set e "trim(coalesce($col,''))"
    set sp "instr($e,' ')"
    set numbered "($e GLOB '\[0-9\]. *' OR $e GLOB '\[0-9\]\[0-9\]. *')"
    if {[string match {*[*?]*} $pattern]} {
        set op GLOB
        set pattern [string map {[ [[]} $pattern]
    } else {
        set op =
    }
    set p "lower([fossil::sqlstr $pattern])"
    set candidates [list \
        "lower($e)" \
        "lower(trim(CASE WHEN $numbered THEN substr($e,instr($e,'. ')+2) ELSE $e END,' \[\]'))" \
        "CASE WHEN $numbered THEN substr($e,1,instr($e,'.')-1) ELSE '' END" \
        "lower(CASE WHEN $sp>0 THEN substr($e,1,$sp-1) ELSE '' END)" \
        "lower(CASE WHEN $sp>0 THEN substr($e,$sp+1) ELSE '' END)"]
    set any [join [lmap c $candidates {string cat "$c $op $p"}] { OR }]
    return "($col IS NOT NULL AND $col<>'' AND ($any))"
}

# Condition on the number $expr: "comments:3", "comments:>5" (also >=, <,
# <=), "comments:1..5" ("*" or nothing for an open end), "comments:0,2"
# (comma means OR).
proc tickets::numberCondition {expr key value} {
    set conds [lmap alt [split $value ,] {
        set alt [string trim $alt]
        if {$alt eq ""} continue
        if {[regexp {^(>=|<=|>|<)?0*([0-9]+)$} $alt -> op n]} {
            if {$op eq ""} { set op = }
            string cat "$expr $op $n"
        } elseif {[regexp {^(?:0*([0-9]+)|\*)?\.\.(?:0*([0-9]+)|\*)?$} $alt -> lo hi]} {
            set range {}
            if {$lo ne ""} { lappend range "$expr >= $lo" }
            if {$hi ne ""} { lappend range "$expr <= $hi" }
            expr {[llength $range] ? "([join $range { AND }])" : 1}
        } else {
            queryError "bad number \"$alt\" in $key:; use N, >N, >=N, <N, <=N or N..M"
        }
    }]
    if {![llength $conds]} { queryError "empty value for $key:" }
    return ([join $conds { OR }])
}

# Condition for a field term; "a,b" means a OR b, "priority:>=7" and
# "tip:>=700" compare numbers.
# Versions ("Found in"): written as 8.6, 8.6.10, 8.6b1.1, with words
# before them ("obsolete: 8.3", "final: 8.0.5"); a branch of a line
# (core-8-6-branch: the 8.6 line, newer than its releases), a release tag
# (core-8-6-10); trunk or main (newer than all).  A key to compare them:
# {major minor patch stage n m} (stage 0 alpha, 1 beta, 2 release), or ""
# if the text is not a version.
proc tickets::versionKey {text} {
    set t [string trim $text]
    regsub {^[A-Za-z][A-Za-z ]*:\s*} $t "" t
    set big 999999
    if {[regexp -nocase {^(trunk|main)$} $t]} { return [list $big 0 0 2 0 0] }
    if {[regexp {^core-([0-9]+)-([0-9]+)-branch$} $t -> a b]} {
        return [list [scan $a %d] [scan $b %d] $big 2 0 0]
    }
    if {[regexp {^core-([0-9]+)-([0-9]+)(?:-([0-9]+))?$} $t -> a b c]} {
        return [list [scan $a %d] [scan $b %d] [expr {$c eq "" ? 0 : [scan $c %d]}] 2 0 0]
    }
    if {[regexp {^([0-9]+)\.([0-9]+)(?:\.([0-9]+))?(?:([ab])([0-9]+)(?:\.([0-9]+))?)?$} $t -> \
            a b c pre n m]} {
        set stage [expr {$pre eq "a" ? 0 : $pre eq "b" ? 1 : 2}]
        return [list [scan $a %d] [scan $b %d] [expr {$c eq "" ? 0 : [scan $c %d]}] $stage \
            [expr {$n eq "" ? 0 : [scan $n %d]}] [expr {$m eq "" ? 0 : [scan $m %d]}]]
    }
    return ""
}

# The version number in a "Found in" text ("obsolete: 8.4.19" -> 8.4.19),
# or the text itself (a branch, trunk, something else).
proc tickets::versionNumber {text} {
    set t [string trim $text]
    regsub {^[A-Za-z][A-Za-z ]*:\s*} $t "" v
    if {[regexp {^[0-9]+\.[0-9]+} $v] && [versionKey $v] ne ""} { return $v }
    return $t
}

proc tickets::versionCompare {a b} {
    foreach x $a y $b {
        if {$x < $y} { return -1 }
        if {$x > $y} { return 1 }
    }
    return 0
}

# The "Found in" values that VALUE (of version:) selects: a version line
# (8.6: 8.6, 8.6.x, 8.6b1, core-8-6-branch...), a comparison (>=8.6.10), a
# range (8.6.10..8.6.13); "none" if VALUE is none of these (then it is
# matched as text: a branch name, a pattern, None).
proc tickets::versionValues {value} {
    set op ""
    set lo ""
    set hi ""
    if {[regexp {^(>=|<=|>|<)(.+)$} $value -> op v]} {
        set key [versionKey $v]
        if {$key eq ""} { return none }
    } elseif {[regexp {^(.+)\.\.(.+)$} $value -> a b]} {
        set lo [versionKey $a]
        set hi [versionKey $b]
        if {$lo eq "" || $hi eq ""} { return none }
        set op range
    } elseif {[regexp {^([0-9]+)(?:\.([0-9]+))?(?:\.([0-9]+))?$} $value -> a b c]} {
        # A line: the parts given.
        set op line
        set parts [lmap x [list $a $b $c] { if {$x eq ""} break; scan $x %d }]
    } else {
        return none
    }
    set result {}
    foreach v [versionTexts] {
        set k [versionKey $v]
        if {$k eq ""} continue
        set ok [switch -- $op {
            line  { expr {[lrange $k 0 [llength $parts]-1] eq $parts && [lindex $k 0] != 999999} }
            range { expr {[versionCompare $k $lo] >= 0 && [versionCompare $k $hi] <= 0} }
            >=    { expr {[versionCompare $k $key] >= 0} }
            <=    { expr {[versionCompare $k $key] <= 0} }
            >     { expr {[versionCompare $k $key] > 0} }
            <     { expr {[versionCompare $k $key] < 0} }
        }]
        if {$ok} { lappend result $v }
    }
    return $result
}

# The distinct "Found in" values of the tickets (read again after a few
# seconds: a search makes several queries).
proc tickets::versionTexts {} {
    variable repo
    variable versionCache
    set now [clock seconds]
    if {[info exists versionCache] && [lindex $versionCache 0] eq $repo
            && $now - [lindex $versionCache 1] < 5} {
        return [lindex $versionCache 2]
    }
    set texts [lmap row [sql "SELECT DISTINCT [fossil::outcol "trim(foundin)"] FROM ticket\
        WHERE foundin IS NOT NULL AND trim(foundin)<>''"] { lindex $row 0 }]
    set versionCache [list $repo $now $texts]
    return $texts
}

proc tickets::fieldCondition {col value} {
    set conds [lmap alt [split $value ,] {
        set alt [string trim $alt]
        if {$alt eq ""} continue
        if {$col in {priority tip_number} && [regexp {^(>=|<=|>|<)0*([0-9]+)$} $alt -> op n]} {
            string cat "CAST($col AS INTEGER) $op $n"
        } elseif {$col eq "foundin" && [set values [versionValues $alt]] ne "none"} {
            # A version, a comparison, a range: the values that are such.
            if {[llength $values]} {
                string cat "trim(coalesce($col,'')) IN ([join [lmap v $values {fossil::sqlstr $v}] ,])"
            } else {
                string cat 0
            }
        } else {
            match $col $alt
        }
    }]
    if {![llength $conds]} { queryError "empty value for $col:" }
    return ([join $conds { OR }])
}

# Start and end (exclusive) dates for 2025, 2025-06 or 2025-06-17.
proc tickets::dateRange {text} {
    switch -regexp -- $text {
        {^[0-9]{4}$}                      { set start $text-01-01; set step year }
        {^[0-9]{4}-[0-9][0-9]$}           { set start $text-01;    set step month }
        {^[0-9]{4}-[0-9][0-9]-[0-9][0-9]$} { set start $text;       set step day }
        default {
            queryError "bad date \"$text\"; use YYYY, YYYY-MM or YYYY-MM-DD"
        }
    }
    # Tcl 9 rejects invalid dates, Tcl 8.6 normalizes them.
    if {[catch {clock scan $start -format %Y-%m-%d -timezone :UTC} t]
            || [clock format $t -format %Y-%m-%d -timezone :UTC] ne $start} {
        queryError "bad date \"$text\""
    }
    set end [clock format [clock add $t 1 $step -timezone :UTC] \
        -format %Y-%m-%d -timezone :UTC]
    list $start $end
}

# created:2025  updated:>=2025-06  created:2024-01-01..2024-03-31
proc tickets::dateCondition {col spec} {
    if {[regexp {^(.*)\.\.(.*)$} $spec -> lo hi]} {
        set conds {}
        if {$lo ni {"" *}} {
            lappend conds "$col >= julianday('[lindex [dateRange $lo] 0]')"
        }
        if {$hi ni {"" *}} {
            lappend conds "$col < julianday('[lindex [dateRange $hi] 1]')"
        }
        return [expr {[llength $conds] ? [join $conds { AND }] : 1}]
    }
    regexp {^(>=|<=|>|<)?(.*)$} $spec -> op text
    lassign [dateRange $text] start end
    switch -- $op {
        >  { return "$col >= julianday('$end')" }
        >= { return "$col >= julianday('$start')" }
        <  { return "$col < julianday('$start')" }
        <= { return "$col < julianday('$end')" }
    }
    return "$col >= julianday('$start') AND $col < julianday('$end')"
}

# $value with each "@me" in its comma list replaced by the logged-in user.
proc tickets::atMe {value} {
    variable me
    join [lmap alt [split $value ,] {
        if {[string tolower [string trim $alt]] eq "@me"} {
            if {$me eq ""} { queryError "@me needs a login" }
            set alt $me
        }
        set alt
    }] ,
}

# Translate the query into an SQL condition.
proc tickets::buildQuery {query canSeePrivate} {
    variable fields
    variable dateFields
    variable allFields
    variable allDateFields
    variable states
    variable countKeys
    variable columns
    variable people
    variable have
    set where {}
    set words {}
    set titleOnly 0
    foreach t [tokenize $query] {
        lassign $t neg key value
        if {$key in {author submitter assignee closer involves}} {
            set value [atMe $value]
        }
        set lvalue [string tolower $value]
        set alts [lmap a [split $lvalue ,] { string trim $a }]
        if {$key eq ""} {
            lappend words $neg $value
            continue
        } elseif {$key eq "state" && [llength $alts]
                && [llength [lmap a $alts { if {$a in $states} continue; set a }]] == 0} {
            # state:open,pending: the states, as is: (not the literal status).
            set cond "[stateExpr] IN ([join [lmap a $alts { fossil::sqlstr $a }] ,])"
        } elseif {[dict exists $fields $key]} {
            set cond [fieldCondition [dict get $fields $key] $value]
        } elseif {[dict exists $dateFields $key]} {
            set cond [dateCondition [dict get $dateFields $key] $value]
        } elseif {[dict exists $countKeys $key]} {
            set expr [dict get $columns [dict get $countKeys $key] sort]
            set cond [numberCondition $expr $key $value]
        } elseif {[dict exists $allFields $key] || [dict exists $allDateFields $key]} {
            queryError "these tickets have no $key field"
        } elseif {$key eq "is"} {
            if {$lvalue in $states} {
                set cond "[stateExpr] = [fossil::sqlstr $lvalue]"
            } elseif {$lvalue in {bug patch rfe support}} {
                set cond [match type $lvalue]
            } elseif {$lvalue eq "private"} {
                set cond [expr {$canSeePrivate && "is_private" in $have ? "is_private = 1" : 0}]
            } else {
                queryError "unknown is:$value"
            }
        } elseif {$key in {no has}} {
            if {[dict exists $countKeys $lvalue]} {
                set cond "[dict get $columns [dict get $countKeys $lvalue] sort] = 0"
            } elseif {[dict exists $fields $lvalue]} {
                set cond "coalesce([dict get $fields $lvalue],'') IN ('','nobody','None')"
            } elseif {[dict exists $allFields $lvalue]} {
                queryError "these tickets have no $lvalue field"
            } else {
                queryError "unknown field in $key:$value"
            }
            if {$key eq "has"} { set cond "NOT ($cond)" }
        } elseif {$key eq "involves"} {
            if {![llength $people]} { queryError "these tickets have no people fields" }
            set cond ([join [lmap col $people {match $col $value}] { OR }])
        } elseif {$key eq "id"} {
            set prefix [string trim $lvalue {[]}]
            set cond "substr(tkt_uuid,1,length([fossil::sqlstr $prefix])) = [fossil::sqlstr $prefix]"
        } elseif {$key eq "in"} {
            if {$lvalue ne "title"} { queryError "only in:title is supported" }
            set titleOnly 1
            continue
        } else {
            # Not a known key: "foo:bar" is free text.
            lappend words $neg $key:$value
            continue
        }
        lappend where [expr {$neg ? "NOT ($cond)" : $cond}]
    }

    # Free-text words and quoted phrases must appear in the title/description.
    # A word that looks like a ticket id also matches the id, also in [...]:
    # 6 or 7 digits are an old SourceForge number, whose converted id is the
    # number filled up with "f" (220849 -> 220849fff...f); 10 hex digits are
    # an abbreviated id (a prefix); 40 are the full id.
    foreach {neg text} $words {
        set like [fossil::sqlstr %[regsub -all {[%_\\]} $text {\\&}]%]
        set cond "title LIKE $like ESCAPE '\\'"
        if {!$titleOnly} { set cond "($cond OR comment LIKE $like ESCAPE '\\')" }
        set id [string tolower [string trim $text {[]}]]
        if {[regexp {^[0-9]{6,7}$} $id]} {
            set full $id[string repeat f [expr {40 - [string length $id]}]]
            set cond "($cond OR tkt_uuid = [fossil::sqlstr $full])"
        } elseif {[regexp {^(?:[0-9a-f]{10}|[0-9a-f]{40})$} $id]} {
            set cond "($cond OR substr(tkt_uuid,1,[string length $id]) = [fossil::sqlstr $id])"
        }
        lappend where [expr {$neg ? "NOT $cond" : $cond}]
    }
    if {!$canSeePrivate && "is_private" in $have} { lappend where {coalesce(is_private,0) = 0} }
    expr {[llength $where] ? [join $where { AND }] : 1}
}

# SQL ORDER BY for the sort order.
proc tickets::orderBy {} {
    variable sorts
    variable columns
    variable sortkey
    variable sortdir
    variable counts
    variable extra
    set order "[dict get $sorts $sortkey sort] [string toupper $sortdir], tkt_mtime DESC"
    # Empty values sort last in either direction.
    if {[dict exists $columns $sortkey] && $sortkey ni [list created updated {*}$counts]} {
        set col [dict get $columns $sortkey expr]
        set order "coalesce($col,'') IN ('','None','nobody'), $order"
    } elseif {$sortkey in [dict values $extra]} {
        set order "coalesce($sortkey,'') IN ('','None','nobody'), $order"
    }
    return $order
}

# Shown columns from a comma-separated list of names ("all" for all
# columns); unknown names are ignored.  Resolution means the Status column
# that shows it.
proc tickets::parseColumns {spec} {
    variable aliases
    variable columns
    variable extra
    set spec [string tolower $spec]
    if {$spec eq "all"} { set spec [join [dict keys $columns] ,] }
    set result {}
    foreach name [split $spec ,] {
        set key [getdef $aliases [string trim $name] ""]
        dict for {col x} $extra {
            if {$key eq $x} { set key $col }
        }
        if {[dict exists $columns $key] && $key ni $result} { lappend result $key }
    }
    return $result
}

# Sort key and direction from "<column>[-asc|-desc]", or "" if unknown.
proc tickets::parseSort {spec} {
    variable aliases
    variable sorts
    set spec [string tolower $spec]
    set dir ""
    regexp {^(.*)-(asc|desc)$} $spec -> spec dir
    if {![dict exists $aliases $spec]} { return "" }
    set key [dict get $aliases $spec]
    list $key [expr {$dir ne "" ? $dir : [dict get $sorts $key dir]}]
}

# Until a repository is used: the fields of the Tcl/Tk trackers.
tickets::configure {tkt_id tkt_uuid tkt_mtime tkt_ctime type status resolution
    subsystem priority severity foundin private_contact title comment submitter
    assignee closer closedate is_private}
