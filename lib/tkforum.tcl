# The Forum tab of tktaalik: the threads of the repository's forum, newest
# activity first, and the posts of the one selected, threaded (replies
# after the post they answer, indented), each the newest version of it,
# rendered by Fossil (Markdown, wiki or plain text).  Links to other posts
# open their thread here, links to tickets in the Tickets tab, others in
# the browser.  New threads and replies are sent to the server through
# its web forms (web::forumPost), then pulled.

source [file join [file dirname [file normalize [info script]]] fossil.tcl]
source [file join [file dirname [file normalize [info script]]] tablecols.tcl]
source [file join [file dirname [file normalize [info script]]] htmltext.tcl]
source [file join [file dirname [file normalize [info script]]] web.tcl]

namespace eval tkforum {
    variable repo ""
    variable root ""
    variable remote ""
    variable threads          ;# array: root post rid -> dict of the thread
    variable filter ""
    variable searched ""      ;# the filter of the list shown
    variable limit 1000       ;# threads shown; More doubles it
    variable total 0
    variable selected ""      ;# the root of the thread shown
    variable status ""
    variable hashes {}        ;# [hash] in the thread shown -> link
    variable marks {}         ;# post hash -> its position in the text
    variable scrollTo {}      ;# {thread post}: where showThread scrolls
    variable posts {}         ;# the posts shown: {rid depth edited} each
    variable me ""            ;# the default user: who posts
    variable format Markdown  ;# of new posts
    variable formats {
        Markdown text/x-markdown  "Fossil wiki" text/x-fossil-wiki  {Plain text} text/plain
    }
    variable postTitle ""     ;# of a new thread
    variable webUser          ;# server URL -> the user to post as
    variable webPassword ""   ;# in the window
    variable passwords        ;# server URL -> password (this session only)
    variable config {}
    variable configFile [config::path forum]
}

proc tkforum::loadConfig {} {
    variable configFile
    variable config
    set config [config::get $configFile forum]
}

proc tkforum::saveConfig {} {
    variable configFile
    variable config
    variable filter
    if {[winfo exists .forum.main.list.t]} {
        dict set config table [tablecols::state .forum.main.list.t]
    }
    dict set config filter $filter
    config::put $configFile $config {table}
}

proc tkforum::build {} {
    variable config
    variable filter
    menu .forum.menu
    .forum.menu add cascade -label File -underline 0 -menu [menu .forum.menu.file]
    tktaalik::fileMenu .forum.menu.file
    .forum.menu.file add command -label Refresh -underline 0 -accelerator F5 -command tkforum::reload
    tktaalik::quitEntry .forum.menu.file
    .forum.menu add cascade -label Forum -underline 1 -menu [menu .forum.menu.forum]
    .forum.menu.forum add command -label "New thread\u2026" -underline 0 -accelerator Ctrl+N \
        -command tkforum::compose
    loadConfig
    set filter [tktaalik::getdef $config filter ""]

    ttk::frame .forum.top -padding {6 6 6 2}
    ttk::label .forum.top.fl -text "Find:"
    ttk::entry .forum.top.filter -textvariable tkforum::filter -width 40
    pack .forum.top.fl .forum.top.filter -side left -padx {0 6}
    icons::tooltip .forum.top.filter "Words of the title, or the user who started the thread"
    trace add variable ::tkforum::filter write {::apply {args {
        tktaalik::typing .forum.top.filter
        after cancel tkforum::reload
        after 300 tkforum::reload
    }}}

    ttk::panedwindow .forum.main -orient vertical
    ttk::frame .forum.main.list
    set t .forum.main.list.t
    ttk::treeview $t -show headings -selectmode browse -yscrollcommand {.forum.main.list.y set}
    ttk::scrollbar .forum.main.list.y -command [list $t yview]
    grid $t .forum.main.list.y -sticky news
    grid columnconfigure .forum.main.list 0 -weight 1
    grid rowconfigure .forum.main.list 0 -weight 1
    set table [tktaalik::getdef $config table {}]
    tablecols::setup $t {
        title    {heading Thread width 50 stretch 1}
        user     {heading "Started by" width 14}
        started  {heading Started width 16 dir desc}
        last     {heading "Last post" width 16 dir desc}
        lastuser {heading "Last by" width 14}
        posts    {heading Posts width 6 type integer dir desc anchor e}
    } -fixed {title} -defaults {user started last lastuser posts} \
        -shown [tktaalik::getdef $table shown {}] -order [tktaalik::getdef $table order {}] \
        -sort [tktaalik::getdef $table sort {last desc}]

    ttk::frame .forum.main.thread
    set d .forum.main.thread.text
    text $d -wrap word -height 16 -padx 8 -pady 6 -font TkTextFont -state disabled \
        -yscrollcommand {.forum.main.thread.y set}
    ttk::scrollbar .forum.main.thread.y -command [list $d yview]
    $d tag configure title -font TkHeadingFont -spacing3 6
    $d tag configure head -font TkHeadingFont -spacing1 8 -spacing3 2
    $d tag configure meta -font TkDefaultFont -foreground gray40
    $d tag configure missing -foreground gray45
    grid $d .forum.main.thread.y -sticky news
    grid columnconfigure .forum.main.thread 0 -weight 1
    grid rowconfigure .forum.main.thread 0 -weight 1
    .forum.main add .forum.main.list -weight 2
    .forum.main add .forum.main.thread -weight 3

    ttk::frame .forum.b -padding {6 2}
    ttk::label .forum.b.status -textvariable tkforum::status -anchor w
    ttk::button .forum.b.more -text More -command tkforum::more
    ttk::button .forum.b.browse -text "Open in browser" -command tkforum::browse
    ttk::button .forum.b.new -text "New thread\u2026" -command tkforum::compose
    pack .forum.b.browse .forum.b.more .forum.b.new -side right -padx {4 0}
    pack .forum.b.status -side left -fill x -expand 1
    pack .forum.top -fill x
    pack .forum.b -side bottom -fill x
    pack .forum.main -fill both -expand 1

    bind $t <<TreeviewSelect>> {tkforum::showThread [lindex [.forum.main.list.t selection] 0]}
    tktaalik::shortcut forum <F5> tkforum::reload
    tktaalik::shortcut forum <Control-n> tkforum::compose
    ttk::style configure Small.TButton -padding {8 0} -width 0
    tktaalik::shortcut forum <Control-f> {focus .forum.top.filter; .forum.top.filter selection range 0 end}
    popup::attach .forum.main.list.t tkforum::popupMenu
}

proc tkforum::setRepository {path newRoot} {
    variable repo $path
    variable root $newRoot
    variable remote [fossil::remoteUrl $path]
    variable me
    lassign [fossil::run user default -R $path] code out
    set me [expr {$code ? "" : [string trim $out]}]
    variable limit 1000
    tktaalik::setTitle forum "Forum \u2014 [file rootname [file tail $repo]]"
    reload
}

proc tkforum::activate {} {
    if {[tktaalik::changed forum]} { reload }
    focus .forum.main.list.t
}

# The title of a thread from the timeline comment of its first post
# ("Post: TITLE").
proc tkforum::title {comment} {
    regsub {^[^:]*:\s*} $comment {} comment
    return $comment
}

# The threads: the newest activity first, as many as the limit; with the
# filter, those whose title or starter has it.
proc tkforum::reload {} {
    variable repo
    variable threads
    variable filter
    variable searched
    variable limit
    variable total
    variable status
    variable selected
    after cancel tkforum::reload
    array unset threads
    set searched $filter
    set f [string tolower [string trim $filter]]
    set where ""
    if {$f ne ""} {
        set like [fossil::sqlstr %[string map {% \\% _ \\_ \\ \\\\} $f]%]
        set where "AND (lower(e.comment) LIKE $like ESCAPE '\\' OR lower(e.user) LIKE $like ESCAPE '\\')"
    }
    set rows {}
    set total 0
    try {
        # The posts that are not replaced by an edit; per thread the newest
        # of them, and how many.
        set with "WITH replaced(rid) AS MATERIALIZED (
             SELECT fprev FROM forumpost WHERE fprev IS NOT NULL),
            cur AS MATERIALIZED (SELECT f.fpid, f.froot, f.fmtime,
             row_number() OVER (PARTITION BY f.froot ORDER BY f.fmtime DESC) AS k,
             count(*) OVER (PARTITION BY f.froot) AS n
             FROM forumpost f WHERE f.fpid NOT IN replaced)"
        set rows [fossil::sql $repo "$with SELECT c.froot, c.n,
             strftime('%Y-%m-%d %H:%M', r.fmtime), strftime('%Y-%m-%d %H:%M', c.fmtime),
             [fossil::outcol "coalesce(e.user,'')"], [fossil::outcol "coalesce(e.comment,'')"],
             [fossil::outcol "coalesce(le.user,'')"]
            FROM cur c JOIN forumpost r ON r.fpid=c.froot
            LEFT JOIN event e ON e.objid=c.froot LEFT JOIN event le ON le.objid=c.fpid
            WHERE c.k=1 $where ORDER BY c.fmtime DESC LIMIT $limit"]
        set total [lindex [fossil::sql $repo "$with SELECT count(*) FROM cur c\
            LEFT JOIN event e ON e.objid=c.froot WHERE c.k=1 $where"] 0 0]
    } trap {FOSSIL DB} msg {
        # (No forum: no forumpost table.)
        if {![string match "*no such table*" $msg]} { set status "Cannot read the forum: $msg" }
    }
    set items {}
    foreach row $rows {
        lassign $row froot n started last user comment lastuser
        set title [title $comment]
        set threads($froot) [dict create title $title user $user started $started last $last \
            lastuser $lastuser posts $n]
        lappend items [list $froot [dict create title $title user $user started $started \
            last $last lastuser $lastuser posts $n] {} {}]
    }
    set t .forum.main.list.t
    tablecols::fill $t $items
    if {$total == 0 && $f eq ""} {
        set status "No forum in this repository"
    } elseif {$total > [llength $rows]} {
        set status "[llength $rows] newest of $total threads"
    } else {
        set status "$total threads"
    }
    .forum.b.more state [expr {$total > [llength $rows] ? "!disabled" : "disabled"}]
    if {$selected ne "" && [$t exists $selected]} {
        $t selection set [list $selected]
        $t see $selected
    } elseif {[llength [$t children {}]]} {
        $t selection set [lrange [$t children {}] 0 0]
    } else {
        showThread ""
    }
}

proc tkforum::more {} {
    variable limit
    set limit [expr {$limit * 2}]
    reload
}

# A post's artifact: its cards (H title, N mimetype, U user, D date) and
# its text (the W card).
proc tkforum::parse {artifact} {
    set w [string first "\nW " "\n$artifact"]
    if {$w < 0} { return [list {} ""] }
    set head [string range $artifact 0 [expr {$w - 1}]]
    set end [string first "\n" $artifact $w]
    set text [string range $artifact [expr {$end + 1}] end]
    set z [string last "\nZ " $text]
    if {$z >= 0} { set text [string range $text 0 [expr {$z - 1}]] }
    set cards {}
    foreach line [split $head "\n"] {
        if {[string index $line 1] ne " "} continue
        dict set cards [string index $line 0] \
            [string map {"\\s" " " "\\n" "\n" "\\\\" "\\"} [string range $line 2 end]]
    }
    list $cards $text
}

# The first version of a post, from its edit (PREVNAME: the array of the
# version each one replaces).
proc tkforum::firstVersion {prevName id} {
    upvar 1 $prevName prev
    while {[info exists prev($id)] && $prev($id) ne ""} { set id $prev($id) }
    return $id
}

# Show a thread: its posts threaded, each its newest version.
proc tkforum::showThread {froot} {
    variable repo
    variable threads
    variable selected
    variable hashes
    variable marks
    variable posts
    set selected $froot
    set d .forum.main.thread.text
    $d configure -state normal
    $d delete 1.0 end
    htmltext::reset $d
    set marks {}
    set shown {}
    if {$froot eq "" || ![info exists threads($froot)]} {
        $d configure -state disabled
        return
    }
    # All versions of all posts; the text of those not replaced.
    set rows [fossil::sql $repo "SELECT f.fpid, coalesce(f.fprev,''), coalesce(f.firt,''),
        strftime('%Y-%m-%d %H:%M', f.fmtime), [fossil::outcol "coalesce(e.user,'')"], b.uuid,
        CASE WHEN f.fpid IN (SELECT fprev FROM forumpost WHERE froot=$froot AND fprev IS NOT NULL)
         THEN '' ELSE [fossil::outcol "content(b.uuid)"] END, f.fmtime
        FROM forumpost f JOIN blob b ON b.rid=f.fpid LEFT JOIN event e ON e.objid=f.fpid
        WHERE f.froot=$froot ORDER BY f.fmtime"]
    # A version's post: the first version of its chain of edits.
    array set prev {}
    array set row {}
    foreach r $rows {
        lassign $r fpid fprev
        set prev($fpid) $fprev
        set row($fpid) $r
    }
    array set replaced {}
    foreach r $rows { if {[lindex $r 1] ne ""} { set replaced([lindex $r 1]) 1 } }
    array set current {}
    array set children {}
    set order {}
    foreach r $rows {
        lassign $r fpid fprev firt
        if {[info exists replaced($fpid)]} continue
        set post [firstVersion prev $fpid]
        set current($post) $fpid
        lappend order $post
    }
    # In order of the first versions (edits do not move a post).
    set order [lmap p [lsort -real -index 0 [lmap post $order {
        list [lindex $row($post) 7] $post
    }]] { lindex $p 1 }]
    set top {}
    foreach post $order {
        set firt [lindex $row($current($post)) 2]
        set to [expr {$firt eq "" ? "" : [firstVersion prev $firt]}]
        if {$to eq "" || ![info exists current($to)]} {
            lappend top $post
        } else {
            lappend children($to) $post
        }
    }
    set texts [lmap post $order { lindex $row($current($post)) 6 }]
    set hashes [fossil::hashLinks $repo $texts]
    $d insert end "[dict get $threads($froot) title]\n" title
    set indent [font measure TkTextFont 0000]
    # Depth first: each post, then its replies.
    set stack [lreverse [lmap p $top { list $p 0 }]]
    while {[llength $stack]} {
        lassign [lindex $stack end] post depth
        set stack [lrange $stack 0 end-1]
        set r $row($current($post))
        lassign $r fpid - - date user uuid artifact
        lassign [parse $artifact] cards text
        set margin [expr {min($depth, 8) * $indent}]
        set tag head$depth
        $d tag configure $tag -lmargin1 $margin -lmargin2 $margin
        dict set marks $uuid [$d index "end - 1 char"]
        lappend shown [list $fpid $depth [expr {$current($post) ne $post}]]
        set first [lindex $row($post) 3]
        set when $first
        if {$current($post) ne $post} { append when ", edited $date" }
        $d insert end $user [list head $tag] "  $when" [list meta $tag]
        if {[canPost]} {
            ttk::button $d.reply$fpid -text Reply\u2026 -style Small.TButton \
                -command [list tkforum::compose $uuid]
            $d window create end -window $d.reply$fpid -padx 8 -align center
        }
        $d insert end \n [list meta $tag]
        set mimetype [expr {[dict exists $cards N] ? [dict get $cards N] : "text/x-fossil-wiki"}]
        if {[string trim $text] eq ""} {
            $d insert end "(deleted)\n" [list missing $tag]
        } else {
            set html [fossil::render $repo $mimetype $text]
            if {$html eq ""} { set html "<pre>[string map {& &amp; < &lt; > &gt;} $text]</pre>" }
            htmltext::insert $d $html -margin $margin -command tkforum::followLink \
                -external tkforum::isExternal \
                -autolink [list {\[([0-9a-fA-F]{4,40})\]} tkforum::hashLink]
        }
        if {[info exists children($post)]} {
            foreach c [lreverse $children($post)] { lappend stack [list $c [expr {$depth + 1}]] }
        }
    }
    set posts $shown
    $d tag raise sel
    $d configure -state disabled
    # At the post Go to or a link asked for (showPost), else at the top.
    variable scrollTo
    if {[lindex $scrollTo 0] eq $froot && [dict exists $marks [lindex $scrollTo 1]]} {
        $d yview [dict get $marks [lindex $scrollTo 1]]
    } else {
        set scrollTo {}
        $d yview moveto 0
    }
}

# ------------------------------------------------------------- writing

# Posts go to the server through its web forms (web::forumPost), as from
# the browser: the user logs in there, so anyone allowed to post on the
# website can, without the right to push.  The password is asked for and
# kept for the session only.  Then a pull brings the post here.

proc tkforum::canPost {} {
    variable remote
    expr {$remote ne "" && [auto_execok curl] ne ""}
}

# The window to write a post: a new thread, or a reply to the post REPLYTO
# (its hash).
proc tkforum::compose {{replyTo ""}} {
    variable formats
    variable repo
    variable remote
    variable postTitle
    variable webUser
    variable webPassword
    variable passwords
    variable me
    if {$repo eq ""} return
    if {![canPost]} {
        if {$remote eq ""} {
            ui::infoBox -title Forum "Posting needs the server." \
                "This repository has no server URL to post to (fossil remote)."
        } else {
            ui::infoBox -title Forum "Posting needs curl." \
                "Posts are sent with curl, which was not found."
        }
        return
    }
    set w .forum.compose
    destroy $w
    if {$replyTo eq ""} {
        set title "New thread"
    } else {
        lassign [lindex [fossil::sql $repo "SELECT [fossil::outcol "coalesce(e.user,'')"],
            strftime('%Y-%m-%d %H:%M', f.fmtime),
            [fossil::outcol "coalesce((SELECT comment FROM event WHERE objid=f.froot),'')"]
            FROM forumpost f LEFT JOIN event e ON e.objid=f.fpid
            WHERE f.fpid=(SELECT rid FROM blob WHERE uuid=[fossil::sqlstr $replyTo])"] 0] \
            user date thread
        set title "Reply: [tkforum::title $thread]"
    }
    set f [ui::dialog $w $title -escape [list destroy $w] -help forum#writing]
    grid columnconfigure $f 1 -weight 1
    if {$replyTo eq ""} {
        set postTitle ""
        ttk::label $f.lt -text Title
        ttk::entry $f.title -textvariable tkforum::postTitle -width 60
        grid $f.lt $f.title -sticky ew -pady {0 6}
        grid $f.lt -sticky w -padx {0 8}
    } else {
        ttk::label $f.to -text "In reply to $user, $date" -foreground gray35
        grid $f.to - -sticky w -pady {0 6}
    }
    formattext::create $f.editor -formats $formats -variable tkforum::format -repo $repo -height 12
    grid $f.editor - -sticky news
    grid rowconfigure $f 1 -weight 1
    # Who: the user of the server URL, else the default user; the password
    # given before in this session, else the one Fossil saved for the
    # user of the server URL.
    set urlUser [fossil::remoteUser $repo]
    if {![info exists webUser($remote)]} {
        set webUser($remote) [expr {$urlUser ne "" ? $urlUser : $me}]
    }
    if {[info exists passwords($remote)]} {
        set webPassword $passwords($remote)
    } elseif {$urlUser ne "" && $webUser($remote) eq $urlUser} {
        set webPassword [fossil::savedPassword $repo]
    } else {
        set webPassword ""
    }
    ttk::frame $f.login
    ttk::label $f.login.lu -text "Post to $remote as"
    ttk::entry $f.login.user -textvariable tkforum::webUser($remote) -width 16
    ttk::label $f.login.lp -text Password
    ttk::entry $f.login.password -textvariable tkforum::webPassword -show * -width 16
    pack $f.login.lu $f.login.user $f.login.lp $f.login.password -side left -padx {0 6}
    grid $f.login - -sticky w -pady {8 0}
    ttk::frame $f.b
    ttk::button $f.b.post -text Post -default active -command [list tkforum::post $replyTo]
    ttk::button $f.b.cancel -text Cancel -command [list destroy $w]
    pack $f.b.cancel $f.b.post -side right -padx {4 0}
    grid $f.b - -sticky ew -pady {8 0}
    bind [formattext::widget $f.editor] <Control-Return> "[list tkforum::post $replyTo]; break"
    bind $f.login.password <Return> [list tkforum::post $replyTo]
    focus [expr {$replyTo eq "" ? "$f.title" : [formattext::widget $f.editor]}]
}

# Post what the window has: asked first, then sent, then pulled here.
proc tkforum::post {replyTo} {
    variable repo
    variable remote
    variable postTitle
    variable webUser
    variable webPassword
    variable passwords
    set w .forum.compose
    if {![winfo exists $w]} return
    set f $w.f
    set text [string trim [formattext::get $f.editor]]
    set title [string trim $postTitle]
    set user [string trim $webUser($remote)]
    if {$replyTo eq "" && $title eq ""} {
        ui::infoBox -parent $w -title Forum "A new thread needs a title."
        return
    }
    if {$text eq ""} {
        ui::infoBox -parent $w -title Forum "The post is empty."
        return
    }
    if {$user eq "" || $webPassword eq ""} {
        ui::infoBox -parent $w -title Forum "Posting needs your user and password on the server."
        focus [expr {$user eq "" ? "$f.login.user" : "$f.login.password"}]
        return
    }
    set fields [dict create content $text mimetype [formattext::mimetype $f.editor]]
    if {$replyTo eq ""} {
        dict set fields title $title
        set what "Start the thread \"$title\""
    } else {
        dict set fields fpid $replyTo
        set what "Post this reply"
    }
    if {![ui::confirm -parent $w -title Forum "$what on $remote?" \
            "As $user.  It goes to the server now and cannot be taken back (an edit\
            is a new version); then this repository pulls it."]} return
    try {
        ui::busy {
            lassign [web::forumPost $remote $user $webPassword $fields] hash held
        }
    } trap {WEB LOGIN} msg {
        ui::errorBox -parent $w -title Forum "Not logged in." $msg
        focus $f.login.password
        return
    } trap {WEB} msg {
        ui::errorBox -parent $w -title Forum "The post was not sent." $msg
        return
    }
    set passwords($remote) $webPassword
    destroy $w
    if {$held} {
        ui::infoBox -title Forum "Posted; it waits for a moderator." \
            "The post shows here once a moderator of $remote has approved it\
            and the repository has pulled it."
        return
    }
    ui::busy {
        lassign [fossil::run pull -R $repo] code out
    }
    if {$code} {
        ui::errorBox -title Forum "Posted, but the pull failed." [string trim $out]
        return
    }
    tktaalik::navigate
    reload
    showPost $hash 0
}

proc tkforum::hashLink {match hash} {
    variable hashes
    set hash [string tolower $hash]
    expr {[dict exists $hashes $hash] ? [dict get $hashes $hash] : ""}
}

# A link to a post: its thread, here, at the post.
# (REMEMBER 0: the caller has recorded the place for Back already.)
proc tkforum::showPost {hash {remember 1}} {
    variable repo
    variable marks
    variable filter
    set row [lindex [fossil::sql $repo "SELECT f.froot, b.uuid FROM forumpost f JOIN blob b\
        ON b.rid=f.fpid WHERE b.uuid >= [fossil::sqlstr $hash]\
        AND b.uuid < [fossil::sqlstr $hash]||'g' LIMIT 1"] 0]
    if {$row eq ""} { return 0 }
    lassign $row froot uuid
    # An earlier version of an edited post: the newest one is shown.
    set newest [lindex [fossil::sql $repo "WITH RECURSIVE v(rid) AS (\
        SELECT rid FROM blob WHERE uuid=[fossil::sqlstr $uuid]\
        UNION ALL SELECT f.fpid FROM forumpost f JOIN v ON f.fprev=v.rid)\
        SELECT b.uuid FROM v JOIN blob b ON b.rid=v.rid JOIN forumpost f ON f.fpid=v.rid\
        ORDER BY f.fmtime DESC LIMIT 1"] 0 0]
    if {$newest ne ""} { set uuid $newest }
    if {$remember} { tktaalik::navigate }
    set t .forum.main.list.t
    if {![$t exists $froot]} {
        set filter ""
        reload
    }
    if {![$t exists $froot]} { return 0 }
    $t selection set [list $froot]
    $t see $froot
    update idletasks
    # Shown at the post (the newest version of it); kept for the thread, as
    # the selection shows it again (<<TreeviewSelect>>, after this).
    variable scrollTo [list $froot $uuid]
    showThread $froot
    return 1
}

# A link that followLink opens in the browser: not a post of this forum
# (one that is here), not a ticket; a URL, or a page of the server if the
# repository has one.
proc tkforum::isExternal {href} {
    variable remote
    if {[string match tkt:* $href] || [string match #* $href]} { return 0 }
    if {[regexp {^/?forum(?:post|thread)/([0-9a-fA-F]{4,64})} $href -> hash]
            || [regexp {^info:([0-9a-fA-F]{4,64})$} $href -> hash]} {
        if {[hasPost $hash]} { return 0 }
    }
    if {[goto::linkTarget $href] ne ""} { return 0 }
    if {[regexp {^[a-zA-Z][a-zA-Z0-9+.-]*://|^mailto:} $href]} { return 1 }
    expr {$remote ne ""}
}

proc tkforum::hasPost {hash} {
    variable repo
    llength [fossil::sql $repo "SELECT 1 FROM forumpost f JOIN blob b ON b.rid=f.fpid\
        WHERE b.uuid GLOB [fossil::sqlstr [string tolower $hash]*] LIMIT 1"]
}

proc tkforum::followLink {href} {
    variable remote
    if {[regexp {^/?forum(?:post|thread)/([0-9a-fA-F]{4,64})} $href -> hash]} {
        if {[showPost [string tolower $hash]]} return
    }
    # A check-in and the like: in its tab.
    if {![string match tkt:* $href] && [goto::openLink $href]} return
    switch -glob -- $href {
        tkt:* {
            tktaalik::show tickets
            tktsearch::showTicket [string range $href 4 end]
        }
        info:* {
            # A post of this forum: here.
            if {[showPost [string range $href 5 end]]} return
            if {$remote ne ""} { fossil::browse $remote/info/[string range $href 5 end] }
        }
        *://* - mailto:* { fossil::browse $href }
        "#*"             {}
        /*               { if {$remote ne ""} { fossil::browse $remote$href } }
        default          { if {$remote ne ""} { fossil::browse $remote/$href } }
    }
}

proc tkforum::browse {} {
    variable repo
    variable remote
    variable selected
    if {$remote eq "" || $selected eq ""} return
    set uuid [lindex [fossil::sql $repo "SELECT uuid FROM blob WHERE rid=$selected"] 0 0]
    fossil::browse $remote/forumpost/[string range $uuid 0 15]
}

# Where we are (tktaalik::location): the filter, the limit, the thread,
# how far it is scrolled.
proc tkforum::here {} {
    variable searched
    variable limit
    variable selected
    list $searched $limit $selected [.forum.main.thread.text index @0,0]
}

# Back or Forward to a place of here.
proc tkforum::goTo {place} {
    variable filter
    variable limit
    variable selected
    lassign $place f l thread top
    set filter $f
    set limit $l
    set selected $thread
    reload
    after idle [list apply {{top} {
        if {$top ne ""} { .forum.main.thread.text yview $top }
    }} $top]
}

# The context menu of a thread.
proc tkforum::popupMenu {m item} {
    variable threads
    variable remote
    variable repo
    if {![info exists threads($item)]} return
    set user [dict get $threads($item) user]
    $m add command -label "Threads started by $user" -state [expr {$user eq "" ? "disabled" : "normal"}] \
        -command [list set tkforum::filter $user]
    popup::separator $m
    popup::button $m .forum.b.browse
    popup::separator $m
    popup::copy $m "Copy title" [dict get $threads($item) title]
    set uuid [lindex [fossil::sql $repo "SELECT uuid FROM blob WHERE rid=$item"] 0 0]
    popup::copy $m "Copy link" [expr {$remote eq "" ? "" : "$remote/forumpost/[string range $uuid 0 15]"}]
}
