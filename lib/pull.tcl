# The Timeline tab (lib/tktimeline.tcl): pull -- the check-ins of the
# remote repository brought in (nothing is pushed).

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

# Pull from a remote ("fossil pull"; never push or sync), with its
# options, then show what came: the Last pull view.
proc tktimeline::pull {} {
    variable repo
    variable pullOpt
    variable pullChan
    if {[info exists pullChan] && $pullChan ne ""} { bell; return }
    set remotes [remotes]
    if {![llength $remotes]} {
        tk_messageBox -icon info -title Pull -message "The repository has no remote." \
            -detail "Add one in Repository \u25b8 Remotes."
        return
    }
    array set pullOpt {private 0 all 0 ipv4 0 verily 0 verbose 0 auth ""}
    set pullOpt(remote) [lindex $remotes 0 0]
    set w .timeline.pull
    destroy $w
    toplevel $w
    wm title $w Pull
    wm transient $w .
    ttk::frame $w.f -padding 10
    pack $w.f -fill both -expand 1
    ttk::label $w.f.l -text "Pull from:"
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
    ttk::label $w.f.into -text "into [file tail $repo].  Nothing is pushed." -foreground gray40
    ttk::checkbutton $w.f.private -text "Private branches too" -variable tktimeline::pullOpt(private)
    ttk::checkbutton $w.f.all -text "From all the remotes" -variable tktimeline::pullOpt(all)
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
    ttk::button $w.f.b.ok -text Pull -default active -command tktimeline::startPull
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
    set auth [string trim $pullOpt(auth)]
    if {$auth ne "" && (![regexp {^[^:\s]+:\S*$} $auth] || [catch {fossil::arg $auth}])} {
        tk_messageBox -icon info -parent $w -title Pull -message "HTTP authentication: user:password"
        return
    }
    set cmd [list fossil pull]
    if {$pullOpt(all)} {
        lappend cmd --all
    } elseif {$pullOpt(remote) ne "default"} {
        # Another remote: once, the default stays.
        if {![fossil::argOk $pullOpt(remote) Pull]} return
        lappend cmd [fossil::arg $pullOpt(remote)] --once
    }
    foreach {key option} {private --private ipv4 --ipv4 verily --verily verbose -v} {
        if {$pullOpt($key)} { lappend cmd $option }
    }
    # (In one word: the password cannot be taken for anything else.)
    if {$auth ne ""} { lappend cmd --httpauth=$auth }
    lappend cmd -R $repo
    variable pullCmd $cmd
    set pullBefore [lindex [fossil::sql $repo "SELECT coalesce(max(rcvid),0) FROM rcvfrom"] 0 0]
    try {
        set pullChan [open |[list {*}$cmd 2>@1] r+]
    } on error msg {
        set pullChan ""
        tk_messageBox -icon error -parent $w -title Pull -message $msg
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
    # What came: the Last pull view if it came from a server (the view
    # knows pulls by their address); else everything.
    set new [fossil::sql $repo "SELECT ipaddr IS NOT NULL FROM rcvfrom WHERE rcvid>$pullBefore
        AND rcvid IN (SELECT rcvid FROM blob JOIN event ON objid=rid)"]
    if {[llength $new]} {
        tktaalik::navigate
        set v [expr {[lsearch -exact [join $new] 1] >= 0 ? "lastpull" : "all"}]
        # (The view is a term of the search: in place of the one there.)
        variable query
        set query [string trim "[lindex [splitView $query] 1] [viewTerm $v]"]
    }
    changedHere
}
