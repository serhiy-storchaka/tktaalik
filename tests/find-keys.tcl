# Ctrl+F and Ctrl+/ (as on GitHub) go to the search or filter box of every
# tab, its text selected, from wherever the focus is in the tab; also in
# Settings and the manual's window.
source [file join [file dirname [info script]] common.tcl]
need scratch
start timeline $T(scratch)/co 1000x700
proc tryKeys {label box} {
    foreach key {<Control-f> <Control-slash>} {
        $box delete 0 end
        $box insert 0 text
        $box selection clear
        focus -force .
        update
        event generate [focus] $key
        update
        check "$label $key: [focus]" {[focus] eq $box && [$box selection present]}
    }
}
foreach {tab box} {
    timeline .timeline.top.q
    tickets .tickets.top.q
    branches .branches.top.q
    tags .tags.top.filter
    files .files.top.filter
    wiki .wiki.top.filter
    forum .forum.top.filter
    search .search.top.q
    stash .stash.top.q
} {
    tktaalik::show $tab; update
    waitUntil {[winfo ismapped $box]}
    tryKeys $tab $box
}

tksettings::window; update
waitUntil {[winfo exists .settings.top.filter] && [winfo ismapped .settings.top.filter]}
foreach key {<Control-f> <Control-slash>} {
    focus -force .settings; update
    event generate [focus] $key; update
    check "settings $key: [focus]" {[focus] eq ".settings.top.filter"}
}
destroy .settings
done
