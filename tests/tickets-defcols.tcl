# Tickets: the default columns.
source [file join [file dirname [info script]] common.tcl]
tktaalik::main tickets [list $T(repo)]
update
set t .tickets.main.list.t
check "fresh: [$t cget -displaycolumns]" {[lindex [$t cget -displaycolumns] end] eq "updated" && [$t set [lindex [$t children {}] 0] updated] ne ""}
set tablecols::on($t,updated) 0; tablecols::toggle $t updated; update
tablecols::defaultColumns $t; update
check "Default columns brings it back" {"updated" in [$t cget -displaycolumns]}
if {$T(repo2) ne ""} {
    tktaalik::openPath $T(repo2); update
    check "tips: [$t cget -displaycolumns]" {"updated" in [$t cget -displaycolumns]}
} else {
    puts "skip another ticket schema (no TKTAALIK_REPO2)"
}
done
