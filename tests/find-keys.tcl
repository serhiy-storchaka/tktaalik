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

# In text and entry fields: Ctrl+A selects all; Tk's Ctrl+F, Ctrl+/ and
# Ctrl+Shift+P do nothing there (Tktaalik's keys).
toplevel .tk
text .tk.t; ttk::entry .tk.e; pack .tk.t .tk.e
.tk.t insert 1.0 "one\ntwo"; .tk.e insert 0 "words here"
proc key {w k} { focus -force $w; update; event generate $w $k; update }
.tk.t mark set insert 2.1
key .tk.t <Control-a>
check "text Ctrl+A: all selected" {[.tk.t get sel.first sel.last] eq "one\ntwo\n" || [.tk.t get sel.first sel.last] eq "one\ntwo"}
.tk.t tag remove sel 1.0 end; .tk.t mark set insert 1.1
key .tk.t <Control-f>
check "text Ctrl+F: the cursor stays ([.tk.t index insert])" {[.tk.t index insert] eq "1.1"}
key .tk.t <Control-slash>
check "text Ctrl+/: nothing selected" {![llength [.tk.t tag ranges sel]]}
.tk.t mark set insert 2.1
key .tk.t <Control-P>
check "text Ctrl+Shift+P: nothing selected, the cursor stays" {![llength [.tk.t tag ranges sel]] && [.tk.t index insert] eq "2.1"}
.tk.e icursor 3; .tk.e selection clear
key .tk.e <Control-a>
check "entry Ctrl+A: all selected" {[.tk.e selection present] && [.tk.e index sel.first] == 0 && [.tk.e index sel.last] == 10}
.tk.e selection clear; .tk.e icursor 3
key .tk.e <Control-f>
check "entry Ctrl+F: the cursor stays" {[.tk.e index insert] == 3}
destroy .tk
done
