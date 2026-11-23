# The Timeline tab (lib/tktimeline.tcl): pull and push -- the check-ins
# of a remote repository brought in, or ours sent there (only when asked,
# after a confirmation of what goes; nothing syncs).

# ------------------------------------------------------------------- pull

# The remotes of the repository: {name url} each, the default first.
proc tktimeline::remotes {} {
    variable repo
    lassign [fossil::run remote list -R $repo] code out
    if {$code} { return {} }
    set list {}
    foreach line [split $out \n] {
        if {[regexp {^(\S+)\s+(\S+)} $line -> name url]} { lappend list [list $name $url] }
    }
    lsort -command {::apply {{a b} {
        expr {[lindex $a 0] eq "default" ? -1 : [lindex $b 0] eq "default" ? 1
            : [string compare [lindex $a 0] [lindex $b 0]]}
    }}} $list
}

# Pull from a remote ("fossil pull"), then show what came: the Last pull
# view; or push to one ("fossil push"), after a confirmation of what goes
# (KIND pull or push).  Both take the same options, in the same window.
# Neither syncs: a pull sends nothing, a push brings nothing.
proc tktimeline::pull {{kind pull}} {
    variable repo
    variable pullOpt
    variable pullChan
    if {[info exists pullChan] && $pullChan ne ""} { bell; return }
    set title [string totitle $kind]
    set remotes [remotes]
    if {![llength $remotes]} {
        tk_messageBox -icon info -title $title -message "The repository has no remote." \
            -detail "Add one in Repository \u25b8 Remotes."
        return
    }
    array set pullOpt {private 0 all 0 ipv4 0 verily 0 verbose 0 auth ""}
    set pullOpt(kind) $kind
    set pullOpt(remote) [lindex $remotes 0 0]
    set w .timeline.pull
    destroy $w
    toplevel $w
    wm title $w $title
    wm transient $w .
    ttk::frame $w.f -padding 10
    pack $w.f -fill both -expand 1
    ttk::label $w.f.l -text [dict get {pull "Pull from:" push "Push to:"} $kind]
    ttk::combobox $w.f.r -state readonly -textvariable tktimeline::pullOpt(remote) \
        -values [lmap r $remotes { lindex $r 0 }] -width 20
    ttk::label $w.f.url -foreground gray40
    set update [list ::apply {{w remotes} {
        foreach r $remotes {
            if {[lindex $r 0] eq $::tktimeline::pullOpt(remote)} {
                $w.f.url configure -text [lindex $r 1]
            }
        }
    }} $w $remotes]
    bind $w.f.r <<ComboboxSelected>> $update
    {*}$update
    if {$kind eq "pull"} {
        set into "into [file tail $repo].  Nothing is pushed."
    } else {
        set into "from [file tail $repo].  Nothing is pulled; what goes is shown first."
    }
    ttk::label $w.f.into -text $into -foreground gray40
    ttk::checkbutton $w.f.private -text "Private branches too" -variable tktimeline::pullOpt(private)
    ttk::checkbutton $w.f.all -text [dict get {pull "From all the remotes" push "To all the remotes"} $kind] \
        -variable tktimeline::pullOpt(all)
    if {[llength $remotes] < 2} { $w.f.all state disabled }
    ttk::checkbutton $w.f.ipv4 -text "IPv4 only" -variable tktimeline::pullOpt(ipv4)
    ttk::checkbutton $w.f.verily -text "Verily: make sure nothing is overlooked (slower)" \
        -variable tktimeline::pullOpt(verily)
    ttk::checkbutton $w.f.verbose -text "Verbose output" -variable tktimeline::pullOpt(verbose)
    ttk::label $w.f.al -text "HTTP authentication:"
    ttk::entry $w.f.a -textvariable tktimeline::pullOpt(auth) -width 30 -show *
    ttk::label $w.f.an -text "user:password, if the web server asks for it" -foreground gray40
    text $w.f.out -width 80 -height 8 -font TkFixedFont -state disabled -wrap none
    ttk::frame $w.f.b
    ttk::button $w.f.b.ok -text $title -default active -command tktimeline::startPull
    ttk::button $w.f.b.stop -text Stop -command tktimeline::stopPull -state disabled
    ttk::button $w.f.b.cancel -text Close -command [list destroy $w]
    pack $w.f.b.cancel $w.f.b.stop $w.f.b.ok -side right -padx {4 0}
    grid $w.f.l $w.f.r -sticky w -pady 2
    grid $w.f.url - -sticky w
    grid $w.f.into - -sticky w -pady {0 6}
    foreach c {private all ipv4 verily verbose} { grid $w.f.$c - -sticky w }
    grid $w.f.al $w.f.a -sticky w -pady {6 0}
    grid $w.f.an - -sticky w
    grid $w.f.out - -sticky news -pady {8 0}
    grid $w.f.b - -sticky e -pady {8 0}
    grid columnconfigure $w.f 1 -weight 1
    grid rowconfigure $w.f 9 -weight 1
    bind $w <Escape> [list destroy $w]
    focus $w.f.b.ok
}

proc tktimeline::startPull {} {
    variable repo
    variable pullOpt
    variable pullChan
    variable pullBefore
    set w .timeline.pull
    set kind $pullOpt(kind)
    set title [string totitle $kind]
    set auth [string trim $pullOpt(auth)]
    if {$auth ne "" && (![regexp {^[^:\s]+:\S*$} $auth] || [catch {fossil::arg $auth}])} {
        tk_messageBox -icon info -parent $w -title $title -message "HTTP authentication: user:password"
        return
    }
    set cmd [list fossil $kind]
    if {$pullOpt(all)} {
        lappend cmd --all
    } elseif {$pullOpt(remote) ne "default"} {
        # Another remote: once, the default stays.
        if {![fossil::argOk $pullOpt(remote) $title]} return
        lappend cmd [fossil::arg $pullOpt(remote)] --once
    }
    foreach {key option} {private --private ipv4 --ipv4 verily --verily verbose -v} {
        if {$pullOpt($key)} { lappend cmd $option }
    }
    # (In one word: the password cannot be taken for anything else.)
    if {$auth ne ""} { lappend cmd --httpauth=$auth }
    lappend cmd -R $repo
    if {$kind eq "push" && ![confirmPush $w]} return
    variable pullCmd $cmd
    variable ridBefore
    lassign [lindex [fossil::sql $repo "SELECT (SELECT coalesce(max(rcvid),0) FROM rcvfrom),
        (SELECT coalesce(max(rid),0) FROM blob)"] 0] pullBefore ridBefore
    try {
        set pullChan [fossil::lenient [open |[list {*}[fossil::command $cmd] 2>@1] r+]]
    } on error msg {
        set pullChan ""
        tk_messageBox -icon error -parent $w -title $title -message $msg
        return
    }
    chan close $pullChan write
    fconfigure $pullChan -blocking 0 -encoding utf-8
    $w.f.b.ok state disabled
    $w.f.b.stop state !disabled
    $w.f.out configure -state normal
    $w.f.out delete 1.0 end
    $w.f.out configure -state disabled
    variable pullBusy [ui::busyHold .]
    fileevent $pullChan readable tktimeline::pullOutput
}

proc tktimeline::pullOutput {} {
    variable pullChan
    variable pullBefore
    variable repo
    variable view
    set w .timeline.pull
    set text [read $pullChan]
    if {[winfo exists $w]} {
        $w.f.out configure -state normal
        # (Fossil redraws its progress line with carriage returns.)
        $w.f.out insert end [regsub -all {[^\n]*\r(?!\n)} $text ""]
        $w.f.out see end
        $w.f.out configure -state disabled
    }
    if {![eof $pullChan]} return
    fconfigure $pullChan -blocking 1
    set failed [catch {close $pullChan} msg]
    set pullChan ""
    variable pullBusy
    ui::busyRelease $pullBusy
    if {[winfo exists $w]} {
        $w.f.b.ok state !disabled
        $w.f.b.stop state disabled
        if {$failed} {
            $w.f.out configure -state normal
            $w.f.out insert end "\n[regsub {\n?child process exited abnormally$} $msg {}]" error
            $w.f.out tag configure error -foreground red3
            $w.f.out configure -state disabled
        }
    }
    # After a push: the Outgoing view and the marks of what is not pushed
    # yet, again.
    variable pullOpt
    if {$pullOpt(kind) eq "push"} {
        changedHere
        return
    }
    # What came: the Last pull view if it came from a server (the view
    # knows pulls by their address); else everything.  (The new artifacts
    # by their rids: see lastPull.)
    variable ridBefore
    set new [fossil::sql $repo "SELECT DISTINCT r.ipaddr IS NOT NULL
        FROM blob b CROSS JOIN event e CROSS JOIN rcvfrom r
        WHERE b.rid>$ridBefore AND e.objid=b.rid AND r.rcvid=b.rcvid AND b.rcvid>$pullBefore"]
    if {[llength $new]} {
        tktaalik::navigate
        set v [expr {[lsearch -exact [join $new] 1] >= 0 ? "lastpull" : "all"}]
        # (The view is a term of the search: in place of the one there.)
        variable query
        set query [string trim "[lindex [splitView $query] 1] [viewTerm $v]"]
    }
    changedHere
    # The pull moved the check-in of the checkout to another branch (a tag
    # change: the next commit or update would go there): said, and an
    # update to the old branch offered.
    set root $::tktaalik::root
    if {!$failed && $root ne ""} {
        set moved [tkcommit::branchMoved $root $pullBefore]
        if {[llength $moved]} {
            lassign $moved to from user date
            set detail "It was moved[expr {$from ne "" ? " from $from" : ""}] by $user on $date (a tag\
                change, as \"fossil amend --branch\" makes), so the next commit or update of the\
                checkout would go to $to."
            if {$from eq "" || [catch {fossil::arg $from}]} {
                ui::infoBox -title Pull "The pull moved the check-in of the checkout to $to." $detail
            } elseif {[ui::ask -title Pull -icon warning "The pull moved the check-in of the checkout to $to." \
                    "$detail\n\nUpdate the checkout to the newest check-in of $from now?"]} {
                tktaalik::show commit
                tkcommit::updateCheckout $from
            }
        }
    }
}

# Push?  Says where to and what waits to go (as the Outgoing view: the
# events among the artifacts not pushed yet, private ones only with
# --private).  Fossil records as unsent only what its commands make for
# sending (check-ins, branches, wiki, tickets, forum...), not tag
# changes; those go all the same, as the remote asks for what it lacks:
# also everything for a remote never pushed to.
proc tktimeline::confirmPush {w} {
    variable repo
    variable pullOpt
    # (The remote named in the question, its URL below: a long one would
    # make the question long.)
    set urls {}
    foreach r [remotes] {
        if {$pullOpt(all) || [lindex $r 0] eq $pullOpt(remote)} { lappend urls "[lindex $r 0]: [lindex $r 1]" }
    }
    set where [if {$pullOpt(all)} {string cat "all the remotes"} else {set pullOpt(remote)}]
    set private [if {!$pullOpt(private)} {string cat "AND rid NOT IN (SELECT rid FROM private)"}]
    set count [lindex [fossil::sql $repo "SELECT count(*) FROM unsent WHERE 1 $private"] 0 0]
    set events [fossil::sql $repo "SELECT e.type, date(e.mtime), e.user, [fossil::outcol coalesce(e.comment,'')]
        FROM event e WHERE e.objid IN (SELECT rid FROM unsent WHERE 1 $private) ORDER BY e.mtime"]
    set names {ci check-in w wiki t ticket g tag e technote f forum}
    set lines {}
    foreach row [lrange $events 0 19] {
        lassign $row type date user comment
        set comment [fossil::oneLine $comment]
        if {[string length $comment] > 70} { set comment "[string range $comment 0 68]\u2026" }
        set name [if {[dict exists $names $type]} {dict get $names $type} else {set type}]
        lappend lines "$date  $user  $name: $comment"
    }
    if {[llength $events] > 20} { lappend lines "\u2026 and [expr {[llength $events] - 20}] more" }
    set detail "[join $urls \n]\n\n"
    if {$count == 0} {
        append detail "No check-ins, wiki pages, tickets or posts wait to go.  Fossil still sends\
            tag changes and anything else the remote does not have."
    } else {
        append detail "Not pushed yet (the Outgoing view): [expr {$count == 1 ? "1 artifact" : "$count artifacts"}]"
        if {[llength $events]} {
            append detail ", with [expr {[llength $events] == 1 ? "this event" : "these [llength $events] events"}]:\n\n[join $lines \n]"
        } else {
            append detail "."
        }
        append detail "\n\nFossil also sends tag changes (not counted here) and anything else the\
            remote does not have."
    }
    if {!$pullOpt(private)} {
        append detail "  Private branches stay here."
    } else {
        append detail "  Private branches go too."
    }
    ui::confirm -parent $w -title Push "Push from [file tail $repo] to $where?" $detail
}
