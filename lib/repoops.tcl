# Operations on repositories and checkouts, from the File, Checkout and
# Repository menus: clone a repository, make a new one, open or close a
# checkout, back up, list the known repositories and checkouts ("fossil
# all list"), the changes of all checkouts, pull, export, import or reset
# the configuration, open the repository in the browser served locally
# ("fossil ui") and the remote's chat, download its archive.  Each asks
# first; nothing is ever pushed or synced (clone and pull only download).

namespace eval repoops {
    variable f                  ;# array: the fields of the dialog shown
    variable done ""            ;# ok or cancel: the dialog's answer
    variable uiChan ""          ;# the "fossil ui" serving the repository
    variable uiRepo ""
    variable uiUrl ""
    variable running ""         ;# the handle (fossil::start) of the command shown running
    variable uiPage ""          ;# the page to show when it is served
    variable areas {all email interwiki project shun skin ticket user alias subscriber}
}

# ------------------------------------------------------------- dialogs

# A dialog of FIELDS ({key label kind ?arg?} each; kinds: entry, secret,
# check, combo (arg: the values; anything can be typed), choice (arg: the
# values, only those), save, open (arg: file types), dir) with an OK
# button labelled OK; the values in f(key).  VALIDATE is called with the
# dialog and returns "" or a problem to show ("-": none to show, the
# dialog stays).  1 if OK.  One at a time: modal (another one asked for
# while it is open is refused).
proc repoops::form {w title intro fields ok {validate ""}} {
    ui::form $w $title $intro $fields $ok -array ::repoops::f -done ::repoops::done \
        -validate $validate
}

# A path as typed: "~" and "~user" as the home folders (Tcl 9 does not
# expand them), relative to the folder Tktaalik is in; "" stays "".
proc repoops::path {text} {
    set text [string trim $text]
    if {$text eq ""} { return "" }
    if {[regexp {^~([^/\\]*)(.*)$} $text -> user rest]} {
        if {$user eq ""} {
            set home [expr {[info exists ::env(HOME)] ? $::env(HOME) : [file normalize ~]}]
        } elseif {[catch {file home $user} home]} {
            # (Tcl 8.6: no "file home"; its normalize knows ~user.)
            set home [file normalize ~$user]
        }
        set text $home$rest
    }
    file normalize $text
}


proc repoops::browse {w key kind types} {
    ui::Browse $w ::repoops::f $key $kind $types
}

proc repoops::ask {title message detail} {
    ui::confirm -title $title $message $detail
}

proc repoops::failed {title what out} {
    tk_messageBox -icon error -title $title -message $what -detail [string trim $out]
}

# A word of the command line from what was typed: not taken for an option
# or a redirection (fossil::arg), with a message.
proc repoops::arg {title value} {
    if {[catch {fossil::arg $value} msg]} {
        tk_messageBox -icon info -title $title -message "This cannot be passed to fossil:" \
            -detail "$value\n\n(It starts with \"-\", \"<\", \">\" or \"|\".)"
        return -code return
    }
    return $value
}

# Run a command that may take long (the network) in a window that shows
# its output, in the directory DIR if not ""; DONE is called with the exit
# code and the output.  SHOWN: the command line to show (passwords
# masked), else COMMAND.  STOP: whether it can be stopped (a Stop
# button); everything running is stopped on quit (stopAll).
proc repoops::runShown {title command done {dir ""} {shown ""} {stop 1}} {
    variable running
    if {$running ne ""} {
        tk_messageBox -icon info -title $title -message "Another operation is running." \
            -detail "Wait for it, or stop it, first."
        return ""
    }
    if {$shown eq ""} { set shown "fossil [join [lrange $command 1 end]]" }
    set w [fossil::runWindow -w .repoopsRun -dir $dir -shown $shown -stop $stop \
        -onDone [list repoops::runDone $done] -command $command $title]
    set running [fossil::windowJob $w]
    return $w
}

proc repoops::runDone {done code text} {
    variable running
    set running ""
    uplevel #0 [list {*}$done $code $text]
}

# Stop the command running (its processes killed).
proc repoops::stopRunning {} {
    variable running
    if {$running eq ""} return
    fossil::stop $running
}

# On quit: everything running stopped (a clone, a download, the Pull of
# the Timeline, the repository served for the browser).
proc repoops::stopAll {} {
    fossil::stopAll
    # (The Timeline's own: a pull, a bisect run.)
    if {[info commands ::tktimeline::stopAll] ne ""} {
        catch ::tktimeline::stopAll
    } elseif {[info commands ::tktimeline::stopPull] ne ""} {
        catch ::tktimeline::stopPull
    }
    if {[info commands ::tkuv::stopDownload] ne ""} { catch ::tkuv::stopDownload }
    stopLocal
}

# Another repository is shown: the repository served for the browser (of
# the one shown before) stopped.
proc repoops::repositoryChanged {} {
    variable uiChan
    variable uiRepo
    if {$uiChan ne "" && $uiRepo ne $::tktaalik::repo} { stopLocal }
}



# Run fossil (in DIR if not ""), waiting: {code output}.
proc repoops::runFossil {dir args} {
    set busy [ui::busyHold]
    try {
        fossil::run -dir $dir {*}$args
    } finally {
        ui::busyRelease $busy
    }
}

# ------------------------------------------------------------- clone, init

# Clone a repository (it only downloads), then show it; a checkout too if
# a folder is given.
proc repoops::clone {} {
    if {[ui::formBusy]} return
    variable f
    array unset f
    set f(private) 0
    set f(uv) 0
    set f(savepw) 0
    set f(nested) 0
    set f(once) 0
    set fields {
        url URL entry {}
        file "Repository file" save {{{Fossil repositories} {.fossil}}}
        workdir "Checkout folder" dir {}
        admin "Admin user" entry {}
        auth "HTTP user:password" secret {}
        private "Private branches too (--private)" check {}
        uv "Unversioned files too (-u)" check {}
        savepw "Remember the HTTP password (--save-http-password)" check {}
        once "Do not remember the URL as the remote (--once)" check {}
        nested "The checkout inside another checkout (--nested)" check {}
    }
    if {![form .repoopsForm "Clone repository" "Make a local copy of a repository: its URL\
            (or a repository file), the new file, and optionally a folder for a checkout\
            of it.  This only downloads." [lmap {k l kind a} $fields {list $k $l $kind $a}] \
            Clone repoops::cloneCheck]} return
    set source [cloneSource $f(url)]
    set file [path $f(file)]
    set dir [path $f(workdir)]
    set cmd [list fossil clone]
    set shown [list fossil clone]
    if {[string trim $f(admin)] ne ""} {
        set admin [repoops::arg Clone [string trim $f(admin)]]
        lappend cmd -A $admin
        lappend shown -A $admin
    }
    if {$f(auth) ne ""} {
        # (The password is not shown in the window.)
        lappend cmd -B [repoops::arg Clone $f(auth)]
        lappend shown -B [regsub {:.*$} $f(auth) {:****}]
    }
    foreach {k o} {private --private uv -u savepw --save-http-password once --once nested --nested} {
        if {$f($k)} { lappend cmd $o; lappend shown $o }
    }
    if {$dir ne ""} { lappend cmd --workdir $dir; lappend shown --workdir $dir }
    lappend cmd [repoops::arg Clone $source] $file
    # (A URL with user:password@: not shown either.)
    lappend shown [regsub {^([a-z]+://[^:/@]*):[^@/]*@} $source {\1:****@}] $file
    if {![ask Clone "Clone $source?" "Into $file[expr {
            $dir eq "" ? "" : ", with a checkout in $dir"}].\nIt only downloads."]} return
    # (Run beside the new checkout: in another checkout fossil refuses,
    # unless nested.)
    set where [file dirname [expr {$dir ne "" ? $dir : $file}]]
    file mkdir $where
    runShown "Clone" $cmd [list repoops::cloned $file $dir] $where [join $shown]
}

# The source of a clone as typed: a URL as it is; a repository file (also
# relative, or with "~") as a full path, since the clone runs elsewhere.
proc repoops::cloneSource {text} {
    set text [string trim $text]
    if {[regexp {^[a-zA-Z][a-zA-Z0-9+.-]*:} $text] && ![regexp {^[a-zA-Z]:[/\\]} $text]} {
        return $text
    }
    path $text
}

proc repoops::cloneCheck {w} {
    variable f
    if {[string trim $f(url)] eq ""} { return "The URL is missing." }
    set file [path $f(file)]
    if {$file eq ""} { return "The repository file is missing." }
    if {[file exists $file]} { return "There is a file [file tail $file] already." }
    set dir [path $f(workdir)]
    if {$dir ne "" && [file isdirectory $dir] && [llength [glob -nocomplain -directory $dir *]]} {
        return "The checkout folder is not empty."
    }
    return ""
}

proc repoops::cloned {file dir code out} {
    if {$code || ![file exists $file]} return
    set detail ""
    if {[regexp -line {^admin-user:\s*(.*)$} $out -> admin]} { set detail "Admin user: $admin" }
    tk_messageBox -icon info -title Clone -message "Cloned into [file tail $file]." -detail $detail
    tktaalik::openPath [expr {$dir ne "" && [file isdirectory $dir] ? $dir : $file}]
}

# A new, empty repository.
proc repoops::newRepository {} {
    if {[ui::formBusy]} return
    variable f
    array unset f
    if {![form .repoopsForm "New repository" "Make a new, empty repository." {
            {file "Repository file" save {{{Fossil repositories} {.fossil}}}}
            {name "Project name" entry}
            {desc "Description" entry}
            {admin "Admin user" entry}
            {template "Settings from (a repository)" open {{{Fossil repositories} {.fossil}} {{All files} *}}}
        } Create repoops::newCheck]} return
    set file [path $f(file)]
    set cmd [list init]
    if {[string trim $f(name)] ne ""} { lappend cmd --project-name [repoops::arg "New repository" [string trim $f(name)]] }
    if {[string trim $f(desc)] ne ""} { lappend cmd --project-desc [repoops::arg "New repository" [string trim $f(desc)]] }
    if {[string trim $f(admin)] ne ""} { lappend cmd -A [repoops::arg "New repository" [string trim $f(admin)]] }
    if {[string trim $f(template)] ne ""} { lappend cmd --template [path $f(template)] }
    lappend cmd $file
    lassign [repoops::runFossil "" {*}$cmd] code out
    if {$code} { failed "New repository" "fossil init failed:" $out; return }
    set detail ""
    if {[regexp -line {^admin-user:\s*(.*)$} $out -> admin]} { set detail "Admin user: $admin" }
    if {[ui::ask -title "New repository" \
            "[file tail $file] is made.  Show it?" $detail]} {
        tktaalik::openPath $file
    }
}

proc repoops::newCheck {w} {
    variable f
    set file [path $f(file)]
    if {$file eq ""} { return "The repository file is missing." }
    if {[file exists $file]} { return "There is a file [file tail $file] already." }
    set template [path $f(template)]
    if {$template ne "" && ![file isfile $template]} { return "No repository $template." }
    return ""
}






# ------------------------------------------------------------- checkouts

# A new checkout of the repository shown ("fossil open --workdir").
proc repoops::newCheckout {} {
    if {[ui::formBusy]} return
    variable f
    set repo $::tktaalik::repo
    if {$repo eq ""} return
    array unset f
    foreach k {empty setmtime keep nested force} { set f($k) 0 }
    set branches [lmap r [fossil::sql $repo "SELECT DISTINCT value FROM tagxref WHERE tagtype>0\
        AND tagid=(SELECT tagid FROM tag WHERE tagname='branch') ORDER BY 1"] { lindex $r 0 }]
    if {![form .repoopsForm "New checkout" "A checkout (the files of a version, to work on) of\
            [file tail $repo] in a folder." [list \
            {dir Folder dir} \
            [list version "Version (empty: the newest)" combo $branches] \
            {empty "Empty: no files, but connected (--empty)" check} \
            {setmtime "File times as in the repository (--setmtime)" check} \
            {keep "Keep the files already there (-k)" check} \
            {nested "Inside another checkout (--nested)" check} \
            {force "Even if the folder is not empty (-f)" check}] \
            Open repoops::checkoutCheck]} return
    set dir [path $f(dir)]
    set cmd [list open $repo]
    if {[string trim $f(version)] ne ""} { lappend cmd [repoops::arg "New checkout" [string trim $f(version)]] }
    lappend cmd --workdir $dir --nosync
    foreach {k o} {empty --empty setmtime --setmtime keep -k nested --nested force -f} {
        if {$f($k)} { lappend cmd $o }
    }
    if {![ask "New checkout" "Open a checkout of [file tail $repo] in $dir?" "Fossil writes the\
            files of the version there.  Nothing is synced."]} return
    file mkdir $dir
    # (Beside it: in another checkout fossil refuses, unless nested.)
    lassign [repoops::runFossil [file dirname $dir] {*}$cmd] code out
    if {$code} { failed "New checkout" "fossil open failed:" $out; return }
    tktaalik::openPath $dir
}

proc repoops::checkoutCheck {w} {
    variable f
    set dir [path $f(dir)]
    if {$dir eq ""} { return "The folder is missing." }
    if {[file exists $dir] && ![file isdirectory $dir]} { return "$dir is not a folder." }
    return ""
}

# Close the checkout shown ("fossil close"): its files stay; the
# repository is shown then.
proc repoops::closeCheckout {} {
    set root $::tktaalik::root
    set repo $::tktaalik::repo
    if {$root eq ""} return
    lassign [repoops::runFossil $root changes] code out
    if {$code} {
        # (Not counted as changes: -f would be passed for them.)
        failed "Close checkout" "Cannot tell the changes of the checkout (fossil changes):" $out
        return
    }
    set changed [llength [lmap l [split [string trim $out] \n] { if {[string trim $l] eq ""} continue; set l }]]
    set stashes 0
    catch { set stashes [lindex [fossil::checkoutSql $root "SELECT count(*) FROM stash"] 0 0] }
    set detail "Fossil forgets the checkout; its files stay in the folder.  Tktaalik then\
        shows the repository [file tail $repo]."
    set force 0
    if {$changed} {
        append detail "\n\n$changed changed files: their changes are not committed and\
            Fossil will not know them."
        set force 1
    }
    if {$stashes} {
        append detail "\n\n$stashes stashes: they are lost with the checkout."
        set force 1
    }
    if {![ask "Close checkout" "Close the checkout $root?" $detail]} return
    lassign [repoops::runFossil $root close {*}[expr {$force ? "-f" : ""}]] code out
    if {$code} { failed "Close checkout" "fossil close failed:" $out; return }
    tktaalik::openPath $repo
}

# The repositories this computer knows ("fossil all list"), in menu M.
# (--dry-run: else fossil forgets those it cannot find now, as on a disk
# not mounted, without asking.)
proc repoops::knownMenu {m {checkouts 0}} {
    $m delete 0 end
    foreach path [known $checkouts] {
        $m add command -label $path -command [list tktaalik::openPath $path]
    }
    if {[$m index end] eq "none"} {
        $m add command -label "(none known)" -state disabled
    }
    if {$checkouts} {
        $m add separator
        $m add command -label "Changes in all of them\u2026" -command repoops::allChanges
    }
}

proc repoops::known {checkouts} {
    lassign [fossil::run all list {*}[expr {$checkouts ? "-c" : ""}] --dry-run] code out
    if {$code} { return {} }
    lsort -unique [lmap l [split [string trim $out] \n] {
        set l [string trimright [string trim $l] /]
        # (Not the DELETE of the dry run, nor what is not there now.)
        if {$l eq "" || ![file exists $l] || [string match "DELETE *" $l]} continue
        set l }]
}

# The uncommitted changes of every checkout this computer knows (as
# "fossil all changes", which would also forget the ones not found).
proc repoops::allChanges {} {
    set w .repoopsChanges
    destroy $w
    toplevel $w
    wm title $w "Changes in all checkouts"
    text $w.t -height 24 -width 90 -wrap none -font TkFixedFont -yscrollcommand [list $w.y set]
    ttk::scrollbar $w.y -command [list $w.t yview]
    $w.t tag configure head -font TkHeadingFont -spacing1 6
    $w.t tag configure none -foreground gray45
    ttk::frame $w.b -padding 6
    ttk::button $w.b.close -text Close -command [list destroy $w]
    pack $w.b.close -side right
    pack $w.b -side bottom -fill x
    pack $w.y -side right -fill y
    pack $w.t -fill both -expand 1
    bind $w <Escape> [list destroy $w]
    set busy [ui::busyHold]
    set clean {}
    try {
        foreach dir [known 1] {
            lassign [repoops::runFossil $dir changes] code out
            if {$code} {
                $w.t insert end "$dir\n" head "[string trim $out]\n" none
            } elseif {[string trim $out] ne ""} {
                $w.t insert end "$dir\n" head "[string trimright $out]\n" ""
            } else {
                lappend clean $dir
            }
        }
    } finally {
        ui::busyRelease $busy
    }
    if {[llength $clean]} {
        $w.t insert end "Without changes\n" head "[join $clean \n]\n" none
    }
    $w.t configure -state disabled
}



# ------------------------------------------------------------- repository

proc repoops::backup {} {
    set repo $::tktaalik::repo
    if {$repo eq ""} return
    # (Beside the repository, not in the checkout.)
    set file [tk_getSaveFile -title "Back up repository" -initialdir [file dirname $repo] \
        -initialfile [file rootname [file tail $repo]]-backup.fossil \
        -filetypes {{{Fossil repositories} {.fossil}}}]
    if {$file eq ""} return
    set file [path $file]
    if {[sameFile $file $repo]} {
        tk_messageBox -icon info -title "Back up" -message "That is the repository itself." \
            -detail "Choose another file for the backup."
        return
    }
    # (The save dialog asked about replacing a file: --overwrite.)
    lassign [repoops::runFossil "" backup --overwrite -R $repo $file] code out
    if {$code} { failed "Back up" "fossil backup failed:" $out; return }
    tk_messageBox -icon info -title "Back up" -message "Backed up into [file tail $file]." \
        -detail "[format %.1f [expr {[file size $file] / 1048576.0}]] MB"
}

# Whether A and B are the same file (also through links).
proc repoops::sameFile {a b} {
    if {[file normalize $a] eq [file normalize $b]} { return 1 }
    if {![file exists $a] || ![file exists $b]} { return 0 }
    file stat $a sa
    file stat $b sb
    expr {$sa(dev) == $sb(dev) && $sa(ino) == $sb(ino)}
}

# The names of the remotes of the repository, the default first.
proc repoops::remoteNames {repo} {
    set names [lmap l [split [string trim [lindex [fossil::run remote list -R $repo] 1]] \n] {
        lindex $l 0 }]
    if {"default" in $names} { set names [linsert [lsearch -all -inline -not -exact $names default] 0 default] }
    return $names
}

# Pull the configuration of an area from the remote (download only).
proc repoops::pullConfiguration {} {
    if {[ui::formBusy]} return
    variable f
    variable areas
    set repo $::tktaalik::repo
    if {$repo eq ""} return
    set remotes [remoteNames $repo]
    if {![llength $remotes]} {
        tk_messageBox -icon info -title "Pull configuration" -message "There is no remote to pull from." \
            -detail "Add one in Repository \u25b8 Remotes."
        return
    }
    array unset f
    set f(area) ticket
    set f(remote) [lindex $remotes 0]
    set f(overwrite) 0
    if {![form .repoopsForm "Pull configuration" "Bring the configuration of the server (its\
            ticket setup and reports, skin...) into this repository.  It only downloads." [list \
            [list area Area choice $areas] [list remote "From remote" choice $remotes] \
            {overwrite "Replace the local configuration of the area (--overwrite)" check}] Pull]} return
    set cmd [list fossil configuration pull $f(area)]
    # (A named remote by its name: its saved password is used; not by URL.)
    if {$f(remote) ne "default"} { lappend cmd [repoops::arg "Pull configuration" $f(remote)] }
    if {$f(overwrite)} { lappend cmd --overwrite }
    lappend cmd -R $repo
    if {![ask "Pull configuration" "Pull the $f(area) configuration from $f(remote)?" \
            "It changes this repository's configuration of that area[expr {$f(overwrite)
                ? ", replacing it" : ""}].  Nothing is pushed."]} return
    runShown "Pull configuration" $cmd {::apply {{code out} { repoops::configChanged }}}
}

proc repoops::exportConfiguration {} {
    if {[ui::formBusy]} return
    variable f
    variable areas
    set repo $::tktaalik::repo
    if {$repo eq ""} return
    array unset f
    set f(area) ticket
    if {![form .repoopsForm "Export configuration" "Write the configuration of an area (ticket\
            setup and reports, skin, users...) to a file." [list [list area Area choice $areas] \
            {file File save {{{Configuration} {.cfg}} {{All files} *}}}] Export \
            repoops::exportCheck]} return
    set file [path $f(file)]
    lassign [repoops::runFossil "" configuration export $f(area) $file -R $repo] code out
    if {$code} { failed "Export configuration" "fossil configuration export failed:" $out; return }
    tk_messageBox -icon info -title "Export configuration" -message "Exported into [file tail $file]."
}

proc repoops::exportCheck {w} {
    variable f
    set file [path $f(file)]
    if {$file eq ""} { return "The file is missing." }
    if {[file isdirectory $file]} { return "$file is a folder." }
    if {[file exists $file] && ![ui::ask -parent $w -default no \
            -title "Export configuration" "Replace [file tail $file]?" \
            "There is a file of that name already."]} {
        return -
    }
    return ""
}

proc repoops::importConfiguration {} {
    if {[ui::formBusy]} return
    variable f
    set repo $::tktaalik::repo
    if {$repo eq ""} return
    array unset f
    set f(merge) 1
    if {![form .repoopsForm "Import configuration" "Read a configuration exported before (Export\
            configuration) into this repository." {
            {file File open {{{Configuration} {.cfg}} {{All files} *}}}
            {merge "Merge with the configuration here (else replace it)" check}
        } Import {::apply {{w} { if {![file isfile [repoops::path $::repoops::f(file)]]} { return "No such file." } }}}]} return
    set file [path $f(file)]
    set how [expr {$f(merge) ? "merge" : "import"}]
    if {![ask "Import configuration" "[string totitle $how] [file tail $file] into [file tail $repo]?" \
            "It changes this repository's configuration.  Nothing is pushed."]} return
    lassign [repoops::runFossil "" configuration $how $file -R $repo] code out
    if {$code} { failed "Import configuration" "fossil configuration $how failed:" $out; return }
    configChanged
    tk_messageBox -icon info -title "Import configuration" -message "Imported [file tail $file]."
}

# Reset the configuration of an area to Fossil's defaults (no dry run in
# Fossil: asked, offering to export it first).
proc repoops::resetConfiguration {} {
    if {[ui::formBusy]} return
    variable f
    variable areas
    set repo $::tktaalik::repo
    if {$repo eq ""} return
    array unset f
    set f(area) skin
    set f(export) 1
    if {![form .repoopsForm "Reset configuration" "Put the configuration of an area (skin, ticket\
            setup and reports...) back to Fossil's defaults, in this repository." [list \
            [list area Area choice [lsearch -all -inline -not -exact $areas all]] \
            {export "Export it to a file first" check}] Reset\u2026]} return
    if {$f(export)} {
        set file [tk_getSaveFile -title "Export the $f(area) configuration first" \
            -initialdir [file dirname $repo] -initialfile $f(area).cfg \
            -filetypes {{{Configuration} {.cfg}} {{All files} *}}]
        if {$file eq ""} return
        lassign [repoops::runFossil "" configuration export $f(area) [path $file] -R $repo] code out
        if {$code} { failed "Reset configuration" "fossil configuration export failed:" $out; return }
    }
    if {![ask "Reset configuration" "Reset the $f(area) configuration of [file tail $repo]?" \
            "It goes back to Fossil's defaults[expr {$f(export) ? "; the export can be imported\
            again" : ", and cannot be taken back"}].  Nothing is pushed."]} return
    lassign [repoops::runFossil "" configuration reset $f(area) -R $repo] code out
    if {$code} { failed "Reset configuration" "fossil configuration reset failed:" $out; return }
    configChanged
    tk_messageBox -icon info -title "Reset configuration" -message "The $f(area) configuration is reset."
}





# The configuration changed (ticket reports, setup...): the reports shown
# again.
proc repoops::configChanged {} {
    if {[winfo exists .reports] && [winfo ismapped .reports]} { ticketreports::setRepository }
}

# ------------------------------------------------------------- browser

# The repository served here ("fossil ui", on this computer only), in the
# browser, at what is shown (the check-in, ticket, wiki page...); stopped
# on quit or when another repository is shown.
proc repoops::openLocally {} {
    variable uiChan
    variable uiRepo
    variable uiUrl
    variable uiPage
    set repo $::tktaalik::repo
    if {$repo eq ""} return
    set page [currentPage]
    if {$uiChan ne "" && $uiRepo eq $repo && $uiUrl ne ""} {
        fossil::browse $uiUrl$page
        return
    }
    stopLocal
    set uiRepo $repo
    set uiUrl ""
    set uiPage $page
    set uiChan [fossil::pipe [list ui --nobrowser $repo << "" 2>@1]]
    fconfigure $uiChan -blocking 0
    fileevent $uiChan readable [list repoops::uiRead $uiChan]
}

# The web page of what the tab shown shows: "" (the home page) else.
proc repoops::currentPage {} {
    set repo $::tktaalik::repo
    switch -- $::tktaalik::active {
        timeline {
            set rid [lindex [.timeline.main.list.t selection] 0]
            if {$rid ne ""} {
                set uuid [lindex [fossil::sql $repo "SELECT uuid FROM blob WHERE rid=[expr {int($rid)}]"] 0 0]
                if {$uuid ne ""} { return info/$uuid }
            }
        }
        tickets {
            set uuid $::tktsearch::shownTicket
            if {$uuid ne ""} { return tktview/$uuid }
        }
        branches {
            set name [lindex [.branches.main.list.t selection] 0]
            if {$name ne ""} { return timeline?r=[fossil::urlquery $name] }
        }
        wiki {
            set tag $::tkwiki::shown
            if {[string match wiki-* $tag]} { return wiki?name=[fossil::urlquery [string range $tag 5 end]] }
            if {[string match event-* $tag]} { return technote/[string range $tag 6 end] }
        }
        forum {
            set froot $::tkforum::selected
            if {$froot ne ""} {
                set uuid [lindex [fossil::sql $repo "SELECT uuid FROM blob WHERE rid=[expr {int($froot)}]"] 0 0]
                if {$uuid ne ""} { return forumpost/[string range $uuid 0 15] }
            }
        }
    }
    return ""
}

proc repoops::uiRead {chan} {
    variable uiChan
    variable uiUrl
    variable uiPage
    if {[eof $chan]} {
        catch {close $chan}
        if {$chan eq $uiChan} { set uiChan "" }
        return
    }
    set line [gets $chan]
    if {$uiUrl eq "" && [regexp {port (?:[^:\s]+:)?(\d+)} $line -> port]} {
        set uiUrl http://localhost:$port/
        fossil::browse $uiUrl$uiPage
    }
}

proc repoops::stopLocal {} {
    variable uiChan
    variable uiUrl
    if {$uiChan eq ""} return
    fossil::kill [pid $uiChan]
    catch {close $uiChan}
    set uiChan ""
    set uiUrl ""
}

# The chat of the default remote, in the browser.
proc repoops::openChat {} {
    set url [fossil::remoteUrl $::tktaalik::repo]
    if {$url eq ""} {
        tk_messageBox -icon info -title Chat -message "This repository has no remote with a chat." \
            -detail "Add one in Repository \u25b8 Remotes."
        return
    }
    fossil::browse $url/chat
}

# The chat's messages from the server, as an archive in a file of its own
# ("fossil chat pull --out": download only; the server must allow it:
# Setup privilege).
proc repoops::chatArchive {} {
    if {[ui::formBusy]} return
    variable f
    set repo $::tktaalik::repo
    if {$repo eq ""} return
    if {[fossil::remoteUrl $repo] eq ""} {
        tk_messageBox -icon info -title "Chat archive" -message "This repository has no remote with a chat." \
            -detail "Add one in Repository \u25b8 Remotes."
        return
    }
    array unset f
    set f(all) 1
    set f(file) [file join [file dirname $repo] [file rootname [file tail $repo]]-chat.db]
    if {![form .repoopsForm "Chat archive" "Download the messages of the remote's chat into a\
            file (an SQLite database).  The server allows it only to users with Setup privilege." {
            {file File save {{{SQLite databases} {.db}} {{All files} *}}}
            {all "All the messages (else the ones not downloaded before)" check}
        } Download {::apply {{w} { if {[repoops::path $::repoops::f(file)] eq ""} { return "The file is missing." } }}}]} return
    set cmd [list fossil chat pull --out [path $f(file)]]
    if {$f(all)} { lappend cmd --all }
    lappend cmd -R $repo
    runShown "Chat archive" $cmd {::apply {{code out} {}}}
}




