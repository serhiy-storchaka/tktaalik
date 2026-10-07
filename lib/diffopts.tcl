# The options of the diffs shown in the Commit and Stash tabs (the ones of
# "fossil diff" that change what is compared), in a menu of their own.

namespace eval diffopts {
    variable ignoreSpace 0      ;# -w: ignore all white space
    variable ignoreTrailing 0   ;# -Z: ignore white space at line ends
    variable stripCR 0          ;# --strip-trailing-cr
    variable invert 0           ;# --invert
    variable context ""         ;# -c N: lines of context ("" default, -1 all)
}

# The options for "fossil diff" (and "stash show", "patch diff"...).
proc diffopts::args {} {
    variable ignoreSpace
    variable ignoreTrailing
    variable stripCR
    variable invert
    variable context
    set result {}
    if {$ignoreSpace} { lappend result -w }
    if {$ignoreTrailing} { lappend result -Z }
    if {$stripCR} { lappend result --strip-trailing-cr }
    if {$invert} { lappend result --invert }
    if {$context ne ""} { lappend result -c $context }
    return $result
}

# Fill the menu M; COMMAND is run after a change.
proc diffopts::menu {m command} {
    $m add checkbutton -label "Ignore white space" -variable diffopts::ignoreSpace -command $command
    $m add checkbutton -label "Ignore white space at line ends" \
        -variable diffopts::ignoreTrailing -command $command
    $m add checkbutton -label "Ignore CR at line ends" -variable diffopts::stripCR -command $command
    $m add checkbutton -label "Inverted (new to old)" -variable diffopts::invert -command $command
    $m add separator
    foreach {label value} {"Default context" "" "No context" 0 "3 lines of context" 3
            "10 lines of context" 10 "Whole files" -1} {
        $m add radiobutton -label $label -value $value -variable diffopts::context -command $command
    }
}
