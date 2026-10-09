# Go to (Ctrl+G, the File menu of every tab): a hash prefix, a ticket id, a
# tag or a branch name, shown where it belongs: a check-in in the Timeline,
# a branch in the Branches tab, a ticket (or a change of it) in the Tickets
# tab, a wiki page or technote version in the Wiki tab, a forum post in the
# Forum tab, a file's content in the Files tab, an attachment where it is
# attached.  When the text names more than one, they are listed to choose
# from.  Also takes "[hash]" and links (.../info/HASH, .../tktview/HASH),
# and, through "fossil whatis", Fossil's other names of check-ins: tip,
# current, prev, next, root:BRANCH, start:, merge-in:, tag:NAME...; a date
# and time names the last event by then (a check-in or a ticket change...).

namespace eval goto {
    variable text ""
    variable history {}       ;# the texts gone to, newest first
    variable found {}         ;# row id -> {kind name description script}
    variable status ""
}

# What TEXT names: a list of {kind name description script}, the script
# going there.
proc goto::find {text} {
    set repo $::tktaalik::repo
    set text [string trim $text]
    # A link or a [hash]: the name in it.
    regexp {^\[([^\]]+)\]$} $text -> text
    regexp {/(?:info|tktview|forumpost|artifact|timeline\?c=)/?([0-9a-fA-F]{4,64})} $text -> text
    regexp {^(?:tkt|info):([0-9a-fA-F]{4,64})$} $text -> text
    set found {}
    if {$text eq ""} { return {} }
    set q [fossil::sqlstr $text]
    # A branch: its newest check-in carries it.
    if {[llength [fossil::sql $repo "SELECT 1 FROM tagxref WHERE tagtype>0 AND value=$q\
            AND tagid=(SELECT tagid FROM tag WHERE tagname='branch') LIMIT 1"]]} {
        lappend found [list Branch $text "" [list goto::branch $text]]
    }
    # A tag (not a branch's own): the newest check-in with it.
    set row [lindex [fossil::sql $repo "SELECT b.uuid, strftime('%Y-%m-%d %H:%M', e.mtime),\
        [fossil::outcol "coalesce(e.comment,'')"] FROM tagxref x JOIN blob b ON b.rid=x.rid\
        LEFT JOIN event e ON e.objid=x.rid WHERE x.tagtype>0\
        AND x.tagid=(SELECT tagid FROM tag WHERE tagname='sym-'||$q)\
        AND NOT EXISTS (SELECT 1 FROM tagxref y WHERE y.rid=x.rid AND y.value=$q\
            AND y.tagid=(SELECT tagid FROM tag WHERE tagname='branch'))\
        ORDER BY x.mtime DESC LIMIT 1"] 0]
    if {$row ne ""} {
        lassign $row uuid date comment
        lappend found [list Tag $text "[string range $uuid 0 9]  $date  $comment" \
            [list goto::checkin $uuid]]
    }
    if {![regexp {^[0-9a-fA-F]{4,64}$} $text]} {
        if {![llength $found]} { set found [whatis $text] }
        return $found
    }
    set p [fossil::sqlstr [string tolower $text]*]
    # Tickets (their ids are not artifacts).
    foreach row [fossil::sql $repo "SELECT tkt_uuid, [fossil::outcol "coalesce(title,'')"]\
            FROM ticket WHERE tkt_uuid GLOB $p LIMIT 20"] {
        lassign $row uuid title
        lappend found [list Ticket [string range $uuid 0 9] $title [list goto::ticket $uuid]]
    }
    # Artifacts: what each is.
    lappend found {*}[artifacts "b.uuid GLOB $p"]
    if {![llength $found]} { set found [whatis $text] }
    return $found
}

# What the artifacts matching the SQL condition WHERE (on blob b) are: a
# list as of find.
proc goto::artifacts {where} {
    set repo $::tktaalik::repo
    set found {}
    foreach row [fossil::sql $repo "SELECT b.rid, b.uuid, coalesce(e.type,''),\
            coalesce(strftime('%Y-%m-%d %H:%M', e.mtime),''), [fossil::outcol "coalesce(e.user,'')"],\
            [fossil::outcol "coalesce(e.comment,'')"]\
            FROM blob b LEFT JOIN event e ON e.objid=b.rid WHERE $where LIMIT 20"] {
        lassign $row rid uuid type date user comment
        set short [string range $uuid 0 9]
        set about [string trim "$date  $user  $comment"]
        switch -- $type {
            ci {
                lappend found [list Check-in $short $about [list goto::checkin $uuid]]
                continue
            }
            t {
                # A change of a ticket: tagged tkt-UUID.
                set tkt [tagOf $rid tkt-*]
                if {$tkt ne ""} {
                    set tkt [string range $tkt 4 end]
                    lappend found [list "Ticket change" $short $about [list goto::ticket $tkt]]
                    continue
                }
            }
            w - e {
                set tag [tagOf $rid [expr {$type eq "w" ? "wiki-*" : "event-*"}]]
                if {$tag ne ""} {
                    set kind [expr {$type eq "w" ? "Wiki page" : "Technote"}]
                    lappend found [list $kind $short $about [list goto::wiki $tag $uuid]]
                    continue
                }
            }
            f {
                lappend found [list "Forum post" $short $about [list goto::forum $uuid]]
                continue
            }
        }
        if {$type ne ""} {
            # Other events (tag changes...): in the Timeline.
            lappend found [list Event $short $about [list goto::checkin $uuid]]
            continue
        }
        # A file's content: the first check-in with it.
        set file [lindex [fossil::sql $repo "SELECT c.uuid, [fossil::outcol n.name],\
            strftime('%Y-%m-%d %H:%M', e.mtime) FROM mlink m JOIN filename n ON n.fnid=m.fnid\
            JOIN blob c ON c.rid=m.mid JOIN event e ON e.objid=m.mid\
            WHERE m.fid=$rid ORDER BY e.mtime LIMIT 1"] 0]
        if {$file ne ""} {
            lassign $file ci name date
            lappend found [list File $short "$name  (in [string range $ci 0 9], $date)" \
                [list goto::file $ci $name]]
            continue
        }
        # An attachment: where it is attached.
        set att [lindex [fossil::sql $repo "SELECT a.target, [fossil::outcol a.filename]\
            FROM attachment a WHERE a.src=[fossil::sqlstr $uuid] ORDER BY a.mtime DESC LIMIT 1"] 0]
        if {$att ne ""} {
            lassign $att target name
            lappend found [list Attachment $short "$name, on $target" [list goto::attached $target]]
            continue
        }
        lappend found [list Artifact $short "(a control artifact or a cluster: nothing to show)" {}]
    }
    return $found
}

# Fossil's other names of check-ins ("fossil whatis"): tip, current,
# prev, next (in a checkout), dates, root:BRANCH, start:, merge-in:,
# tag:NAME...  Then what the artifacts are, as for a hash.
proc goto::whatis {name} {
    set repo $::tktaalik::repo
    set root $::tktaalik::root
    # (fossil takes "-..." for an option, exec "<..." for a redirection.)
    if {[catch {fossil::arg $name}]} { return {} }
    if {$root ne ""} {
        # In the checkout: its current, prev and next.
        lassign [fossil::run -dir $root whatis $name] code out
    } else {
        lassign [fossil::run whatis $name -R $repo] code out
    }
    # (Without -q, which Fossil 2.21 lacks: an unknown name is "unknown:",
    # with no artifact line.)
    if {$code} { return {} }
    set uuids [lsort -unique [lmap {- uuid} [regexp -all -inline -line {^artifact:\s+([0-9a-f]{40,64})$} $out] {set uuid}]]
    if {![llength $uuids]} { return {} }
    set found [artifacts "b.uuid IN ([join [lmap u $uuids {fossil::sqlstr $u}] ,])"]
    # Named as asked: "tip", not the hash.
    lmap item $found { lset item 1 "$name ([lindex $item 1])"; set item }
}

# The tag of an artifact matching PATTERN (wiki-*, event-*, tkt-*).
proc goto::tagOf {rid pattern} {
    lindex [fossil::sql $::tktaalik::repo "SELECT t.tagname FROM tagxref x JOIN tag t\
        ON t.tagid=x.tagid WHERE x.rid=$rid AND t.tagname GLOB [fossil::sqlstr $pattern]\
        LIMIT 1"] 0 0
}

# ---------------------------------------------------------------- links

# Where a link in a rendered text can be shown in the application: a
# script, or "" (then it is for the browser).  Links to an artifact or a
# ticket (info:HASH, /info/NAME, /timeline?c=NAME, /tktview/HASH...), to a
# branch or a tag (/timeline?r=BRANCH, /timeline?t=TAG), to a diff
# (/vdiff?branch=BRANCH, /vdiff?from=A&to=B); also as URLs of the
# repository's own server.  Remembered for each repository.
proc goto::linkTarget {href} {
    variable linkCache
    set repo $::tktaalik::repo
    if {$repo eq ""} { return "" }
    set key $repo\n$href
    if {[info exists linkCache($key)]} { return $linkCache($key) }
    set linkCache($key) ""
    # A URL of this repository's server: its path.
    variable remotes
    if {![info exists remotes($repo)]} { set remotes($repo) [fossil::remoteUrl $repo] }
    set remote $remotes($repo)
    if {$remote ne "" && [string match -nocase $remote/* $href]} {
        set href [string range $href [string length $remote] end]
    }
    if {[regexp -nocase {^(?:info|tkt):([0-9a-f]{4,64})$} $href -> name]} {
        set script [nameTarget [string tolower $name] artifact]
    } elseif {![regexp {^/([a-z]+)(?:/([^?#]*))?(?:\?([^#]*))?} $href -> page rest query]} {
        return ""
    } else {
        set params {}
        foreach pair [split $query &] {
            if {[regexp {^([^=]+)=(.*)$} $pair -> k v]} { dict set params $k [fossil::urlDecode $v] }
        }
        set rest [fossil::urlDecode $rest]
        set script ""
        switch -- $page {
            info - ci - vinfo - artifact - hexdump - tktview - forumpost - forumthread {
                set name [expr {$rest ne "" ? $rest : [dictGet $params name]}]
                if {$name ne ""} { set script [nameTarget $name artifact] }
            }
            timeline {
                foreach {k how} {r branch t branch c artifact} {
                    if {[dict exists $params $k]} {
                        set script [nameTarget [dict get $params $k] $how]
                        break
                    }
                }
            }
            vdiff {
                if {[dict exists $params branch]} {
                    set b [dict get $params branch]
                    if {[nameTarget $b branch] ne ""} { set script [list goto::diffBranch $b] }
                } elseif {[dict exists $params from] && [dict exists $params to]} {
                    set from [dict get $params from]
                    set to [dict get $params to]
                    if {[nameTarget $from artifact] ne "" && [nameTarget $to artifact] ne ""} {
                        set script [list goto::diffVersions $from $to]
                    }
                }
            }
        }
    }
    set linkCache($key) $script
    return $script
}

proc goto::dictGet {d key} {
    expr {[dict exists $d $key] ? [dict get $d $key] : ""}
}

# What NAME (a hash, a branch, a tag...) is to be shown as: the script of
# its first kind in the order of PREFER (artifact: a check-in first;
# branch: the branch, a tag's check-in).
proc goto::nameTarget {name prefer} {
    set repo $::tktaalik::repo
    if {[catch {fossil::arg $name}] || [string length $name] > 200} { return "" }
    try {
        if {[regexp {^[0-9a-f]{40,64}$} $name]} {
            # A whole hash (as hashLinks makes them): the artifact, or
            # the ticket.
            set items [artifacts "b.uuid=[fossil::sqlstr $name]"]
            if {![llength $items] && [llength [fossil::sql $repo "SELECT 1 FROM ticket\
                    WHERE tkt_uuid=[fossil::sqlstr $name]"]]} {
                set items [list [list Ticket $name "" [list goto::ticket $name]]]
            }
        } else {
            set items [find $name]
        }
    } trap {FOSSIL DB} {} {
        return ""
    }
    set order [expr {$prefer eq "branch"
        ? {Branch Tag Check-in}
        : {Check-in Ticket "Ticket change" "Wiki page" Technote "Forum post" File Attachment Event Tag Branch}}]
    foreach kind $order {
        foreach item $items {
            if {[lindex $item 0] eq $kind && [lindex $item 3] ne ""} { return [lindex $item 3] }
        }
    }
    return ""
}

# Follow a link in the application if it can be: 1 if it was.
proc goto::openLink {href} {
    set script [linkTarget $href]
    if {$script eq ""} { return 0 }
    uplevel #0 $script
    return 1
}

# ---------------------------------------------------------------- going

proc goto::checkin {uuid} {
    tktaalik::navigate
    if {![tktaalik::show timeline]} return
    tktimeline::setQuery hash:[string range $uuid 0 15]
}

proc goto::branch {name} {
    tktaalik::navigate
    if {![tktaalik::show branches]} return
    tkbranches::showBranch $name
}

proc goto::ticket {uuid} {
    tktaalik::navigate
    if {![tktaalik::show tickets]} return
    tktsearch::showTicket $uuid
}

# A wiki page or technote (TAG), at the version UUID.
proc goto::wiki {tag uuid} {
    set i [lsearch -exact [concat {*}[fossil::sql $::tktaalik::repo "SELECT b.uuid\
        FROM tag t JOIN tagxref x ON x.tagid=t.tagid JOIN blob b ON b.rid=x.rid\
        WHERE t.tagname=[fossil::sqlstr $tag] ORDER BY x.mtime DESC"]] $uuid]
    tktaalik::navigate
    if {![tktaalik::show wiki]} return
    # (All pages, deleted ones too: as Back and Forward go to a place.)
    tkwiki::goTo [list all "" 1 $tag [expr {max($i, 0)}] ""]
}

# Diffs (/vdiff links): in the diff window.
proc goto::diffBranch {name} {
    diffview::run "Branch $name" -- -R $::tktaalik::repo --branch [fossil::arg $name]
}

proc goto::diffVersions {from to} {
    diffview::run "[string range $from 0 9] \u2192 [string range $to 0 9]" -- \
        -R $::tktaalik::repo --from [fossil::arg $from] --to [fossil::arg $to]
}

proc goto::forum {uuid} {
    tktaalik::navigate
    if {![tktaalik::show forum]} return
    tkforum::showPost $uuid 0
}

# A file at a check-in: its content.
proc goto::file {checkin name} {
    tktaalik::navigate
    if {![tktaalik::show files]} return
    tkfiles::goTo [list $checkin "" $name .files.main.right.nb.content ""]
}

# Where an attachment is: a ticket, else a wiki page or technote.
proc goto::attached {target} {
    set repo $::tktaalik::repo
    if {[llength [fossil::sql $repo "SELECT 1 FROM ticket WHERE tkt_uuid=[fossil::sqlstr $target]"]]} {
        ticket $target
    } elseif {[llength [fossil::sql $repo "SELECT 1 FROM tag WHERE tagname='event-'||[fossil::sqlstr $target]"]]} {
        wiki event-$target ""
    } else {
        wiki wiki-$target ""
    }
}

# ---------------------------------------------------------------- window

proc goto::window {} {
    variable history
    if {[tktaalik::dialogWindow .goto "Go to"]} { build }
    wm transient .goto .
    .goto.top.e configure -values $history
    focus .goto.top.e
    .goto.top.e selection range 0 end
}

proc goto::build {} {
    wm geometry .goto 720x300
    ttk::frame .goto.top -padding {8 8 8 4}
    ttk::label .goto.top.l -text "Hash, ticket id, tag or branch:"
    ttk::combobox .goto.top.e -textvariable goto::text -font TkFixedFont -width 40
    icons::tooltip .goto.top.e "A hash or a prefix of one, a ticket id, a tag, a branch;\nalso tip, current, prev, next, a date (2026-09-01: the last event by then),\nroot:BRANCH, start:BRANCH, merge-in:BRANCH"
    ttk::button .goto.top.go -text Go -default active -command goto::go
    pack .goto.top.l -side left
    pack .goto.top.go -side right -padx {4 0}
    pack .goto.top.e -side left -fill x -expand 1 -padx {6 0}
    ttk::frame .goto.list
    set t .goto.list.t
    ttk::treeview $t -columns {kind name about} -show headings -selectmode browse \
        -yscrollcommand {.goto.list.y set}
    ttk::scrollbar .goto.list.y -command [list $t yview]
    set char [font measure TkDefaultFont 0]
    foreach {col heading width stretch} {kind Kind 12 0 name Name 14 0 about "" 50 1} {
        $t heading $col -text $heading -anchor w
        $t column $col -width [expr {$width * $char}] -stretch $stretch
    }
    $t tag configure none -foreground gray50
    grid $t .goto.list.y -sticky news
    grid columnconfigure .goto.list 0 -weight 1
    grid rowconfigure .goto.list 0 -weight 1
    ttk::label .goto.status -textvariable goto::status -padding {8 2} -anchor w
    pack .goto.top -fill x
    pack .goto.status -side bottom -fill x
    pack .goto.list -fill both -expand 1 -padx 8
    bind .goto.top.e <Return> goto::go
    bind .goto.top.e <<ComboboxSelected>> goto::go
    bind .goto.top.e <Down> {
        set t .goto.list.t
        if {[llength [$t children {}]]} { focus $t; $t selection set [lindex [$t children {}] 0] }
        break
    }
    bind $t <Double-1> {goto::choose [.goto.list.t identify item %x %y]}
    bind $t <Return> {goto::choose [lindex [.goto.list.t selection] 0]}
    popup::attach $t goto::popupMenu
}

# Find the text: one thing, go there; several, list them.
proc goto::go {} {
    variable text
    variable history
    variable found
    variable status
    set t .goto.list.t
    $t delete [$t children {}]
    set found {}
    set text [string trim $text]
    if {$text eq ""} return
    if {$::tktaalik::repo eq ""} { set status "No repository"; return }
    try {
        set items [find $text]
    } trap {FOSSIL DB} msg {
        set status "Cannot search: $msg"
        return
    }
    set history [lrange [linsert [lsearch -all -inline -not -exact $history $text] 0 $text] 0 29]
    .goto.top.e configure -values $history
    if {![llength $items]} {
        set status "Nothing named \"$text\": not a hash prefix, ticket id, tag, branch or other\
            name of a check-in here"
        bell
        return
    }
    set n 0
    foreach item $items {
        lassign $item kind name about script
        set id i[incr n]
        dict set found $id $item
        $t insert {} end -id $id -values [list $kind $name $about] \
            -tags [expr {$script eq "" ? "none" : ""}]
    }
    if {[llength $items] == 1 && [lindex $items 0 3] ne ""} {
        choose i1
        return
    }
    set status "[llength $items] things named \"$text\": choose one (double-click, Return)"
    focus $t
    $t selection set i1
    $t focus i1
}

proc goto::choose {id} {
    variable found
    variable status
    if {$id eq "" || ![dict exists $found $id]} return
    set script [lindex [dict get $found $id] 3]
    if {$script eq ""} { bell; return }
    set status ""
    wm withdraw .goto
    uplevel #0 $script
}

# The context menu of a match.
proc goto::popupMenu {m item} {
    variable found
    if {![dict exists $found $item]} return
    lassign [dict get $found $item] kind name about script
    $m add command -label "Go to it" -command [list goto::choose $item] \
        -state [expr {$script eq "" ? "disabled" : "normal"}]
    popup::separator $m
    popup::copy $m "Copy name" $name
    popup::default $m "Go to it"
}
