# The Wiki tab: deleted pages (hidden unless "Show deleted", as in
# fossil wiki list --all) and the Technote ID column (scratch copy).
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set R $W/tk.fossil
set f [open $T(tmp)/text w]; puts $f "Some text."; close $f
set f [open $T(tmp)/empty w]; close $f
exec fossil wiki create "Gone Page" $T(tmp)/text -R $R
exec fossil wiki commit "Gone Page" $T(tmp)/empty -R $R
exec fossil wiki create "A Note" $T(tmp)/text --technote "2026-10-01 12:00:00" -R $R
set id [string range [lindex [fossil::sql $R "SELECT tagname FROM tag WHERE tagname GLOB 'event-*'"] 0 0] 6 end]
tktaalik::main tickets [list $R]
update
tktaalik::show wiki; update
set t .wiki.main.list.t
check "deleted page hidden by default" {![$t exists "wiki-Gone Page"]}
check "status says so: $tkwiki::status" {[string match "*1 deleted not shown*" $tkwiki::status]}
.wiki.top.deleted invoke; update
check "Show deleted: shown, greyed" {[$t exists "wiki-Gone Page"] && "deleted" in [$t item "wiki-Gone Page" -tags] && [string match "*(deleted)" [$t set "wiki-Gone Page" title]]}
$t selection set [list "wiki-Gone Page"]; update
check "its text: empty" {[string match "(empty*" [.wiki.main.page.text get 1.0 end]]}
.wiki.top.deleted invoke; update
check "hidden again" {![$t exists "wiki-Gone Page"]}
# The technote and its ID.
check "Technote ID column hidden by default" {"id" ni [$t cget -displaycolumns]}
set tablecols::on($t,id) 1; tablecols::toggle $t id; update
check "shown on request" {"id" in [$t cget -displaycolumns]}
check "the technote's ID: [$t set event-$id id]" {$id ne "" && [$t set event-$id id] eq $id && [$t set event-$id title] eq "A Note"}
check "pages have none" {[$t set "wiki-Migrating scripts to Tk 9" id] eq ""}
done
