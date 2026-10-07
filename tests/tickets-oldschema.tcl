# Comments on old ticket schemas (no icomment): appended to the "comment"
# field ("fossil ticket set UUID +comment"); on a scratch copy.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set R $W/tk.fossil
catch {exec fossil sql -R $R "ALTER TABLE ticketchng DROP COLUMN icomment"}
set ::boxes {}
tktaalik::main tickets [list $R]
update
set uuid [lindex [fossil::sql $R "SELECT tkt_uuid FROM ticket ORDER BY tkt_mtime DESC LIMIT 1"] 0 0]
tktsearch::showTicket $uuid; update
check "a comment button without icomment" {[winfo exists .tickets.main.details.nb.comments.text.reply.add]}
tktsearch::commentDialog $uuid; update
set box [formattext::widget .tickets.comment.f.editor]
check "the format: wiki, not chosen" {[formattext::mimetype .tickets.comment.f.editor] eq "text/x-fossil-wiki" && [winfo class .tickets.comment.f.editor.top.format] eq "TLabel"}
check "the fields: [dict keys [tktsearch::commentFields x]]" {"+comment" in [dict keys [tktsearch::commentFields x]] && "icomment" ni [dict keys [tktsearch::commentFields x]]}
set before [lindex [fossil::sql $R "SELECT [fossil::outcol comment] FROM ticket WHERE tkt_uuid='$uuid'"] 0 0]
$box insert end "An appended remark."
tktsearch::postComment $uuid; update
set after [lindex [fossil::sql $R "SELECT [fossil::outcol comment] FROM ticket WHERE tkt_uuid='$uuid'"] 0 0]
check "asked: [lindex $::boxes end]" {[string match "Post this comment*" [lindex $::boxes end]]}
check "appended, the old text kept" {[string first $before $after] == 0 && [string length $after] > [string length $before]}
check "with who and when: [string range $after [string length $before] end]" {[regexp "<hr><i>$::tickets::me added on \\d{4}-\\d\\d-\\d\\d \\d\\d:\\d\\d:\\d\\d:</i><br>\nAn appended remark.$" $after]}
done
