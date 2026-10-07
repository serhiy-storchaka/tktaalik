# Non-ASCII text from escapes: help, separators, arrows, emoji.
source [file join [file dirname [info script]] common.tcl]
proc u8 {s} { encoding convertfrom utf-8 $s }
tktaalik::main branches [list $T(repo)]
update
# The manual (UTF-8 files) in its window.
help::show branches; update
set help [.help.main.text get 1.0 end]
check "the manual: check mark, half circle, triangle" {[string first [u8 "\xe2\x9c\x93"] $help] >= 0 && [string first [u8 "\xe2\x97\x90"] $help] >= 0 && [string first [u8 "\xe2\x96\xb8"] $help] >= 0 && [string first "\\u" $help] < 0}
# The help buttons of the searches: the manual, at the search syntax.
set ok 1
foreach tab {timeline tickets branches stash search} {
    # (Stash needs a checkout: not here.)
    if {![tktaalik::show $tab]} continue
    update
    wm withdraw .help
    .$tab.top.help invoke; update
    if {![winfo ismapped .help] || $help::page ne $tab || $help::shownId ne "$tab#search-syntax"} { set ok 0; puts "  $tab: $help::page $help::shownId" }
}
check "help buttons open the manual's search syntax" {$ok}
check "status separator" {[string first [u8 "\xc2\xb7"] $tkbranches::status] >= 0}
check "sort arrow in heading: [.branches.main.list.t heading updated -text]" {[.branches.main.list.t heading updated -text] eq [u8 "Updated \xe2\x96\xbc"]}
# The emoji of the Tk 8.6 fallback, as UTF-8 decoded.
check "emoji: [tktsearch::sign priority 9] [tktsearch::sign severity critical] [tktsearch::sign state open]" {[tktsearch::sign priority 9] eq [u8 "\xf0\x9f\x9a\xa8"] && [tktsearch::sign severity critical] eq [u8 "\xf0\x9f\x9b\x91"] && [tktsearch::sign state open] eq [u8 "\xf0\x9f\x94\xb5"] && [tktsearch::sign state closed fixed] eq [u8 "\xe2\x9c\x94"]}
check "joinValues: [tktsearch::joinValues Closed Fixed]" {[tktsearch::joinValues Closed Fixed] eq [u8 "Closed \xc2\xb7 Fixed"]}
check "window title dash: [wm title .]" {[string first [u8 "\xe2\x80\x94"] [wm title .]] >= 0}
done
