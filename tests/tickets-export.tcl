# Ticket reports: the results saved as a file, tab-separated or CSV.
source [file join [file dirname [info script]] common.tcl]
tktaalik::main tickets [list $T(repo)]
update
ticketreports::window; update
set l .reports.main.list
set k [lsearch -glob [$l get 0 end] "4. *"]
$l selection clear 0 end; $l selection set $k
event generate $l <<ListboxSelect>>; update
set n [llength [.reports.main.out.t children {}]]
foreach ext {tsv csv} {
    set file $T(tmp)/report.$ext
    set ::saveTo $file
    ticketreports::save
    set f [open $file]; fconfigure $f -encoding utf-8; set text [read $f]; close $f
    set lines [split [string trimright $text \n] \n]
    set head [lindex $lines 0]
    check "$ext: [expr {[llength $lines] - 1}] rows of $n, header [string range $head 0 40]" {[llength $lines] - 1 == $n && [string match "#*" $head]}
}
check "csv: commas, quoted where needed" {[string match "#,*" [lindex [split $text \n] 0]]}
check "status: $ticketreports::status" {[string match "Saved $n rows*" $ticketreports::status]}
done
