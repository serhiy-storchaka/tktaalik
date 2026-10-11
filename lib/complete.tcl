# Completion in the search boxes of the tabs: the keys of the search
# syntax (user:, is:...) and their values (users, branches, states...) in
# a list below the box, for the word at the cursor.
#
#   complete::attach ENTRY SOURCE
#       completion in ENTRY (an entry or combobox): SOURCE is a command
#       giving the keys, a dict key -> {DESCRIPTION VALUES ?ICON?}; VALUES
#       a command (called with the text typed of the value) giving the
#       values, or "" for none; ICON a command (called with a value)
#       giving the name of its icon (lib/icons.tcl), or "" for none:
#       shown in Tk 9 only (as the images in the tables)
#   complete::show ENTRY ?ALL?
#       the list for the word at the cursor (ALL: also for an empty word,
#       all the keys); closed if nothing matches
#   complete::fixed VALUES PREFIX    VALUES (for a key with fixed values)
#   complete::users REPO PREFIX      the users of REPO
#   complete::branches REPO PREFIX   its branches
#   complete::tags REPO PREFIX       its tags (branches too)
#   complete::files REPO PREFIX      file names starting with PREFIX
#   complete::column REPO TABLE COLUMN PREFIX
#                                    the values a column has
#   complete::cached REPO WHAT SQL   the first column of what SQL gives,
#                                    kept a minute
#   complete::icon NAME VALUE        NAME (one icon for all the values)
#   complete::fileIcon NAME          the icon of the kind of file NAME
#
# The list opens as you type a key or a value (after "key:" or a comma);
# Down and Up choose, Tab or Return takes the one chosen (Tab: the first
# if none), a click too; Escape closes the list; Ctrl+Space opens it for
# all the keys.  Return without a choice searches, as before.

source [file join [file dirname [file normalize [info script]]] fossil.tcl]

namespace eval complete {
    variable sources            ;# array: entry -> its SOURCE
    variable at                 ;# array: entry -> {from to kind} of the word
    variable cache {}           ;# {repo what} -> {time values}
    variable maxShown 200
}

proc complete::attach {e source} {
    variable sources
    set sources($e) $source
    if {"Complete" ni [bindtags $e]} { bindtags $e [linsert [bindtags $e] 0 Complete] }
    bind $e <Destroy> {+complete::forget %W}
    # (Once: the keys of the list, before the box's own: Return searches,
    # Escape clears, Down opens the history when no list is shown.)
    if {[bind Complete <KeyRelease>] eq ""} {
        bind Complete <KeyRelease> {complete::typed %W %K}
        bind Complete <Down> {if {[complete::move %W 1]} break}
        bind Complete <Up> {if {[complete::move %W -1]} break}
        bind Complete <Tab> {if {[complete::accept %W 1]} break}
        bind Complete <Return> {if {[complete::accept %W 0]} break}
        bind Complete <KP_Enter> {if {[complete::accept %W 0]} break}
        bind Complete <Escape> {if {[complete::close %W]} break}
        bind Complete <Control-space> {complete::show %W 1; break}
        bind Complete <FocusOut> {after 150 [list complete::closeUnlessFocused %W]}
    }
}

proc complete::forget {e} {
    variable sources
    variable at
    unset -nocomplain sources($e) at($e)
}

proc complete::list_ {e} { return $e.complete.l }

# The labels of the list shown (for tests), "" if none.
proc complete::labels {e} {
    if {![shown $e]} return
    set l [list_ $e]
    lmap item [$l children {}] { $l item $item -text }
}

proc complete::typed {e key} {
    switch -glob -- $key {
        Up - Down - Return - KP_Enter - Escape - Tab - ISO_Left_Tab -
        Shift_* - Control_* - Alt_* - Meta_* - Super_* - Caps_Lock - Num_Lock {}
        Left - Right - Home - End - Prior - Next { close $e }
        default { show $e 0 }
    }
}

# The word at the cursor: {from to neg key value valueFrom}; key "" for a
# key being typed (the word itself).
proc complete::word {e} {
    set text [$e get]
    set cur [$e index insert]
    set from $cur
    while {$from > 0 && ![string is space [string index $text $from-1]]} { incr from -1 }
    set to $cur
    while {$to < [string length $text] && ![string is space [string index $text $to]]} { incr to }
    set word [string range $text $from $cur-1]
    set start $from
    if {[string index $word 0] eq "-"} {
        set word [string range $word 1 end]
        incr start
    }
    if {[regexp {^([A-Za-z_]+):(.*)$} $word -> key value]} {
        # Of a list (a,b): the last one.
        set comma [string last , $value]
        set valueFrom [expr {$start + [string length $key] + 1 + $comma + 1}]
        set value [string range $value $comma+1 end]
        return [list $from $to [string tolower $key] $value $valueFrom $start]
    }
    list $from $to "" $word $start $start
}

proc complete::show {e {all 0}} {
    variable sources
    variable at
    variable maxShown
    if {![info exists sources($e)]} return
    lassign [word $e] from to key typed valueFrom keyFrom
    if {[catch {uplevel #0 $sources($e)} keys]} { set keys {} }
    set items {}
    if {$key eq ""} {
        if {$typed eq "" && !$all} { close $e; return }
        dict for {k spec} $keys {
            if {[string equal -nocase -length [string length $typed] $typed $k]} {
                lappend items [list $k: "$k:  \u2014 [lindex $spec 0]" ""]
            }
        }
        set replace [list $keyFrom $to]
        set kind key
    } else {
        if {![dict exists $keys $key]} { close $e; return }
        lassign [dict get $keys $key] - command iconCommand
        if {$command eq ""} { close $e; return }
        # (Icons in a list: Tk 9 only, as in the tables.)
        if {![package vsatisfies [package provide Tk] 9] || [info commands ::icons::get] eq ""} {
            set iconCommand ""
        }
        set prefix [string trimleft $typed \"]
        if {[catch {uplevel #0 [list {*}$command $prefix]} values]} { set values {} }
        foreach v $values {
            if {$v eq "" || ![string equal -nocase -length [string length $prefix] $prefix $v]} continue
            # (Typed in full already: nothing to add.)
            if {[string equal -nocase $v $prefix]} continue
            set icon ""
            if {$iconCommand ne "" && [catch {uplevel #0 [list {*}$iconCommand $v]} icon]} { set icon "" }
            lappend items [list $v $v $icon]
            if {[llength $items] >= $maxShown} break
        }
        # (To the end of this value, not the rest of the list.)
        set text [$e get]
        set end $valueFrom
        while {$end < $to && [string index $text $end] ne ","} { incr end }
        set replace [list $valueFrom $end]
        set kind value
    }
    if {![llength $items]} { close $e; return }
    set at($e) [list {*}$replace $kind $items]
    Popup $e $items [lindex $replace 0]
}

proc complete::Popup {e items from} {
    set w $e.complete
    if {![winfo exists $w]} {
        toplevel $w -borderwidth 1 -relief solid -background gray50
        wm withdraw $w
        wm overrideredirect $w 1
        # A list of one column, an icon before the text (no expander).
        ttk::style layout Complete.Treeview.Item {
            Treeitem.padding -sticky nswe -children {
                Treeitem.image -side left -sticky {} Treeitem.text -sticky nswe
            }
        }
        ttk::treeview $w.l -style Complete.Treeview -show tree -selectmode browse \
            -takefocus 0 -yscrollcommand [list $w.y set]
        ttk::scrollbar $w.y -command [list $w.l yview]
        pack $w.y -side right -fill y
        pack $w.l -fill both -expand 1
        # (A click takes it; the box keeps the focus.)
        bind $w.l <ButtonRelease-1> [list complete::clicked $e %x %y]
        bind $w.l <ButtonPress-1> break
    }
    set l $w.l
    $l delete [$l children {}]
    set font [ttk::style lookup Treeview -font]
    if {$font eq ""} { set font TkDefaultFont }
    set width 0
    set iconWidth 0
    foreach item $items {
        lassign $item - label icon
        set image [expr {$icon eq "" ? "" : [icons::get $icon row]}]
        if {$image ne ""} { set iconWidth [image width $image] }
        $l insert {} end -text $label -image $image
        set width [expr {max($width, [font measure $font $label])}]
    }
    # (Rows without an icon: their text where the others' is.)
    if {$iconWidth} {
        foreach item [$l children {}] {
            if {[$l item $item -image] eq ""} { $l item $item -image [Blank $iconWidth] }
        }
    }
    set width [expr {min($width + $iconWidth + 16, [winfo screenwidth $e] / 2)}]
    $l column #0 -width $width
    $l configure -height [expr {min([llength $items], 10)}]
    if {[llength $items] > 10} { pack $w.y -side right -fill y -before $l } else { pack forget $w.y }
    # Below the box, from the word's start.
    set x [winfo rootx $e]
    set bbox [$e bbox $from]
    if {[llength $bbox]} { incr x [lindex $bbox 0] }
    set y [expr {[winfo rooty $e] + [winfo height $e]}]
    wm geometry $w +$x+$y
    wm deiconify $w
    raise $w
}

# An empty image as wide as the icons.
proc complete::Blank {width} {
    set name ::complete::blank$width
    if {$name ni [image names]} { image create photo $name -width $width -height 1 }
    return $name
}

proc complete::shown {e} {
    expr {[winfo exists $e.complete] && [winfo ismapped $e.complete]}
}

proc complete::close {e} {
    variable at
    unset -nocomplain at($e)
    if {![shown $e]} { return 0 }
    wm withdraw $e.complete
    return 1
}

proc complete::closeUnlessFocused {e} {
    if {[winfo exists $e] && [focus] ne $e} { close $e }
}

proc complete::move {e by} {
    if {![shown $e]} { return 0 }
    set l [list_ $e]
    set rows [$l children {}]
    set n [llength $rows]
    set i [lsearch -exact $rows [lindex [$l selection] 0]]
    set i [expr {$i < 0 ? ($by > 0 ? 0 : $n - 1) : ($i + $by + $n) % $n}]
    $l selection set [list [lindex $rows $i]]
    $l see [lindex $rows $i]
    return 1
}

# The one chosen into the box (FIRST: the first if none is): 1 if done.
proc complete::accept {e first} {
    variable at
    if {![shown $e] || ![info exists at($e)]} { return 0 }
    set l [list_ $e]
    set i [lsearch -exact [$l children {}] [lindex [$l selection] 0]]
    if {$i < 0} {
        if {!$first} { close $e; return 0 }
        set i 0
    }
    lassign $at($e) from to kind items
    set text [lindex $items $i 0]
    # (A value with a space or a comma: quoted.)
    if {$kind eq "value" && [regexp {[\s,"]} $text]} { set text "\"[string map {\" {}} $text]\"" }
    close $e
    $e delete $from $to
    $e insert $from $text
    $e icursor [expr {$from + [string length $text]}]
    $e xview insert
    # A key: its values at once.
    if {$kind eq "key"} { after idle [list complete::show $e 0] }
    return 1
}

proc complete::clicked {e x y} {
    set l [list_ $e]
    set item [$l identify item $x $y]
    if {$item eq ""} return
    $l selection set [list $item]
    accept $e 0
    focus $e
}

# --------------------------------------------------------------- values

proc complete::fixed {values prefix} { return $values }

proc complete::icon {name value} { return $name }

proc complete::fileIcon {name} {
    if {[info commands ::imageview::fileKind] eq ""} { return "" }
    return a-[imageview::fileKind $name 0]
}

# What a query gives, kept a minute (the lists of a large repository).
proc complete::cached {repo what sql} {
    variable cache
    set key [list $repo $what]
    set now [clock seconds]
    if {[dict exists $cache $key] && $now - [lindex [dict get $cache $key] 0] < 60} {
        return [lindex [dict get $cache $key] 1]
    }
    if {$repo eq "" || [catch {fossil::sql $repo $sql} rows]} { set rows {} }
    set values [lmap row $rows { lindex $row 0 }]
    dict set cache $key [list $now $values]
    return $values
}

proc complete::users {repo prefix} {
    linsert [cached $repo users "SELECT login FROM user
        WHERE login NOT IN ('anonymous','nobody','developer','reader')
        UNION SELECT DISTINCT user FROM event WHERE user<>'' ORDER BY 1"] 0 @me
}

proc complete::branches {repo prefix} {
    cached $repo branches "SELECT DISTINCT [fossil::outcol value] FROM tagxref
        WHERE tagtype>0 AND tagid=(SELECT tagid FROM tag WHERE tagname='branch') ORDER BY 1"
}

proc complete::tags {repo prefix} {
    cached $repo tags "SELECT [fossil::outcol substr(tagname,5)] FROM tag
        WHERE tagname GLOB 'sym-*' ORDER BY 1"
}

proc complete::files {repo prefix} {
    if {$repo eq ""} { return {} }
    set glob [fossil::sqlstr "[string map {* {[*]} ? {[?]} [ {[[]}} $prefix]*"]
    if {[catch {fossil::sql $repo "SELECT [fossil::outcol name] FROM filename
            WHERE name GLOB $glob ORDER BY name LIMIT 200"} rows]} { return {} }
    lmap row $rows { lindex $row 0 }
}

proc complete::column {repo table column prefix} {
    cached $repo $table.$column "SELECT DISTINCT [fossil::outcol "trim($column)"] FROM $table
        WHERE trim(coalesce($column,''))<>'' ORDER BY 1 LIMIT 500"
}
