# Links in rendered text: the hand over every link; after one that opens
# the browser, an arrow (an image, part of the link).
source [file join [file dirname [info script]] common.tcl]
start tickets "" 900x600
toplevel .t
text .t.x -cursor xterm -font TkTextFont
pack .t.x -fill both -expand 1
htmltext::insert .t.x {<p><a href="timeline.md">inside</a> plain <a href="https://example.org/">outside</a> <a href="mailto:a@example.org">mail</a></p>} -command list
update
proc over {w index} {
    $w see $index; update
    lassign [$w bbox $index] x y
    event generate $w <Motion> -x [expr {$x + 2}] -y [expr {$y + 2}]; update
    $w cget -cursor
}
set i [.t.x search inside 1.0]
set o [.t.x search outside 1.0]
set m [.t.x search mail 1.0]
set p [.t.x search plain 1.0]
check "inside: [over .t.x $i]" {[over .t.x $i] eq $htmltext::linkCursor}
check "outside: [over .t.x $o]" {[over .t.x $o] eq $htmltext::linkCursor}
check "plain text: back to [over .t.x $p]" {[over .t.x $p] eq "xterm"}
check "from inside to outside" {[over .t.x $i] eq $htmltext::linkCursor && [over .t.x $o] eq $htmltext::linkCursor}
check "mailto: the hand too" {[over .t.x $m] eq $htmltext::linkCursor}
check "the tags: [.t.x tag names $o]" {"ht-external" in [.t.x tag names $o] && "ht-external" ni [.t.x tag names $i]}
# The arrow after external links: an image, part of the link.
set images [.t.x image names]
check "an arrow after each external link: [llength $images]" {[llength $images] == 2}
# (image names: not in the order of the text)
set a [lindex [lsort -command {apply {{x y} {expr {[.t.x compare $x < $y] ? -1 : 1}}}} [lmap n $images {.t.x index $n}]] 0]
check "after \"outside\", with its link: [.t.x tag names $a]" {[.t.x compare $a == "$o + 7 chars"] && "ht-external" in [.t.x tag names $a] && [lsearch -glob [.t.x tag names $a] ht-href-*] >= 0}
check "none after the internal link" {[.t.x compare $a > $i] && [lsearch -exact [lmap n $images {.t.x index $n}] [.t.x index "$i + 6 chars"]] < 0}
check "the text (copied) without it: [.t.x get 1.0 1.end]" {[.t.x get 1.0 1.end] eq "inside plain outside mail"}
set ::followed ""
.t.x delete 1.0 end
htmltext::reset .t.x
htmltext::insert .t.x {<p><a href="https://example.org/x">site</a></p>} -command {set ::followed}
update
set img [.t.x index [lindex [.t.x image names] end]]
.t.x see $img; update
lassign [.t.x bbox $img] x y w h
event generate .t.x <Motion> -x [expr {$x + $w / 2}] -y [expr {$y + $h / 2}]; update
event generate .t.x <1> -x [expr {$x + $w / 2}] -y [expr {$y + $h / 2}]
event generate .t.x <ButtonRelease-1> -x [expr {$x + $w / 2}] -y [expr {$y + $h / 2}]; update
check "clicking the arrow follows the link: $::followed" {$::followed eq "https://example.org/x"}
# (Again: on Windows the real pointer, elsewhere, may have left the window.)
event generate .t.x <Motion> -x [expr {$x + $w / 2}] -y [expr {$y + $h / 2}]; update
check "the hand over the arrow" {[.t.x cget -cursor] eq $htmltext::linkCursor}
# -external: the caller decides.
.t.x delete 1.0 end
htmltext::reset .t.x
htmltext::insert .t.x {<p><a href="/info/abc">server</a> <a href="tkt:1234">ticket</a></p>} \
    -command list -external tktsearch::isExternal
update
check "a server path: outside" {"ht-external" in [.t.x tag names [.t.x search server 1.0]]}
check "a ticket: inside" {"ht-external" ni [.t.x tag names [.t.x search ticket 1.0]]}
# Not followed (no -command, as in previews): nothing is external.
.t.x delete 1.0 end
htmltext::reset .t.x
htmltext::insert .t.x {<p><a href="https://example.org/">site</a></p>}
check "links not followed: no arrow" {![llength [.t.x image names]] || [lsearch -glob [.t.x tag names 1.0] ht-external] < 0 && [.t.x get 1.0 1.end] eq "site"}
destroy .t
# The tabs' rules.
tktaalik::show wiki; update
check "wiki: page inside, URL outside" {![tkwiki::isExternal "/wiki?name=Migrating+scripts+to+Tk+9"] && [tkwiki::isExternal https://example.org] && ![tkwiki::isExternal tkt:1234]}
check "tickets: tkt inside, info: of what is not here outside" {![tktsearch::isExternal tkt:1234] && [tktsearch::isExternal info:0000000000ab] && [tktsearch::isExternal https://x]}
set post [lindex [fossil::sql $T(repo) "SELECT substr(b.uuid,1,12) FROM forumpost f JOIN blob b ON b.rid=f.fpid LIMIT 1"] 0 0]
tktaalik::show forum; update
check "forum: a post here inside, one not here outside" {![tkforum::isExternal /forumpost/$post] && [tkforum::isExternal /forumpost/0000000000ab] && [tkforum::isExternal https://x]}
# Without a server: its pages cannot be opened, so they are not external.
set saved $tktsearch::remote
set tktsearch::remote ""
check "no server: info: and paths inside, URLs outside" {![tktsearch::isExternal info:abcd] && ![tktsearch::isExternal /timeline] && [tktsearch::isExternal https://x]}
set tktsearch::remote $saved
# The manual: web links only.
check "manual: https outside, mailto not followed" {[regexp -nocase {^https?://} https://x] && ![regexp -nocase {^https?://} mailto:a@b]}
done
