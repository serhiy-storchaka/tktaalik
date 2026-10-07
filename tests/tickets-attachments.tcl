# Tickets: attachments: view, save, apply a patch (scratch checkout).
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
set ::boxes {}
set ::answers {yesno no}
proc tk_getSaveFile {args} { return $::T(tmp)/saved-[dict get $args -initialfile] }
set ::urls {}
proc tktsearch::openUrl {path} { lappend ::urls $path }
proc co {args} { fossilIn $::W/co {*}$args }
proc menuLabels {m} {
    set l {}
    for {set i 0} {$i <= [$m index end]} {incr i} {
        lappend l [expr {[$m type $i] eq "separator" ? "--" : "[$m entrycget $i -label]/[$m entrycget $i -state]"}]
    }
    return $l
}
proc rclick {tv item} {
    .tickets.main.details.nb select .tickets.main.details.nb.attachments; $tv see $item; update
    lassign [$tv bbox $item] x y
    event generate $tv <3> -x [expr {$x + 5}] -y [expr {$y + 5}] -rootx 300 -rooty 300
    update
    set l [menuLabels .tickets.attctx]
    tk::MenuUnpost .tickets.attctx
    return $l
}
tktaalik::main tickets [list $W/co id:595d72d0a6]
wm geometry . 1200x800+0+0
update
set d .tickets.main.details.nb.comments.text
set tv .tickets.main.details.nb.attachments.tv
check "a table: [$tv cget -columns]" {[winfo class $tv] eq "Treeview" && [$tv cget -columns] eq {file size user date comment}}
set rows [lmap i [$tv children {}] {$tv item $i -values}]
puts "  rows: $rows"
check "missing content: greyed, not local" {[llength [lmap i [$tv children {}] {if {"missing" in [$tv item $i -tags] && [$tv set $i size] eq "not local"} {set i} else continue}]] == 3}
set labels [rclick $tv [lindex [$tv children {}] end]]
check "menu of a missing one: $labels" {[lindex $labels 0] eq "View/disabled" && "Open in browser/normal" in $labels}
tktsearch::openAttachment [lindex [$tv children {}] 0]
check "double-click a missing one: the server, $::urls" {[string match "attachview?tkt=595d72d0a6*&file=*" [lindex $::urls end]]}
# a ticket with a patch that is here
tktsearch::setQuery id:34e934161e; update
set tv .tickets.main.details.nb.attachments.tv
set i [lindex [$tv children {}] 0]
check "size shown: [$tv item $i -values]" {[string match "*bytes" [$tv set $i size]] || [string match "* KB" [$tv set $i size]]}
set labels [rclick $tv $i]
check "menu: $labels" {$labels eq {View/normal Save…/normal {Apply to the checkout…/normal} -- {Open in browser/normal} {Copy file name/normal}}}
tktsearch::openAttachment $i; update
set w .diffview$diffview::count
check "double-click views it: [$w.status cget -text]" {[winfo exists $w] && [string match "1 file*" [$w.status cget -text]]}
destroy $w
.tickets.attctx invoke Save…; update
set src [lindex [tickets::sql "SELECT src FROM attachment WHERE filename='wish_manual.patch' AND isLatest"] 0 0]
exec fossil artifact -R $W/tk.fossil $src $T(tmp)/expected.patch
check "saved exactly" {[exec cmp $T(tmp)/saved-wish_manual.patch $T(tmp)/expected.patch] eq ""}
.tickets.attctx invoke "Apply to the checkout…"; update
check "apply: refused cleanly (already applied): [lindex $::boxes end]" {[string match "*does not apply*" [lindex $::boxes end]] && [co changes] eq ""}
done
