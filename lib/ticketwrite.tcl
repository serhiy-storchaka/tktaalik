# Writing tickets: comments, field changes and new tickets, for the Tk
# application "tktsearch".  Uses lib/ticketquery.tcl (tickets::sql,
# tickets::repo, tickets::me).
#
# The changes go through "fossil ticket set/add" in the local repository and
# are never synced: pushing them stays a separate step.  The fields and
# values are passed in a file (the global --args option), one per line, with
# --quote decoding (not "-q": since Fossil 2.28 that is the global --quiet,
# and the values would be stored undecoded).  So a value may start with "<",
# "|" or ">" (which exec would take as a redirection) and contain anything:
#   - "\" is written as "\\", line breaks and tabs as "\n", "\r", "\t";
#   - a leading "-" as "\-" (--quote decodes it, and the line is then not taken
#     for an option, which would also be split at the first space).
# Empty values cannot be written this way: --args skips empty lines, and on
# the command line Fossil ignores an empty value.

namespace eval tickets {
    variable writeRepo ""       ;# the repository the fields below are for
    variable ticketFields {}    ;# writable fields of the ticket table
    variable changeFields {}    ;# and of ticketchng (comments)
}

# The fields "fossil ticket" accepts: the columns of ticket and ticketchng
# except Fossil's own tkt_* columns.
proc tickets::writableFields {} {
    variable writeRepo
    variable repo
    variable ticketFields
    variable changeFields
    if {$writeRepo ne $repo} {
        foreach {var table} {ticketFields ticket changeFields ticketchng} {
            set $var [lmap row [sql "SELECT name FROM pragma_table_info('$table')"] {
                set name [lindex $row 0]
                if {[string match tkt_* $name]} continue
                set name
            }]
        }
        set writeRepo $repo
    }
    list $ticketFields $changeFields
}

# (A field "+NAME" appends to NAME: "fossil ticket set" does that.)
proc tickets::canWrite {field} {
    lassign [writableFields] ticket change
    set field [string trimleft $field +]
    expr {$field in $ticket || $field in $change}
}

# A value as a line of the --args file, for --quote decoding.
proc tickets::argLine {value} {
    set line [string map {\\ \\\\ \n \\n \r \\r \t \\t} $value]
    if {[string match -* $line]} { set line \\$line }
    return $line
}

proc tickets::writeError {msg} {
    throw {TICKETS WRITE} $msg
}

# The number of changes of ticket $uuid that Fossil has applied (each has
# a ticket event in the timeline).
proc tickets::appliedChanges {uuid} {
    lindex [sql "SELECT count(*) FROM ticketchng c JOIN event e\
        ON e.objid=c.tkt_rid AND e.type='t'\
        WHERE c.tkt_id=(SELECT tkt_id FROM ticket WHERE tkt_uuid=[fossil::sqlstr $uuid])"] 0 0
}

# Change ticket $uuid ("set") or create one ("add", $uuid ""): $fields is
# a dict of field names and values.  Returns the ticket's id.  Errors are
# thrown as {TICKETS WRITE}.
proc tickets::writeTicket {mode uuid fields} {
    variable repo
    if {![dict size $fields]} { writeError "nothing to change" }
    dict for {field value} $fields {
        if {![canWrite $field]} { writeError "these tickets have no field \"$field\"" }
        if {$value eq ""} {
            writeError "\"$field\" cannot be set to an empty value from here"
        }
    }
    set before [expr {$mode eq "set" ? [appliedChanges $uuid] : 0}]

    set f [file tempfile argsfile]
    fconfigure $f -encoding utf-8 -translation lf
    dict for {field value} $fields {
        puts $f $field
        puts $f [argLine $value]
    }
    close $f
    set command [list fossil ticket $mode]
    if {$mode eq "set"} { lappend command $uuid }
    lappend command --quote -R $repo --args $argsfile
    set cmd [fossil::command $command]
    set code [catch {exec {*}$cmd << "" 2>@1} out]
    file delete $argsfile
    set out [regsub {\n?child process exited abnormally$} $out ""]
    if {$code || ![regexp {ticket (?:set|add) succeeded for ([0-9a-f]+)} $out -> id]} {
        writeError [string trim $out]
    }
    # Make sure Fossil applied it: a malformed change is stored but ignored.
    if {[appliedChanges $id] <= $before} {
        writeError "Fossil stored the change but did not apply it ($id)"
    }
    return $id
}

# The *_choices lists of the ticket-common script (the values the web
# pages offer), without running the script: a dict like
# {type {Bug Support Patch RFE} status {...} ...}.
proc tickets::choices {} {
    set script [lindex [sql "SELECT value FROM config WHERE name='ticket-common'"] 0 0]
    set result {}
    foreach {match name} [regexp -all -inline -indices -line \
            {^\s*set\s+(\w+)_choices\s+\{} $script] {
        # The opening brace is the last character of the match.
        set from [lindex $match 1]
        # The matching closing brace: the shortest complete word.
        for {set to $from} {$to < [string length $script]} {incr to} {
            if {[string index $script $to] eq "\}"
                    && [info complete [string range $script $from $to]]} break
        }
        set list [string range $script [expr {$from + 1}] [expr {$to - 1}]]
        if {![catch {llength $list}]} {
            dict set result [string range $script {*}$name] $list
        }
    }
    return $result
}

# The number of artifacts not pushed yet.
proc tickets::unsent {} {
    lindex [sql "SELECT count(*) FROM unsent"] 0 0
}
