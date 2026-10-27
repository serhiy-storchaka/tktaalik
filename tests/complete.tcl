# Completion in the search boxes: the keys as a word is typed, the values
# after "key:" and after a comma; Down, Up, Tab, Return, Escape, a click;
# Return without a choice searches as before.
source [file join [file dirname [info script]] common.tcl]
start timeline "" 1100x700
tktaalik::show timeline; update
set q .timeline.top.q
proc typeIn {e text} {
    $e delete 0 end
    focus -force $e; update
    foreach ch [split $text ""] {
        $e insert insert $ch
        set sym [expr {[dict exists {: colon , comma " " space - minus / slash . period} $ch]
            ? [dict get {: colon , comma " " space - minus / slash . period} $ch] : $ch}]
        event generate $e <KeyRelease> -keysym $sym
    }
    update
}
proc shown {e} { complete::shown $e }
proc items {e} { complete::labels $e }
# The icons of the list's rows (Tk 9): the names, "" for none.
proc icons {e} {
    set l $e.complete.l
    lmap item [$l children {}] {
        set image [$l item $item -image]
        set name ""
        dict for {key img} $::icons::images { if {$img eq $image} { set name [regsub -- {-[0-9]+$} $key ""] } }
        set name
    }
}
set tk9 [package vsatisfies [package provide Tk] 9]
proc key {e k} { focus -force $e; update; event generate $e $k; update }

typeIn $q us
check "a key typed: offered [list [items $q]]" {[shown $q] && [string match "user:*" [lindex [items $q] 0]]}
check "keys: no icons" {[lsort -unique [icons $q]] eq "{}"}
key $q <Tab>
check "Tab: the key, its values at once: [list [$q get]]" {[$q get] eq "user:" && [shown $q] && "@me" in [items $q]}
key $q <Escape>
check "Escape: closed, the text kept" {![shown $q] && [$q get] eq "user:"}
typeIn $q "kind:t"
check "values for the typed start: [list [items $q]]" {[items $q] eq {ticket tag technote}}
check "kinds: their icons (Tk 9 only): [list [icons $q]]" {
    [icons $q] eq [expr {$tk9 ? {k-ticket k-tag k-technote} : {{} {} {}}}]}
key $q <Down>
key $q <Down>
key $q <Return>
check "Down, Return: the chosen one: [list [$q get]]" {[$q get] eq "kind:tag" && ![shown $q]}
typeIn $q "kind:ci,w"
check "after a comma: [list [items $q]]" {[items $q] eq {wiki}}
key $q <Tab>
check "into the list: [list [$q get]]" {[$q get] eq "kind:ci,wiki"}
typeIn $q "-i"
check "a negated key: [list [items $q]]" {[llength [items $q]] >= 2 && [string match "in:*" [lindex [items $q] 0]]}
key $q <Tab>
check "kept the minus: [list [$q get]]" {[$q get] eq "-in:"}
key $q <Escape>
typeIn $q "is:mer"
key $q <Tab>
check "is:: [list [$q get]]" {[$q get] eq "is:merge"}
# A word that is no key: nothing; a value typed in full: nothing.
typeIn $q "zzz"
check "no key: no list" {![shown $q]}
typeIn $q "is:merge"
check "typed in full: no list" {![shown $q]}
# Return without a choice: the search, the list closed.
typeIn $q "branch:core-9-0-b"
check "branches: [lrange [items $q] 0 2]" {"core-9-0-branch" in [items $q]}
check "branches: the branch icon (Tk 9)" {[lsort -unique [icons $q]] eq [expr {$tk9 ? "k-branch" : "{}"}]}
set ::searched 0
rename tktimeline::search tktimeline::realSearch
proc tktimeline::search {args} { set ::searched 1; tktimeline::realSearch {*}$args }
key $q <Return>
check "Return without a choice: searched, closed" {$::searched && ![shown $q]}
rename tktimeline::search {}
rename tktimeline::realSearch tktimeline::search
# Ctrl+Space: all the keys.
$q delete 0 end
key $q <Control-space>
check "Ctrl+Space: all the keys ([llength [items $q]])" {[llength [items $q]] == [dict size [tktimeline::completion]]}
# A click.
set l $q.complete.l
set item [lindex [$l children {}] [lsearch -glob [items $q] "path:*"]]
$l see $item; update
waitUntil {[llength [$l bbox $item]]}
lassign [$l bbox $item] x y
event generate $l <ButtonRelease-1> -x [expr {$x + 4}] -y [expr {$y + 2}]
update
check "a click: [list [$q get]]" {[$q get] eq "path:"}
typeIn $q "path:generic/tkBu"
check "files: [lrange [items $q] 0 1]" {"generic/tkButton.c" in [items $q]}
check "files: the C icon (Tk 9)" {[lindex [icons $q] [lsearch [items $q] generic/tkButton.c]] eq [expr {$tk9 ? "a-c" : ""}]}
key $q <Escape>
# Escape with no list: the box's own (cleared).
key $q <Escape>
check "Escape with no list: cleared as before" {[$q get] eq ""}

# The other tabs.
tktaalik::show tickets; update
waitUntil {[winfo exists .tickets.top.q]}
set q .tickets.top.q
typeIn $q "stat"
check "tickets: state:, status: [list [items $q]]" {[lsearch -glob [items $q] "status:*"] >= 0 && [lsearch -glob [items $q] "state:*"] >= 0}
typeIn $q "status:"
check "tickets: the states [lrange [items $q] 0 5]" {[lsearch -nocase [items $q] open] >= 0 && [lsearch -nocase [items $q] closed] >= 0}
check "tickets: the status icons (Tk 9): [lrange [icons $q] 0 3]" {!$tk9 ||
    [lindex [icons $q] [lsearch -nocase [items $q] open]] eq "st-open"}
typeIn $q "type:B"
check "tickets: values listed as they are: [list [items $q]]" {"Bug" in [items $q]}
key $q <Tab>
check "tickets: put in the box in lower case: [list [$q get]]" {[$q get] eq "type:bug"}
typeIn $q "assignee:"
check "tickets: @me among the people" {[lindex [items $q] 0] eq "@me" && [llength [items $q]] > 1}
typeIn $q "version:"
check "tickets: version: the versions, newest first: [lrange [items $q] 0 4]" {
    [llength [items $q]] > 10 && [lsearch -regexp [items $q] {[^0-9.ab]}] < 0
    && [tickets::versionCompare [tickets::versionKey [lindex [items $q] 0]] [tickets::versionKey [lindex [items $q] end]]] > 0}
typeIn $q "version:8.6."
check "tickets: version:8.6.: [lrange [items $q] 0 2]" {[lindex [items $q] 0] eq [lindex [lsort -command {::apply {{a b} {
    tickets::versionCompare [tickets::versionKey $b] [tickets::versionKey $a]}}} [items $q]] 0] && [string match 8.6.* [lindex [items $q] 0]]}
typeIn $q "priority:"
check "tickets: priority icons (Tk 9): [lrange [icons $q] 0 3]" {!$tk9 || [string match pr-* [lindex [icons $q] 0]]}
typeIn $q "severity:"
check "tickets: severities by rank, not by name: [list [items $q]]" {
    [lsearch -nocase [items $q] minor] >= 0 && [lsearch -nocase [items $q] minor] < [lsearch -nocase [items $q] critical]
    && [lsearch -nocase [items $q] cosmetic] < [lsearch -nocase [items $q] minor]}
typeIn $q "is:"
check "tickets: is: states with icons, types without (Tk 9)" {!$tk9 ||
    ([lindex [icons $q] [lsearch [items $q] pending]] eq "st-pending" && [lindex [icons $q] [lsearch [items $q] bug]] eq "")}
typeIn $q "is:r"
check "tickets: is: [list [items $q]]" {[items $q] eq {rfe}}
key $q <Escape>
tktaalik::show branches; update
waitUntil {[winfo exists .branches.top.q]}
set q .branches.top.q
typeIn $q "merged:core-8-6-b"
check "branches: merged: [lrange [items $q] 0 1]" {"core-8-6-branch" in [items $q]}
key $q <Escape>
done
