# The Preview tab of Files: an image, Markdown, wiki, HTML and man pages
# (with ".so" read from the same version, groff or mandoc, or the text
# as it is without them); links between the files; an older version; a
# file with no preview.  A small repository made here.
source [file join [file dirname [info script]] common.tcl]
set D $T(tmp)
file delete -force $D/co $D/p.fossil
exec fossil init $D/p.fossil
file mkdir $D/co
fossilIn $D/co open $D/p.fossil
file mkdir $D/co/docs $D/co/man
proc write {name text} { set f [open $::D/co/$name w]; fconfigure $f -encoding utf-8; puts -nonewline $f $text; close $f }
write docs/guide.md {# Guide

See [the page](page.html), [the tool](../man/tool.1),
[nothing](none.md) and [the web](https://example.com/x).
}
write docs/page.html {<html><head><title>Hidden title</title><style>p { color: red }</style></head>
<body><h1>Heading</h1><p>Hello <b>bold</b> world</p><script>hidden()</script></body></html>
}
write notes.wiki "Some <b>wiki</b> text\n"
write man/man.macros {.de XX
BS\\fI\\$1\\fR
..
}
write man/tool.1 {.so man.macros
.TH TOOL 1
.SH NAME
tool \- does \fBthings\fR
.SH DESCRIPTION
.XX macrowords
}
write plain.txt "plain\n"
set img [image create photo -width 30 -height 20]
$img put red -to 0 0 30 20
$img write $D/co/pic.png -format png
fossilIn $D/co add docs man notes.wiki plain.txt pic.png
fossilIn $D/co commit -m "files to preview" --no-warnings
write docs/guide.md "# Guide, again\n"
fossilIn $D/co commit -m "the guide changed" --no-warnings

check "kinds" {[lmap n {a.PNG b.md c.wiki d.html e.htm f.1 g.n h.3tcl i.txt j.c} {preview::kind $n}]
    eq {image markdown wiki html html man man man {} {}}}
check "a relative link" {[tkfiles::linkedFile docs/guide.md ../man/tool.1#x] eq "man/tool.1"
    && [tkfiles::linkedFile docs/guide.md page.html?a=1] eq "docs/page.html"
    && [tkfiles::linkedFile docs/guide.md ../../x] eq "" && [tkfiles::linkedFile a.md https://x/y] eq ""
    && [tkfiles::linkedFile a.md #top] eq "" && [tkfiles::linkedFile a.md /info/abc] eq ""}

start files $D/co
tktaalik::show files; update
set t .files.main.tree.t
set nb .files.main.right.nb
set p $nb.preview
set d $p.doc.t
waitUntil {[$t exists f:docs/guide.md]}
proc pick {path} {
    $::t selection set [list f:$path]
    update
}
proc shown {} { $::d get 1.0 end }

# No preview: the tab disabled, Preview of the file refused.
pick plain.txt
check "a text: no preview" {[$nb tab $p -state] eq "disabled"}
set before [$nb select]
tkfiles::showPane preview
check "not shown" {[$nb select] eq $before}
# An image: fitted, with its size.
pick pic.png
check "an image: the tab enabled" {[$nb tab $p -state] eq "normal"}
tkfiles::showPane preview; update
waitUntil {[winfo exists $p.img.c]}
check "the image: [$p.img.b.size cget -text]" {[$p.img.b.size cget -text] eq "30 × 20" && $imageview::fit($p.img)
    && ![winfo ismapped $p.doc]}
# Markdown, rendered by Fossil; another file is not shown without its tab.
pick docs/guide.md
waitUntil {[string match "*Guide, again*" [shown]]}
check "Markdown: [string trim [shown]]" {![winfo exists $p.img] && [winfo ismapped $p.doc]}
# The first version, from the history.
tkfiles::showHistory; update
set h $nb.history.t
waitUntil {[llength [$h children {}]] == 2}
set first [lindex [$h children {}] end]
tkfiles::showAt $first preview; update
waitUntil {[string match "*the page*" [shown]]}
check "the first version: links" {[llength [$d tag ranges ht-link]] == 8 && [string match "*at [string range $first 0 9]" [.files.main.right.title cget -text]]}
# Its links: HTML, then the man page; a file not there; the web.
tkfiles::previewLink $first docs/guide.md page.html; update
waitUntil {[string match "*Heading*" [shown]]}
check "HTML: [string trim [shown]]" {$tkfiles::file eq "docs/page.html" && [string match "*Hello bold world*" [shown]]
    && ![string match "*Hidden*" [shown]] && ![string match "*hidden()*" [shown]] && ![string match "*color*" [shown]]}
tktaalik::goBack; update
waitUntil {$tkfiles::file eq "docs/guide.md" && [string match "*the page*" [shown]]}
check "back to the guide" {[lindex $tkfiles::at 0] eq $first}
tkfiles::previewLink $first docs/guide.md ../man/tool.1; update
waitUntil {[string match "*NAME*" [shown]]}
set man [shown]
if {[preview::formatter] ne ""} {
    set bold [join [lmap {a b} [$d tag ranges man-b] {$d get $a $b}] |]
    check "a man page: [string trim $man]" {$tkfiles::file eq "man/tool.1" && [string match "*does things*" $man]
        && [string match "*BS*macrowords*" $man] && ![string match "*.so*" $man] && [string match "*things*" $bold]
        && [llength [$d tag ranges man-i]] > 0}
}
# Without a program for man pages: as it is.
set keep $preview::formatter
set preview::formatter ""
tkfiles::loadPreview; update
check "no groff: the source" {[string match "Neither groff*" [shown]] && [string match "*.TH TOOL 1*" [shown]]
    && [string match "*.de XX*" [shown]]}
set preview::formatter $keep
set file $tkfiles::file
set bells 0
rename bell realBell
proc bell {args} { incr ::bells }
tkfiles::previewLink $first docs/guide.md none.md
check "a missing file: no change" {$tkfiles::file eq $file}
tkfiles::previewLink $first docs/guide.md https://example.com/x
check "the web: [lindex $::browsed end]" {[lindex $::browsed end] eq "https://example.com/x"}
rename bell {}
rename realBell bell
# Wiki, at the version of the tree; the context menus.
pick notes.wiki
tkfiles::showPane preview; update
waitUntil {[string match "*Some wiki text*" [shown]]}
check "wiki: bold" {[string match "*Some wiki text*" [shown]] && $tkfiles::at eq ""}
proc menuAt {item} {
    set t .files.main.tree.t
    $t see $item
    waitUntil {[llength [$t bbox $item]] > 0}
    lassign [$t bbox $item] x y
    tkfiles::treeMenu [expr {$x + 5}] [expr {$y + 3}] 0 0
    return .files.treectx
}
proc tk_popup {m x y args} {}
set m [menuAt f:plain.txt]
check "a text's menu: Preview disabled" {[$m entrycget [$m index Preview] -state] eq "disabled"}
set m [menuAt f:pic.png]
check "an image's menu: Preview" {[$m entrycget [$m index Preview] -state] eq "normal"}
done
