# The Users window of tktaalik (Repository menu): the users of the
# repository, their capabilities explained, and which one is the default
# user (the one changes are recorded as, "fossil user default") and how it
# is determined.  New users, a user's contact, capabilities and password,
# and the default user can be changed, in the local repository, after a
# confirmation (users cannot be deleted in Fossil).

source [file join [file dirname [file normalize [info script]]] fossil.tcl]
source [file join [file dirname [file normalize [info script]]] tablecols.tcl]

namespace eval tkusers {
    variable repo ""
    variable root ""
    variable users            ;# array: login -> dict {cap info mtime}
    variable default ""       ;# the default user
    variable defaultFrom ""   ;# how it is determined ("repository", "USER"...)
    variable status ""
    # The capabilities (www/caps/ref.md of Fossil).
    variable caps {
        a {Admin: everything but Setup}
        b {Attach files to wiki pages and tickets}
        c {Append to tickets}
        d {(not used)}
        e {Read email addresses and other personal data}
        f {Create wiki pages}
        g {Clone the repository}
        h {Follow hyperlinks}
        i {Check in}
        j {Read wiki pages}
        k {Edit wiki pages}
        l {Moderate wiki edits}
        m {Append to wiki pages}
        n {Create tickets}
        o {Check out (read the files)}
        p {Change own password}
        q {Moderate ticket changes}
        r {Read tickets}
        s {Setup: everything}
        t {Edit ticket formats and reports}
        u {Everything the "reader" user can do}
        v {Everything the "developer" user can do}
        w {Edit tickets}
        x {Push and pull private branches}
        y {Write unversioned files}
        z {Download ZIP archives and tarballs}
        2 {Read the forum}
        3 {Write to the forum (moderated)}
        4 {Write to the forum, trusted (not moderated)}
        5 {Moderate the forum}
        6 {Forum admin: grant forum capabilities}
        7 {Get email alerts}
        A {Send announcements}
        B {Attach files to forum posts}
        C {Chat}
        D {Debug (developers of Fossil)}
        L {Is logged in}
    }
    # Users that stand for a kind of user, not a person.
    variable special {nobody anonymous reader developer}
}

# Open the window (made the first time), for the repository shown.
proc tkusers::window {} {
    if {[tktaalik::dialogWindow .users Users]} { build }
    setRepository $::tktaalik::repo $::tktaalik::root
    focus .users.main.list.t
}

proc tkusers::build {} {
    ttk::panedwindow .users.main -orient horizontal
    ui::splitByWeights .users.main
    ttk::frame .users.main.list
    set t .users.main.list.t
    ttk::treeview $t -show headings -selectmode browse -yscrollcommand {.users.main.list.y set} \
        -xscrollcommand {.users.main.list.x set}
    ttk::scrollbar .users.main.list.y -command [list $t yview]
    ttk::scrollbar .users.main.list.x -orient horizontal -command [list $t xview]
    grid $t .users.main.list.y -sticky news
    grid .users.main.list.x -sticky ew
    grid columnconfigure .users.main.list 0 -weight 1
    grid rowconfigure .users.main.list 0 -weight 1
    $t tag configure special -foreground gray45
    $t tag configure default -font TkHeadingFont
    # (Contact, of any length, last.)
    tablecols::setup $t {
        login  {heading User width 20}
        cap    {heading Capabilities width 14}
        mtime  {heading Changed width 16 dir desc}
        info   {heading Contact width 24 stretch 1}
    } -fixed {login} -defaults {cap mtime info} -sort {login asc}

    ttk::frame .users.main.details
    set d .users.main.details.text
    text $d -wrap word -width 40 -height 20 -padx 8 -pady 6 -font TkTextFont -state disabled \
        -yscrollcommand {.users.main.details.y set}
    ttk::scrollbar .users.main.details.y -command [list $d yview]
    $d tag configure title -font TkHeadingFont -spacing3 4
    $d tag configure meta -foreground gray40
    $d tag configure letter -font TkFixedFont
    $d tag configure inherited -foreground gray40
    $d configure -tabs [list [font measure TkFixedFont 000]]
    grid $d .users.main.details.y -sticky news
    grid columnconfigure .users.main.details 0 -weight 1
    grid rowconfigure .users.main.details 0 -weight 1
    .users.main add .users.main.list -weight 3
    .users.main add .users.main.details -weight 2

    ttk::frame .users.b -padding 6
    ttk::label .users.b.status -textvariable tkusers::status -anchor w
    ttk::button .users.b.new -text "New user\u2026" -command {tkusers::edit ""}
    ttk::button .users.b.edit -text "Edit\u2026" -command {tkusers::edit [lindex [.users.main.list.t selection] 0]}
    ttk::button .users.b.default -text "Make default user\u2026" -command tkusers::makeDefault
    ttk::button .users.b.unset -text "Unset default\u2026" -command tkusers::unsetDefault
    ttk::button .users.b.close -text Close -command {wm withdraw .users}
    pack .users.b.close .users.b.unset .users.b.default .users.b.edit .users.b.new -side right -padx {4 0}
    icons::tooltip .users.b.unset "No default user in the repository: then the -U option,\nor\
        FOSSIL_USER, USER, LOGNAME or USERNAME of the environment\n(Fossil 2.26 or newer)"

    pack .users.b.status -side left -fill x -expand 1
    pack .users.b -side bottom -fill x
    pack .users.main -fill both -expand 1
    bind $t <<TreeviewSelect>> {tkusers::showDetails [lindex [.users.main.list.t selection] 0]}
    bind $t <Double-1> {tkusers::edit [lindex [.users.main.list.t selection] 0]}
    bind .users <F5> tkusers::reload
    popup::attach .users.main.list.t tkusers::popupMenu
}

proc tkusers::setRepository {path newRoot} {
    variable repo $path
    variable root $newRoot
    wm title .users "Users \u2014 [file rootname [file tail $repo]]"
    reload
}

proc tkusers::reload {} {
    variable repo
    variable users
    variable default
    variable special
    variable status
    variable defaultFrom
    array unset users
    try {
        set rows [fossil::sql $repo "SELECT [fossil::outcol login], [fossil::outcol cap],\
            [fossil::outcol "coalesce(info,'')"],\
            coalesce(strftime('%Y-%m-%d %H:%M',mtime,'unixepoch'),'') FROM user"]
    } trap {FOSSIL DB} msg {
        set status "Cannot read the users: $msg"
        set rows {}
    }
    # "LOGIN (determined by WHERE)"; before Fossil 2.26 only the login
    # (no -v): from the repository if it is its default-user.
    set default ""
    set defaultFrom ""
    if {[newDefault]} {
        lassign [fossil::run user default -v -R $repo] code out
        if {!$code && ![regexp {^(.*?) \(determined by (.*)\)$} [string trim $out] -> default defaultFrom]} {
            set default [string trim $out]
        }
    } else {
        lassign [fossil::run user default -R $repo] code out
        if {!$code} {
            set default [string trim $out]
            set mine [lindex [fossil::sql $repo "SELECT [fossil::outcol value] FROM config WHERE name='default-user'"] 0 0]
            if {$default ne "" && $default eq $mine} { set defaultFrom repository }
        }
    }
    set items {}
    foreach row $rows {
        lassign $row login cap info mtime
        set users($login) [dict create cap $cap info $info mtime $mtime]
        set tags {}
        if {$login in $special} { lappend tags special }
        if {$login eq $default} { lappend tags default }
        set shown [expr {$login eq $default ? "\u2605 $login" : $login}]
        lappend items [list $login [dict create login $shown cap $cap info $info mtime $mtime] \
            [dict create login $login] $tags]
    }
    set t .users.main.list.t
    set keep [lindex [$t selection] 0]
    tablecols::fill $t $items
    # The contacts are of any length: as wide as the longest (the default
    # user's row is bold).
    set width [font measure TkHeadingFont Contact]
    foreach login [array names users] {
        set font [expr {$login eq $default ? "TkHeadingFont" : "TkDefaultFont"}]
        set width [expr {max($width, [font measure $font [dict get $users($login) info]])}]
    }
    $t column info -width [expr {$width + [font measure TkDefaultFont 00]}]
    if {$keep eq "" || ![$t exists $keep]} { set keep $default }
    if {$keep ne "" && [$t exists $keep]} {
        $t selection set $keep
        $t see $keep
    } else {
        showDetails ""
    }
    if {![info exists msg]} {
        set status "[llength $rows] users; default user: [expr {$default eq "" ? "none" : $default}]"
        if {$defaultFrom ne ""} { append status " (from $defaultFrom)" }
    }
    .users.b.unset state [expr {$defaultFrom eq "repository" && [newDefault] ? "!disabled" : "disabled"}]
}

# The capabilities of a user, each letter explained; what it inherits.
proc tkusers::showDetails {login} {
    variable users
    variable caps
    variable default
    variable special
    set d .users.main.details.text
    $d configure -state normal
    $d delete 1.0 end
    if {$login eq "" || ![info exists users($login)]} {
        $d configure -state disabled
        .users.b.default state disabled
        .users.b.edit state disabled
        return
    }
    set u $users($login)
    $d insert end "$login\n" title
    if {[dict get $u info] ne ""} { $d insert end "[dict get $u info]\n" meta }
    if {$login eq $default} { $d insert end "The default user: changes are recorded as $login.\n" meta }
    $d insert end \n
    set cap [dict get $u cap]
    if {$cap eq ""} { $d insert end "No capabilities of its own.\n" meta }
    foreach c [split $cap ""] {
        set text [expr {[dict exists $caps $c] ? [dict get $caps $c] : "(unknown)"}]
        $d insert end "$c\t" letter "$text\n" ""
    }
    # Every user has the capabilities of "nobody", logged-in ones also
    # those of "anonymous".
    set from [expr {$login eq "nobody" ? {} : $login eq "anonymous" ? {nobody} : {nobody anonymous}}]
    if {[string first u $cap] >= 0} { lappend from reader }
    if {[string first v $cap] >= 0} { lappend from developer }
    foreach other $from {
        if {![info exists users($other)]} continue
        set extra [lmap c [split [dict get $users($other) cap] ""] {
            if {[string first $c $cap] >= 0} continue; set c }]
        if {![llength $extra]} continue
        $d insert end "\nAlso, from \"$other\":\n" inherited
        foreach c $extra {
            set text [expr {[dict exists $caps $c] ? [dict get $caps $c] : "(unknown)"}]
            $d insert end "$c\t" {letter inherited} "$text\n" inherited
        }
    }
    $d configure -state disabled
    variable defaultFrom
    set ok [expr {($login ne $default || $defaultFrom ne "repository") && $login ni $special}]
    .users.b.default state [expr {$ok ? "!disabled" : "disabled"}]
    .users.b.edit state !disabled
}

# Whether this Fossil (2.26 or newer) tells how the default user is
# determined (user default -v) and can unset it ("").
proc tkusers::newDefault {} {
    fossil::helpMatches user "*user default ?OPTIONS?*"
}

# Make the selected user the default user (fossil user default).
proc tkusers::makeDefault {} {
    variable repo
    variable default
    variable defaultFrom
    set login [lindex [.users.main.list.t selection] 0]
    # (The same user, but from the environment: kept in the repository.)
    if {$login eq "" || ($login eq $default && $defaultFrom eq "repository")} return
    if {![ui::confirm -parent .users -title Users \
            "Make $login the default user of [file tail $repo]?" \
            "Changes made here (commits, ticket changes) will be recorded as $login.\
                Now: [expr {$default eq "" ? "none" : $default}]."]} return
    lassign [fossil::run user default $login -R $repo] code out
    if {$code} {
        tk_messageBox -parent .users -icon error -title Users -message "fossil user default failed:" \
            -detail $out
    }
    reload
}

# No default user in the repository ("fossil user default ''"): then it
# comes from the -U option or the environment.
proc tkusers::unsetDefault {} {
    variable repo
    variable default
    if {![ui::confirm -parent .users -title Users \
            "Unset the default user of [file tail $repo]?" \
            "Now: $default.  Then changes made here will be recorded as the user\
                named by FOSSIL_USER, USER, LOGNAME or USERNAME."]} return
    lassign [fossil::run user default "" -R $repo] code out
    if {$code} {
        tk_messageBox -parent .users -icon error -title Users -message "fossil user default failed:" \
            -detail $out
    }
    reload
}

# A new user (LOGIN ""), or a user's contact, capabilities and password:
# "fossil user new/contact/capabilities/password".
proc tkusers::edit {login} {
    variable repo
    variable users
    variable caps
    variable form
    set w .users.edit
    destroy $w
    toplevel $w
    wm title $w [expr {$login eq "" ? "New user" : "Edit user $login"}]
    wm transient $w .users
    array unset form
    if {$login eq ""} {
        # The capabilities of new users ("default-perms").
        set cap [lindex [fossil::sql $repo "SELECT coalesce((SELECT value FROM config\
            WHERE name='default-perms'),'u')"] 0 0]
        set form(login) ""
        set form(info) ""
    } else {
        set cap [dict get $users($login) cap]
        set form(login) $login
        set form(info) [dict get $users($login) info]
    }
    set form(pw) ""
    set form(pw2) ""
    set form(done) ""
    ttk::frame $w.f -padding 10
    ttk::label $w.f.ll -text User:
    ttk::entry $w.f.login -textvariable tkusers::form(login) -width 24
    if {$login ne ""} { $w.f.login state readonly }
    ttk::label $w.f.li -text Contact:
    ttk::entry $w.f.info -textvariable tkusers::form(info) -width 40
    ttk::label $w.f.lp -text Password:
    ttk::entry $w.f.pw -textvariable tkusers::form(pw) -show * -width 24
    ttk::label $w.f.lp2 -text Again:
    ttk::entry $w.f.pw2 -textvariable tkusers::form(pw2) -show * -width 24
    grid $w.f.ll $w.f.login -sticky w -pady 2
    grid $w.f.li $w.f.info -sticky ew -pady 2
    grid $w.f.lp $w.f.pw -sticky w -pady 2
    grid $w.f.lp2 $w.f.pw2 -sticky w -pady 2
    if {$login ne ""} {
        ttk::label $w.f.hint -foreground gray35 -text "An empty password: unchanged."
        grid x $w.f.hint -sticky w
    }
    # The capabilities: a check box each, in two columns.
    ttk::labelframe $w.f.caps -text Capabilities -padding 6
    set keys [dict keys $caps]
    set half [expr {([llength $keys] + 1) / 2}]
    set i 0
    foreach c $keys {
        set form(cap,$c) [expr {[string first $c $cap] >= 0}]
        ttk::checkbutton $w.f.caps.c$i -variable tkusers::form(cap,$c) \
            -text "$c  [dict get $caps $c]"
        grid $w.f.caps.c$i -row [expr {$i % $half}] -column [expr {$i / $half}] -sticky w -padx {0 12}
        incr i
    }
    grid $w.f.caps - -sticky news -pady {8 0}
    ttk::frame $w.f.b
    ttk::button $w.f.b.ok -text [expr {$login eq "" ? "Create" : "Save"}] -default active \
        -command {set tkusers::form(done) ok}
    ttk::button $w.f.b.cancel -text Cancel -command {set tkusers::form(done) cancel}
    pack $w.f.b.cancel $w.f.b.ok -side right -padx {4 0}
    grid $w.f.b - -sticky e -pady {8 0}
    grid columnconfigure $w.f 1 -weight 1
    pack $w.f -fill both -expand 1
    bind $w <Return> {set tkusers::form(done) ok}
    bind $w <Escape> {set tkusers::form(done) cancel}
    wm protocol $w WM_DELETE_WINDOW {set tkusers::form(done) cancel}
    focus [expr {$login eq "" ? "$w.f.login" : "$w.f.info"}]
    while 1 {
        vwait tkusers::form(done)
        if {$form(done) ne "ok"} break
        if {[save $login $cap]} break
    }
    destroy $w
}

# Save the form of edit: 1 if done (or nothing to do).  (The password is
# passed on the command line of fossil: Fossil has no other way.)
proc tkusers::save {login oldCap} {
    variable repo
    variable users
    variable caps
    variable form
    set w .users.edit
    set name [string trim $form(login)]
    set info [string trim $form(info)]
    set cap [join [lmap c [dict keys $caps] { if {$form(cap,$c)} { set c } else continue }] ""]
    # (Capabilities not in the list stay.)
    foreach c [split $oldCap ""] {
        if {![dict exists $caps $c] && [string first $c $cap] < 0} { append cap $c }
    }
    set problem ""
    if {$login eq "" && ![regexp {^[^\s"'<>&-][^\s"'<>&]*$} $name]} {
        set problem "The user name: no spaces, quotes or \"<>&\", not starting with \"-\"."
    } elseif {$login eq "" && [info exists users($name)]} {
        set problem "There is a user named $name already."
    } elseif {$form(pw) ne $form(pw2)} {
        set problem "The two passwords differ."
    } elseif {$login eq "" && $form(pw) eq ""} {
        set problem "The password is missing."
    } elseif {[regexp {^[-<>|]|^2>} $form(pw)] || [regexp {^[-<>|]|^2>} $info]} {
        set problem "The contact and the password cannot start with \"-\", \"<\", \">\" or \"|\"."
    }
    if {$problem ne ""} {
        tk_messageBox -parent $w -icon info -title [wm title $w] -message $problem
        return 0
    }
    # What changes.
    set steps {}
    set what {}
    if {$login eq ""} {
        lappend steps [list new $name $info $form(pw)] [list capabilities $name $cap]
        lappend what "a new user $name" "capabilities: [expr {$cap eq "" ? "none" : $cap}]"
    } else {
        if {$info ne [dict get $users($login) info]} {
            lappend steps [list contact $login $info]
            lappend what "contact: [expr {$info eq "" ? "none" : $info}]"
        }
        if {$cap ne $oldCap} {
            lappend steps [list capabilities $login $cap]
            lappend what "capabilities: [expr {$oldCap eq "" ? "none" : $oldCap}] \u2192\
                [expr {$cap eq "" ? "none" : $cap}]"
        }
        if {$form(pw) ne ""} {
            lappend steps [list password $login $form(pw)]
            lappend what "a new password"
        }
    }
    if {![llength $steps]} { return 1 }
    if {![ui::confirm -parent $w -title [wm title $w] \
            [expr {$login eq "" ? "Create the user $name?" : "Change the user $login?"}] \
            "[join $what \n]\n\nIn [file tail $repo]; nothing is synced."]} {
        return 0
    }
    foreach step $steps {
        lassign [fossil::run user {*}$step -R $repo] code out
        if {$code} {
            tk_messageBox -parent $w -icon error -title [wm title $w] \
                -message "fossil user [lindex $step 0] failed:" -detail $out
            reload
            return 0
        }
    }
    reload
    set name [expr {$login eq "" ? $name : $login}]
    if {[.users.main.list.t exists $name]} {
        .users.main.list.t selection set [list $name]
        .users.main.list.t see $name
    }
    return 1
}

# The context menu of a user: the buttons of the window.
proc tkusers::popupMenu {m item} {
    variable users
    foreach b {edit default unset} { popup::button $m .users.b.$b }
    popup::separator $m
    popup::copy $m "Copy user name" $item
    popup::copy $m "Copy contact" [expr {[info exists users($item)] ? [dict get $users($item) info] : ""}]
    popup::default $m [.users.b.edit cget -text]
}
