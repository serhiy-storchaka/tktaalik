# Writing in the Tickets tab: the comment dialog (instead of a box in the
# details), and the preview of comments and descriptions, in each format;
# on a scratch copy.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set ::boxes {}
set R $W/tk.fossil
start tickets $R
set uuid [lindex [fossil::sql $R "SELECT tkt_uuid FROM ticket ORDER BY tkt_mtime DESC LIMIT 1"] 0 0]
tktsearch::showTicket $uuid; update
set d .tickets.main.details.nb.comments.text
check "no text box in the details: a button" {[winfo exists $d.reply.add] && ![winfo exists $d.reply.text]}
$d.reply.add invoke; update
set w .tickets.comment
set e $w.f.editor
check "the dialog: [wm title $w]" {[winfo ismapped $w] && [string match "Comment on [string range $uuid 0 9]" [wm title $w]]}
check "Write and Preview tabs" {[$e.nb tab 0 -text] eq "Write" && [$e.nb tab 1 -text] eq "Preview"}
check "focus in the text" {[focus] eq [formattext::widget $e]}
# Markdown, previewed.
set tktsearch::format Markdown
[formattext::widget $e] insert end "## A heading\n\nSome *emphasis* and `code`.\n"
$e.nb select $e.nb.pre; update
set p $e.nb.pre.t
set heading 0
foreach tag [$p tag names] { if {[regexp {^ht-font-.*-[01][01][1-6]$} $tag] && [llength [$p tag ranges $tag]]} { set heading 1 } }
check "preview: rendered, [string trim [$p get 1.0 end]]" {$heading && [string first "##" [$p get 1.0 end]] < 0 && [string first "A heading" [$p get 1.0 end]] >= 0}
# Another format: the preview follows.
set tktsearch::format {Plain text}
event generate $e.top.format <<ComboboxSelected>>; update
check "plain text: as written" {[string first "## A heading" [$p get 1.0 end]] >= 0}
set tktsearch::format Markdown
event generate $e.top.format <<ComboboxSelected>>; update
# Ctrl+Shift+P: back to Write.
focus -force $p; update
event generate $p <Control-P>; update
check "Ctrl+Shift+P: Write" {[$e.nb select] eq "$e.nb.src"}
# Post: as Markdown, after a confirmation.
set before [llength [fossil::sql $R "SELECT 1 FROM ticketchng WHERE tkt_id=(SELECT tkt_id FROM ticket WHERE tkt_uuid='$uuid')"]]
tktsearch::postComment $uuid; update
set row [lindex [fossil::sql $R "SELECT mimetype, [fossil::outcol icomment] FROM ticketchng WHERE tkt_id=(SELECT tkt_id FROM ticket WHERE tkt_uuid='$uuid') ORDER BY tkt_mtime DESC LIMIT 1"] 0]
check "posted: [lindex $row 0], asked [lindex $::boxes end]" {[lindex $row 0] eq "text/x-markdown" && [string match "## A heading*" [lindex $row 1]] && [string match "Post this comment (Markdown)*" [lindex $::boxes end]] && ![winfo exists $w]}
check "shown rendered in the details" {[string first "A heading" [$d get 1.0 end]] >= 0 && [string first "## A heading" [$d get 1.0 end]] < 0}

# New ticket: the description with its preview.
tktsearch::newTicket; update
set f .tickets.new.f
check "new ticket: the editor" {[winfo exists $f.editor.nb.pre]}
check "Create needs a description" {[$f.buttons.create instate disabled]}
$f.etitle insert 0 "A test ticket"
[formattext::widget $f.editor] insert end "Steps:\n\n1. one\n2. two\n"
update
check "Create enabled" {[$f.buttons.create instate !disabled]}
set tktsearch::format Markdown
$f.editor.nb select $f.editor.nb.pre; update
check "new ticket preview: a list" {[string match "*1.\tone*" [$f.editor.nb.pre.t get 1.0 end]]}
tktsearch::createTicket; update
set new [lindex [fossil::sql $R "SELECT cmimetype, [fossil::outcol comment] FROM ticket WHERE title='A test ticket'"] 0]
check "created: [lindex $new 0]" {[lindex $new 0] eq "text/x-markdown" && [string match "Steps:*" [lindex $new 1]]}
# Edit ticket: the comment with its preview.
tktsearch::editTicket $uuid; update
check "edit ticket: the editor" {[winfo exists .tickets.edit.f.editor.nb.pre]}
destroy .tickets.edit
# F1 in the dialog: the comments in the manual.
tktsearch::commentDialog $uuid; update
check "F1 context: [help::context [formattext::widget $w.f.editor]]" {[help::context [formattext::widget $w.f.editor]] eq "tickets#comments"}
tktsearch::closeComment
done
