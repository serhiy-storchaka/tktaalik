# The Information window of a repository opened without a checkout: its
# checkouts (fossil info -v -R prints check-out lines) in their section;
# the statistics, the hash policy, the Fossil running; the quick check.
source [file join [file dirname [info script]] common.tcl]
tktaalik::main tickets [list $T(repo)]
update
tkinfo::window; update
set text [.info.text get 1.0 end]
set n [regexp -all -line {^check-out:} [lindex [fossil::run info -v -R $T(repo)] 1]]
check "fossil lists $n checkouts" {$n >= 0}
if {$n} {
    check "a Checkouts section, no raw check-out lines" {[string match "*\nCheckouts\n*" $text] && [string first "check-out\t" $text] < 0}
}
check "Statistics: compression, project age, SQLite" {[string match "*\nStatistics\n*Compression\t*" $text] && [string match "*Project age\t*" $text] && [string match "*SQLite\t*" $text]}
check "the hash policy: [regexp -inline -line {Hash policy\t.*} $text]" {[regexp -line {^Hash policy\t\S+} $text]}
check "the Fossil version: [tktaalik::fossilVersion]" {[string first "\nFossil\nVersion\t[tktaalik::fossilVersion]" $text] >= 0 && [regexp {^\d+\.\d+} [tktaalik::fossilVersion]]}
tkinfo::check; update
check "the quick check: $tkinfo::status" {$tkinfo::status eq "Database check: ok"}
done
