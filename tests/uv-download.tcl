# Unversioned files, Download (uv revert): the question names the files to
# download (only those: no transfer noise) and says that files only here
# are removed; then they are those of the server.  On scratch copies.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set D $T(tmp)
set R $W/tk.fossil
# The "server": a copy with a file of its own.
file copy $R $D/server.fossil
set f [open $D/s.txt w]; puts $f server; close $f
exec fossil uv add $D/s.txt --as s.txt -R $D/server.fossil
# Here: a file only here.
set f [open $D/l.txt w]; puts $f local; close $f
exec fossil uv add $D/l.txt --as l.txt -R $R
exec fossil remote file://$D/server.fossil -R $R << ""
set ::asked {}
proc tkuv::confirm {message detail} { lappend ::asked $message $detail; return 1 }
tktaalik::main tickets [list $R]
update
tkuv::window; update
tkuv::download
after 100 {set ::tick 1}; vwait ::tick
waitUntil {$::repoops::running eq ""}
update
set detail [lindex $::asked 1]
check "asked: the file to download" {[string match "*Downloaded (1):*s.txt*" $detail]}
check "no transfer noise" {[string first Bytes $detail] < 0 && [string first "waiting for server" $detail] < 0 && [string first Sent: $detail] < 0}
check "says that files only here are removed" {[string match "*files that are only here are removed*" $detail]}
set names [lmap r [fossil::sql $R "SELECT name FROM unversioned WHERE hash IS NOT NULL ORDER BY 1"] {lindex $r 0}]
check "then those of the server: $names" {$names eq "s.txt"}
done
