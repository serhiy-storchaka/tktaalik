# Tickets: the details header and the Comments/Check-ins/Attachments tabs.
source [file join [file dirname [info script]] common.tcl]
set ::urls {}
proc tktsearch::openUrl {path} { lappend ::urls $path }
# A ticket with check-ins and comments, and one with attachments.
tktaalik::main tickets [list $T(repo) {checkins:>=3 comments:>=2 attachments:>=1}]
wm geometry . 1270x900+0+0
update
set t .tickets.main.list.t
set nb .tickets.main.details.nb
set h .tickets.main.details.head
set d $nb.comments.text
proc tabs {} { lmap tab [$::nb tabs] {list [$::nb tab $tab -text] [$::nb tab $tab -state]} }
set first [lindex [$t children {}] 0]
check "a ticket: $first" {$first ne ""}
$t selection set $first; update
puts "  tabs: [tabs]"
set nc [llength [$nb.checkins.tv children {}]]
set na [llength [$nb.attachments.tv children {}]]
check "tab labels have counts" {[lindex [tabs] 1 0] eq "Check-ins ($nc)" && [lindex [tabs] 2 0] eq "Attachments ($na)" && $nc >= 3 && $na >= 1}
check "header: title and fields, [$h cget -height] lines" {[string match "*Status: *" [$h get 1.0 end]] && [$h cget -height] >= 3}
lassign [$h dlineinfo "end - 1 char"] - ly - lh
check "header: the last line visible ([expr {$ly + $lh}] <= [winfo height $h])" {[$h dlineinfo "end - 1 char"] ne "" && $ly + $lh <= [winfo height $h]}
check "comments tab: cards, comment button" {[string match "*commented*" [$d get 1.0 end]] && [winfo exists $d.reply.add]}
check "no check-ins or attachments in the comments" {![string match "*mentioning this ticket*" [$d get 1.0 end]]}
$nb select $nb.checkins; update
check "check-ins table fills the tab: [winfo height $nb.checkins.tv] of [winfo height $nb.checkins]" {[winfo height $nb.checkins.tv] > [winfo height $nb.checkins] * 0.8}
set c [lindex [$nb.checkins.tv children {}] 0]
$nb.checkins.tv selection set $c; $nb.checkins.tv focus $c; focus -force $nb.checkins.tv; update; event generate $nb.checkins.tv <Return>; update
check "Return shows the check-in in the Timeline: [list $tktimeline::query]" {$tktaalik::active eq "timeline" && $tktimeline::query eq "hash:[string range $c 0 15]"}
tktaalik::show tickets; update
# A ticket without attachments: that tab disabled; the shown tab kept or reset.
$nb select $nb.attachments; update
set tktsearch::query {checkins:0 attachments:0 comments:>=1}; tktsearch::search; update
$t selection set [lindex [$t children {}] 0]; update
puts "  tabs: [tabs]"
check "empty tabs disabled" {[lindex [tabs] 1 1] eq "disabled" && [lindex [tabs] 2 1] eq "disabled"}
check "falls back to Comments" {[$nb select] eq "$nb.comments"}
# Back to the first: the tables refilled.
set tktsearch::query {checkins:>=3 comments:>=2 attachments:>=1}; tktsearch::search; update
$t selection set $first; update
check "refilled: [llength [$nb.checkins.tv children {}]]" {[llength [$nb.checkins.tv children {}]] == $nc}
# No ticket: everything empty.
$t selection set {}; update
check "nothing selected: empty" {[string trim [$h get 1.0 end]] eq "" && [llength [$nb.checkins.tv children {}]] == 0}
$t selection set $first; update
# An unposted comment is kept as a draft of its ticket.
$d.reply.add invoke; update
[formattext::widget .tickets.comment.f.editor] insert end "draft text"
tktsearch::closeComment; update
check "a draft: [$d.reply.note cget -text]" {[string match "*draft*" [$d.reply.note cget -text]]}
$t selection set [lindex [$t children {}] 1]; update
check "other ticket: no draft" {![string match "*draft*" [$d.reply.note cget -text]]}
$t selection set $first; update
$d.reply.add invoke; update
check "draft back: [formattext::get .tickets.comment.f.editor]" {[formattext::get .tickets.comment.f.editor] eq "draft text"}
[formattext::widget .tickets.comment.f.editor] delete 1.0 end
tktsearch::closeComment; update
# Alt+underlined letter switches the tab.
focus -force $nb; update
event generate $nb <Alt-i>; update
check "Alt+I: [$nb select]" {[$nb select] eq "$nb.checkins"}
event generate $nb <Alt-a>; update
check "Alt+A: [$nb select]" {[$nb select] eq "$nb.attachments"}
$nb select $nb.comments; update
# The header rewraps when narrower.
set before [$h cget -height]
wm geometry . 700x900; update; update
lassign [$h dlineinfo "end - 1 char"] - ly - lh
check "rewraps: $before -> [$h cget -height] lines, last visible" {[$h cget -height] > $before && [$h dlineinfo "end - 1 char"] ne "" && $ly + $lh <= [winfo height $h]}
wm geometry . 1270x900; update
$nb select $nb.attachments; update
$nb select $nb.comments; update
done
