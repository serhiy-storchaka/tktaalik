# Tickets: attaching files.  Fossil has no command for it: Tktaalik writes
# the attachment artifact (as Fossil's web page does) and brings it in with
# the file; Fossil crosslinks it.  On a scratch copy.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
set R $W/tk.fossil
proc bytes {path} { set f [open $path rb]; set d [read $f]; close $f; return $d }
proc writeBytes {path data} { set f [open $path wb]; puts -nonewline $f $data; close $f }
# A ticket without attachments.
set uuid [lindex [sql "SELECT tkt_uuid FROM ticket WHERE tkt_uuid NOT IN (SELECT target FROM attachment)
    ORDER BY tkt_mtime DESC LIMIT 1" $R] 0 0]
proc rows {} {
    sql "SELECT filename, coalesce(comment,''), user, src FROM attachment
        WHERE target='$::uuid' AND isLatest AND src<>'' ORDER BY filename" $::R
}
# Two files: text with CR/LF and a byte that is not UTF-8; a patch.
writeBytes $T(tmp)/notes.txt "line one\r\nline \xff two\r\n"
writeBytes $T(tmp)/fix.patch "--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b\n"
start tickets $R
tktsearch::setQuery id:[string range $uuid 0 9]; update
waitUntil {$tktsearch::shownTicket eq $uuid}
set nb .tickets.main.details.nb
check "the Attachments tab usable without any: [$nb tab $nb.attachments -text]" \
    {[$nb tab $nb.attachments -state] eq "normal" && [$nb tab $nb.attachments -text] eq "Attachments (0)"}
check "an Attach button there" {[winfo exists $nb.attachments.bar.attach]}
$nb select $nb.attachments; update
check "the scrollbar as wide as it asks: [winfo width $nb.attachments.y]" \
    {[winfo width $nb.attachments.y] == [winfo reqwidth $nb.attachments.y]}
.tickets.menu.ticket invoke 0; destroy .tickets.new
tktsearch::ticketMenu .tickets.menu.ticket
check "in the Ticket menu: [.tickets.menu.ticket entrycget {Attach files*} -state]" \
    {[.tickets.menu.ticket entrycget "Attach files*" -state] eq "normal"}

# Cancelled: nothing written.
set ::openFrom [list $T(tmp)/notes.txt $T(tmp)/fix.patch]
whenOpen .tickets.attach {set ::ui::done cancel}
tktsearch::attachFiles $uuid
check "cancelled: none" {![llength [rows]]}

# Attached, with a comment.
whenOpen .tickets.attach {set ::ui::f(comment) "Two files"; set ::ui::done ok}
tktsearch::attachFiles $uuid
set r [rows]
check "attached: [lmap x $r {lrange $x 0 2}]" {[llength $r] == 2 && [lindex $r 0 0] eq "fix.patch"
    && [lindex $r 1 0] eq "notes.txt" && [lindex $r 1 1] eq "Two files" && [lindex $r 1 2] eq $::tickets::me}
lassign [fossil::run artifact -R $R [lindex $r 1 3] $T(tmp)/got] code out
check "the content byte for byte" {!$code && [bytes $T(tmp)/got] eq [bytes $T(tmp)/notes.txt]}
set tv $nb.attachments.tv
check "listed: [lmap i [$tv children {}] {$tv set $i file}]" \
    {[lsort [lmap i [$tv children {}] {$tv set $i file}]] eq {fix.patch notes.txt}}
check "the tab counts them: [$nb tab $nb.attachments -text]" {[$nb tab $nb.attachments -text] eq "Attachments (2)"}
check "found by has:attachments" {[llength [::tickets::sql "SELECT 1 FROM attachment WHERE target='$uuid'"]] == 2}
# The control artifact as Fossil writes it: A, C, D, U, Z.
set ctl [lindex [sql "SELECT b.uuid FROM attachment a JOIN blob b ON b.rid=a.attachid
    WHERE a.target='$uuid' AND a.filename='notes.txt'" $R] 0 0]
lassign [fossil::run artifact -R $R $ctl] code text
check "its cards: [string map {\n { | }} $text]" {[regexp "^A notes.txt $uuid \[0-9a-f\]+\nC Two\\\\sfiles\nD \[0-9-\]+T\[0-9:.\]+\nU \\S+\nZ \[0-9a-f\]{32}$" $text]}

# In the Timeline, the attachment is a change of its ticket.
tktaalik::show timeline; update
waitUntil {[llength [.timeline.main.list.t children {}]]}
set tl [lindex [lmap id [.timeline.main.list.t children {}] {
    if {[string match "$ctl*" [dict get $tktimeline::rows($id) uuid]]} {set id} else continue}] 0]
check "the Timeline row has its ticket: [expr {$tl eq "" ? "" : [dict get $tktimeline::rows($tl) ticket]}]" \
    {$tl ne "" && [dict get $tktimeline::rows($tl) ticket] eq $uuid}
tktaalik::show tickets; update

# The same name again: replaces it, said first.
writeBytes $T(tmp)/notes.txt "newer\n"
set ::openFrom [list $T(tmp)/notes.txt]
set ::intro ""
whenOpen .tickets.attach {set ::intro [.tickets.attach.f.intro cget -text]; set ::ui::done ok}
tktsearch::attachFiles $uuid
check "the question names it: $::intro" {[string match "*Replaces notes.txt*" $::intro]}
set r [rows]
lassign [fossil::run artifact -R $R [lindex $r 1 3]] code out
check "replaced: the newest is listed" {[llength $r] == 2 && $out eq "newer"}

# Deleted (the context menu's Delete...): no longer listed; a record
# without content, the file still in the repository.
set src [lindex [rows] 0 3]
set ::answers [dict create okcancel cancel]
tktsearch::deleteAttachment $uuid fix.patch
check "Cancel: still there" {[llength [rows]] == 2}
set ::answers [dict create okcancel ok]
set ::boxes {}
tktsearch::deleteAttachment $uuid fix.patch
check "asked first: [lindex $::boxes end]" {[string match "Delete the attachment fix.patch of the ticket*" [lindex $::boxes end]]}
check "deleted: [lmap x [rows] {lindex $x 0}]" {[lmap x [rows] {lindex $x 0}] eq "notes.txt"}
check "the tab follows: [$nb tab $nb.attachments -text]" {[$nb tab $nb.attachments -text] eq "Attachments (1)"}
check "the file still in the repository" {[llength [sql "SELECT 1 FROM blob WHERE uuid='$src'" $R]]}
set del [lindex [sql "SELECT b.uuid FROM attachment a JOIN blob b ON b.rid=a.attachid
    WHERE a.target='$uuid' AND a.filename='fix.patch' AND a.isLatest" $R] 0 0]
lassign [fossil::run artifact -R $R $del] code text
check "its cards: [string map {\n { | }} $text]" {[regexp "^A fix.patch $uuid\nD \[0-9-\]+T\[0-9:.\]+\nU \\S+\nZ \[0-9a-f\]{32}$" $text]}
set tv $nb.attachments.tv
$nb select $nb.attachments; update
set item [lindex [$tv children {}] 0]
$tv see $item; update
lassign [$tv bbox $item] x y
set ::posted ""
proc tk_popup {m args} { set ::posted $m }
event generate $tv <3> -x [expr {$x + 5}] -y [expr {$y + 3}] -rootx 10 -rooty 10; update
check "Delete... in the context menu" {$::posted ne "" && ![catch {$::posted index "Delete\u2026"}]}

# A file that looks like an artifact: refused.
writeBytes $T(tmp)/art.txt "D 2020-01-01T00:00:00\nZ 0123456789abcdef0123456789abcdef\n"
set ::openFrom [list $T(tmp)/art.txt]
set ::boxes {}
tktsearch::attachFiles $uuid
check "refused: [lindex $::boxes end]" {[string match "art.txt cannot be attached*" [lindex $::boxes end]] && [llength [rows]] == 1}
done
