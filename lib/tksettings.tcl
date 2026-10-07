# The Settings window of tktaalik (Repository menu): the settings of the repository ("fossil
# settings"), where each value comes from, Fossil's help for it, and
# setting or unsetting it for this repository (local) or for all
# repositories (global, in ~/.fossil).  Versioned settings are files in
# the checkout (.fossil-settings/NAME): they are shown, but changed by
# editing and committing the file.

source [file join [file dirname [file normalize [info script]]] fossil.tcl]
source [file join [file dirname [file normalize [info script]]] tablecols.tcl]

namespace eval tksettings {
    variable repo ""
    variable root ""
    variable settings           ;# array: name -> dict {local global versioned file}
    variable filter ""
    variable onlySet 0
    variable selected ""
    variable status ""
}

# Run fossil for the repository: in the checkout (the versioned settings
# count there), else with -R.
proc tksettings::fossil {args} {
    variable repo
    variable root
    fossil::runIn $root $repo {*}$args
}

# The output of "fossil settings": name -> {scope value file}.  A value of
# more lines comes on the following lines, indented by four spaces.
proc tksettings::parse {text} {
    set result {}
    set name ""
    foreach line [split $text \n] {
        if {[regexp {^\s+\(overridden by contents of file (.+)\)\s*$} $line -> file]} {
            if {$name ne ""} { dict set result $name file $file }
        } elseif {[regexp {^    (.*)$} $line -> more]} {
            if {$name ne ""} {
                set value [dict get $result $name value]
                dict set result $name value [expr {$value eq "" ? $more : "$value\n$more"}]
            }
        } elseif {[regexp {^(\S+)\s*(?:\((local|global)\)\s?(.*))?$} $line -> name scope value]} {
            dict set result $name [dict create scope $scope value [string trim $value] file ""]
        }
    }
    return $result
}

proc tksettings::reload {} {
    variable settings
    variable status
    variable root
    lassign [fossil settings] code out
    lassign [fossil settings --global] gcode gout
    if {$code} {
        set status "fossil settings failed: $out"
        return
    }
    set effective [parse $out]
    set global [expr {$gcode ? {} : [parse $gout]}]
    array unset settings
    dict for {name s} $effective {
        set g [expr {[dict exists $global $name] && [dict get $global $name scope] eq "global"
            ? [dict get $global $name value] : ""}]
        set l [expr {[dict get $s scope] eq "local" ? [dict get $s value] : ""}]
        set settings($name) [dict create local $l global $g file [dict get $s file] \
            isLocal [expr {[dict get $s scope] eq "local"}] \
            isGlobal [expr {[dict exists $global $name] && [dict get $global $name scope] eq "global"}]]
    }
    showList
}

# Where the value in effect comes from.
proc tksettings::origin {s} {
    if {[dict get $s file] ne ""} { return versioned }
    if {[dict get $s isLocal]} { return local }
    if {[dict get $s isGlobal]} { return global }
    return default
}

proc tksettings::oneLine {text} {
    set lines [split $text \n]
    expr {[llength $lines] > 1 ? "[lindex $lines 0] \u2026 ([llength $lines] lines)" : $text}
}

proc tksettings::showList {} {
    variable settings
    variable filter
    variable onlySet
    variable status
    variable selected
    set f [string tolower [string trim $filter]]
    set rows {}
    set n 0
    foreach name [lsort [array names settings]] {
        set s $settings($name)
        set from [origin $s]
        if {$onlySet && $from eq "default"} continue
        if {$f ne "" && [string first $f $name] < 0} continue
        set value [expr {$from eq "local" ? [dict get $s local] : $from eq "global" ? [dict get $s global] : ""}]
        if {$from eq "versioned"} { set value "(file [dict get $s file])" }
        lappend rows [list $name [dict create name $name value [oneLine $value] from $from \
            local [oneLine [dict get $s local]] global [oneLine [dict get $s global]]] {} \
            [expr {$from eq "default" ? "" : "set"}]]
        incr n
    }
    set t .settings.main.list.t
    tablecols::fill $t $rows
    if {$selected ne "" && [$t exists $selected]} {
        $t selection set $selected
        $t see $selected
    } elseif {[llength [$t children {}]]} {
        $t selection set [lindex [$t children {}] 0]
    } else {
        showDetails ""
    }
    set set [llength [lmap name [array names settings] {
        if {[origin $settings($name)] eq "default"} continue; set name }]]
    set status "$n of [array size settings] settings  \u00b7  $set set"
}

# ---------------------------------------------------------------- details

# Fossil's help for a setting: {header text}.
proc tksettings::help {name} {
    lassign [fossil::run help [fossil::arg $name]] code out
    set lines [split [string trim $out] \n]
    list [lindex $lines 0] [string trim [join [lrange $lines 1 end] \n]]
}

proc tksettings::showDetails {name} {
    variable settings
    variable selected
    variable root
    set selected $name
    set d .settings.main.details.help
    $d configure -state normal
    $d delete 1.0 end
    set e .settings.main.details.edit
    $e.value delete 1.0 end
    if {$name eq "" || ![info exists settings($name)]} {
        $d configure -state disabled
        foreach b {local global unlocal unglobal} { $e.b.$b state disabled }
        return
    }
    set s $settings($name)
    lassign [help $name] header text
    $d insert end "$name\n" title
    set extra ""
    regexp {\(([^)]*)\)\s*$} $header -> extra
    set where [origin $s]
    $d insert end "In effect: " label [dict get {versioned "the versioned file"
        local "the value for this repository" global "the global value"
        default "the default"} $where]
    if {$extra ne ""} { $d insert end "  \u00b7  $extra" meta }
    $d insert end \n
    foreach {label key} {"This repository" local "Global" global} {
        set v [dict get $s $key]
        if {$v eq "" && ![dict get $s is[string totitle $key]]} continue
        $d insert end "$label: " label [expr {[string first \n $v] >= 0 ? "\n$v" : $v}] value \n
    }
    if {[dict get $s file] ne ""} {
        $d insert end "Versioned: " label "[dict get $s file] in the checkout, which overrides the\
            other values; edit and commit the file to change it.\n" ""
        if {$root ne ""} {
            catch {
                set f [open [file join $root [dict get $s file]]]
                set content [read $f]
                close $f
                $d insert end [string trimright $content] value \n
            }
        }
    }
    $d insert end \n "" $text help
    $d configure -state disabled
    $d yview moveto 0
    # The value to set: the one of this repository, else the global one.
    set v [expr {[dict get $s isLocal] ? [dict get $s local] : [dict get $s global]}]
    $e.value insert end $v
    $e.b.local state !disabled
    $e.b.global state !disabled
    $e.b.unlocal state [expr {[dict get $s isLocal] ? "!disabled" : "disabled"}]
    $e.b.unglobal state [expr {[dict get $s isGlobal] ? "!disabled" : "disabled"}]
}

# Where the global settings are: as "fossil info" says in a checkout, else
# as Fossil finds it: $FOSSIL_HOME/.fossil, ~/.fossil, the XDG config dir.
proc tksettings::configDb {} {
    variable root
    if {$root ne ""} {
        lassign [fossil info] code out
        if {!$code && [regexp -line {^config-db:\s+(.*\S)} $out -> db]} { return $db }
    }
    if {[info exists ::env(FOSSIL_HOME)]} { return [file join $::env(FOSSIL_HOME) .fossil] }
    set home [file join $::env(HOME) .fossil]
    if {[file exists $home]} { return $home }
    set xdg [expr {[info exists ::env(XDG_CONFIG_HOME)] ? $::env(XDG_CONFIG_HOME)
        : [file join $::env(HOME) .config]}]
    file join $xdg fossil.db
}

# Set or unset the selected setting, locally or globally, after asking.
proc tksettings::change {how scope} {
    variable selected
    variable repo
    if {$selected eq ""} return
    set name $selected
    set value [string trim [.settings.main.details.edit.value get 1.0 end]]
    set opts [expr {$scope eq "global" ? {--global} : {}}]
    set where [expr {$scope eq "global"
        ? "for all repositories (in [configDb])" : "for [file tail $repo]"}]
    if {$how eq "set"} {
        if {$value eq ""} {
            tk_messageBox -icon info -title Settings -message "The value is empty." \
                -detail "To remove a value, use Unset."
            return
        }
        if {[catch {fossil::arg $value}]} {
            tk_messageBox -icon info -title Settings \
                -message "This value cannot be passed to fossil from here." \
                -detail "It starts with \"-\", \"<\", \">\", \"|\" or \"2>\", or is \"&\"."
            return
        }
        set command [list fossil settings $name $value {*}$opts]
        set message "Set $name $where?"
        set detail "New value:\n$value"
    } else {
        set command [list fossil unset $name {*}$opts]
        set message "Unset $name $where?"
        set detail "Its value is removed."
    }
    if {$name eq "autosync" && $how eq "set" && [string tolower $value] ni {off 0 no false pullonly}} {
        append detail "\n\nWith autosync on, Fossil pushes after commits and other changes,\
            and the Branches tab refuses to close, hide or create branches."
    }
    if {![ui::confirm -title Settings $message $detail]} return
    lassign [fossil {*}[lrange $command 1 end]] code out
    reload
    if {$code} {
        tk_messageBox -icon error -title Settings -message "[lindex $command 1] failed:" -detail $out
    }
}

# ----------------------------------------------------------------- window

# Open the window (made the first time), for the repository shown.
proc tksettings::window {} {
    if {[tktaalik::dialogWindow .settings Settings]} { build }
    setRepository $::tktaalik::repo $::tktaalik::root
    focus .settings.main.list.t
}

proc tksettings::build {} {
    wm geometry .settings 1000x600
    ttk::frame .settings.top -padding {6 6 6 2}
    ttk::label .settings.top.fl -text "Find:"
    ttk::entry .settings.top.filter -textvariable tksettings::filter -width 30
    ttk::checkbutton .settings.top.only -text "Only the ones set" -variable tksettings::onlySet \
        -command tksettings::showList
    pack .settings.top.fl .settings.top.filter .settings.top.only -side left -padx {0 6}
    trace add variable ::tksettings::filter write {::apply {args {
        after cancel tksettings::showList
        after 200 tksettings::showList
    }}}

    ttk::panedwindow .settings.main -orient horizontal
    ttk::frame .settings.main.list
    set t .settings.main.list.t
    ttk::treeview $t -show headings -selectmode browse -yscrollcommand {.settings.main.list.y set}
    ttk::scrollbar .settings.main.list.y -command [list $t yview]
    grid $t .settings.main.list.y -sticky news
    grid columnconfigure .settings.main.list 0 -weight 1
    grid rowconfigure .settings.main.list 0 -weight 1
    $t tag configure set -font TkHeadingFont
    tablecols::setup $t {
        name   {heading Setting width 24}
        value  {heading "Value in effect" width 24 stretch 1}
        from   {heading From width 10}
        local  {heading "This repository" width 16}
        global {heading Global width 16}
    } -fixed {name value} -defaults {from} -sort {name asc}

    ttk::frame .settings.main.details
    set d .settings.main.details.help
    text $d -wrap word -width 60 -height 20 -padx 8 -pady 6 -font TkTextFont -state disabled \
        -yscrollcommand {.settings.main.details.y set}
    ttk::scrollbar .settings.main.details.y -command [list $d yview]
    $d tag configure title -font TkHeadingFont -spacing3 4
    $d tag configure label -foreground gray40
    $d tag configure meta -foreground gray40
    $d tag configure value -font TkFixedFont
    $d tag configure help -font TkFixedFont -foreground gray25
    set e .settings.main.details.edit
    ttk::frame $e -padding {0 6 0 0}
    ttk::label $e.l -text "Value:"
    text $e.value -height 3 -width 40 -wrap none -font TkFixedFont -undo 1
    ttk::frame $e.b
    foreach {b label how scope} {
        local    "Set for this repository" set local
        global   "Set globally"            set global
        unlocal  "Unset here"              unset local
        unglobal "Unset globally"          unset global
    } {
        ttk::button $e.b.$b -text $label -command [list tksettings::change $how $scope]
        pack $e.b.$b -side left -padx {0 4}
    }
    grid $e.l -sticky w
    grid $e.value -sticky ew
    grid $e.b -sticky w -pady {4 0}
    grid columnconfigure $e 0 -weight 1
    grid $d .settings.main.details.y -sticky news
    grid $e - -sticky ew -padx 6 -pady {0 6}
    grid columnconfigure .settings.main.details 0 -weight 1
    grid rowconfigure .settings.main.details 0 -weight 1
    .settings.main add .settings.main.list -weight 2
    .settings.main add .settings.main.details -weight 3

    ttk::label .settings.status -textvariable tksettings::status -padding {6 2} -anchor w
    pack .settings.top -fill x
    pack .settings.status -side bottom -fill x
    pack .settings.main -fill both -expand 1

    bind $t <<TreeviewSelect>> {tksettings::showDetails [lindex [.settings.main.list.t selection] 0]}
    bind .settings <F5> tksettings::reload
    bind .settings <Control-f> {focus .settings.top.filter}
    popup::attach .settings.main.list.t tksettings::popupMenu
}

proc tksettings::setRepository {path newRoot} {
    variable repo $path
    variable root $newRoot
    wm title .settings "Settings \u2014 [file rootname [file tail $repo]]"
    reload
}

# The context menu of a setting: the buttons of its details (they set the
# value in the box there), and copying.
proc tksettings::popupMenu {m item} {
    set e .settings.main.details.edit.b
    foreach b {local global unlocal unglobal} { popup::button $m $e.$b }
    popup::separator $m
    popup::copy $m "Copy name" $item
    popup::copy $m "Copy value" [string trim [.settings.main.details.edit.value get 1.0 end]]
}
