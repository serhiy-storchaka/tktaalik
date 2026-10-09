# The Users window: a new user, a user's contact, capabilities and
# password, the default user unset and how it is determined; on a scratch
# copy.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set ::boxes {}
set ::answer ok
set R $W/tk.fossil
tktaalik::main tickets [list $R]
update
tkusers::window; update
set t .users.main.list.t
proc row {login} { lindex [fossil::sql $::R "SELECT cap, coalesce(info,''), pw FROM user WHERE login='$login'"] 0 }
set me $tkusers::default
# (Unset default: Fossil 2.26 and newer only.)
check "default from the repository: $tkusers::status" {$me ne "" && $tkusers::defaultFrom eq "repository" && [string match "*(from repository)" $tkusers::status] && [.users.b.unset instate [expr {[tkusers::newDefault] ? "!disabled" : "disabled"}]]}

# A new user: the form filled in as the user would.
# (Then OK; Cancel if the form stays open, as after a refusal.)
set ::gen 0
proc fill {script} {
    set g [incr ::gen]
    after 300 [list apply [list {} "$script; set tkusers::form(done) ok
        after 300 {if {\$::gen == $g} {set tkusers::form(done) cancel}}"]]
}
fill {
    set tkusers::form(login) "bad name"
}
set ::boxes {}
tkusers::edit ""; update
check "a bad name refused: [lindex $::boxes 0]" {[string match "The user name*" [lindex $::boxes 0]] && ![llength [row bad]]}
fill {
    set tkusers::form(login) qtester
    set tkusers::form(info) "Q Tester <q@example.invalid>"
    set tkusers::form(pw) one
    set tkusers::form(pw2) two
}
set ::boxes {}
tkusers::edit ""; update
check "passwords differ: [lindex $::boxes 0]" {[lindex $::boxes 0] eq "The two passwords differ." && ![llength [row qtester]]}
fill {
    set tkusers::form(login) qtester
    set tkusers::form(info) "Q Tester <q@example.invalid>"
    set tkusers::form(pw) secret
    set tkusers::form(pw2) secret
    foreach k [array names tkusers::form cap,*] { set tkusers::form($k) 0 }
    set tkusers::form(cap,o) 1
    set tkusers::form(cap,i) 1
    set tkusers::form(cap,2) 1
}
set ::boxes {}
tkusers::edit ""; update
lassign [row qtester] cap info pw
check "created: caps $cap, contact $info, asked [lindex $::boxes 0]" {$cap eq "io2" && $info eq "Q Tester <q@example.invalid>" && $pw ne "" && $pw ne "secret" && [lindex $::boxes 0] eq "Create the user qtester?"}
check "shown, selected" {[$t exists qtester] && [$t selection] eq "qtester"}

# Edit: contact and capabilities; the password unchanged when empty.
fill {
    set tkusers::form(info) "Q <new@example.invalid>"
    set tkusers::form(cap,i) 0
    set tkusers::form(cap,k) 1
}
tkusers::edit qtester; update
lassign [row qtester] cap2 info2 pw2
check "edited: $cap2, $info2, password kept" {$cap2 eq "ko2" && $info2 eq "Q <new@example.invalid>" && $pw2 eq $pw}
fill { set tkusers::form(pw) other; set tkusers::form(pw2) other }
tkusers::edit qtester; update
check "new password" {[lindex [row qtester] 2] ni [list $pw ""]}
# Cancelled at the confirmation: nothing changes.
set ::answer cancel
fill { set tkusers::form(info) "Nobody" }
tkusers::edit qtester; update
set ::answer ok
check "cancelled: contact kept" {[lindex [row qtester] 1] eq "Q <new@example.invalid>"}

# Unset the default user, then make it the default again (Fossil 2.26 and
# newer: older ones cannot unset it).
if {![tkusers::newDefault]} done
tkusers::unsetDefault; update
check "unset: [string trim [lindex [fossil::run user default -v -R $R] 1]]" {$tkusers::defaultFrom ne "repository" && [.users.b.unset instate disabled]}
$t selection set [list $me]; update
check "Make default enabled for $me again" {[.users.b.default instate !disabled]}
tkusers::makeDefault; update
check "default again: $tkusers::default" {$tkusers::default eq $me && $tkusers::defaultFrom eq "repository"}
done
