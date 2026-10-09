# The Unversioned files window of tktaalik (Repository menu): the files
# Fossil keeps outside the check-ins ("fossil uv"), only the newest of
# each: view, export, edit (text), add, rename, touch and remove them.
# Changes are made in the local repository, after a confirmation, and are
# permanent (unversioned files have no history); they reach the server
# only with "fossil uv sync", which is never run here.

source [file join [file dirname [file normalize [info script]]] fossil.tcl]

namespace eval tkuv {
    variable repo ""
    variable root ""
    variable remote ""
    variable files {}         ;# name -> {size date hash stored}
    variable filter ""
    variable status ""
    variable dlgName ""       ;# the dialogs: a name, a date, done
    variable dlgDate ""
    variable dlgDone ""
}

# Open the window (made the first time), for the repository shown.
proc tkuv::window {} {
    if {[tktaalik::dialogWindow .uv "Unversioned files"]} { build }
    setRepository $::tktaalik::repo $::tktaalik::root
    focus .uv.list.t
}

proc tkuv::build {} {
    wm geometry .uv 900x420
    ttk::frame .uv.top -padding {6 6 6 2}
    ttk::label .uv.top.fl -text "Find:"
    ttk::entry .uv.top.filter -textvariable tkuv::filter -width 30
    pack .uv.top.fl .uv.top.filter -side left -padx {0 6}
    icons::tooltip .uv.top.filter "Part of the name, or a pattern: *.zip, doc/*"
    trace add variable ::tkuv::filter write {::apply {args {
        after cancel tkuv::showList
        after 200 tkuv::showList
    }}}
    ttk::frame .uv.list
    set t .uv.list.t
    ttk::treeview $t -columns {name size stored date hash} -show headings -selectmode extended \
        -yscrollcommand {.uv.list.y set}
    ttk::scrollbar .uv.list.y -command [list $t yview]
    set char [font measure TkDefaultFont 0]
    foreach {col heading chars anchor stretch} {
        name Name 40 w 1  size Size 10 e 0  stored Stored 10 e 0  date "Date (UTC)" 17 w 0
        hash Hash 18 w 0
    } {
        $t heading $col -text $heading -anchor $anchor
        $t column $col -width [expr {$chars * $char}] -anchor $anchor -stretch $stretch
    }
    grid $t .uv.list.y -sticky news
    grid columnconfigure .uv.list 0 -weight 1
    grid rowconfigure .uv.list 0 -weight 1

    ttk::frame .uv.b -padding 6
    foreach {b label command} {
        view   View               tkuv::view
        export "Export\u2026"     tkuv::export
        edit   "Edit\u2026"       tkuv::edit
        add    "Add\u2026"        tkuv::add
        rename "Rename\u2026"     tkuv::renameFile
        touch  "Touch\u2026"      tkuv::touch
        remove "Remove\u2026"     tkuv::remove
        browse "Open in browser"  tkuv::browse
        download "Download\u2026" tkuv::download
    } {
        ttk::button .uv.b.$b -text $label -command $command
        pack .uv.b.$b -side left -padx {0 4}
    }
    ttk::button .uv.b.close -text Close -command {wm withdraw .uv}
    pack .uv.b.close -side right
    icons::tooltip .uv.b.export "Save the selected files to a folder (or one to a file)"
    icons::tooltip .uv.b.edit "Edit a text file and store it again"
    icons::tooltip .uv.b.add "Add files, or replace ones with the same name"
    icons::tooltip .uv.b.rename "Store the file under another name (with the time now)"
    icons::tooltip .uv.b.touch "Change the time of the selected files"
    ttk::label .uv.status -textvariable tkuv::status -padding {6 2} -anchor w
    pack .uv.top -fill x
    pack .uv.status -side bottom -fill x
    pack .uv.b -side bottom -fill x
    pack .uv.list -fill both -expand 1 -padx 6
    bind $t <<TreeviewSelect>> tkuv::updateButtons
    bind $t <Double-1> {if {[%W identify region %x %y] eq "cell"} tkuv::view}
    bind $t <Return> tkuv::view
    bind $t <Delete> tkuv::remove
    bind $t <Control-a> {%W selection set [%W children {}]}
    bind .uv <F5> tkuv::reload
    popup::attach .uv.list.t tkuv::popupMenu
}

proc tkuv::setRepository {path newRoot} {
    variable repo $path
    variable root $newRoot
    variable remote [fossil::remoteUrl $path]
    wm title .uv "Unversioned files \u2014 [file rootname [file tail $repo]]"
    reload
}

proc tkuv::reload {} {
    variable repo
    variable files
    variable status
    set files {}
    try {
        # (A removed file stays as a row without a hash, to sync the removal.)
        set rows [fossil::sql $repo "SELECT [fossil::outcol name], sz,\
            strftime('%Y-%m-%d %H:%M:%S', mtime, 'unixepoch'), hash, coalesce(length(content), -1)\
            FROM unversioned WHERE hash IS NOT NULL ORDER BY name"]
    } trap {FOSSIL DB} msg {
        set rows {}
        if {![string match "*no such table*" $msg]} { set status "Cannot read the files: $msg" }
    }
    foreach row $rows {
        lassign $row name size date hash stored
        dict set files $name [list $size $date $hash $stored]
    }
    showList
}

proc tkuv::sizeText {size} {
    if {$size < 1024} { return "$size bytes" }
    if {$size < 1048576} { return "[format %.1f [expr {$size / 1024.0}]] KB" }
    format "%.1f MB" [expr {$size / 1048576.0}]
}

# The files that match the filter: a pattern if it has * ? or [, else
# a part of the name (both without case).
proc tkuv::matches {name} {
    variable filter
    set f [string trim $filter]
    if {$f eq ""} { return 1 }
    if {[regexp {[*?\[]} $f]} { return [string match -nocase $f $name] }
    expr {[string first [string tolower $f] [string tolower $name]] >= 0}
}

proc tkuv::showList {} {
    variable files
    variable status
    after cancel tkuv::showList
    set t .uv.list.t
    set keep [$t selection]
    $t delete [$t children {}]
    set n 0
    set total 0
    dict for {name info} $files {
        lassign $info size date hash stored
        if {![matches $name]} continue
        # (Stored: compressed, as "fossil uv list" shows; none if the
        # content is not here.)
        $t insert {} end -id $name -values [list $name [sizeText $size] \
            [expr {$stored >= 0 ? [sizeText $stored] : "not here"}] $date [string range $hash 0 15]]
        incr n
        incr total $size
    }
    set keep [lmap i $keep { if {[$t exists $i]} { set i } else continue }]
    if {![llength $keep]} { set keep [lrange [$t children {}] 0 0] }
    $t selection set $keep
    if {[llength $keep]} { $t see [lindex $keep 0] }
    set all [dict size $files]
    set status [expr {$all == 0 ? "No unversioned files"
        : $n == $all ? "$all files, [sizeText $total]" : "$n of $all files, [sizeText $total]"}]
    if {$all} { append status "; changes here reach the server only with \"fossil uv sync\"" }
    updateButtons
}

proc tkuv::selected {} {
    .uv.list.t selection
}

proc tkuv::updateButtons {} {
    set n [llength [selected]]
    foreach b {view edit rename} { .uv.b.$b state [expr {$n == 1 ? "!disabled" : "disabled"}] }
    foreach b {export touch remove} { .uv.b.$b state [expr {$n ? "!disabled" : "disabled"}] }
    variable remote
    .uv.b.browse state [expr {$n == 1 && $remote ne "" ? "!disabled" : "disabled"}]
    .uv.b.download state !disabled
}

proc tkuv::confirm {message detail} {
    ui::confirm -parent .uv -title "Unversioned files" $message $detail
}

proc tkuv::failed {what out} {
    tk_messageBox -parent .uv -icon error -title "Unversioned files" \
        -message "fossil uv $what failed:" -detail [string trim $out]
}

# Run fossil uv ... for the repository: 1 if it worked (else reported).
proc tkuv::uv {args} {
    variable repo
    lassign [fossil::run uv {*}$args -R $repo] code out
    if {$code} { failed [lindex $args 0] $out }
    expr {!$code}
}

# A name or a file as an argument (not taken for an option).
proc tkuv::arg {name} {
    if {[catch {fossil::arg $name} a]} {
        tk_messageBox -parent .uv -icon error -title "Unversioned files" \
            -message "\"$name\" cannot be passed to fossil."
        return -code return
    }
    return $a
}

# The content of a file, as bytes ("" and a message if it cannot be read).
proc tkuv::content {name} {
    variable repo
    if {[catch {
        set p [open |[list [fossil::exe] uv cat [fossil::arg $name] -R $repo 2>@1] rb]
        set data [read $p]
        close $p
    } msg]} {
        failed cat $msg
        return -code return
    }
    return $data
}

# The content as text, or a message that it is not text.
proc tkuv::textOf {name} {
    set data [content $name]
    if {[string first \0 $data] >= 0} {
        tk_messageBox -parent .uv -icon info -title "Unversioned files" \
            -message "$name is not a text file." -detail "Export it to look at it."
        return -code return
    }
    encoding convertfrom utf-8 $data
}

proc tkuv::view {} {
    set name [lindex [selected] 0]
    if {[llength [selected]] != 1} return
    diffview::show $name [textOf $name]
}

# Export: one file to a file, several to a folder.
proc tkuv::export {} {
    set names [selected]
    if {![llength $names]} return
    if {[llength $names] == 1} {
        set name [lindex $names 0]
        set out [tk_getSaveFile -parent .uv -title "Export $name" -initialfile [file tail $name]]
        if {$out eq ""} return
        uv export [arg $name] [file normalize $out]
        return
    }
    set dir [tk_chooseDirectory -parent .uv -title "Export [llength $names] files to"]
    if {$dir eq ""} return
    set done 0
    foreach name $names {
        # (Names with folders keep them under the folder chosen.)
        if {![uv export [arg $name] [file normalize [file join $dir $name]]]} break
        incr done
    }
    variable status "Exported $done files to $dir"
}

# Store a file under a name (a new one, or a new content for one).
proc tkuv::store {file name {mtime ""}} {
    set opts [expr {$mtime ne "" ? [list --mtime $mtime] : {}}]
    uv add [file normalize $file] --as [arg $name] {*}$opts
}

# A small dialog: a name (and a hint); "" if cancelled.
proc tkuv::askName {title label initial hint} {
    variable dlgName $initial
    variable dlgDone ""
    set w .uv.ask
    destroy $w
    toplevel $w
    wm title $w $title
    wm transient $w .uv
    ttk::frame $w.f -padding 10
    ttk::label $w.f.l -text $label
    ttk::entry $w.f.e -textvariable tkuv::dlgName -width 50
    ttk::label $w.f.hint -text $hint -foreground gray35 -justify left
    ttk::frame $w.f.b
    ttk::button $w.f.b.ok -text OK -default active -command {set tkuv::dlgDone ok}
    ttk::button $w.f.b.cancel -text Cancel -command {set tkuv::dlgDone cancel}
    pack $w.f.b.cancel $w.f.b.ok -side right -padx {4 0}
    grid $w.f.l $w.f.e -sticky ew -pady 2
    grid x $w.f.hint -sticky w
    grid $w.f.b - -sticky e -pady {8 0}
    grid columnconfigure $w.f 1 -weight 1
    pack $w.f -fill both -expand 1
    bind $w <Return> {set tkuv::dlgDone ok}
    bind $w <Escape> {set tkuv::dlgDone cancel}
    wm protocol $w WM_DELETE_WINDOW {set tkuv::dlgDone cancel}
    focus $w.f.e
    $w.f.e selection range 0 end
    vwait tkuv::dlgDone
    destroy $w
    if {$dlgDone ne "ok"} { return "" }
    string trim $dlgName
}

# A name Fossil takes: "" if so, else what is wrong with it.
proc tkuv::badName {name} {
    if {$name eq ""} { return "The name is missing." }
    if {[regexp {\s} $name]} { return "\"$name\": names cannot have spaces." }
    if {[string match /* $name] || [string match */ $name] || [string match *//* $name]
            || "." in [split $name /] || ".." in [split $name /]} {
        return "\"$name\": not a file name (a folder, or a path out of the repository)."
    }
    return ""
}

# A file's name as Fossil takes it (spaces become "_").
proc tkuv::nameOf {file} {
    regsub -all {\s+} [file tail $file] _ name
    return $name
}

# Add files: one under a name chosen, several under their names (in a
# folder chosen).  Replacing a file asks first.
proc tkuv::add {} {
    variable files
    variable dlgDone
    set paths [tk_getOpenFile -parent .uv -title "Add unversioned files" -multiple 1]
    if {![llength $paths]} return
    if {[llength $paths] == 1} {
        set name [askName "Add [file tail [lindex $paths 0]]" "Name:" [nameOf [lindex $paths 0]] \
            "The name in the repository; it can have folders: doc/x.html"]
        if {$name eq ""} return
        set names [list $name]
    } else {
        set folder [askName "Add [llength $paths] files" "Folder:" "" \
            "Optional: a folder for them in the repository (doc, releases/1.0)"]
        if {$dlgDone ne "ok"} return
        set folder [string trim $folder /]
        set names [lmap p $paths { expr {$folder eq "" ? [nameOf $p] : "$folder/[nameOf $p]"} }]
    }
    foreach n $names {
        set problem [badName $n]
        if {$problem ne ""} {
            tk_messageBox -parent .uv -icon info -title "Add" -message $problem
            return
        }
    }
    set replaced [lmap n $names { if {[dict exists $files $n]} { set n } else continue }]
    set detail "Nothing is synced.  Changes to unversioned files cannot be undone."
    if {[llength $replaced]} {
        set detail "Replaces [join $replaced {, }] (the old content is lost).\n\n$detail"
    }
    # The time of the files (--mtime): now, or another (at the next sync
    # the newer one wins).
    set when [askName "Add" "Time (UTC):" "" \
        "Empty: now.  Or YYYY-MM-DD HH:MM:SS, e.g. the time of the release"]
    if {$dlgDone ne "ok"} return
    set when [string trim $when]
    if {$when ne "" && ![regexp {^\d{4}-\d\d-\d\d( \d\d:\d\d(:\d\d)?)?$} $when]} {
        tk_messageBox -parent .uv -icon info -title Add -message "The time: YYYY-MM-DD HH:MM:SS."
        return
    }
    if {![confirm "Add [join $names {, }]?" $detail]} return
    foreach p $paths n $names {
        if {![store $p $n $when]} break
    }
    reload
    .uv.list.t selection set [lmap n $names { if {[.uv.list.t exists $n]} { set n } else continue }]
}

# Rename: the content stored under the new name, the old one removed
# (Fossil has no rename: the time becomes now).
proc tkuv::renameFile {} {
    variable files
    set names [selected]
    if {[llength $names] != 1} return
    set old [lindex $names 0]
    set new [askName "Rename $old" "New name:" $old ""]
    if {$new eq "" || $new eq $old} return
    set problem [badName $new]
    if {$problem ne ""} {
        tk_messageBox -parent .uv -icon info -title "Rename" -message $problem
        return
    }
    set detail "Nothing is synced.  Changes to unversioned files cannot be undone."
    if {[dict exists $files $new]} { set detail "Replaces $new.\n\n$detail" }
    if {![confirm "Rename $old to $new?" $detail]} return
    close [file tempfile tmp]
    try {
        if {[uv export [arg $old] $tmp] && [store $tmp $new]} { uv rm [arg $old] }
    } finally {
        file delete $tmp
    }
    reload
    if {[.uv.list.t exists $new]} { .uv.list.t selection set [list $new] }
}

# Touch: the time of the selected files, now or a date given.
proc tkuv::touch {} {
    set names [selected]
    if {![llength $names]} return
    set when [askName "Touch" "Time (UTC):" [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S" -gmt 1] \
        "YYYY-MM-DD HH:MM:SS; files with a newer time win at the next sync"]
    if {$when eq ""} return
    if {![regexp {^\d{4}-\d\d-\d\d( \d\d:\d\d(:\d\d)?)?$} $when]} {
        tk_messageBox -parent .uv -icon info -title Touch -message "The time: YYYY-MM-DD HH:MM:SS."
        return
    }
    if {![confirm "Set the time of [join $names {, }] to $when?" "Nothing is synced."]} return
    uv touch {*}[lmap n $names { arg $n }] --mtime $when
    reload
}

proc tkuv::remove {} {
    set names [selected]
    if {![llength $names]} return
    if {![confirm "Remove [join $names {, }]?" "The removal reaches the server with the next\
            \"fossil uv sync\" (not done here).  It cannot be undone."]} return
    uv rm {*}[lmap n $names { arg $n }]
    reload
}

# Edit a text file in a window; stored again when saved.
proc tkuv::edit {} {
    variable dlgDone ""
    set names [selected]
    if {[llength $names] != 1} return
    set name [lindex $names 0]
    set text [textOf $name]
    set crlf [expr {[string first "\r\n" $text] >= 0}]
    set w .uv.edit
    destroy $w
    toplevel $w
    wm title $w "Edit $name"
    wm transient $w .uv
    wm geometry $w 800x600
    ttk::frame $w.f -padding 8
    ::text $w.f.t -wrap none -undo 1 -font TkFixedFont \
        -yscrollcommand [list $w.f.y set] -xscrollcommand [list $w.f.x set]
    ttk::scrollbar $w.f.y -command [list $w.f.t yview]
    ttk::scrollbar $w.f.x -orient horizontal -command [list $w.f.t xview]
    ttk::frame $w.f.b
    ttk::label $w.f.b.hint -text "Nothing is synced." -foreground gray35
    ttk::button $w.f.b.save -text Save -command {set tkuv::dlgDone ok}
    ttk::button $w.f.b.cancel -text Cancel -command {set tkuv::dlgDone cancel}
    pack $w.f.b.hint -side left
    pack $w.f.b.cancel $w.f.b.save -side right -padx {4 0}
    grid $w.f.t $w.f.y -sticky news
    grid $w.f.x -sticky ew
    grid $w.f.b - -sticky ew -pady {8 0}
    grid columnconfigure $w.f 0 -weight 1
    grid rowconfigure $w.f 0 -weight 1
    pack $w.f -fill both -expand 1
    $w.f.t insert end [string map {"\r\n" "\n"} $text]
    $w.f.t edit reset
    $w.f.t edit modified 0
    bind $w <Escape> {set tkuv::dlgDone cancel}
    wm protocol $w WM_DELETE_WINDOW {set tkuv::dlgDone cancel}
    focus $w.f.t
    while 1 {
        vwait tkuv::dlgDone
        if {$dlgDone ne "ok"} break
        if {![$w.f.t edit modified]} break
        if {![confirm "Store the new $name?" "The old content is lost (unversioned files\
                have no history).  Nothing is synced."]} continue
        set new [$w.f.t get 1.0 "end - 1 char"]
        if {$crlf} { set new [string map {"\n" "\r\n"} $new] }
        set fh [file tempfile tmp]
        fconfigure $fh -encoding utf-8 -translation lf
        puts -nonewline $fh $new
        close $fh
        try {
            set ok [store $tmp $name]
        } finally {
            file delete $tmp
        }
        if {$ok} break
    }
    destroy $w
    reload
}

# The file on the server (/uv/NAME).
proc tkuv::browse {} {
    variable remote
    set names [selected]
    if {$remote eq "" || [llength $names] != 1} return
    set q ""
    foreach c [split [encoding convertto utf-8 [lindex $names 0]] ""] {
        append q [expr {[regexp {[A-Za-z0-9._~/-]} $c] ? $c : [format %%%02X [scan $c %c]]}]
    }
    fossil::browse $remote/uv/$q
}

# The context menu of a file: the buttons of the window.
proc tkuv::popupMenu {m item} {
    foreach b {view export edit rename touch remove} { popup::button $m .uv.b.$b }
    popup::separator $m
    popup::button $m .uv.b.browse
    popup::separator $m
    popup::copy $m "Copy name" $item
    popup::default $m [.uv.b.view cget -text]
}

# Make the unversioned files those of the server ("fossil uv revert":
# downloads; never uv sync, which would send ours): what it would do
# first (-n), then after a confirmation.
proc tkuv::download {} {
    variable repo
    # (Any remote, a file too: not only a web one as for the browser.)
    lassign [fossil::run remote -R $repo] code url
    set url [string trim $url]
    if {$code || $url in {"" off}} {
        tk_messageBox -parent .uv -icon info -title Download -message "This repository has no remote." \
            -detail "Add one in Repository \u25b8 Remotes."
        return
    }
    ui::busy {
        lassign [fossil::run uv revert -n -v -R $repo] code out
    }
    if {$code} { failed "revert -n" $out; return }
    # The dry run names the files it would download ("UV-PULL: NAME"),
    # not those it would remove: the ones here that the server lacks
    # (Fossil cannot tell which before it runs).
    set pulled [lmap l [split [string map {\r \n} $out] \n] {
        if {![regexp {^UV-PULL:\s*(.*\S)} $l -> name]} continue
        set name }]
    set here [lindex [fossil::sql $repo "SELECT count(*) FROM unversioned WHERE hash IS NOT NULL"] 0 0]
    set detail "The files here become those of the server: the ones below are downloaded\
        (new or changed there), and files that are only here are removed (Fossil's dry run\
        cannot tell which: $here files are here now).  Nothing is sent.  It cannot be undone."
    append detail [expr {[llength $pulled]
        ? "\n\nDownloaded ([llength $pulled]):\n[join [lrange $pulled 0 19] \n][expr {[llength $pulled] > 20 ? "\n\u2026" : ""}]"
        : "\n\nNothing new to download."}]
    if {![confirm "Download the unversioned files of $url?" $detail]} return
    repoops::runShown "Download unversioned files" [list fossil uv revert -R $repo] \
        {::apply {{code out} { if {[winfo exists .uv]} tkuv::reload }}}
}
