# The charts (lib/charts.tcl): bars, lines and grids drawn to the size of
# the canvas and the text, their tooltips and clicks (real buttons too),
# the data copied and the SVG; sparklines and the diffstat helpers.
source [file join [file dirname [info script]] common.tcl]
toplevel .c
wm geometry .c 800x600+0+0
set ::clicked {}
proc clicked {args} { lappend ::clicked $args }
charts::bars .c.a -title "Per month" -categories {2026-01 2026-02 2026-03} \
    -keys {k1 k2 k3} -series {A {1 5 2} B {0 3 4}} -command clicked
charts::bars .c.h -title Users -horizontal 1 -categories {alice bob} -series {Check-ins {30 7}}
charts::grid .c.g -title Days -rows {Mon Tue} -columns {W1 "" W3} \
    -cells {0 0 1 d1 "" 0 1 0 d2 "" 1 2 9 d3 "Nine"} -command clicked
charts::message .c.m "Nothing here"
grid .c.a .c.h -sticky news
grid .c.g .c.m -sticky news
grid columnconfigure .c {0 1} -weight 1
grid rowconfigure .c {0 1} -weight 1
update; after 100; update

check "bars: 5 segments (the zero left out)" {[llength [.c.a find withtag bar]] == 5}
check "the legend: A and B" {[llength [lmap i [.c.a find all] {
    if {[.c.a type $i] eq "text" && [.c.a itemcget $i -text] in {A B}} { set i } else continue }]] == 2}
# The axis: about five steps of 1, 2 or 5 times a power of ten.
check "ticks: [charts::Ticks 7] [charts::Ticks 830] [charts::Ticks 0]" {[charts::Ticks 7] eq {2 8} && [charts::Ticks 830] eq {200 1000} && [charts::Ticks 0] eq {1 1}}
check "numbers: [charts::number 1234567] [charts::bytes 1500] [charts::bytes 2500000]" {[charts::number 1234567] eq "1,234,567" && [charts::bytes 1500] eq "1.5 kB" && [charts::bytes 2500000] eq "2.5 MB"}
check "cut: [charts::Fit abcdefghijklmnop 60 ChartFont middle]" {[string match "a*…*p" [charts::Fit abcdefghijklmnop 60 ChartFont middle]] && [font measure ChartFont [charts::Fit abcdefghijklmnop 60 ChartFont]] <= 60}

# Hover: the values in a tooltip; a click: the command with the key and series.
set seg [lindex [.c.a find withtag bar1] end]
eval [string map {%X 100 %Y 100} [.c.a bind $seg <Enter>]]
after 800 {set ::w 1}; vwait ::w
check "tooltip: [string map {\n |} [expr {[winfo exists .iconsTip] ? [.iconsTip.l cget -text] : ""}]]" {[winfo exists .iconsTip] && [.iconsTip.l cget -text] eq "2026-02\nA: 5\nB: 3\nTotal: 8"}
eval [.c.a bind $seg <Leave>]
eval [.c.a bind $seg <ButtonRelease-1>]
check "click: $::clicked" {$::clicked eq {{k2 B}}}
set ::clicked {}
set cell [lindex [.c.g find withtag cell2] 0]
eval [string map {%X 100 %Y 100} [.c.g bind $cell <Enter>]]
after 800 {set ::w 1}; vwait ::w
check "a cell's own tip" {[winfo exists .iconsTip] && [.iconsTip.l cget -text] eq "Nine"}
eval [.c.g bind $cell <Leave>]
eval [.c.g bind $cell <ButtonRelease-1>]
check "a cell clicked: $::clicked" {$::clicked eq {d3}}
check "shades: none grey, more darker" {[.c.g itemcget [lindex [.c.g find withtag cell1] 0] -fill] eq $charts::empty
    && [.c.g itemcget $cell -fill] eq [charts::Shade 9 9]}
check "the message" {[.c.m itemcget [lindex [.c.m find all] 0] -text] eq "Nothing here"}

# The data and the SVG.
check "data: [string map {\n | \t ,} [charts::tsv .c.a]]" {[charts::tsv .c.a] eq "\tA\tB\n2026-01\t1\t0\n2026-02\t5\t3\n2026-03\t2\t4"}
check "grid data" {[lindex [split [charts::tsv .c.g] \n] 2] eq "Tue\tW3\td3\t9"}
set svg [charts::svg .c.a]
check "SVG: a document with the bars and the texts" {[string match "<?xml*<svg *</svg>" $svg]
    && [regexp -all {<rect } $svg] >= 6 && [string match "*>Per month</text>*" $svg]}
set ::saveTo $T(tmp)/chart.svg
charts::Save .c.a svg
set f [open $T(tmp)/chart.svg]
set saved [read $f]
close $f
check "saved as SVG" {$saved eq "$svg\n" || [string trim $saved] eq [string trim $svg]}

# Larger text: larger fonts, the chart drawn again.
set before [font actual ChartFont -size]
ui::textSize 1.5; update
check "text size: [font actual ChartFont -size] after $before" {[font actual ChartFont -size] == round($before * 1.5) && [llength [.c.a find withtag bar]] == 5}
ui::textSize 1; update
# Resized: drawn to the new size.
lassign [.c.a coords [lindex [.c.a find withtag col2] 0]] - - x2
wm geometry .c 1000x600; update; after 100; update
check "resized: drawn again wider" {[lindex [.c.a coords [lindex [.c.a find withtag col2] 0]] 2] > $x2}

# A real click on a bar (XTEST on Xvfb).
if {[realInput]} {
    set ::clicked {}
    lassign [.c.a coords [lindex [.c.a find withtag bar0] 0]] x1 y1 x2 y2
    event generate .c.a <Motion> -warp 1 -x [expr {int(($x1 + $x2) / 2)}] -y [expr {int($y2 - 2)}]
    update; after 200; update
    exec $T(xbutton) 1
    after 200 {set ::w 1}; vwait ::w
    check "a real click: $::clicked" {$::clicked eq {{k1 A}}}
} else {
    puts "(no real input: not checked)"
}

# Sparklines and the diffstat.
set img [charts::spark {0 2 4} 30 10]
check "spark: [image width $img]x[image height $img], tallest at the right" {[image width $img] == 30 && [image height $img] == 10
    && ![$img transparency get 25 1] && [$img transparency get 5 1] && [$img transparency get 15 1]}
set stats [charts::numstat "  INSERTED    DELETED\n        54          0 tests/a b.test\n         1          2 x.c\n        55          2 TOTAL over 2 changed files"]
check "numstat: $stats" {$stats eq {{tests/a b.test} 54 0 x.c 1 2}}
text .c.t
charts::statTags .c.t
.c.t insert end "f" "" \n
charts::stat .c.t 1.1 30 10 40
check "a stat: [list [.c.t get 1.0 1.end]]" {[string match "f  +30 −10  *" [.c.t get 1.0 1.end]]
    && [llength [.c.t tag ranges baradd]] == 2 && [string length [.c.t get {*}[.c.t tag ranges baradd]]] == 15
    && [string length [.c.t get {*}[.c.t tag ranges bardel]]] == 5}
set img [charts::statImage 3 1 4 40 6]
check "stat image: green then red" {[image width $img] == 40 && [lindex [$img get 5 2] 1] > [lindex [$img get 5 2] 0]
    && [lindex [$img get 35 2] 0] > [lindex [$img get 35 2] 1]}
check "colours: the same for a name, not grey" {[charts::colour trunk] eq [charts::colour trunk] && [charts::colour trunk] ne "#999999"}
done
