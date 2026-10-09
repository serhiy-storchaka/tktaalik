# The Forum tab of tktaalik: the threads of the repository's forum, newest
# activity first, and the posts of the one selected, threaded (replies
# after the post they answer, indented), each the newest version of it,
# rendered by Fossil (Markdown, wiki or plain text).  Links to other posts
# open their thread here, links to tickets in the Tickets tab, others in
# the browser.  New threads, replies, edits and deletions are sent through
# the server's web forms (web::forumPost), then pulled; or, by those who
# may push there (or without a server), stored in the repository
# (fossil::importArtifact), for the next push or sync.

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
    variable me ""            ;# the default user (tkforum::poster)
    variable format Markdown  ;# of new posts
    variable formats {
        Markdown text/x-markdown  "Fossil wiki" text/x-fossil-wiki  {Plain text} text/plain
    }
    variable postTitle ""     ;# of a new thread
    variable webUser          ;# server URL -> the user to post as
    variable webPassword ""   ;# in the window
    variable passwords        ;# server URL -> password (this session only)
    variable pushers          ;# server URL,user -> whether the user may push
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
    .forum.menu add cascade -label Forum -underline 1 -menu [menu .forum.menu.forum \
        -postcommand {tkforum::forumMenu .forum.menu.forum}]
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
    ui::splitByWeights .forum.main
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
                -command [list tkforum::compose reply $uuid]
            $d window create end -window $d.reply$fpid -padx 8 -align center
            # One's own posts (not deleted): Edit and Delete too.
            if {$user eq [poster] && [string trim $text] ne ""} {
                ttk::button $d.edit$fpid -text Edit\u2026 -style Small.TButton \
                    -command [list tkforum::compose edit $uuid]
                ttk::button $d.delete$fpid -text Delete\u2026 -style Small.TButton \
                    -command [list tkforum::compose delete $uuid]
                $d window create end -window $d.edit$fpid -padx 2 -align center
                $d window create end -window $d.delete$fpid -padx 2 -align center
            }
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
    variable repo
    variable remote
    expr {$repo ne "" && ($remote eq "" || [auto_execok curl] ne "")}
}

# Who posts: the user given in this session, else the user of the server
# URL, else the default user.
proc tkforum::poster {} {
    variable repo
    variable remote
    variable webUser
    variable me
    if {![info exists webUser($remote)]} {
        set urlUser [fossil::remoteUser $repo]
        set webUser($remote) [expr {$urlUser ne "" ? $urlUser : $me}]
    }
    return $webUser($remote)
}

# The window to write a post (MODE new: a new thread; reply: a reply to
# the post HASH; edit: a new version of it) or to delete one (delete: the
# same window without the text).
proc tkforum::compose {{mode new} {hash ""}} {
    variable formats
    variable format
    variable repo
    variable remote
    variable postTitle
    variable webPassword
    variable passwords
    if {$repo eq ""} return
    if {![canPost]} {
        ui::infoBox -title Forum "Posting needs curl." \
            "Posts are sent to the server with curl, which was not found."
        return
    }
    if {$remote eq "" && [poster] in {"" anonymous nobody}} {
        ui::infoBox -title Forum "Posts need a user." \
            "This repository has no server and no default user to record them as\
            (fossil user default)."
        return
    }
    set w .forum.compose
    destroy $w
    set postTitle ""
    set first 0
    if {$mode ne "new"} {
        lassign [lindex [fossil::sql $repo "SELECT [fossil::outcol "coalesce(e.user,'')"],
            strftime('%Y-%m-%d %H:%M', f.fmtime),
            [fossil::outcol "coalesce((SELECT comment FROM event WHERE objid=f.froot),'')"],
            [fossil::outcol "content(b.uuid)"]
            FROM forumpost f JOIN blob b ON b.rid=f.fpid LEFT JOIN event e ON e.objid=f.fpid
            WHERE b.uuid=[fossil::sqlstr $hash]"] 0] \
            user date thread artifact
        lassign [parse $artifact] cards text
        # (A thread's first post has its title: kept, and editable.)
        set first [dict exists $cards H]
        if {$first} { set postTitle [dict get $cards H] }
    }
    set title [dict get {new "New thread" reply Reply edit Edit delete Delete} $mode]
    if {$mode ne "new"} { append title ": [tkforum::title $thread]" }
    set f [ui::dialog $w $title -escape [list destroy $w] -help forum#writing]
    grid columnconfigure $f 1 -weight 1
    if {$mode eq "new" || ($mode eq "edit" && $first)} {
        ttk::label $f.lt -text Title
        ttk::entry $f.title -textvariable tkforum::postTitle -width 60
        grid $f.lt $f.title -sticky ew -pady {0 6}
        grid $f.lt -sticky w -padx {0 8}
    }
    switch $mode {
        reply { set about "In reply to $user, $date" }
        edit { set about "Your post of $date: the edit is a new version of it" }
        delete { set about "Your post of $date" }
        default { set about "" }
    }
    if {$about ne ""} {
        ttk::label $f.to -text $about -foreground gray35
        grid $f.to - -sticky w -pady {0 6}
    }
    if {$mode eq "delete"} {
        ttk::label $f.what -wraplength 520 -justify left -text "Its text is replaced by\
            nothing (a new, empty version); the earlier versions stay in the history, and\
            replies to it stay."
        grid $f.what - -sticky w
    } else {
        if {$mode eq "edit"} {
            set type [expr {[dict exists $cards N] ? [dict get $cards N] : "text/x-fossil-wiki"}]
            foreach {name t} $formats {
                if {$t eq $type} { set format $name }
            }
        }
        formattext::create $f.editor -formats $formats -variable tkforum::format -repo $repo -height 12
        grid $f.editor - -sticky news
        grid rowconfigure $f [lindex [grid info $f.editor] [expr {[lsearch [grid info $f.editor] -row] + 1}]] -weight 1
        if {$mode eq "edit"} { [formattext::widget $f.editor] insert end $text }
        bind [formattext::widget $f.editor] <Control-Return> "tkforum::postDefault; break"
    }
    # The password given before in this session, else the one Fossil saved
    # for the user of the server URL.
    set who [poster]
    set urlUser [fossil::remoteUser $repo]
    if {[info exists passwords($remote)]} {
        set webPassword $passwords($remote)
    } elseif {$urlUser ne "" && $who eq $urlUser} {
        set webPassword [fossil::savedPassword $repo]
    } else {
        set webPassword ""
    }
    ttk::frame $f.login
    if {$remote eq ""} {
        # (No server: here, as the default user.)
        ttk::label $f.login.lu -text "As $who, in this repository" -foreground gray35
        pack $f.login.lu -side left
    } else {
        ttk::label $f.login.lu -text "[expr {$mode eq "delete" ? "On" : "Post to"}] $remote as"
        ttk::entry $f.login.user -textvariable tkforum::webUser($remote) -width 16
        ttk::label $f.login.lp -text Password
        ttk::entry $f.login.password -textvariable tkforum::webPassword -show * -width 16
        pack $f.login.lu $f.login.user $f.login.lp $f.login.password -side left -padx {0 6}
        bind $f.login.password <Return> tkforum::postDefault
        # (Another user or password: whether it may push, again.)
        bind $f.login.user <FocusOut> tkforum::checkPush
        bind $f.login.password <FocusOut> tkforum::checkPush
    }
    grid $f.login - -sticky w -pady {8 0}
    # Two ways: through the server's web form, or made in this repository
    # (sent by the next push or sync): for those who may push there (asked
    # when the password is known; else when pressed), and without a server.
    ttk::frame $f.b
    set verb [dict get {new Post reply Post edit Save delete Delete} $mode]
    ttk::button $f.b.web -text "$verb via web" -command [list tkforum::post $mode $hash web]
    ttk::button $f.b.repo -text "$verb via repository" -command [list tkforum::post $mode $hash repo]
    ttk::button $f.b.cancel -text Cancel -command [list destroy $w]
    pack $f.b.cancel -side right -padx {4 0}
    grid $f.b - -sticky ew -pady {8 0}
    if {$mode eq "new"} {
        focus $f.title
    } elseif {$mode eq "delete"} {
        focus $f.b.cancel
    } else {
        focus [formattext::widget $f.editor]
    }
    checkPush
}

# The user may push to the server: 1, 0, or "" (not known: no password
# yet, or the server not reached).
proc tkforum::mayPush {} {
    variable remote
    variable pushers
    set key $remote,[string trim [poster]]
    expr {[info exists pushers($key)] ? $pushers($key) : ""}
}

# Ask the server (once a session for each user) if the password is
# known, then show the buttons.
proc tkforum::checkPush {} {
    variable repo
    variable remote
    variable pushers
    variable webPassword
    set f .forum.compose.f
    if {![winfo exists $f]} return
    set user [string trim [poster]]
    if {$remote ne "" && $user ne "" && $webPassword ne "" && [mayPush] eq ""} {
        set project [lindex [fossil::sql $repo "SELECT value FROM config WHERE name='project-code'"] 0 0]
        variable passwords
        ui::busy {
            # (Logged in: the password kept for the session.)
            if {![catch { set pushers($remote,$user) [web::canPush $remote $user $webPassword $project] }]} {
                set passwords($remote) $webPassword
            }
        }
    }
    showButtons
}

# Via web with a server; via repository without one, or for those who
# may push (or may not be known yet).  The default: the repository's if
# it is sure.
proc tkforum::showButtons {} {
    variable remote
    set f .forum.compose.f
    if {![winfo exists $f]} return
    set may [mayPush]
    pack forget $f.b.web $f.b.repo
    set shown {}
    if {$remote eq "" || $may ne "0"} { lappend shown $f.b.repo }
    if {$remote ne ""} { lappend shown $f.b.web }
    foreach b $shown { pack $b -side right -padx {4 0} -after $f.b.cancel }
    set default [expr {$remote eq "" || $may eq "1" ? "$f.b.repo" : "$f.b.web"}]
    foreach b [list $f.b.web $f.b.repo] {
        $b configure -default [expr {$b eq $default ? "active" : "normal"}]
    }
}

proc tkforum::postDefault {} {
    set f .forum.compose.f
    foreach b [list $f.b.repo $f.b.web] {
        if {[winfo ismapped $b] && [$b cget -default] eq "active"} { $b invoke; return }
    }
}

# Send what the window has (see compose): asked first, then sent, then
# pulled here.
proc tkforum::post {mode hash {how web}} {
    variable repo
    variable remote
    variable postTitle
    variable webPassword
    variable passwords
    variable pushers
    set w .forum.compose
    if {![winfo exists $w]} return
    set f $w.f
    set text [expr {$mode eq "delete" ? "" : [string trim [formattext::get $f.editor]]}]
    set title [string trim $postTitle]
    set user [string trim [poster]]
    if {[winfo exists $f.title] && $title eq ""} {
        ui::infoBox -parent $w -title Forum "A thread needs a title."
        return
    }
    if {$mode ne "delete" && $text eq ""} {
        ui::infoBox -parent $w -title Forum "The post is empty."
        return
    }
    if {$remote ne "" && ($user eq "" || $webPassword eq "")} {
        ui::infoBox -parent $w -title Forum "Posting needs your user and password on the server."
        focus [expr {$user eq "" ? "$f.login.user" : "$f.login.password"}]
        return
    }
    set mimetype [expr {$mode eq "delete" ? "text/x-fossil-wiki" : [formattext::mimetype $f.editor]}]
    set project [lindex [fossil::sql $repo "SELECT value FROM config WHERE name='project-code'"] 0 0]
    # Via repository with a server: only for those who may push there.
    if {$how eq "repo" && $remote ne ""} {
        if {[mayPush] eq ""} {
            try {
                ui::busy {
                    set pushers($remote,$user) [web::canPush $remote $user $webPassword $project]
                }
                set passwords($remote) $webPassword
            } trap {WEB LOGIN} msg {
                ui::errorBox -parent $w -title Forum "Not logged in." $msg
                focus $f.login.password
                return
            } trap {WEB} msg {
                ui::errorBox -parent $w -title Forum "The server was not reached." $msg
                return
            }
        }
        if {![mayPush]} {
            showButtons
            ui::errorBox -parent $w -title Forum "$user may not push to $remote." \
                "Use \"[$f.b.web cget -text]\": the server's web form."
            return
        }
        set how push
    }
    set what [dict get {new "Start the thread" reply "Post this reply" edit "Save this edit"
        delete "Delete this post"} $mode]
    if {$mode eq "new"} { append what " \"$title\"" }
    switch $how {
        repo {
            set where "in [file tail $repo]"
            set detail "As $user.  It is stored in this repository (it has no server to\
                post to; a sync sends it if it has another remote)."
        }
        push {
            set where "in [file tail $repo]"
            set detail "As $user, who may push to $remote: it is stored in this\
                repository, and your next push or sync sends it there."
        }
        web {
            set where "on $remote"
            set detail "As $user.  It goes to the server now, through its web form; then\
                this repository pulls it."
        }
    }
    append detail "  It cannot be taken back (an edit or a deletion is a new version;\
        the earlier ones stay)."
    if {![ui::confirm -parent $w -title Forum "$what $where?" $detail]} return
    if {$how eq "web"} {
        set fields [dict create]
        if {$mode ne "delete"} {
            dict set fields content $text
            dict set fields mimetype $mimetype
        }
        if {$mode ne "new"} {
            dict set fields fpid $hash
            dict set fields action $mode
        }
        # (A thread's first post: its title; "" when deleted.)
        if {[winfo exists $f.title]} {
            dict set fields title $title
        } elseif {$mode eq "delete" && $postTitle ne ""} {
            dict set fields title ""
        }
        try {
            ui::busy {
                lassign [web::forumPost $remote $user $webPassword $fields] newHash held
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
            ui::infoBox -title Forum "Sent; it waits for a moderator." \
                "It shows here once a moderator of $remote has approved it\
                and the repository has pulled it."
            return
        }
        ui::busy {
            lassign [fossil::run pull -R $repo] code out
        }
        if {$code} {
            ui::errorBox -title Forum "Sent, but the pull failed." [string trim $out]
            return
        }
    } else {
        set cards [Cards $mode $hash $title $mimetype $user $text]
        set dir [fossil::tempDir]
        try {
            ui::busy {
                set newHash [fossil::buildArtifact $repo $cards $dir/artifact]
                fossil::importArtifact $repo $dir/artifact $newHash
            }
            destroy $w
        } trap {FOSSIL ARTIFACT} msg {
            ui::errorBox -parent $w -title Forum "Not stored." $msg
            return
        } finally {
            file delete -force $dir
        }
    }
    tktaalik::navigate
    reload
    showPost $newHash 0
}

# The cards of a post made here, as Fossil makes them (forum_post() in
# its forum.c), but the Z card: D, G (the thread), H (the title of a
# thread's first post), I (the post replied to), N (unless Fossil wiki),
# P (the version edited), U, W.
proc tkforum::Cards {mode hash title mimetype user text} {
    variable repo
    set cards "D [clock format [clock seconds] -format %Y-%m-%dT%H:%M:%S.000 -gmt 1]\n"
    if {$mode ne "new"} {
        lassign [lindex [fossil::sql $repo "SELECT (SELECT uuid FROM blob WHERE rid=f.froot),
            coalesce((SELECT uuid FROM blob WHERE rid=f.firt),''), f.firt IS NULL
            FROM forumpost f WHERE f.fpid=(SELECT rid FROM blob WHERE uuid=[fossil::sqlstr $hash])"] 0] \
            root firt first
        append cards "G $root\n"
    }
    switch $mode {
        new { append cards "H [fossil::card $title]\n" }
        reply { append cards "I $hash\n" }
        edit - delete {
            if {$first} {
                append cards "H [fossil::card [expr {$mode eq "delete" ? "" : $title}]]\n"
            } else {
                append cards "I $firt\n"
            }
        }
    }
    if {$mimetype ne "text/x-fossil-wiki"} { append cards "N [fossil::card $mimetype]\n" }
    if {$mode in {edit delete}} { append cards "P $hash\n" }
    append cards "U [fossil::card $user]\n"
    append cards "W [string length [encoding convertto utf-8 $text]]\n$text\n"
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
# The Forum menu: a new thread, then what the context menu has for the
# thread selected.
proc tkforum::forumMenu {m} {
    popup::fill $m tkforum::popupMenu [lindex [.forum.main.list.t selection] 0]
    $m insert 0 command -label "New thread\u2026" -underline 0 -accelerator Ctrl+N -command tkforum::compose
    if {[$m index end] > 0} { $m insert 1 separator }
}

proc tkforum::popupMenu {m item} {
    variable threads
    variable remote
    variable repo
    if {![info exists threads($item)]} return
    set user [dict get $threads($item) user]
    if {![popup::inBar]} {
        $m add command -label "Threads started by $user" -state [expr {$user eq "" ? "disabled" : "normal"}] \
            -command [list set tkforum::filter $user]
        popup::separator $m
    }
    popup::button $m .forum.b.browse
    popup::separator $m
    popup::copy $m "Copy title" [dict get $threads($item) title]
    set uuid [lindex [fossil::sql $repo "SELECT uuid FROM blob WHERE rid=$item"] 0 0]
    popup::copy $m "Copy link" [expr {$remote eq "" ? "" : "$remote/forumpost/[string range $uuid 0 15]"}]
}
