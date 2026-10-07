# The settings files of Tktaalik: one Tcl dict per file in
# ~/.config/tktaalik/ ($XDG_CONFIG_HOME/tktaalik/ if that is set).
#
#   config::path NAME                 the file NAME.conf there
#   config::get FILE NAME ?OLD...?    the dict in FILE, {} if none; if FILE
#                                     is the default one for NAME and does
#                                     not exist yet, the first of the OLD
#                                     files (in ~/.config, from before the
#                                     settings moved) that does
#   config::put FILE DICT ?NESTED?    write it, making the directory: one
#                                     key per line, and the values of the
#                                     NESTED keys (dicts) one key per line
#                                     too, indented.  It reads back the same.

namespace eval config {}

proc config::dir {} {
    set base [expr {[info exists ::env(XDG_CONFIG_HOME)] && $::env(XDG_CONFIG_HOME) ne ""
        ? $::env(XDG_CONFIG_HOME) : [file join $::env(HOME) .config]}]
    file join $base tktaalik
}

proc config::path {name} {
    file join [dir] $name.conf
}

proc config::get {file name args} {
    if {![file exists $file] && $file eq [path $name]} {
        foreach old $args {
            set old [file join [file dirname [dir]] $old]
            if {[file exists $old]} {
                set file $old
                break
            }
        }
    }
    if {[catch {
        set f [open $file]
        set dict [read $f]
        close $f
        dict size $dict
    }]} {
        return {}
    }
    return $dict
}

proc config::put {file dict {nested {}}} {
    set text ""
    dict for {key value} $dict {
        append text [list $key] " "
        if {$key in $nested && ![catch {dict size $value}] && [dict size $value]} {
            append text "\{\n"
            dict for {k v} $value { append text "    " [list $k $v] \n }
            append text "\}\n"
        } else {
            append text [list $value] \n
        }
    }
    catch {
        file mkdir [file dirname $file]
        set f [open $file w]
        puts -nonewline $f $text
        close $f
    }
}
