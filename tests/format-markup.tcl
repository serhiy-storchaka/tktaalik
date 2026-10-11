# The markup buttons and keys of the text editors (formattext): each action
# in Markdown, Fossil wiki and HTML, around the selection or on its lines,
# taken off when done again; one Undo step; nothing for plain text.
source [file join [file dirname [info script]] common.tcl]
toplevel .fm
set formats {Markdown text/x-markdown "Fossil wiki" text/x-fossil-wiki HTML text/html {Plain text} text/plain}
set ::fmFormat Markdown
formattext::create .fm.e -formats $formats -variable fmFormat
pack .fm.e -fill both -expand 1
toplevel .fm2
formattext::create .fm2.e -formats $formats -variable fmFormat
pack .fm2.e
update
set t [formattext::widget .fm.e]
proc use {format} { set ::fmFormat $format; formattext::changed .fm.e; update }
# The text, a selection (from, to as indices) or a cursor; ACTION; the text.
proc run {text action {from ""} {to ""}} {
    set t $::t
    $t delete 1.0 end
    $t insert 1.0 $text
    $t tag remove sel 1.0 end
    if {$to ne ""} { $t tag add sel $from $to } elseif {$from ne ""} { $t mark set insert $from }
    formattext::apply .fm.e $action
    $t get 1.0 "end - 1 char"
}
proc sel {} { if {[llength [$::t tag ranges sel]]} { $::t get sel.first sel.last } }

use Markdown
check "md bold" {[run "a word here" bold 1.2 1.6] eq "a **word** here" && [sel] eq "word"}
check "md bold again: off" {[formattext::apply .fm.e bold] && [$t get 1.0 "end - 1 char"] eq "a word here" && [sel] eq "word"}
check "md bold, marks selected too: off" {[run "a **word** here" bold 1.2 1.10] eq "a word here"}
check "md bold, no selection: the cursor between" {[run "ab" bold 1.1] eq "a****b" && [$t index insert] eq "1.3"}
check "md italic" {[run "x y" italic 1.2 1.3] eq "x _y_"}
check "md code" {[run "call f()" code 1.5 1.8] eq "call `f()`"}
check "md link: the URL to type selected" {[run "see docs" link 1.4 1.8] eq "see \[docs\](url)" && [sel] eq "url"}
check "md link of a URL: the text to type selected" {[run "https://x.org/a" link 1.0 1.15] eq "\[text\](https://x.org/a)" && [sel] eq "text"}
check "md heading" {[run "Title" heading 1.2] eq "## Title"}
check "md heading again: off" {[run "## Title" heading 1.2] eq "Title"}
check "md bullets on the lines, the empty one left" {[run "one\n\ntwo" bullet 1.0 3.3] eq "- one\n\n- two"}
check "md bullets off" {[run "- one\n- two" bullet 1.0 2.5] eq "one\ntwo"}
check "md numbered" {[run "a\nb\nc" number 1.0 3.1] eq "1. a\n2. b\n3. c"}
check "md numbered off" {[run "1. a\n2. b" number 1.0 2.4] eq "a\nb"}
check "md quote" {[run "said" quote 1.0] eq "> said"}
check "md code block" {[run "x = 1\ny = 2" block 1.0 2.5] eq "```\nx = 1\ny = 2\n```"}
check "md code block off (inside)" {[run "```\nx = 1\n```" block 2.1] eq "x = 1"}
check "md code block on an empty line: the cursor inside" {[run "" block] eq "```\n\n```" && [$t index insert] eq "2.0"}
check "md selection to the start of a line: not that line" {[run "a\nb" bullet 1.0 2.0] eq "- a\nb"}

use "Fossil wiki"
check "wiki bold" {[run "a b" bold 1.2 1.3] eq "a <b>b</b>"}
check "wiki link" {[run "page" link 1.0 1.4] eq "\[url|page\]" && [sel] eq "url"}
check "wiki heading" {[run "Title" heading 1.0] eq "<h2>Title</h2>"}
check "wiki heading off" {[run "<h2>Title</h2>" heading 1.0] eq "Title"}
check "wiki bullets" {[run "a\nb" bullet 1.0 2.1] eq "  *  a\n  *  b"}
check "wiki numbered" {[run "a" number 1.0] eq "  #  a"}
check "wiki quote" {[run "q" quote 1.0] eq "<blockquote>\nq\n</blockquote>"}
check "wiki code block" {[run "x" block 1.0] eq "<verbatim>\nx\n</verbatim>"}

use HTML
check "html italic" {[run "a" italic 1.0 1.1] eq "<i>a</i>"}
check "html link" {[run "home" link 1.0 1.4] eq "<a href=\"url\">home</a>" && [sel] eq "url"}
check "html bullets" {[run "a\nb" bullet 1.0 2.1] eq "<ul>\n<li>a</li>\n<li>b</li>\n</ul>"}
check "html bullets off" {[run "<ul>\n<li>a</li>\n</ul>" bullet 1.0 3.5] eq "a"}
check "html numbered" {[run "a" number 1.0] eq "<ol>\n<li>a</li>\n</ol>"}
check "html code block" {[run "x" block 1.0] eq "<pre>\nx\n</pre>"}

# One step of Undo puts it back.
use Markdown
$t configure -undo 1
run "plain" bold 1.0 1.5
$t edit reset
formattext::apply .fm.e italic
$t edit undo
check "undo: one step" {[$t get 1.0 "end - 1 char"] eq "**plain**"}

# The keys, as on GitHub.
foreach {key action expected} {
    <Control-b> bold "**w**" <Control-i> italic "_w_" <Control-e> code "`w`"
    <Control-k> link "\[w\](url)" <Control-H> heading "## w" <Control-E> block "```\nw\n```"
    <Control-asterisk> bullet "- w" <Control-ampersand> number "1. w" <Control-greater> quote "> w"
} {
    $t delete 1.0 end; $t insert 1.0 w; $t tag remove sel 1.0 end; $t tag add sel 1.0 1.1
    focus -force $t; update
    event generate $t $key
    update
    check "key $key: $action" {[$t get 1.0 "end - 1 char"] eq $expected}
}

# The Preview button: the text rendered in place of it, the markup
# buttons disabled; a markup key back to the text first.
$t delete 1.0 end; $t insert 1.0 w; $t tag remove sel 1.0 end; $t tag add sel 1.0 1.1
set size [list [winfo width .fm] [winfo height .fm]]
.fm.e.top.preview invoke; update
check "preview: the window's size kept: $size [winfo width .fm] [winfo height .fm]" {
    $size eq [list [winfo width .fm] [winfo height .fm]]}
check "preview: shown, the text not, buttons disabled" {[winfo ismapped .fm.e.pre.t] && ![winfo ismapped $t]
    && [.fm.e.top.bold instate disabled] && ![.fm.e.top.preview instate disabled]}
formattext::apply .fm.e bold; update
check "markup from the preview: back to the text, done" {[winfo ismapped $t] && !$formattext::previewOn(.fm.e)
    && [$t get 1.0 "end - 1 char"] eq "**w**" && ![.fm.e.top.bold instate disabled]}

# Plain text: the buttons disabled, the keys left to Tk.
use "Plain text"
check "plain: buttons disabled" {[.fm.e.top.bold instate disabled] && [.fm.e.top.block instate disabled]}
check "plain: nothing done" {[run "w" bold 1.0 1.1] eq "w" && ![formattext::apply .fm.e bold]}
use Markdown
check "back to Markdown: enabled" {![.fm.e.top.bold instate disabled]}
# The buttons do the same.
$t delete 1.0 end; $t insert 1.0 w; $t tag add sel 1.0 1.1
.fm.e.top.code invoke; update
check "button: code" {[$t get 1.0 "end - 1 char"] eq "`w`"}
destroy .fm

# References: to what the selection names at once, else chosen in a window;
# the reference buttons disabled without a repository.
check "no repository: reference buttons disabled" {[.fm2.e.top.ticket instate disabled]
    && ![.fm2.e.top.bold instate disabled]}
destroy .fm2
toplevel .fm
set ::fmFormat Markdown
formattext::create .fm.e -formats $formats -variable fmFormat -repo $T(repo)
pack .fm.e -fill both -expand 1
update
set t [formattext::widget .fm.e]
check "repository: reference buttons enabled, their icons" {![.fm.e.top.ticket instate disabled]
    && [.fm.e.top.branch cget -image] ne "" && [.fm.e.top.link cget -image] ne ""}
lassign [lindex [sql "SELECT tkt_uuid, title FROM ticket WHERE length(title)>12 ORDER BY tkt_mtime DESC LIMIT 1"] 0] tkt title
set tkt10 [string range $tkt 0 9]
set ci [lindex [sql "SELECT b.uuid FROM blob b JOIN event e ON e.objid=b.rid WHERE e.type='ci' ORDER BY e.mtime DESC LIMIT 1"] 0 0]
set ci10 [string range $ci 0 9]
check "resolve: a ticket by its start" {[refpick::resolve $T(repo) ticket [string range $tkt 0 7]] eq $tkt}
check "resolve: a check-in, not as a ticket" {[refpick::resolve $T(repo) checkin $ci10] eq $ci
    && [refpick::resolve $T(repo) ticket $ci10] eq ""}
check "resolve: a branch" {[refpick::resolve $T(repo) branch core-9-0-branch] eq "core-9-0-branch"
    && [refpick::resolve $T(repo) branch no-such-branch-x] eq ""}
check "md ticket: the selected hash" {[run "see $tkt10 here" ticket 1.4 1.14] eq "see \[$tkt10\](/tktview/$tkt10) here"
    && ![winfo exists .fm.refpick]}
check "md check-in" {[run $ci10 checkin 1.0 1.10] eq "\[$ci10\](/info/$ci10)"}
check "md branch" {[run core-9-0-branch branch 1.0 1.15] eq "\[core-9-0-branch\](/timeline?r=core-9-0-branch)"}
use "Fossil wiki"
check "wiki ticket" {[run $tkt10 ticket 1.0 1.10] eq "\[$tkt10\]"}
check "wiki branch" {[run core-9-0-branch branch 1.0 1.15] eq "\[/timeline?r=core-9-0-branch|core-9-0-branch\]"}
use HTML
check "html check-in" {[run $ci10 checkin 1.0 1.10] eq "<a href=\"/info/$ci10\">$ci10</a>"}

# A text that is no hash: the window, searched for it; the text the link's.
use Markdown
set word crash
run "about $word" ticket 1.6 "1.6 + [string length $word] chars"
update
check "window for a text: open, searched ($word)" {[winfo exists .fm.refpick]
    && [.fm.refpick.f.q get] eq $word && [llength [.fm.refpick.f.list.t children {}]] > 1}
set first [lindex [.fm.refpick.f.list.t children {}] 0]
refpick::move .fm.refpick 1
set second [lindex [.fm.refpick.f.list.t selection] 0]
focus -force .fm.refpick.f.q
waitUntil {[focus] eq ".fm.refpick.f.q"} 5000
event generate .fm.refpick.f.q <Return>
update
set s10 [string range $second 0 9]
check "Down, Return: the second one, the text kept: [list $first $second [winfo exists .fm.refpick] [$t get 1.0 {end - 1 char}]]" {![winfo exists .fm.refpick]
    && $second ne $first && [$t get 1.0 "end - 1 char"] eq "about \[$word\](/tktview/$s10)"}
$t edit undo
check "one Undo step: [list [$t get 1.0 {end - 1 char}]]" {[$t get 1.0 "end - 1 char"] eq "about $word"}

# No selection: the window with everything, searched as typed; Escape.
$t delete 1.0 end; $t tag remove sel 1.0 end
focus -force $t; update
event generate $t <Control-B>
update
check "Ctrl+Shift+B: the branch window" {[winfo exists .fm.refpick] && [wm title .fm.refpick] eq "Insert a branch"
    && [llength [.fm.refpick.f.list.t children {}]] > 10}
.fm.refpick.f.q insert end core-8-6-bra
refpick::search .fm.refpick
check "searched as typed: [llength [.fm.refpick.f.list.t children {}]]" {"core-8-6-branch" in [.fm.refpick.f.list.t children {}]}
.fm.refpick.f.list.t selection set core-8-6-branch
.fm.refpick.b.ok invoke
update
check "Insert: at the cursor" {[$t get 1.0 "end - 1 char"] eq "\[core-8-6-branch\](/timeline?r=core-8-6-branch)"}
focus -force $t; update
event generate $t <Control-C>
update
check "Ctrl+Shift+C: the check-in window, newest first" {[winfo exists .fm.refpick]
    && [lindex [.fm.refpick.f.list.t children {}] 0] eq $ci}
event generate .fm.refpick <Escape>
update
check "Escape: nothing inserted" {![winfo exists .fm.refpick]
    && [$t get 1.0 "end - 1 char"] eq "\[core-8-6-branch\](/timeline?r=core-8-6-branch)"}
destroy .fm
done
