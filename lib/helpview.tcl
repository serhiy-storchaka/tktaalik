# The manual of tktaalik (docs/*.md), in a window of its own: the pages
# rendered by Fossil's Markdown (as wiki pages are), the contents on the
# left, links between pages, Back and Forward, find in the page.  F1 opens
# the page, at the section, for what has the focus (help::context).
#
#   help::show ?PAGE? ?ANCHOR?    open the manual at docs/PAGE.md#ANCHOR
#   help::contextHelp             the page for what has the focus (F1)

source [file join [file dirname [file normalize [info script]]] htmltext.tcl]

namespace eval help {
    variable dir [file join [file dirname [file dirname [file normalize [info script]]]] docs]
    variable page ""          ;# the page shown (its name, without .md)
    variable anchors {}       ;# anchor -> index in the text
    variable back {}
    variable forward {}
    variable find ""
    variable status ""
    # The pages in the order of the contents; the others after them.
    variable order {index timeline tickets branches tags files commit stash wiki forum
        search repository goto diffs keys configuration}
    # F1: the window (or widget) with the focus -> page#anchor, the longest
    # prefix first.  The tabs themselves: their page.
    variable contexts {
        .goto                       goto
        .reports                    tickets#reports
        .info                       repository#information
        .settings                   repository#settings
        .repoopsForm                repository#repository-operations
        .repoopsRun                 repository#repository-operations
        .repoopsChanges             repository#repository-operations
        .info.about                 repository#information
        .users                      repository#users
        .remotes                    repository#remotes
        .uv                         repository#unversioned-files
        .diffview                   diffs
        .help                       index
        .tablecolsPopup             configuration#columns-and-sorting
        .timeline.top               timeline#search-syntax
        .timeline.pull              timeline#pull
        .timeline.bisectrun         timeline#bisect
        .tagwrite                   timeline#editing-check-ins
        .tickets.top                tickets#search-syntax
        .tickets.edit               tickets#editing-tickets
        .tickets.comment            tickets#comments
        .tickets.new                tickets#editing-tickets
        .tickets.close              tickets#closing-tickets
        .tickets.startfix           tickets#starting-a-fix
        .forum.compose              forum#writing
        .tickets.save               tickets#search-syntax
        .tickets.main.details.nb.comments    tickets#comments
        .tickets.main.details.nb.attachments tickets#attachments
        .tickets.main.details.nb.history     tickets#history
        .tickets.main.details       tickets#details
        .tickets.main.list          tickets#the-list
        .branches.top               branches#search-syntax
        .branches.newbranch         branches#managing-branches
        .branches.output            branches#update-and-merge
        .branches.merge             branches#update-and-merge
        .artifact                   timeline#details
        .graveyard                  timeline#purging
        .branches.releases          branches#changes-between-releases
        .branches.targets           branches#merge-state
        .branches.main.details      branches#details
        .tags.main                  tags#the-list
        .files.main.right.nb.blame   files#blame
        .files.main.right.nb.history files#file-history
        .files.main.right.nb.content files#content
        .files.main.right.nb.grep    files#find-in-history
        .files.found                files#a-local-file-in-history
        .files.archive              files#archives
        .commit.merge               commit#merges
        .commit.update              commit#updating
        .commit.updatefiles         commit#updating
        .commit.mergefork           commit#merges
        .commit.threeway            commit#merges
        .commit.compare             commit#diffs
        .commit.touch               commit#file-operations
        .commit.switch              commit#file-operations
        .commit.patch               commit#patches
        .commit.clean               commit#delete-unmanaged-files
        .commit.cleanok             commit#delete-unmanaged-files
        .commit.rename              commit#file-operations
        .commit.remove              commit#file-operations
        .commit.addremove           commit#file-operations
        .commit.reset               commit#file-operations
        .commit.revert              commit#undo-and-redo
        .commit.from                commit#diffs
        .commit.log                 commit#committing
        .stash.top                  stash#search-syntax
        .stash.save                 stash#stashing-changes
        .wiki.edit                  wiki#editing
        .search.top                 search#search-syntax
        .search.fts                 search#the-search-index
        .search.fossilhelp          search#results
        .search.main                search#results
    }
}

# ---------------------------------------------------------------- context

# The page#anchor for widget W (the focus): the longest prefix of its
# path in the contexts; else the tab shown; else the contents.
proc help::context {{w ""}} {
    variable contexts
    if {$w eq ""} { set w [focus] }
    set best ""
    set length 0
    foreach {prefix target} $contexts {
        # (".diffview" also for .diffview1, .diffview2...)
        if {$w eq $prefix || [string match $prefix.* $w]
                || ($prefix eq ".diffview" && [regexp {^\.diffview\d+(\.|$)} $w])} {
            if {[string length $prefix] > $length} {
                set best $target
                set length [string length $prefix]
            }
        }
    }
    # The dialogs of tags: by their title.
    if {[string match .tagwrite* $w] && [winfo exists .tagwrite]} {
        set title [wm title .tagwrite]
        if {[string match "Add tag*" $title]} { set best timeline#tags-on-check-ins }
        if {[string match "Reparent*" $title]} { set best timeline#tags-on-check-ins }
        if {[string match "Save * as an archive*" $title]} { set best timeline#archives }
        if {[string match "Export a bundle*" $title] || [string match "Import *" $title]} { set best branches#bundles }
        if {[string match "Common ancestor*" $title]} { set best branches#the-branch-menu }
        if {[string match "Describe from tags*" $title]} { set best timeline#details }
    }
    if {$best ne ""} { return $best }
    set active [expr {[info exists ::tktaalik::active] ? $::tktaalik::active : ""}]
    if {$active ne ""} { return $active }
    return index
}

proc help::contextHelp {} {
    lassign [split [context] #] page anchor
    show $page $anchor
}

# ---------------------------------------------------------------- window

proc help::show {{name index} {anchor ""}} {
    variable page
    if {![winfo exists .help]} { build }
    wm deiconify .help
    raise .help
    if {$name ne $page} { remember }
    go $name $anchor
    focus .help.main.text
}

proc help::build {} {
    toplevel .help
    wm title .help "Tktaalik manual"
    wm geometry .help 1000x750
    wm protocol .help WM_DELETE_WINDOW {wm withdraw .help}
    ttk::frame .help.bar -padding 4
    ttk::button .help.bar.back -text "\u2190 Back" -command help::goBack -state disabled
    ttk::button .help.bar.forward -text "Forward \u2192" -command help::goForward -state disabled
    ttk::label .help.bar.fl -text "Find:"
    ttk::entry .help.bar.find -textvariable help::find -width 24
    ttk::button .help.bar.close -text Close -command {wm withdraw .help}
    pack .help.bar.back .help.bar.forward -side left -padx {0 4}
    pack .help.bar.close -side right
    pack .help.bar.find .help.bar.fl -side right -padx {4 0}

    ttk::panedwindow .help.main -orient horizontal
    ui::splitByWeights .help.main
    ttk::frame .help.main.toc
    ttk::treeview .help.main.toc.t -show tree -selectmode browse \
        -yscrollcommand {.help.main.toc.y set}
    ttk::scrollbar .help.main.toc.y -command {.help.main.toc.t yview}
    grid .help.main.toc.t .help.main.toc.y -sticky news
    grid columnconfigure .help.main.toc 0 -weight 1
    grid rowconfigure .help.main.toc 0 -weight 1
    set d .help.main.text
    text $d -wrap word -padx 14 -pady 10 -font TkTextFont -state disabled -cursor arrow \
        -yscrollcommand {.help.main.y set} -width 80
    ttk::scrollbar .help.main.y -command [list $d yview]
    ttk::frame .help.main.page
    grid $d -in .help.main.page -row 0 -column 0 -sticky news
    grid .help.main.y -in .help.main.page -row 0 -column 1 -sticky ns
    grid columnconfigure .help.main.page 0 -weight 1
    grid rowconfigure .help.main.page 0 -weight 1
    raise $d
    raise .help.main.y
    .help.main add .help.main.toc -weight 1
    .help.main add .help.main.page -weight 4
    $d tag configure found -background #fff3a0
    ttk::label .help.status -textvariable help::status -padding {6 2} -anchor w
    pack .help.bar -fill x
    pack .help.status -side bottom -fill x
    pack .help.main -fill both -expand 1
    fillContents
    bind .help.main.toc.t <<TreeviewSelect>> help::tocSelected
    popup::attach .help.main.toc.t help::tocMenu
    bind .help.bar.find <Return> {help::findNext; break}
    bind .help <Control-f> {focus .help.bar.find; .help.bar.find selection range 0 end}
    bind .help <Escape> {wm withdraw .help}
    # Keys to scroll the page (it is read only: no insert cursor).
    foreach {key what} {Prior {-1 pages} Next {1 pages} Up {-1 units} Down {1 units}} {
        bind $d <$key> "$d yview scroll $what; break"
    }
    bind $d <Home> "$d yview moveto 0; break"
    bind $d <End> "$d yview moveto 1; break"
    # Back and Forward: Alt+Left, Alt+Right, the mouse side buttons (as in
    # the main window: tktaalik::sideButtons).
    bind .help <<Back>> help::goBack
    bind .help <<Forward>> help::goForward
    if {[package vsatisfies [package provide Tk] 9]} {
        bind .help <Button-4> {event generate %W <<Back>>}
        bind .help <Button-5> {event generate %W <<Forward>>}
    } else {
        bind .help <ButtonPress> {+tktaalik::sideButton %W %b}
    }
}

# The pages: name -> {title headings}, read from the files.
proc help::pages {} {
    variable dir
    variable order
    set names [lmap f [glob -nocomplain -directory $dir *.md] { file rootname [file tail $f] }]
    set ordered [concat [lmap n $order { if {$n in $names} { set n } else continue }] \
        [lsort [lmap n $names { if {$n in $order} continue; set n }]]]
    set result {}
    foreach name $ordered {
        set title $name
        set headings {}
        set f [open [file join $dir $name.md]]
        fconfigure $f -encoding utf-8
        set fence 0
        foreach line [split [read $f] \n] {
            if {[string match "```*" $line]} { set fence [expr {!$fence}]; continue }
            if {$fence} continue
            if {[regexp {^# (.+)$} $line -> t] && $title eq $name} { set title [string trim $t] }
            if {[regexp {^## (.+)$} $line -> h]} { lappend headings [string trim $h] }
        }
        close $f
        dict set result $name [list $title $headings]
    }
    return $result
}

proc help::fillContents {} {
    set t .help.main.toc.t
    $t delete [$t children {}]
    dict for {name info} [pages] {
        lassign $info title headings
        $t insert {} end -id $name -text $title -open 0
        foreach h $headings {
            $t insert $name end -id $name#[slug $h] -text $h
        }
    }
}

# The anchor of a heading, as the pages link to it.
proc help::slug {text} {
    string trim [regsub -all {[^a-z0-9]+} [string tolower $text] -] -
}

# Show page NAME at ANCHOR (or its top).
proc help::go {name {anchor ""}} {
    variable dir
    variable page
    variable anchors
    variable status
    set file [file join $dir $name.md]
    set d .help.main.text
    if {$name ne $page} {
        $d configure -state normal
        $d delete 1.0 end
        htmltext::reset $d
        set anchors {}
        if {![file exists $file]} {
            $d insert end "No page \"$name\" in the manual."
            $d configure -state disabled
            set page $name
            return
        }
        set f [open $file]
        fconfigure $f -encoding utf-8
        set text [read $f]
        close $f
        set html [render $text]
        htmltext::insert $d $html -command help::follow \
            -external {regexp -nocase {^https?://}}
        # The headings: their anchors.
        foreach tag [$d tag names] {
            if {![regexp {^ht-font-.*-[01][01][1-6]$} $tag]} continue
            foreach {from to} [$d tag ranges $tag] {
                set h [slug [$d get $from $to]]
                if {$h ne "" && ![dict exists $anchors $h]} { dict set anchors $h $from }
            }
        }
        $d configure -state disabled
        set page $name
        wm title .help "[lindex [dict get [pages] $name] 0] \u2014 Tktaalik manual"
    }
    set t .help.main.toc.t
    if {[$t exists $name]} { $t item $name -open 1 }
    set status ""
    if {$anchor ne "" && [dict exists $anchors $anchor]} {
        $d yview [dict get $anchors $anchor]
        set id $name#$anchor
    } else {
        if {$anchor ne ""} { set status "No section \"$anchor\" here" }
        $d yview moveto 0
        set id $name
    }
    # (Selected by going there: tocSelected ignores what is shown.)
    variable shownId $id
    if {[$t exists $id]} {
        $t selection set [list $id]
        $t see $id
    }
}

# Markdown as HTML: Fossil's renderer (no repository needed).
proc help::render {text} {
    set html ""
    set name ""
    try {
        set f [file tempfile name]
        fconfigure $f -encoding utf-8
        puts -nonewline $f $text
        close $f
        set p [fossil::pipe [list test-markdown-render $name 2>@1]]
        fconfigure $p -encoding utf-8
        set html [read $p]
        close $p
    } on error {} {
        set html "<pre>[string map {& &amp; < &lt; > &gt;} $text]</pre>"
    } finally {
        if {$name ne ""} { file delete $name }
    }
    return $html
}

proc help::tocSelected {} {
    variable shownId
    set id [lindex [.help.main.toc.t selection] 0]
    if {$id eq "" || ([info exists shownId] && $id eq $shownId)} return
    lassign [split $id #] name anchor
    remember
    go $name $anchor
}

# A link: another page or a section here, or the browser.
proc help::follow {href} {
    variable page
    if {[regexp {^([a-z0-9_-]+)\.md(?:#(.*))?$} $href -> name anchor]} {
        remember
        go $name $anchor
    } elseif {[string match #* $href]} {
        remember
        go $page [string range $href 1 end]
    } elseif {[regexp {^https?://} $href]} {
        fossil::browse $href
    }
}

# ------------------------------------------------------------ Back, Forward

proc help::here {} {
    variable page
    list $page [.help.main.text index @0,0]
}

proc help::remember {} {
    variable page
    variable back
    variable forward
    if {$page eq ""} return
    lappend back [here]
    set forward {}
    buttons
}

proc help::goBack {} {
    variable back
    variable forward
    if {![llength $back]} return
    lappend forward [here]
    set to [lindex $back end]
    set back [lrange $back 0 end-1]
    restore $to
}

proc help::goForward {} {
    variable back
    variable forward
    if {![llength $forward]} return
    lappend back [here]
    set to [lindex $forward end]
    set forward [lrange $forward 0 end-1]
    restore $to
}

proc help::restore {place} {
    lassign $place name index
    go $name
    .help.main.text yview $index
    buttons
}

proc help::buttons {} {
    variable back
    variable forward
    .help.bar.back state [expr {[llength $back] ? "!disabled" : "disabled"}]
    .help.bar.forward state [expr {[llength $forward] ? "!disabled" : "disabled"}]
}

# ---------------------------------------------------------------- find

# The next place of the text to find (from the top of the page shown, or
# after the one found last), all of them marked.
proc help::findNext {} {
    variable find
    variable status
    set d .help.main.text
    $d tag remove found 1.0 end
    if {$find eq ""} return
    set all [$d search -all -nocase -count lengths -- $find 1.0 end]
    if {![llength $all]} {
        set status "\"$find\" is not on this page"
        bell
        return
    }
    foreach i $all n $lengths { $d tag add found $i "$i + $n chars" }
    variable lastFound
    set from [expr {[info exists lastFound] ? "$lastFound + 1 char" : "@0,0"}]
    set i [$d search -nocase -- $find $from end]
    if {$i eq ""} { set i [lindex $all 0] }
    set lastFound $i
    $d see $i
    set status "[llength $all] on this page (Return: the next)"
}

# The context menu of the contents.
proc help::tocMenu {m item} {
    set t .help.main.toc.t
    $m add command -label "Open all" -command [list apply {{t} {
        foreach i [$t children {}] { $t item $i -open 1 } }} $t]
    $m add command -label "Close all" -command [list apply {{t} {
        foreach i [$t children {}] { $t item $i -open 0 } }} $t]
    popup::separator $m
    popup::copy $m "Copy link" [string map {# .md#} $item][expr {[string first # $item] < 0 ? ".md" : ""}]
}
