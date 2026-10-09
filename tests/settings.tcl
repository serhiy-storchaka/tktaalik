# The Settings window: setting and unsetting (scratch copy).
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set ::boxes {}
proc tk_messageBox {args} {
    lappend ::boxes "[dict get $args -message] | [dict get [dict merge {-detail {}} $args] -detail]"
    return ok
}
proc co {args} { fossilIn $::W/co {*}$args }
# a global value and a local multi-line one, set with the command line
co settings --global proxy http://example.invalid:3128
co settings ignore-glob "*.o\n*.so"
tktaalik::main tickets [list $W/co]
tksettings::window
wm geometry . 1200x800+0+0
update
set t .settings.main.list.t
puts "status: $tksettings::status  title: [wm title .]"
check "all settings: [llength [$t children {}]]" {[llength [$t children {}]] == [array size tksettings::settings] && [llength [$t children {}]] > 80}
check "autosync: local off" {[$t set autosync from] eq "local" && [$t set autosync value] eq "off"}
check "proxy: global" {[$t set proxy from] eq "global" && [$t set proxy global] eq "http://example.invalid:3128"}
check "ignore-glob: versioned, local has 2 lines" {[$t set ignore-glob from] eq "versioned" && [dict get $tksettings::settings(ignore-glob) local] eq "*.o\n*.so"}
check "default: case-sensitive" {[$t set case-sensitive from] eq "default"}
set tksettings::onlySet 1; tksettings::showList; update
check "only the set ones: [$t children {}]" {[llength [lmap n [$t children {}] {if {[$t set $n from] eq "default"} {set n} else continue}]] == 0 && [lsort [$t children {}]] eq [lsort [lmap n [array names tksettings::settings] {if {[tksettings::origin $tksettings::settings($n)] eq "default"} continue; set n}]] && "proxy" in [$t children {}]}
set tksettings::onlySet 0; set tksettings::filter glob; after 400 {set ::w 1}; vwait ::w
check "filter: [llength [$t children {}]]" {[llength [$t children {}]] > 3 && [llength [lsearch -all -inline -not [$t children {}] *glob*]] == 0}
set tksettings::filter ""; after 400 {set ::w 1}; vwait ::w
# details
$t selection set autosync; update
set h [.settings.main.details.help get 1.0 end]
check "help shown: [string range [string map {\n |} $h] 0 100]" {[string match "autosync*In effect: the value for this repository*This setting determines when autosync occurs*" $h]}
check "value to edit: off" {[string trim [.settings.main.details.edit.value get 1.0 end]] eq "off"}
check "buttons: unset here on, unset globally off" {![.settings.main.details.edit.b.unlocal instate disabled] && [.settings.main.details.edit.b.unglobal instate disabled]}
$t selection set ignore-glob; update
set h [.settings.main.details.help get 1.0 end]
check "versioned: the file is shown" {[string match "*Versioned: .fossil-settings/ignore-glob*macosx/configure*" $h]}
# set locally
$t selection set localauth; update
.settings.main.details.edit.value delete 1.0 end
.settings.main.details.edit.value insert end 0
.settings.main.details.edit.b.local invoke; update
check "set locally: [co settings localauth]" {[string match "*(local)*0" [co settings localauth]] && [$t set localauth from] eq "local"}
check "asked first: [lindex $::boxes end]" {[string match "Set localauth for tk.fossil?*" [lindex $::boxes end]]}
# set globally (in the scratch home)
.settings.main.details.edit.value delete 1.0 end
.settings.main.details.edit.value insert end 1
.settings.main.details.edit.b.global invoke; update
check "global file named: [lindex $::boxes end]" {[string match "*for all repositories (in $::env(FOSSIL_HOME)/.fossil)*" [lindex $::boxes end]]}
check "set globally: [dict get $tksettings::settings(localauth) global]" {[dict get $tksettings::settings(localauth) global] eq "1" && [$t set localauth from] eq "local"}
# unset both
.settings.main.details.edit.b.unlocal invoke; update
check "unset here: global in effect" {[$t set localauth from] eq "global"}
.settings.main.details.edit.b.unglobal invoke; update
check "unset globally: default" {[$t set localauth from] eq "default"}
# autosync on: warned
$t selection set autosync; update
.settings.main.details.edit.value delete 1.0 end
.settings.main.details.edit.value insert end on
.settings.main.details.edit.b.local invoke; update
check "autosync on warned" {[string match "*Fossil pushes after commits*" [lindex $::boxes end]]}
co settings autosync off
# empty value refused
$t selection set localauth; update
.settings.main.details.edit.value delete 1.0 end
.settings.main.details.edit.b.local invoke; update
check "empty refused" {[string match "The value is empty.*" [lindex $::boxes end]]}
# a multi-line value round trip
$t selection set clean-glob; update
.settings.main.details.edit.value insert end "*.tmp\n*.bak"
.settings.main.details.edit.b.local invoke; update
check "multi-line set: [string map {\n |} [dict get $tksettings::settings(clean-glob) local]]" {[dict get $tksettings::settings(clean-glob) local] eq "*.tmp\n*.bak"}
# the repository only
tktaalik::openPath $W/tk.fossil; update
check "without a checkout: ignore-glob local, not versioned" {[$t set ignore-glob from] eq "local"}
done
