# The Files tab of tktaalik: the files at a version, and for the selected
# file its history (the check-ins on all branches that changed it, under
# its earlier names too), the blame (who last changed each line; only with
# a checkout, as "fossil blame" needs one) and the content, at the version
# of the tree or at one chosen in the history.

source [file join [file dirname [file normalize [info script]]] fossil.tcl]

namespace eval tkfiles {
    variable shownVersion ""    ;# the version of the tree shown
    variable shownFilter ""     ;# and its filter
    variable repo ""
    variable root ""
    variable version ""         ;# as typed or chosen
    variable hash ""            ;# the check-in it names
    variable files {}           ;# the files at the version
    variable filter ""
    variable file ""            ;# the selected file
    variable loaded {}          ;# what is shown of the file: history content blame
    variable blamePipe ""
    variable blameRows {}       ;# line -> check-in
    variable names {}           ;# check-in in the history -> the file's name in it
    variable at {}              ;# content and blame of {check-in name}; {}: the tree's
    variable remote ""
    variable ignoreSpace 0      ;# the blame ignores white space (-w)
    variable ignoreEol 0        ;# and at line ends (-Z)
    variable blameOrigin ""     ;# reverse blame: towards this version (-o)
    variable blameLimit none    ;# how far back: none, N versions, Xs (-n)
    variable fileInfo           ;# array: path -> {date size} at the version
    variable treeSort {name 0}  ;# the tree's order: name, age or size; descending
    variable grepPattern ""     ;# Find in history: the regular expression
    variable grepCase 0         ;# -i
    variable grepOnce 0         ;# --once
    variable grepInvert 0       ;# -v
    variable grepPipe ""
    variable status ""
}

proc tkfiles::sql {statement} {
    variable repo
    fossil::sql $repo $statement
}

# The check-in a version names ("checkout": the checkout's), or "".
proc tkfiles::resolve {name} {
    variable repo
    variable root
    if {$name eq "checkout"} {
        if {$root eq ""} { return "" }
        return [lindex [fossil::checkoutSql $root "SELECT uuid FROM blob
            WHERE rid=(SELECT value FROM vvar WHERE name='checkout')"] 0 0]
    }
    # A branch or a tag: its newest check-in; else a hash prefix.
    set rows [sql "SELECT b.uuid FROM tagxref x JOIN blob b ON b.rid=x.rid
        WHERE x.tagtype>0 AND x.tagid=(SELECT tagid FROM tag WHERE tagname=[fossil::sqlstr sym-$name])
        ORDER BY x.mtime DESC LIMIT 1"]
    if {[llength $rows]} { return [lindex $rows 0 0] }
    if {[regexp {^[0-9a-f]{4,64}$} $name]} {
        set rows [sql "SELECT uuid FROM blob WHERE uuid GLOB [fossil::sqlstr $name*]
            AND rid IN (SELECT objid FROM event WHERE type='ci') LIMIT 2"]
        if {[llength $rows] == 1} { return [lindex $rows 0 0] }
    }
    return ""
}

# The versions to choose from.
proc tkfiles::versions {} {
    variable repo
    variable root
    set list {}
    if {$root ne ""} { lappend list checkout }
    lassign [fossil::run branch list -R $repo] code out
    set branches [lmap line [split $out \n] { string trim $line " *#" }]
    foreach b {main trunk} { if {$b in $branches} { lappend list $b } }
    foreach b [lsort -dictionary $branches] { if {$b ni $list && $b ne ""} { lappend list $b } }
    return $list
}

proc tkfiles::showVersion {} {
    variable version
    variable hash
    variable repo
    variable files
    variable status
    set h [resolve [string trim $version]]
    if {$h eq ""} {
        set status "No check-in \"$version\"."
        .files.status configure -foreground red3
        return
    }
    set hash $h
    variable shownVersion [string trim $version]
    # With when each file last changed and its size ("ls --age -v").
    lassign [fossil::run ls --age -v -R $repo -r $hash] code out
    if {$code} {
        set status "fossil ls failed: $out"
        .files.status configure -foreground red3
        return
    }
    .files.status configure -foreground ""
    variable fileInfo
    array unset fileInfo
    set files {}
    foreach line [split [string trim $out] \n] {
        if {![regexp {^(\S+ \S+)\s+(\d+)\s+(.*)$} [string trim $line] -> date size path]} continue
        lappend files $path
        set fileInfo($path) [list [string range $date 0 15] $size]
    }
    fillTree
}

proc tkfiles::fillTree {} {
    variable files
    variable filter
    variable shownFilter
    set shownFilter $filter
    variable file
    variable hash
    variable version
    variable status
    set t .files.main.tree.t
    $t delete [$t children {}]
    set f [string tolower [string trim $filter]]
    set n 0
    foreach path $files {
        if {$f ne "" && [string first $f [string tolower $path]] < 0} continue
        # The directories, made as needed.
        set parent {}
        set dir ""
        foreach part [lrange [split $path /] 0 end-1] {
            set dir [expr {$dir eq "" ? $part : "$dir/$part"}]
            if {![$t exists d:$dir]} {
                $t insert $parent end -id d:$dir -text $part -open [expr {$f ne ""}] -tags dir
            }
            set parent d:$dir
        }
        variable fileInfo
        lassign [expr {[info exists fileInfo($path)] ? $fileInfo($path) : {{} {}}}] date size
        $t insert $parent end -id f:$path -text [file tail $path] -values [list $date [sizeText $size]]
        # A directory: its newest change.
        for {set p $parent} {$p ne ""} {set p [$t parent $p]} {
            if {[string compare $date [$t set $p age]] > 0} { $t set $p age $date }
        }
        incr n
    }
    sortTree
    set status "$n file[expr {$n == 1 ? "" : "s"}] at $version ([string range $hash 0 9])"
    if {$file ne "" && [$t exists f:$file]} {
        $t see f:$file
        $t selection set f:$file
    }
}

# A size in bytes, short: 512, 3.4 KB, 1.2 MB.
proc tkfiles::sizeText {size} {
    if {$size eq ""} { return "" }
    if {$size < 1024} { return $size }
    if {$size < 1048576} { return [format "%.1f KB" [expr {$size / 1024.0}]] }
    format "%.1f MB" [expr {$size / 1048576.0}]
}

# Sort the tree by a heading: again, the other way.  Directories first.
proc tkfiles::sortBy {key} {
    variable treeSort
    lassign $treeSort k desc
    # (Dates and sizes: the newest, the biggest first.)
    set treeSort [expr {$k eq $key ? [list $key [expr {!$desc}]] : [list $key [expr {$key ne "name"}]]}]
    sortTree
}

proc tkfiles::sortTree {{node {}}} {
    variable treeSort
    variable fileInfo
    lassign $treeSort key desc
    set t .files.main.tree.t
    set keyed {}
    foreach c [$t children $node] {
        set dir [string match d:* $c]
        set v [switch -- $key {
            name { string tolower [$t item $c -text] }
            age  { $t set $c age }
            size {
                expr {!$dir && [info exists fileInfo([string range $c 2 end])]
                    ? [lindex $fileInfo([string range $c 2 end]) 1] : -1}
            }
        }]
        lappend keyed [list [expr {!$dir}] $v $c]
        if {$dir} { sortTree $c }
    }
    set how [expr {$key eq "size" ? "-integer" : "-dictionary"}]
    set sorted [lsort -index 1 $how {*}[expr {$desc ? "-decreasing" : ""}] $keyed]
    set sorted [lsort -index 0 -integer $sorted]
    $t children $node [lmap k $sorted { lindex $k 2 }]
    if {$node eq ""} {
        foreach {h col label} {#0 name File age age "Last changed" size size Size} {
            $t heading $h -text "$label[expr {$col eq $key ? [expr {$desc ? " \u25bc" : " \u25b2"}] : ""}]"
        }
    }
}

# ----------------------------------------------------------------- a file

proc tkfiles::selectFile {} {
    variable file
    variable loaded
    set id [lindex [.files.main.tree.t selection] 0]
    if {![string match f:* $id]} return
    set path [string range $id 2 end]
    if {$path eq $file && [llength $loaded]} return
    # (Another file: at the version of the tree.)
    variable at
    if {$path ne $file} { set at {} }
    set file $path
    set loaded {}
    showTitle
    loadShown
}

proc tkfiles::showTitle {} {
    variable file
    variable at
    set text $file
    if {[llength $at]} {
        lassign $at uuid name
        set text "$name at [string range $uuid 0 9]"
    }
    .files.main.right.title configure -text $text
}

# The file at a version from the history: its content or blame.
proc tkfiles::showAt {uuid tab} {
    variable names
    variable at
    variable loaded
    if {$uuid eq ""} return
    tktaalik::navigate
    set at [list $uuid [dict get $names $uuid]]
    set loaded [lsearch -all -inline -not -regexp $loaded {^(content|blame)$}]
    showTitle
    .files.main.right.nb select .files.main.right.nb.$tab
    loadShown
}

# The history of the selected file (the File menu, the context menu).
proc tkfiles::showHistory {} {
    variable file
    variable at
    variable loaded
    if {$file eq ""} return
    tktaalik::navigate
    if {[llength $at]} {
        set at {}
        set loaded [lsearch -all -inline -not -regexp $loaded {^(content|blame)$}]
        showTitle
    }
    .files.main.right.nb select .files.main.right.nb.history
    loadShown
}

# The Find in history tab of the selected file, its field focused.
proc tkfiles::showGrep {} {
    variable file
    if {$file eq ""} return
    tktaalik::navigate
    .files.main.right.nb select .files.main.right.nb.grep
    focus .files.main.right.nb.grep.top.e
}

# Load what the shown tab needs.
proc tkfiles::loadShown {} {
    variable file
    variable loaded
    if {$file eq ""} return
    set tab [winfo name [.files.main.right.nb select]]
    if {$tab in $loaded} return
    lappend loaded $tab
    switch -- $tab {
        history { loadHistory }
        content { loadContent }
        blame   { loadBlame }
        grep    { clearGrep }
    }
}

# The check-ins that changed the file, and under an earlier name, those
# before it was renamed (back to where it was added).
proc tkfiles::loadHistory {} {
    variable file
    variable names {}
    variable fileHashes {}
    set h .files.main.right.nb.history.t
    $h delete [$h children {}]
    set fnid [lindex [sql "SELECT fnid FROM filename WHERE name=[fossil::sqlstr $file]"] 0 0]
    set queue [list [list $fnid ""]]
    set seen {}
    set rows {}
    while {[llength $queue]} {
        set queue [lassign $queue next]
        lassign $next fnid before
        if {$fnid eq "" || [dict exists $seen $fnid]} continue
        dict set seen $fnid 1
        foreach row [sql "SELECT e.mtime, strftime('%Y-%m-%d %H:%M', e.mtime), b.uuid,
            [fossil::outcol coalesce(e.euser,e.user)],
            coalesce([fossil::outcol "(SELECT value FROM tagxref WHERE rid=m.mid AND tagtype>0
                AND tagid=(SELECT tagid FROM tag WHERE tagname='branch'))"],''),
            CASE WHEN m.pid=0 THEN 'added' WHEN m.fid=0 THEN 'deleted'
                WHEN m.pfnid>0 AND m.pfnid<>m.fnid THEN 'renamed' ELSE 'changed' END,
            [fossil::outcol coalesce(e.ecomment,e.comment)],
            [fossil::outcol "(SELECT name FROM filename WHERE fnid=m.fnid)"],
            max(CASE WHEN m.pfnid>0 AND m.pfnid<>m.fnid THEN m.pfnid ELSE 0 END),
            coalesce((SELECT uuid FROM blob WHERE rid=m.fid),'')
            FROM mlink m JOIN event e ON e.objid=m.mid JOIN blob b ON b.rid=m.mid
            WHERE m.fnid=$fnid AND NOT m.isaux
            [expr {$before eq "" ? "" : "AND e.mtime<$before"}]
            GROUP BY m.mid"] {
            lassign $row mtime - uuid - - - - - pfnid
            if {[dict exists $names $uuid]} continue
            dict set names $uuid [lindex $row 7]
            lappend rows $row
            # Renamed here: the history under the old name, before this.
            if {$pfnid} { lappend queue [list $pfnid $mtime] }
        }
    }
    foreach row [lsort -real -decreasing -index 0 $rows] {
        lassign $row - date uuid user branch how comment name - fhash
        $h insert {} end -id $uuid -values [list $date [string range $uuid 0 9] $user $branch $how \
            $name [string map {\n " "} $comment] [string range $fhash 0 9]]
        variable fileHashes
        dict set fileHashes $uuid $fhash
    }
    # The name column only if it changed.  (The file's own hash, as
    # "fossil finfo -i": after the check-in.)
    set cols {date hash fhash user branch how comment}
    if {[llength [lsort -unique [dict values $names]]] > 1} { set cols {date hash fhash user branch how name comment} }
    $h configure -displaycolumns $cols
    .files.main.right.nb tab .files.main.right.nb.history -text "History ([llength $rows])"
}

# --------------------------------------------------------- find in history

# Find in history ("fossil grep"): the versions of the file (under its
# earlier names too) whose text matches a regular expression, each with
# the lines that do; in the background.
proc tkfiles::clearGrep {} {
    variable grepPipe
    if {$grepPipe ne ""} { catch {close $grepPipe}; set grepPipe "" }
    set g .files.main.right.nb.grep
    $g.t delete [$g.t children {}]
    $g.status configure -text "A regular expression (POSIX extended); Return to search."
}

proc tkfiles::grep {} {
    variable repo
    variable file
    variable names
    variable loaded
    variable grepPattern
    variable grepCase
    variable grepOnce
    variable grepInvert
    variable grepPipe
    if {$file eq ""} return
    clearGrep
    if {$grepPattern eq ""} return
    # (Its names: from the history.)
    if {"history" ni $loaded} {
        lappend loaded history
        loadHistory
    }
    set all [lsort -unique [concat [list $file] [dict values $names]]]
    set opts {}
    if {$grepCase} { lappend opts -i }
    if {$grepOnce} { lappend opts --once }
    if {$grepInvert} { lappend opts -v }
    # (A first "<", ">", "|" or "2>" would be a redirection to exec: the
    # same expression with it in brackets.)
    set pattern $grepPattern
    if {[regexp {^([<>|]|2>)} $pattern -> c]} {
        set pattern "\[[string index $c 0]\][string range $pattern 1 end]"
    }
    set g .files.main.right.nb.grep
    if {[catch {
        set grepPipe [open |[list fossil grep -R $repo {*}$opts -- $pattern \
            {*}[lmap n $all { fossil::arg $n }] << "" 2>@1] r]
    } msg]} {
        $g.status configure -text "Cannot search: $msg"
        return
    }
    $g.status configure -text "Searching\u2026"
    fconfigure $grepPipe -blocking 0 -encoding utf-8
    fileevent $grepPipe readable [list tkfiles::readGrep $grepPipe $file ""]
}

proc tkfiles::readGrep {chan path text} {
    variable grepPipe
    variable file
    variable names
    variable grepInvert
    if {$chan ne $grepPipe || $path ne $file} {
        catch {close $chan}
        return
    }
    append text [::read $chan]
    if {![eof $chan]} {
        fileevent $chan readable [list tkfiles::readGrep $chan $path $text]
        return
    }
    catch {close $chan}
    set grepPipe ""
    set g .files.main.right.nb.grep
    set version ""
    set nv 0
    set nl 0
    foreach line [split [string trimright $text \n] \n] {
        if {[regexp {^== (\S+ \S+) (.*) ([0-9a-f]+) checkin ([0-9a-f]+)$} $line -> date name fh ci]} {
            # The full hash of the check-in (of the history).
            set full $ci
            foreach u [dict keys $names] { if {[string match $ci* $u]} { set full $u; break } }
            set version v:$full
            if {![$g.t exists $version]} {
                $g.t insert {} end -id $version -open 1 -values [list $date [string range $full 0 9] $name ""]
                incr nv
            }
        } elseif {$version ne "" && [regexp {^(\d+):(.*)$} $line -> n code]} {
            $g.t insert $version end -values [list "" "" "line $n" [string trim $code]] -tags line
            incr nl
        } elseif {[string trim $line] ne ""} {
            $g.t insert {} end -values [list "" "" "" $line] -tags error
        }
    }
    $g.status configure -text [expr {$grepInvert
        ? "$nv version[expr {$nv == 1 ? "" : "s"}] without it"
        : "$nl line[expr {$nl == 1 ? "" : "s"}] in $nv version[expr {$nv == 1 ? "" : "s"}]"}]
}

# Double-click: the version's content (at the line).
proc tkfiles::grepOpen {item} {
    set g .files.main.right.nb.grep.t
    if {$item eq ""} return
    set line ""
    if {[$g tag has line $item]} {
        regexp {\d+} [$g set $item name] line
        set item [$g parent $item]
    }
    if {![string match v:* $item]} return
    showAt [string range $item 2 end] content
    if {$line ne ""} {
        set c .files.main.right.nb.content.t
        $c see $line.0
        $c tag remove sel 1.0 end
        $c tag add sel $line.0 "$line.0 lineend"
    }
}

# --------------------------------------------------------------- archive

# The version of the tree as an archive ("fossil zip", "tarball", "sqlar"):
# its format, the folder in it, which files; then where.  Only the file
# chosen is written.
proc tkfiles::archive {} {
    variable repo
    variable hash
    variable version
    variable arch
    if {$hash eq ""} return
    set project [lindex [sql "SELECT coalesce((SELECT value FROM config WHERE name='project-name'),'')"] 0 0]
    regsub -all {[^A-Za-z0-9._-]+} [string tolower $project] - project
    if {$project eq ""} { set project [file rootname [file tail $repo]] }
    regsub -all {[^A-Za-z0-9._-]+} [string trim $version] - v
    array set arch [list format zip name $project-$v include "" exclude "" done ""]
    set w .files.archive
    destroy $w
    toplevel $w
    wm title $w "Save [string trim $version] ([string range $hash 0 9]) as an archive"
    wm transient $w .
    ttk::frame $w.f -padding 10
    ttk::label $w.f.lf -text "Format:"
    ttk::frame $w.f.fmt
    foreach {f label} {zip "ZIP (.zip)" tarball "Tarball (.tar.gz)" sqlar "SQLite archive (.sqlar)"} {
        ttk::radiobutton $w.f.fmt.$f -text $label -value $f -variable tkfiles::arch(format)
        pack $w.f.fmt.$f -side left -padx {0 8}
    }
    ttk::label $w.f.ln -text "Top folder:"
    ttk::entry $w.f.name -textvariable tkfiles::arch(name) -width 40
    ttk::label $w.f.li -text "Only files:"
    ttk::entry $w.f.include -textvariable tkfiles::arch(include) -width 40
    ttk::label $w.f.lx -text "Without files:"
    ttk::entry $w.f.exclude -textvariable tkfiles::arch(exclude) -width 40
    ttk::label $w.f.hint -foreground gray35 \
        -text "Patterns separated by commas, like doc/*,*.md; empty: all files."
    ttk::frame $w.f.b
    ttk::button $w.f.b.ok -text "Save\u2026" -default active -command {set tkfiles::arch(done) ok}
    ttk::button $w.f.b.cancel -text Cancel -command {set tkfiles::arch(done) cancel}
    pack $w.f.b.cancel $w.f.b.ok -side right -padx {4 0}
    grid $w.f.lf $w.f.fmt -sticky w -pady 2
    grid $w.f.ln $w.f.name -sticky ew -pady 2
    grid $w.f.li $w.f.include -sticky ew -pady 2
    grid $w.f.lx $w.f.exclude -sticky ew -pady 2
    grid x $w.f.hint -sticky w
    grid $w.f.b - -sticky e -pady {8 0}
    grid columnconfigure $w.f 1 -weight 1
    pack $w.f -fill both -expand 1
    bind $w <Return> {set tkfiles::arch(done) ok}
    bind $w <Escape> {set tkfiles::arch(done) cancel}
    wm protocol $w WM_DELETE_WINDOW {set tkfiles::arch(done) cancel}
    focus $w.f.name
    vwait tkfiles::arch(done)
    destroy $w
    if {$arch(done) ne "ok"} return
    set ext [dict get {zip .zip tarball .tar.gz sqlar .sqlar} $arch(format)]
    set name [string trim $arch(name)]
    set path [tk_getSaveFile -parent . -title "Save the archive" -initialfile $name$ext]
    if {$path eq ""} return
    saveArchive $arch(format) $path $name [string trim $arch(include)] [string trim $arch(exclude)]
}

# Write the archive (also for the tests): 1 if done.
proc tkfiles::saveArchive {format path name include exclude} {
    variable repo
    variable hash
    variable status
    set opts {}
    # (As --option=VALUE: fossil.exe on Windows would expand a pattern of
    # its own word into the files it matches.)
    if {$name ne ""} { lappend opts --name=$name }
    if {$include ne ""} { lappend opts --include=$include }
    if {$exclude ne ""} { lappend opts --exclude=$exclude }
    if {[catch {foreach v [list $name $include $exclude] { if {$v ne ""} { fossil::arg $v } }} msg]} {
        tk_messageBox -icon info -title Archive -message $msg
        return 0
    }
    . configure -cursor watch
    update idletasks
    lassign [fossil::run $format -R $repo $hash [file normalize $path] {*}$opts] code out
    . configure -cursor ""
    if {$code} {
        tk_messageBox -icon error -title Archive -message "fossil $format failed:" -detail $out
        return 0
    }
    set status "Saved [file tail $path] ([sizeText [file size $path]])"
    return 1
}

# ------------------------------------------------------- a local file

# Find a local file in history ("fossil whatis -f"): the check-ins whose
# file has exactly its content, in a window; double-click one to see it.
proc tkfiles::findLocal {{path ""}} {
    variable repo
    if {$path eq ""} {
        set path [tk_getOpenFile -parent . -title "Find a local file in history"]
        if {$path eq ""} return
    }
    set w .files.found
    if {![winfo exists $w]} {
        toplevel $w
        wm geometry $w 900x360
        wm protocol $w WM_DELETE_WINDOW [list destroy $w]
        bind $w <Escape> [list destroy $w]
        ttk::label $w.l -padding {8 6} -anchor w
        ttk::frame $w.f
        ttk::treeview $w.f.t -columns {date hash user name comment} -show headings \
            -selectmode browse -yscrollcommand [list $w.f.y set]
        ttk::scrollbar $w.f.y -command [list $w.f.t yview]
        set char [font measure TkDefaultFont 0]
        foreach {col heading width} {date Date 18 hash Check-in 11 user User 13 name File 30
                comment Comment 50} {
            $w.f.t heading $col -text $heading -anchor w
            $w.f.t column $col -width [expr {$width * $char}] -stretch [expr {$col eq "comment"}]
        }
        grid $w.f.t $w.f.y -sticky news
        grid columnconfigure $w.f 0 -weight 1
        grid rowconfigure $w.f 0 -weight 1
        ttk::frame $w.b -padding 6
        ttk::button $w.b.open -text "Show it" -command {tkfiles::openFound [lindex [.files.found.f.t selection] 0]}
        ttk::button $w.b.close -text Close -command [list destroy $w]
        pack $w.b.close $w.b.open -side right -padx {4 0}
        pack $w.l -fill x
        pack $w.b -side bottom -fill x
        pack $w.f -fill both -expand 1 -padx 6
        bind $w.f.t <Double-1> {tkfiles::openFound [.files.found.f.t identify item %x %y]}
        bind $w.f.t <Return> {tkfiles::openFound [lindex [.files.found.f.t selection] 0]}
    }
    wm title $w "Found in history: [file tail $path]"
    raise $w
    set t $w.f.t
    $t delete [$t children {}]
    if {[catch {fossil::arg [file normalize $path]} msg]} {
        $w.l configure -text $msg
        return
    }
    lassign [fossil::run whatis -f [file normalize $path] -R $repo] code out
    set hash ""
    set name ""
    set last ""
    foreach line [split $out \n] {
        if {[regexp {^(artifact|unknown):\s+([0-9a-f]+)} $line -> how hash]} {
            if {$how eq "unknown"} { set hash "" }
        } elseif {[regexp {^file:\s+(.*)$} $line -> name]} {
        } elseif {[regexp {^\s+part of \[([0-9a-f]+)\](?: on branch \S+)? by (\S+) on (.*)$} $line -> ci user date]} {
            set full [lindex [sql "SELECT uuid FROM blob WHERE uuid GLOB [fossil::sqlstr $ci*] LIMIT 1"] 0 0]
            # (The same content twice in a check-in: the first name.)
            if {$full eq "" || [$t exists $full]} { set last ""; continue }
            set last [$t insert {} end -id $full -values [list $date [string range $full 0 9] $user $name ""]]
        } elseif {$last ne "" && [regexp {^\s+(\S.*)$} $line -> comment] && [$t set $last comment] eq ""} {
            $t set $last comment $comment
        }
    }
    set n [llength [$t children {}]]
    $w.l configure -text [expr {$code ? "fossil whatis failed: [string trim $out]"
        : $hash eq "" ? "[file tail $path]: this content is in no version of the repository."
        : "[file tail $path] ([string range $hash 0 9]): in $n check-in[expr {$n == 1 ? "" : "s"}].\
            Double-click one to see the file there."}]
    if {$n} { $t selection set [lindex [$t children {}] 0]; focus $t }
}

# A check-in found: the Files tab at it, the file's content.
proc tkfiles::openFound {ci} {
    set t .files.found.f.t
    if {$ci eq "" || ![$t exists $ci]} return
    tktaalik::navigate
    tktaalik::show files
    goTo [list $ci "" [$t set $ci name] .files.main.right.nb.content ""]
}

# The version and the name of the file for the content and the blame.
proc tkfiles::target {} {
    variable hash
    variable file
    variable at
    expr {[llength $at] ? $at : [list $hash $file]}
}

proc tkfiles::loadContent {} {
    variable repo
    set c .files.main.right.nb.content.t
    $c configure -state normal
    $c delete 1.0 end
    lassign [target] version name
    lassign [fossil::run cat -R $repo -r $version [fossil::arg $name]] code out
    if {[string first \0 $out] >= 0} {
        $c insert end "(not a text file)"
    } else {
        set n 0
        foreach line [split $out \n] {
            $c insert end [format "%6d  " [incr n]] lineno $line\n
        }
    }
    $c configure -state disabled
}

# The blame, in the background (it takes a while for a long history).
proc tkfiles::loadBlame {} {
    variable root
    variable file
    variable blamePipe
    variable blameRows {}
    set b .files.main.right.nb.blame.t
    $b configure -state normal
    $b delete 1.0 end
    if {$root eq ""} {
        $b insert end "Blame needs a checkout: \"fossil blame\" works only in one."
        $b configure -state disabled
        return
    }
    if {$blamePipe ne ""} { catch {close $blamePipe} }
    $b insert end "Finding who changed each line\u2026"
    $b configure -state disabled
    lassign [target] version name
    fossil::inDir $root {
        set blamePipe [open |[list fossil blame {*}[blameOptions] -r $version [fossil::arg $name] \
            << "" 2>@1] r]
    }
    fconfigure $blamePipe -blocking 0 -encoding utf-8
    fileevent $blamePipe readable [list tkfiles::readBlame $blamePipe $file ""]
}

# The options of the blame: white space (-w, -Z), reverse towards a version
# (-o), how far back (-n: versions or seconds).
proc tkfiles::blameOptions {} {
    variable ignoreSpace
    variable ignoreEol
    variable blameOrigin
    variable blameLimit
    set opts {}
    if {$ignoreSpace} { lappend opts -w }
    if {$ignoreEol} { lappend opts -Z }
    set origin [string trim $blameOrigin]
    if {$origin ne "" && ![catch {fossil::arg $origin}]} {
        set h [resolve $origin]
        lappend opts -o [expr {$h ne "" ? $h : $origin}]
    }
    set limit [string trim $blameLimit]
    if {[regexp {^\d+s?$} $limit]} { lappend opts -n $limit }
    return $opts
}

proc tkfiles::reblame {} {
    variable loaded
    set loaded [lsearch -all -inline -not -exact $loaded blame]
    loadShown
}

proc tkfiles::readBlame {chan path text} {
    variable blamePipe
    variable file
    variable blameRows
    if {$chan ne $blamePipe || $path ne $file} {
        catch {close $chan}
        return
    }
    append text [read $chan]
    if {![eof $chan]} {
        fileevent $chan readable [list tkfiles::readBlame $chan $path $text]
        return
    }
    catch {close $chan}
    set blamePipe ""
    set b .files.main.right.nb.blame.t
    $b configure -state normal
    $b delete 1.0 end
    # Lines of the same check-in in the same colour, alternating.  Lines
    # not attributed have the width of the annotation in blanks: in a
    # reverse blame those not changed up to the version, else those older
    # than the limit.
    variable blameOrigin
    set none [expr {[string trim $blameOrigin] ne "" ? "unchanged" : "older"}]
    set width 37
    foreach line [split $text \n] {
        if {[regexp {^([0-9a-f]+ \S+\s+[^:]*: ?)} $line prefix]} { set width [string length $prefix]; break }
    }
    set last ""
    set shade 0
    set n 0
    foreach line [split [string trimright $text \n] \n] {
        if {![regexp {^([0-9a-f]+) (\S+)\s+([^:]*): ?(.*)$} $line -> h date user code]} {
            if {[string length $line] >= $width && [string trim [string range $line 0 $width-1]] eq ""} {
                incr n
                lappend blameRows ""
                $b insert end [format "%-10s %-10s %-12s %5d " "" "" $none $n] [list meta none] \
                    [string range $line $width end]\n ""
            } else {
                $b insert end $line\n
            }
            continue
        }
        if {$h ne $last} { set shade [expr {!$shade}]; set last $h }
        incr n
        lappend blameRows $h
        $b insert end [format "%-10s %s %-12s %5d " $h $date [string range $user 0 11] $n] \
            [list meta shade$shade] $code\n shade$shade
    }
    $b configure -state disabled
}

# Double-click: the diff of the check-in for this file.
proc tkfiles::diffCheckin {uuid} {
    variable repo
    variable file
    variable names
    if {$uuid eq "" || $file eq ""} return
    set name [expr {[dict exists $names $uuid] ? [dict get $names $uuid] : $file}]
    diffview::run "$name in [string range $uuid 0 9]" -mode sidebyside -- \
        -R $repo --checkin $uuid [fossil::arg $name]
}

# The context menu of a version in the history.
proc tkfiles::historyMenu {x y X Y} {
    variable names
    variable remote
    set h .files.main.right.nb.history.t
    set uuid [$h identify item $x $y]
    if {$uuid eq ""} return
    $h selection set [list $uuid]
    set name [dict get $names $uuid]
    set there [expr {[$h set $uuid how] eq "deleted" ? "disabled" : "normal"}]
    set m .files.histctx
    $m delete 0 end
    $m add command -label "Diff against the previous version" -command [list tkfiles::diffCheckin $uuid]
    $m add command -label "Show the check-in in Timeline" -command [list goto::checkin $uuid]
    $m add command -label "Content of this version" -state $there \
        -command [list tkfiles::showAt $uuid content]
    $m add command -label "Blame of this version" -state $there \
        -command [list tkfiles::showAt $uuid blame]
    $m add command -label "Save this version\u2026" -state $there \
        -command [list tkfiles::saveVersion $uuid]
    $m add command -label "Open in browser" -state [expr {$remote eq "" ? "disabled" : "normal"}] \
        -command [list fossil::browse $remote/file?name=[fossil::urlquery $name /]&ci=$uuid]
    $m add separator
    $m add command -label "Copy check-in" -command [list ui::copy $uuid]
    variable fileHashes
    set fh [expr {[dict exists $fileHashes $uuid] ? [dict get $fileHashes $uuid] : ""}]
    $m add command -label "Copy file hash" -command [list ui::copy $fh] \
        -state [expr {$fh eq "" ? "disabled" : "normal"}]
    tk_popup $m $X $Y
}

# The context menu of a file in the tree.
proc tkfiles::treeMenu {x y X Y} {
    variable remote
    variable file
    set t .files.main.tree.t
    set id [$t identify item $x $y]
    if {![string match f:* $id]} return
    $t selection set [list $id]
    selectFile
    set m .files.treectx
    $m delete 0 end
    $m add command -label "History of [file tail $file]" -command tkfiles::showHistory
    $m add command -label "Find in its history\u2026" -command tkfiles::showGrep
    foreach {label tab} {Content content Blame blame} {
        $m add command -label $label -command [list apply {{tab} {
            tktaalik::navigate
            .files.main.right.nb select .files.main.right.nb.$tab
        }} $tab]
    }
    $m add command -label "Open in browser" -state [expr {$remote eq "" ? "disabled" : "normal"}] \
        -command [list fossil::browse $remote/finfo?name=[fossil::urlquery $file /]]
    $m add separator
    $m add command -label "Copy path" -command [list ui::copy $file]
    tk_popup $m $X $Y
}

# Save the file as it was in a check-in ("fossil cat -o").
proc tkfiles::saveVersion {uuid} {
    variable repo
    variable names
    set name [dict get $names $uuid]
    set path [tk_getSaveFile -parent . -title "Save $name at [string range $uuid 0 9]" \
        -initialfile [file tail $name]]
    if {$path eq ""} return
    lassign [fossil::run cat -R $repo -r $uuid -o [file normalize $path] [fossil::arg $name]] code out
    if {$code} {
        tk_messageBox -icon error -title Files -message "fossil cat failed:" -detail $out
    }
}

# The context menu of the content or the blame: the lines selected (or
# the one clicked), copied, or a link to them on the remote's web pages
# (as "fossil remote hyperlink FILE A B": the file's artifact, ?ln=A,B).
proc tkfiles::linesMenu {tab x y X Y} {
    variable remote
    variable blameRows
    set w .files.main.right.nb.$tab.t
    if {[$w tag ranges sel] ne ""} {
        set a [expr {int([$w index sel.first])}]
        set b [expr {int([$w index "sel.last - 1 char"])}]
    } else {
        set a [expr {int([$w index @$x,$y])}]
        set b $a
    }
    # (The prefixes: the line number; the annotation of the blame.)
    set skip [expr {$tab eq "content" ? 8 : 41}]
    set lines [lmap l [split [$w get $a.0 "$b.0 lineend"] \n] { string range $l $skip end }]
    set what [expr {$a == $b ? "line $a" : "lines $a\u2013$b"}]
    set m $w.ctx
    destroy $m
    menu $m -tearoff 0
    $m add command -label "Copy $what" -command [list ui::copy [join $lines \n]]
    set url [linesUrl $a $b]
    $m add command -label "Copy link to $what" -command [list ui::copy $url] \
        -state [expr {$url eq "" ? "disabled" : "normal"}]
    if {$tab eq "blame"} {
        set h [lindex $blameRows [expr {$a - 1}]]
        $m add separator
        $m add command -label "Diff of the check-in of line $a" -command [list tkfiles::blameClick $x $y] \
            -state [expr {$h eq "" ? "disabled" : "normal"}]
    }
    tk_popup $m $X $Y
}

# The URL of lines A to B of the file shown, on the remote ("" without one).
proc tkfiles::linesUrl {a b} {
    variable remote
    if {$remote eq ""} { return "" }
    lassign [target] version name
    set fh [lindex [sql "SELECT uuid FROM files_of_checkin([fossil::sqlstr $version])\
        WHERE filename=[fossil::sqlstr $name]"] 0 0]
    if {$fh eq ""} { return "" }
    return $remote/info/[string range $fh 0 9]?ln=[expr {$a == $b ? $a : "$a,$b"}]
}

proc tkfiles::blameClick {x y} {
    variable blameRows
    variable loaded
    if {"history" ni $loaded} {
        lappend loaded history
        loadHistory
    }
    set b .files.main.right.nb.blame.t
    set line [lindex [split [$b index @$x,$y] .] 0]
    set h [lindex $blameRows [expr {$line - 1}]]
    if {$h eq ""} return
    # The full hash, and the row in the history.
    set full [lindex [sql "SELECT uuid FROM blob WHERE uuid GLOB [fossil::sqlstr $h*] LIMIT 1"] 0 0]
    set hist .files.main.right.nb.history.t
    if {[$hist exists $full]} {
        $hist selection set $full
        $hist see $full
    }
    diffCheckin $full
}

# ----------------------------------------------------------------- window

proc tkfiles::build {} {
    menu .files.menu
    .files.menu add cascade -label File -underline 0 -menu [menu .files.menu.file]
    tktaalik::fileMenu .files.menu.file
    .files.menu.file add command -label "History of the file" -underline 0 -command tkfiles::showHistory
    .files.menu.file add command -label "Find in the file's history\u2026" -underline 0 -command tkfiles::showGrep
    .files.menu.file add command -label "Find a local file in history\u2026" -underline 5 \
        -command tkfiles::findLocal
    .files.menu.file add command -label "Save this version as an archive\u2026" -underline 0 \
        -command tkfiles::archive
    .files.menu.file add command -label Refresh -underline 0 -accelerator F5 -command tkfiles::refresh
    tktaalik::quitEntry .files.menu.file
    menu .files.histctx -tearoff 0
    menu .files.treectx -tearoff 0

    ttk::frame .files.top -padding {6 6 6 2}
    ttk::label .files.top.vl -text "Version:"
    ttk::combobox .files.top.version -textvariable tkfiles::version -width 28
    ttk::label .files.top.fl -text "Find file:"
    ttk::entry .files.top.filter -textvariable tkfiles::filter -width 30
    pack .files.top.vl .files.top.version -side left -padx {0 4}
    pack .files.top.filter .files.top.fl -side right -padx {4 0}
    bind .files.top.version <Return> {tktaalik::navigate; tkfiles::showVersion}
    bind .files.top.version <<ComboboxSelected>> {tktaalik::navigate; tkfiles::showVersion}
    trace add variable ::tkfiles::filter write {::apply {args {
        tktaalik::typing .files.top.filter
        after cancel tkfiles::fillTree
        after 200 tkfiles::fillTree
    }}}

    ttk::panedwindow .files.main -orient horizontal
    ttk::frame .files.main.tree
    ttk::treeview .files.main.tree.t -show {tree headings} -columns {age size} -selectmode browse \
        -yscrollcommand {.files.main.tree.y set}
    set char [font measure TkDefaultFont 0]
    .files.main.tree.t column #0 -width [expr {28 * $char}] -stretch 1
    .files.main.tree.t column age -width [expr {17 * $char}] -stretch 0
    .files.main.tree.t column size -width [expr {9 * $char}] -stretch 0 -anchor e
    foreach {h key label} {#0 name File age age "Last changed" size size Size} {
        .files.main.tree.t heading $h -text $label -anchor [expr {$key eq "size" ? "e" : "w"}] \
            -command [list tkfiles::sortBy $key]
    }
    ttk::scrollbar .files.main.tree.y -command {.files.main.tree.t yview}
    grid .files.main.tree.t .files.main.tree.y -sticky news
    grid columnconfigure .files.main.tree 0 -weight 1
    grid rowconfigure .files.main.tree 0 -weight 1
    .files.main.tree.t tag configure dir -foreground gray30

    ttk::frame .files.main.right
    ttk::label .files.main.right.title -font TkHeadingFont -padding {6 4}
    ttk::notebook .files.main.right.nb
    # History.
    set f .files.main.right.nb.history
    ttk::frame $f
    ttk::treeview $f.t -columns {date hash user branch how name comment fhash} -show headings \
        -selectmode browse -yscrollcommand [list $f.y set]
    ttk::scrollbar $f.y -command [list $f.t yview]
    set char [font measure TkDefaultFont 0]
    foreach {col heading width} {date Date 16 hash Check-in 11 fhash File 11 user User 13
            branch Branch 18 how "" 10 name Name 30 comment Comment 50} {
        $f.t heading $col -text $heading -anchor w
        $f.t column $col -width [expr {$width * $char}] -stretch [expr {$col eq "comment"}]
    }
    grid $f.t $f.y -sticky news
    grid columnconfigure $f 0 -weight 1
    grid rowconfigure $f 0 -weight 1
    bind $f.t <Double-1> {tkfiles::diffCheckin [.files.main.right.nb.history.t identify item %x %y]}
    bind $f.t <Return> {tkfiles::diffCheckin [lindex [.files.main.right.nb.history.t selection] 0]}
    bind $f.t <ButtonPress-3> {tkfiles::historyMenu %x %y %X %Y}
    $f.t configure -displaycolumns {date hash fhash user branch how comment}
    # Blame and content.
    foreach tab {blame content} {
        set f .files.main.right.nb.$tab
        ttk::frame $f
        text $f.t -font TkFixedFont -wrap none -state disabled \
            -yscrollcommand [list $f.y set] -xscrollcommand [list $f.x set]
        ttk::scrollbar $f.y -command [list $f.t yview]
        ttk::scrollbar $f.x -orient horizontal -command [list $f.t xview]
        grid $f.t $f.y -sticky news
        grid $f.x -sticky ew
        grid columnconfigure $f 0 -weight 1
        grid rowconfigure $f 0 -weight 1
        $f.t tag configure lineno -foreground gray55
        $f.t tag configure meta -foreground gray40
        $f.t tag configure shade1 -background gray95
        # The selection over the shading: tags made later are above it.
        $f.t tag raise sel
    }
    bind .files.main.right.nb.blame.t <Double-1> {tkfiles::blameClick %x %y}
    foreach tab {blame content} {
        menu .files.main.right.nb.$tab.ctx -tearoff 0
        bind .files.main.right.nb.$tab.t <ButtonPress-3> [list tkfiles::linesMenu $tab %x %y %X %Y]
    }
    # The options of the blame.
    set o .files.main.right.nb.blame.opts
    ttk::frame $o
    ttk::checkbutton $o.space -text "Ignore white space" -variable tkfiles::ignoreSpace \
        -command tkfiles::reblame
    ttk::checkbutton $o.eol -text "At line ends only" -variable tkfiles::ignoreEol \
        -command tkfiles::reblame
    ttk::label $o.lo -text "Reverse, towards:"
    ttk::combobox $o.origin -textvariable tkfiles::blameOrigin -width 16
    ttk::label $o.ln -text "How far back:"
    ttk::combobox $o.limit -textvariable tkfiles::blameLimit -width 8 \
        -values {none 100 1000 5s 30s}
    pack $o.space $o.eol $o.lo $o.origin $o.ln $o.limit -side left -padx {0 6}
    icons::tooltip $o.eol "Ignore only changes of white space at the ends of lines (-Z)"
    icons::tooltip $o.origin "A later version: when each line was changed or removed after\
        \nthe version shown (-o); empty: who last changed it"
    icons::tooltip $o.limit "none: the whole history; N versions; Ns: as far as N seconds\
        \nallow (-n).  Lines from further back: \"older\""
    foreach w [list $o.origin $o.limit] {
        bind $w <Return> tkfiles::reblame
        bind $w <<ComboboxSelected>> tkfiles::reblame
    }
    grid $o - -sticky w -padx 4 -pady 2
    # Find in history.
    set g .files.main.right.nb.grep
    ttk::frame $g
    ttk::frame $g.top -padding {4 4}
    ttk::label $g.top.l -text "Find:"
    ttk::entry $g.top.e -textvariable tkfiles::grepPattern -font TkFixedFont
    ttk::checkbutton $g.top.i -text "Ignore case" -variable tkfiles::grepCase
    ttk::checkbutton $g.top.once -text "The newest match only" -variable tkfiles::grepOnce
    ttk::checkbutton $g.top.v -text "Versions without it" -variable tkfiles::grepInvert
    ttk::button $g.top.go -text Find -command tkfiles::grep
    pack $g.top.l -side left
    pack $g.top.go $g.top.v $g.top.once $g.top.i -side right -padx {6 0}
    pack $g.top.e -side left -fill x -expand 1 -padx {4 0}
    ttk::treeview $g.t -columns {date hash name text} -show headings -selectmode browse \
        -yscrollcommand [list $g.y set]
    ttk::scrollbar $g.y -command [list $g.t yview]
    foreach {col heading width} {date Date 16 hash Check-in 11 name "File, line" 22 text Text 60} {
        $g.t heading $col -text $heading -anchor w
        $g.t column $col -width [expr {$width * $char}] -stretch [expr {$col eq "text"}]
    }
    $g.t tag configure line -font TkFixedFont
    $g.t tag configure error -foreground red3
    ttk::label $g.status -padding {4 2} -anchor w
    grid $g.top - -sticky ew
    grid $g.t $g.y -sticky news
    grid $g.status - -sticky ew
    grid columnconfigure $g 0 -weight 1
    grid rowconfigure $g 1 -weight 1
    bind $g.top.e <Return> tkfiles::grep
    bind $g.t <Double-1> {tkfiles::grepOpen [.files.main.right.nb.grep.t identify item %x %y]}
    bind $g.t <Return> {tkfiles::grepOpen [lindex [.files.main.right.nb.grep.t selection] 0]}
    .files.main.right.nb add .files.main.right.nb.history -text History
    .files.main.right.nb add .files.main.right.nb.blame -text Blame
    .files.main.right.nb add .files.main.right.nb.content -text Content
    .files.main.right.nb add .files.main.right.nb.grep -text "Find in history"
    pack .files.main.right.title -fill x
    pack .files.main.right.nb -fill both -expand 1
    .files.main add .files.main.tree -weight 1
    .files.main add .files.main.right -weight 3

    ttk::label .files.status -textvariable tkfiles::status -padding {6 2} -anchor w
    pack .files.top -fill x
    pack .files.status -side bottom -fill x
    pack .files.main -fill both -expand 1

    bind .files.main.tree.t <<TreeviewSelect>> tkfiles::selectFile
    bind .files.main.tree.t <ButtonPress-3> {tkfiles::treeMenu %x %y %X %Y}
    bind .files.main.right.nb <<NotebookTabChanged>> tkfiles::loadShown
    tktaalik::shortcut files <F5> tkfiles::refresh
    tktaalik::shortcut files <Control-f> {focus .files.top.filter; .files.top.filter selection range 0 end}
}

proc tkfiles::refresh {} {
    variable loaded {}
    showVersion
    loadShown
}

# Where we are (tktaalik::location): the version and filter of the tree, the
# file, the tab of the file, the version of it shown.
proc tkfiles::here {} {
    variable shownVersion
    variable shownFilter
    variable file
    variable at
    list $shownVersion $shownFilter $file [.files.main.right.nb select] $at
}

# Back or Forward to a place of here.
proc tkfiles::goTo {place} {
    variable version
    variable filter
    variable file
    variable at
    variable loaded
    lassign $place v f path tab shownAt
    if {$path ne $file || $shownAt ne $at} {
        set loaded [expr {$path eq $file ? [lsearch -all -inline -not -regexp $loaded {^(content|blame)$}] : {}}]
    }
    set at $shownAt
    if {$tab ne ""} { .files.main.right.nb select $tab }
    set filter $f
    set file $path
    showTitle
    if {$v ne "" && $v ne [string trim $version]} {
        set version $v
        showVersion
    } else {
        fillTree
    }
    after cancel tkfiles::fillTree
    # (The same tab: no <<NotebookTabChanged>>.)
    loadShown
}

proc tkfiles::setRepository {path newRoot} {
    variable repo $path
    variable root $newRoot
    variable version
    variable file ""
    variable loaded {}
    variable at {}
    variable remote [fossil::remoteUrl $path]
    set values [versions]
    .files.top.version configure -values $values
    .files.main.right.nb.blame.opts.origin configure -values [concat {{}} $values]
    set version [lindex $values 0]
    tktaalik::setTitle files "Files \u2014 [file rootname [file tail $repo]]"
    .files.main.right.title configure -text ""
    foreach t {history} { .files.main.right.nb.$t.t delete [.files.main.right.nb.$t.t children {}] }
    foreach t {blame content} {
        .files.main.right.nb.$t.t configure -state normal
        .files.main.right.nb.$t.t delete 1.0 end
        .files.main.right.nb.$t.t configure -state disabled
    }
    showVersion
}

proc tkfiles::activate {} {
    variable version
    # The checkout may have moved.
    if {$version eq "checkout" && [tktaalik::changed files]} refresh
    focus .files.main.tree.t
}
