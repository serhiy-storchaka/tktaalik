# The windows of the Repository menu: Information, Users, Remotes (and
# Settings, see settings.tcl); the changes on a scratch copy.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set ::boxes {}
set ::answer ok
proc tktsearch::browse {url} { lappend ::browsed $url }
start tickets $W/tk.fossil 1200x800

# The menu, in every tab, before Help.
proc labels {} {
    set r {}
    for {set i 0} {$i <= [.menubar index end]} {incr i} { lappend r [.menubar entrycget $i -label] }
    return $r
}
set ok 1
foreach tab {timeline tickets branches tags files commit stash wiki forum search} {
    if {[.nb tab .$tab -state] eq "disabled"} continue
    tktaalik::show $tab; update
    set l [labels]
    set r [lsearch -exact $l Repository]
    set h [lsearch -exact $l Help]
    if {$r < 0 || ($h >= 0 && $r != $h - 1) || ($h < 0 && $r != [llength $l] - 1)} { set ok 0; puts "  $tab: $l" }
}
check "Repository menu in every tab, before Help" {$ok}
set m .menubar.repository
set entries {}
for {set i 0} {$i <= [$m index end]} {incr i} {
    if {[$m type $i] eq "command"} { lappend entries [$m entrycget $i -label] }
}
# (The windows first; then the operations on the repository.)
check "its entries: $entries" {[llength $entries] >= 5 && [string match Information* [lindex $entries 0]] && [string match Remotes* [lindex $entries 3]]}
check "no Settings tab" {".settings" ni [.nb tabs]}

# Information.
tkinfo::window; update
set text [.info.text get 1.0 end]
check "Information: project and counts" {[string match "*project-name*Tk Source Code*Contents*Check-ins*Tickets*Wiki pages*" $text]}
check "Information: title" {[string match "Information*tk" [wm title .info]]}

# Users.
tkusers::window; update
set t .users.main.list.t
set default $tkusers::default
check "Users: the default user ($default) marked and selected" {$default ne "" && [string match "*$default" [$t set $default login]] && [$t selection] eq $default}
check "Users: special users greyed" {"special" in [$t item nobody -tags]}
$t selection set developer; update
set d [.users.main.details.text get 1.0 end]
check "developer: capabilities explained" {[string match "developer*Check in*" $d]}
check "Make default: off for special users" {[.users.b.default instate disabled]}
set other ""
foreach login [$t children {}] { if {$login ni $tkusers::special && $login ne $default} { set other $login; break } }
if {$other ne ""} {
    $t selection set $other; update
    set d [.users.main.details.text get 1.0 end]
    check "$other: inherits from nobody/anonymous" {[string match "*Also, from \"*" $d] || [dict get $tkusers::users($other) cap] ne ""}
    set ::boxes {}
    set ::answer cancel
    tkusers::makeDefault; update
    check "cancelled: still $default" {$tkusers::default eq $default && [llength $::boxes] == 1}
    set ::answer ok
    tkusers::makeDefault; update
    check "made default: $other" {$tkusers::default eq $other && [string trim [exec fossil user default -R $W/tk.fossil]] eq $other}
    tkusers::makeDefault; update
    exec fossil user default $default -R $W/tk.fossil
    tkusers::reload; update
}

# Remotes.
exec fossil remote https://example.invalid/tk -R $W/tk.fossil
tkremotes::window; update
set r .remotes.list.t
check "Remotes: the default" {[$r children {}] eq "default" && [$r set default url] eq "https://example.invalid/tk"}
# Add: the dialog filled in as the user would.
whenOpen .remotes.add {
    set tkremotes::addName mirror
    set tkremotes::addUrl https://mirror.invalid/tk
    set tkremotes::addDone ok
}
set ::answer ok
tkremotes::add; update
check "added: mirror" {[$r exists mirror] && [$r set mirror url] eq "https://mirror.invalid/tk"}
whenOpen .remotes.add {
    set tkremotes::addName mirror
    set tkremotes::addUrl https://other.invalid/
    set tkremotes::addDone ok
    after 300 { set tkremotes::addDone cancel }
}
set ::boxes {}
tkremotes::add; update
check "same name again: refused ([lindex $::boxes 0])" {[string match "*already*" [lindex $::boxes 0]]}
$r selection set mirror; update
tkremotes::makeDefault; update
check "mirror is the default" {[$r set default url] eq "https://mirror.invalid/tk"}
tkremotes::off; update
check "no default" {![$r exists default] && [$r exists mirror]}
$r selection set mirror; update
tkremotes::browse
check "browse: [lindex $::browsed end]" {[lindex $::browsed end] eq "https://mirror.invalid/tk"}
tkremotes::delete; update
check "deleted: mirror" {![$r exists mirror]}

# Another repository: the open windows follow.
tktaalik::openPath $T(repo); update
check "windows follow: [file tail $tkusers::repo]" {$tkusers::repo eq [file normalize $T(repo)] && $tkremotes::repo eq [file normalize $T(repo)] && $tkinfo::repo eq [file normalize $T(repo)]}
done
