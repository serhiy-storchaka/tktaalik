# The Remotes window of tktaalik (Repository menu): the URLs the
# repository syncs with ("fossil remote list"): the default one (used by
# pull and push) and named ones.  Adding, deleting, making one the default
# or turning the default off change the local repository, after a
# confirmation; nothing is synced.  Passwords are never shown (Fossil
# hides them).

source [file join [file dirname [file normalize [info script]]] fossil.tcl]

namespace eval tkremotes {
    variable repo ""
    variable root ""
    variable remotes {}       ;# name -> URL
    variable status ""
    variable addName ""
    variable addUrl ""
    variable addDone ""
}

# Open the window (made the first time), for the repository shown.
proc tkremotes::window {} {
    if {[tktaalik::dialogWindow .remotes Remotes]} { build }
    setRepository $::tktaalik::repo $::tktaalik::root
    focus .remotes.list.t
}

proc tkremotes::build {} {
    wm geometry .remotes 900x320
    ttk::frame .remotes.list
    set t .remotes.list.t
    ttk::treeview $t -columns {name url} -show headings -selectmode browse \
        -yscrollcommand {.remotes.list.y set}
    ttk::scrollbar .remotes.list.y -command [list $t yview]
    set char [font measure TkDefaultFont 0]
    $t heading name -text Name -anchor w
    $t heading url -text URL -anchor w
    $t column name -width [expr {14 * $char}] -stretch 0
    $t column url -width [expr {50 * $char}] -stretch 1
    $t tag configure default -font TkHeadingFont
    grid $t .remotes.list.y -sticky news
    grid columnconfigure .remotes.list 0 -weight 1
    grid rowconfigure .remotes.list 0 -weight 1

    ttk::frame .remotes.b -padding 6
    foreach {b label command} {
        add     "Add\u2026"              tkremotes::add
        saveas  "Save as\u2026"          tkremotes::saveAs
        delete  "Delete\u2026"           tkremotes::delete
        default "Make default\u2026"     tkremotes::makeDefault
        off     "No default\u2026"       tkremotes::off
        scrub   "Forget passwords\u2026" tkremotes::scrub
        browse  "Open in browser"     tkremotes::browse
        link    "Copy link"           tkremotes::copyLink
    } {
        ttk::button .remotes.b.$b -text $label -command $command
        pack .remotes.b.$b -side left -padx {0 4}
    }
    ttk::button .remotes.b.close -text Close -command {wm withdraw .remotes}
    pack .remotes.b.close -side right
    ttk::label .remotes.status -textvariable tkremotes::status -padding {6 2} -anchor w
    pack .remotes.status -side bottom -fill x
    pack .remotes.b -side bottom -fill x
    pack .remotes.list -fill both -expand 1 -padx 6 -pady {6 0}
    icons::tooltip .remotes.b.saveas "A copy of the selected remote under another name,\nwith its saved password (to come back to it later)"
    icons::tooltip .remotes.b.scrub "Forget the saved passwords; the URLs stay"
    icons::tooltip .remotes.b.link "The URL of the checkout on the default remote"
    bind $t <<TreeviewSelect>> tkremotes::updateButtons
    bind $t <Double-1> tkremotes::browse
    bind .remotes <F5> tkremotes::reload
    popup::attach .remotes.list.t tkremotes::popupMenu
}

proc tkremotes::setRepository {path newRoot} {
    variable repo $path
    variable root $newRoot
    wm title .remotes "Remotes \u2014 [file rootname [file tail $repo]]"
    reload
}

# Run fossil remote ... for the repository: {code output}.
proc tkremotes::remote {args} {
    variable repo
    fossil::run remote {*}$args -R $repo
}

proc tkremotes::reload {} {
    variable remotes
    variable status
    lassign [remote list] code out
    set remotes {}
    if {$code} {
        set status "fossil remote list failed: [string trim $out]"
    } else {
        foreach line [split [string trim $out] \n] {
            if {[regexp {^(\S+)\s+(\S+)$} $line -> name url]} { dict set remotes $name $url }
        }
        set n [llength [lsearch -all -not [dict keys $remotes] default]]
        set status [expr {[dict exists $remotes default]
            ? "Pull and push use the default; $n named"
            : "No default remote; $n named"}]
    }
    set t .remotes.list.t
    set keep [lindex [$t selection] 0]
    $t delete [$t children {}]
    # The default first.
    if {[dict exists $remotes default]} {
        $t insert {} end -id default -values [list default [dict get $remotes default]] -tags default
    }
    dict for {name url} $remotes {
        if {$name ne "default"} { $t insert {} end -id $name -values [list $name $url] }
    }
    if {$keep eq "" || ![$t exists $keep]} { set keep [lindex [$t children {}] 0] }
    if {$keep ne ""} { $t selection set $keep }
    updateButtons
}

proc tkremotes::selected {} {
    lindex [.remotes.list.t selection] 0
}

proc tkremotes::updateButtons {} {
    variable remotes
    set name [selected]
    set named [expr {$name ne "" && $name ne "default"}]
    .remotes.b.delete state [expr {$named ? "!disabled" : "disabled"}]
    .remotes.b.default state [expr {$named && (![dict exists $remotes default]
        || [dict get $remotes $name] ne [dict get $remotes default]) ? "!disabled" : "disabled"}]
    .remotes.b.saveas state [expr {$name ne "" ? "!disabled" : "disabled"}]
    .remotes.b.off state [expr {[dict exists $remotes default] ? "!disabled" : "disabled"}]
    .remotes.b.scrub state [expr {[dict size $remotes] ? "!disabled" : "disabled"}]
    variable root
    .remotes.b.link state [expr {$root ne "" && [dict exists $remotes default]
        && [string match http* [dict get $remotes default]] ? "!disabled" : "disabled"}]
    .remotes.b.browse state [expr {$name ne "" && [string match http* [dict get $remotes $name]]
        ? "!disabled" : "disabled"}]
}

proc tkremotes::confirm {message detail} {
    ui::confirm -parent .remotes -title Remotes $message $detail
}

# Run a change; report a failure; show the list again.
proc tkremotes::change {args} {
    lassign [remote {*}$args] code out
    if {$code} {
        tk_messageBox -parent .remotes -icon error -title Remotes \
            -message "fossil remote [lindex $args 0] failed:" -detail [string trim $out]
    }
    reload
    return [expr {!$code}]
}

# A new named remote: asks for the name and the URL.  Without a name, the
# URL becomes the default remote.  With FROM (a remote), a copy of it
# under the name, with its saved password ("fossil remote add NAME FROM").
proc tkremotes::add {{from ""}} {
    variable addName ""
    variable addUrl ""
    variable addDone ""
    variable remotes
    set w .remotes.add
    destroy $w
    toplevel $w
    wm title $w [expr {$from eq "" ? "Add a remote" : "Save the remote $from as"}]
    wm transient $w .remotes
    ttk::frame $w.f -padding 10
    ttk::label $w.f.ln -text Name:
    ttk::entry $w.f.name -textvariable tkremotes::addName -width 20
    ttk::label $w.f.lu -text URL:
    ttk::entry $w.f.url -textvariable tkremotes::addUrl -width 50
    if {$from ne ""} {
        set addUrl [dict get $remotes $from]
        $w.f.url state readonly
    } else {
        ttk::label $w.f.hint -foreground gray35 \
            -text "Without a name: the URL becomes the default remote."
    }
    ttk::frame $w.f.b
    ttk::button $w.f.b.ok -text Add -default active -command {set tkremotes::addDone ok}
    ttk::button $w.f.b.cancel -text Cancel -command {set tkremotes::addDone cancel}
    pack $w.f.b.cancel $w.f.b.ok -side right -padx {4 0}
    grid $w.f.ln $w.f.name -sticky w -pady 2
    grid $w.f.lu $w.f.url -sticky ew -pady 2
    if {$from eq ""} { grid x $w.f.hint -sticky w }
    grid $w.f.b - -sticky e -pady {8 0}
    grid columnconfigure $w.f 1 -weight 1
    pack $w.f -fill both -expand 1
    bind $w <Return> {set tkremotes::addDone ok}
    bind $w <Escape> {set tkremotes::addDone cancel}
    wm protocol $w WM_DELETE_WINDOW {set tkremotes::addDone cancel}
    focus $w.f.name
    while 1 {
        vwait tkremotes::addDone
        if {$addDone ne "ok"} break
        set name [string trim $addName]
        set url [string trim $addUrl]
        # (A repository file: "~" as the home folder, which Tcl 9 does not
        # expand.)
        if {[string match ~* $url]} { set url [repoops::path $url] }
        set problem ""
        if {$name eq "" && $from eq ""} {
            # The default remote.
            if {$url eq ""} {
                tk_messageBox -parent $w -icon info -title "Add a remote" -message "The URL is missing."
                continue
            }
            if {[catch {fossil::arg $url}]} {
                tk_messageBox -parent $w -icon info -title "Add a remote" \
                    -message "A URL cannot start with \"-\", \"<\", \">\" or \"|\"."
                continue
            }
            set now [expr {[dict exists $remotes default] ? [dict get $remotes default] : "none"}]
            if {![confirm "Make $url the default remote?" "Pull and push will use it\
                    instead of\n$now"]} continue
            if {[change $url]} break
            continue
        }
        if {![regexp {^[A-Za-z0-9_.-]+$} $name] || $name eq "default"} {
            set problem "The name: letters, digits, \"_\", \".\" or \"-\" (not \"default\")."
        } elseif {[dict exists $remotes $name]} {
            set problem "There is a remote named $name already."
        } elseif {$url eq ""} {
            set problem "The URL is missing."
        } elseif {[catch {fossil::arg $url}]} {
            set problem "A URL cannot start with \"-\", \"<\", \">\" or \"|\"."
        }
        if {$problem ne ""} {
            tk_messageBox -parent $w -icon info -title "Add a remote" -message $problem
            continue
        }
        if {![confirm "Add the remote $name?" "$url\n\nNothing is synced; pull and push\
                still use the default remote."]} continue
        # (A copy by the name: with the password Fossil keeps for it.)
        if {[change add $name [expr {$from ne "" ? $from : $url}]]} break
    }
    destroy $w
}

proc tkremotes::saveAs {} {
    set name [selected]
    if {$name ne ""} { add $name }
}

proc tkremotes::delete {} {
    variable remotes
    set name [selected]
    if {$name eq "" || $name eq "default"} return
    if {![confirm "Delete the remote $name?" [dict get $remotes $name]]} return
    change delete $name
}

# Make a named remote the default one: pull and push will use it.
proc tkremotes::makeDefault {} {
    variable remotes
    set name [selected]
    if {$name eq "" || $name eq "default"} return
    set now [expr {[dict exists $remotes default] ? [dict get $remotes default] : "none"}]
    if {![confirm "Make $name the default remote?" "Pull and push will use\n[dict get $remotes $name]\
            \ninstead of\n$now"]} return
    change $name
}

proc tkremotes::off {} {
    variable remotes
    if {![dict exists $remotes default]} return
    if {![confirm "Turn the default remote off?" "Pull and push will need a URL or a\
            remote name.  The default now:\n[dict get $remotes default]"]} return
    change off
}

# Forget the saved passwords ("fossil remote scrub").
proc tkremotes::scrub {} {
    if {![confirm "Forget the saved passwords?" "The URLs stay; Fossil will ask\
            for the password at the next pull or push."]} return
    change scrub
}

# The URL of the checkout on the default remote ("fossil remote
# hyperlink"), to the clipboard.
proc tkremotes::copyLink {} {
    variable root
    variable status
    if {$root eq ""} return
    lassign [fossil::run -dir $root remote hyperlink] code out
    set out [string trim $out]
    if {$code || ![regexp {^https?://\S+$} $out]} {
        tk_messageBox -parent .remotes -icon error -title Remotes \
            -message "fossil remote hyperlink failed:" -detail $out
        return
    }
    ui::copy $out
    set status "Copied: $out"
}

# The remote's web pages, without the user name in the URL.
proc tkremotes::browse {} {
    variable remotes
    set name [selected]
    if {$name eq ""} return
    set url [dict get $remotes $name]
    if {![string match http* $url]} return
    regsub {^(https?://)[^@/]*@} $url {\1} url
    tktsearch::browse $url
}

# The context menu of a remote: the buttons of the window.
proc tkremotes::popupMenu {m item} {
    variable remotes
    foreach b {default saveas delete} { popup::button $m .remotes.b.$b }
    popup::separator $m
    foreach b {browse link} { popup::button $m .remotes.b.$b }
    popup::separator $m
    popup::copy $m "Copy URL" [expr {[dict exists $remotes $item] ? [dict get $remotes $item] : ""}]
}
