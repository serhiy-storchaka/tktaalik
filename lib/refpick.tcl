# References to a repository's tickets, check-ins and branches, for the
# text editors (formattext): what a text names, and a window to find one.
#
#   refpick::resolve REPO KIND TEXT
#       the ticket or check-in (KIND ticket, checkin) whose hash starts
#       with TEXT, or the branch named TEXT: its full hash or name; ""
#       if none, or more than one
#   refpick::choose PARENT REPO KIND QUERY COMMAND
#       a window to find one (searched as typed, from QUERY): the one
#       chosen given to COMMAND (appended), then the window closed; the
#       window
#   refpick::find REPO KIND QUERY
#       what the window lists: {ID CELLS} rows, the newest first (200 at
#       most)

source [file join [file dirname [file normalize [info script]]] fossil.tcl]
source [file join [file dirname [file normalize [info script]]] ui.tcl]
source [file join [file dirname [file normalize [info script]]] tablecols.tcl]

namespace eval refpick {
    variable pick               ;# array: window -> {repo kind command}
    variable titles {ticket "Insert a ticket" checkin "Insert a check-in" branch "Insert a branch"}
}

proc refpick::resolve {repo kind text} {
    set text [string trim $text]
    if {$repo eq "" || $text eq ""} { return "" }
    if {$kind eq "branch"} {
        set rows [fossil::sql $repo "SELECT 1 FROM tagxref WHERE tagtype>0
            AND tagid=(SELECT tagid FROM tag WHERE tagname='branch')
            AND value=[fossil::sqlstr $text] LIMIT 1"]
        return [expr {[llength $rows] ? $text : ""}]
    }
    if {![regexp {^[0-9a-fA-F]{4,64}$} $text]} { return "" }
    set glob [fossil::sqlstr "[string tolower $text]*"]
    if {$kind eq "ticket"} {
        set rows [fossil::sql $repo "SELECT tkt_uuid FROM ticket WHERE tkt_uuid GLOB $glob LIMIT 2"]
    } else {
        set rows [fossil::sql $repo "SELECT b.uuid FROM blob b JOIN event e ON e.objid=b.rid
            WHERE e.type='ci' AND b.uuid GLOB $glob LIMIT 2"]
    }
    expr {[llength $rows] == 1 ? [lindex $rows 0 0] : ""}
}

proc refpick::find {repo kind query} {
    set query [string trim $query]
    # The text anywhere (LIKE, its % and _ taken as they are), or a hash
    # prefix.
    set like [fossil::sqlstr "%[string map {\\ \\\\ % \\% _ \\_} $query]%"]
    set hex [regexp {^[0-9a-fA-F]+$} $query]
    set glob [fossil::sqlstr "[string tolower $query]*"]
    switch -- $kind {
        ticket {
            set where [expr {$query eq "" ? "" : "WHERE [fossil::outcol "coalesce(title,'')"] LIKE $like ESCAPE '\\'
                [expr {$hex ? "OR tkt_uuid GLOB $glob" : ""}]"}]
            # (Old schemas may have no title or status: the hash only then.)
            if {[catch {fossil::sql $repo "SELECT tkt_uuid, [fossil::outcol "coalesce(title,'')"],
                    [fossil::outcol "coalesce(status,'')"], date(tkt_mtime)
                    FROM ticket $where ORDER BY tkt_mtime DESC LIMIT 200"} rows]} {
                set rows [fossil::sql $repo "SELECT tkt_uuid, '', '', date(tkt_mtime) FROM ticket
                    [expr {$hex ? "WHERE tkt_uuid GLOB $glob" : ""}] ORDER BY tkt_mtime DESC LIMIT 200"]
            }
            lmap row $rows {
                lassign $row id title status date
                list $id [dict create id [string range $id 0 9] title $title status $status date $date]
            }
        }
        checkin {
            set comment [fossil::outcol "coalesce(e.ecomment,e.comment,'')"]
            set where [expr {$query eq "" ? "" : "AND ($comment LIKE $like ESCAPE '\\'
                [expr {$hex ? "OR b.uuid GLOB $glob" : ""}])"}]
            lmap row [fossil::sql $repo "SELECT b.uuid, $comment, [fossil::outcol "coalesce(e.euser,e.user,'')"],
                    datetime(e.mtime) FROM event e JOIN blob b ON b.rid=e.objid
                    WHERE e.type='ci' $where ORDER BY e.mtime DESC LIMIT 200"] {
                lassign $row id comment user date
                list $id [dict create id [string range $id 0 9] title $comment status $user date $date]
            }
        }
        branch {
            set where [expr {$query eq "" ? "" : "AND value LIKE $like ESCAPE '\\'"}]
            lmap row [fossil::sql $repo "SELECT [fossil::outcol value], date(max(mtime)) FROM tagxref
                    WHERE tagtype>0 AND tagid=(SELECT tagid FROM tag WHERE tagname='branch') $where
                    GROUP BY value ORDER BY max(mtime) DESC LIMIT 200"] {
                lassign $row name date
                list $name [dict create id $name date $date]
            }
        }
    }
}

proc refpick::choose {parent repo kind query command} {
    variable pick
    variable titles
    set w [winfo toplevel $parent].refpick
    set f [ui::dialog $w [dict get $titles $kind] -escape [list destroy $w] -bar 1 \
        -help tickets#references]
    wm transient $w [winfo toplevel $parent]
    set pick($w) [dict create repo $repo kind $kind command $command]
    bind $w <Destroy> [list refpick::forget $w %W]
    ttk::entry $f.q
    $f.q insert 0 $query
    ttk::frame $f.list
    set t [ttk::treeview $f.list.t -show headings -selectmode browse -height 14 \
        -yscrollcommand [list $f.list.y set]]
    ttk::scrollbar $f.list.y -command [list $t yview]
    pack $f.list.y -side right -fill y
    pack $t -fill both -expand 1
    set cols [dict get {
        ticket {id {heading Ticket width 12} title {heading Title width 50 stretch 1}
                status {heading Status width 10} date {heading Changed width 11}}
        checkin {id {heading Check-in width 12} title {heading Comment width 50 stretch 1}
                 status {heading User width 12} date {heading Date width 17}}
        branch {id {heading Branch width 40 stretch 1} date {heading "Last check-in" width 12}}
    } $kind]
    tablecols::setup $t $cols -fixed [dict keys $cols] -sort {date desc}
    ui::buttons $w.b Insert [list refpick::done $w] [list destroy $w]
    # (The buttons kept when the window is made small.)
    pack configure $w.b -before $w.f
    pack $f.q -fill x -pady {0 6}
    pack $f.list -fill both -expand 1
    bind $f.q <KeyRelease> [list ui::later [list refpick::search $w] 250]
    bind $f.q <Return> [list refpick::done $w]
    bind $f.q <Down> [list refpick::move $w 1]
    bind $f.q <Up> [list refpick::move $w -1]
    bind $t <Double-1> [list refpick::done $w]
    bind $t <Return> [list refpick::done $w]
    search $w
    focus $f.q
    $f.q selection range 0 end
    return $w
}

proc refpick::forget {w window} {
    variable pick
    if {$window eq $w} { unset -nocomplain pick($w) }
}

# The list for the text searched (again only if it has changed).
proc refpick::search {w} {
    variable pick
    if {![winfo exists $w]} return
    set query [$w.f.q get]
    if {[dict exists $pick($w) last] && [dict get $pick($w) last] eq $query} return
    dict set pick($w) last $query
    set t $w.f.list.t
    if {[catch {find [dict get $pick($w) repo] [dict get $pick($w) kind] $query} rows]} {
        set rows {}
    }
    tablecols::fill $t $rows
    set first [lindex [$t children {}] 0]
    if {$first ne ""} { $t selection set [list $first]; $t focus $first; $t see $first }
}

proc refpick::move {w by} {
    set t $w.f.list.t
    set items [$t children {}]
    if {![llength $items]} return
    set i [lsearch -exact $items [lindex [$t selection] 0]]
    set i [expr {max(0, min([llength $items] - 1, $i + $by))}]
    set item [lindex $items $i]
    $t selection set [list $item]
    $t focus $item
    $t see $item
}

# The one selected (else the first) to the command.
proc refpick::done {w} {
    variable pick
    # (A search still waiting: done first.)
    search $w
    set t $w.f.list.t
    set id [lindex [$t selection] 0]
    if {$id eq ""} { set id [lindex [$t children {}] 0] }
    if {$id eq ""} { bell; return }
    set command [dict get $pick($w) command]
    destroy $w
    uplevel #0 [list {*}$command $id]
}
