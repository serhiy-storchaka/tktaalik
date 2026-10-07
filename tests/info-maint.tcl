# The Information window: the login group, About Fossil (version -v), the
# verification's count (the artifacts checked), and the maintenance:
# repack and rebuild run, asked first.  On a small scratch repository.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set D $T(tmp)
exec fossil init $D/small.fossil
set ::boxes {}
set ::answers {yesnocancel no}
tktaalik::main tickets [list $D/small.fossil]
update
tkinfo::window; update
set text [.info.text get 1.0 end]
check "login group" {[string match "*Login group\t*" $text]}
tkinfo::aboutFossil; update
check "About Fossil: [lindex [split [.info.about.t get 1.0 end] \n] 0]" {[string match "*version*" [.info.about.t get 1.0 end]]}
destroy .info.about
# Verification: the count of the artifacts checked (not phantoms).
tkinfo::verify
waitUntil {$tkinfo::verifying eq ""}
set n [lindex [fossil::sql $D/small.fossil "SELECT count(*) FROM blob WHERE size>=0"] 0 0]
check "verified: $tkinfo::status (of $n)" {[string match "Verified: $n artifacts*" $tkinfo::status]}
# Repack, without a backup.
proc waitRun {} {
    after 100 {set ::tick 1}; vwait ::tick
    waitUntil {$::repoops::running eq ""}
    update
}
tkinfo::repack; waitRun
check "repack: [.repoopsRun.b.status cget -text]" {[.repoopsRun.b.status cget -text] eq "Done" && [.repoopsRun.b.stop instate disabled]}
check "asked first: [lindex $::boxes end-1]" {[lsearch -glob $::boxes "Repack *"] >= 0}
destroy .repoopsRun
# Rebuild: its options.
whenOpen .repoopsForm {
    array set ::repoops::f {backup 0 index Omit compress 1}
    set ::repoops::done ok
}
tkinfo::rebuild; waitRun
set shown [.repoopsRun.t get 1.0 end]
check "rebuild: [.repoopsRun.b.status cget -text], options shown" {[.repoopsRun.b.status cget -text] eq "Done" && [string match "*rebuild --noindex --compress*" $shown]}
done
