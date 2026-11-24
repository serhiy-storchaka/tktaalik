# make-repos.tcl DIR: the repositories the tests read, made from nothing in
# a few seconds, with what the tests look for and no more:
#
#   DIR/tk.fossil     in the shape of Tk's (its ticket setup and reports,
#                     data/tk-ticket.conf; its branch and tag names, its
#                     files): TKTAALIK_REPO
#   DIR/tips.fossil   another ticket schema (the TIPs', with a tip_number,
#                     data/tips-ticket.conf) and a technote: TKTAALIK_REPO2
#   DIR/forum.fossil  a forum: a thread of replies to replies and edits (as
#                     the Fossil forum's "New thread for testing"), others:
#                     TKTAALIK_FORUM
#
# run.sh makes them for those not set, again when this script changes and
# each month (one ticket has changes of the last year).
#
# Check-ins are made in a checkout with the dates and users given
# (--date-override, --user-override); tickets, wiki pages, attachments and
# forum posts are written as artifacts (Fossil has no command that takes
# their dates and IDs) and brought in as one bundle.  The same script gives
# the same artifacts, with the same hashes, on the same day (the changes of
# one ticket are dated from it); the tests do not count on the hashes, as
# they are not those of the real repositories either.
#
# Runs in tclsh or wish (8.6 or 9), with fossil on the PATH (2.21 or newer).

if {[llength $argv] != 1} { puts stderr "usage: make-repos.tcl DIR"; exit 2 }
if {[info commands wm] ne ""} { wm withdraw . }
set dir [file normalize [lindex $argv 0]]
set here [file dirname [file normalize [info script]]]
set R $dir/tk.fossil
set co $dir/build
file delete -force $R $dir/tips.fossil $dir/forum.fossil $co
file mkdir $dir $co
set env(FOSSIL_HOME) $dir/build-home
file delete -force $env(FOSSIL_HOME)
file mkdir $env(FOSSIL_HOME)
cd $co

proc f {args} { exec fossil {*}$args 2>@1 }
proc write {path text} {
    file mkdir [file dirname $path]
    set ch [open $path wb]
    puts -nonewline $ch [encoding convertto utf-8 $text]
    close $ch
}

# ------------------------------------------------------------- texts

# Words in an order of their own for each seed: text that does not
# compress to nothing and differs from file to file.
set words {window widget event the a of to is in for with on menu button
    canvas text entry font color image bind focus grab geometry option
    toplevel frame label scrollbar configure command value list string
    returns when if not be are this that which may each new old size}
proc prose {seed n {width 9}} {
    global words
    set x [expr {$seed * 7919 + 17}]
    set out ""
    for {set i 0} {$i < $n} {incr i} {
        set line {}
        for {set j 0} {$j < $width} {incr j} {
            set x [expr {($x * 1103515245 + 12345) % 2147483648}]
            lappend line [lindex $words [expr {($x >> 16) % [llength $words]}]]
        }
        append out [string toupper [string index $line 0]][string range [join $line] 1 end].\n
    }
    return $out
}

proc readme {v} {
    set t "README: Tk\n\nThis is the Tk source distribution, version $v.\n"
    append t "Tk is a graphical user interface toolkit for Tcl.\n\n"
    append t [prose 1 26]
    append t "\nSee the file license.terms for the terms of use.\n"
}

proc license {} {
    set t "This software is copyrighted by the Regents of the University of\n"
    append t "California, Sun Microsystems, Inc., and other parties.\n\n"
    append t [prose 2 24]
    append t "\nGOVERNMENT USE: see the license of Tcl.\n"
}

proc tkh {v} {
    set t "/*\n * tk.h --\n *\n *\tDeclarations for Tk-related things.\n */\n\n"
    append t "#ifndef _TK\n#define _TK\n\n#define TK_VERSION \"[join [lrange [split $v .] 0 1] .]\"\n"
    append t "#define TK_PATCH_LEVEL \"$v\"\n\n"
    append t [string map {. ;} [prose 3 12]]
    append t "\n#endif /* _TK */\n"
}

# doc/wm.n: the copyright line kept from the first version on; LEVEL adds
# what later versions changed (lines of 8.6.0 too).
proc wmn {level} {
    set t "'\\\"\n'\\\" Copyright (c) 1991-1994 The Regents of the University of California.\n"
    append t "'\\\" Copyright (c) 1994-1997 Sun Microsystems, Inc.\n.TH wm n 8.6 Tk \"Tk Built-In Commands\"\n"
    append t ".SH NAME\nwm \\- Communicate with [expr {$level >= 2 ? "the " : ""}]window manager\n.SH SYNOPSIS\n\\fBwm\\fR \\fIoption window \\fR?\\fIargs\\fR?\n"
    append t ".SH DESCRIPTION\n" [prose 4 20]
    append t ".TP\n\\fBwm attributes \\fIwindow\\fR\n" [prose 5 6]
    append t ".TP\n\\fBwm attributes \\fIwindow\\fR \\fB\\-alpha\\fR\n" [prose 6 6]
    if {$level >= 1} { append t ".PP\n" [prose 7 8] }
    if {$level >= 2} {
        append t ".TP\n\\fBwm attributes \\fIwindow\\fR \\fB\\-topmost\\fR\n" [prose 8 6]
        append t ".PP\nThe events <<WMChanged>> tell of a change.\n"
    }
    if {$level >= 3} { append t ".SH EXAMPLE\n" [prose 9 6] }
    append t ".SH KEYWORDS\naspect ratio, deiconify, focus model, geometry, grid, group, icon[expr {$level >= 3 ? ", stacking order" : ""}]\n"
}

# doc/wish.1: the 3 lines of the -use option added later (the patch of the
# ticket 34e934161e is that change: applied already).
proc wish1 {withUse} {
    set lines {}
    foreach l [split [string trimright "'\\\"\n'\\\" Copyright (c) 1991-1994 The Regents of the University of California.\n.TH wish 1 8.0 Tk \"Tk Applications\"\n.SH NAME\nwish \\- Simple windowing shell\n[prose 10 90]" \n] \n] {
        lappend lines $l
    }
    set use [list {.TP 15} {\fB\-use \fIid\fR} {Specifies that the main window is to be embedded in the window whose identifier is \fIid\fR.}]
    if {$withUse} { set lines [linsert $lines 86 {*}$use] }
    lappend lines {*}[split [string trimright [prose 11 12] \n] \n] ".SH KEYWORDS" "shell, toolkit"
    return [join $lines \n]\n
}

proc wishPatch {} {
    set old [split [wish1 0] \n]
    set new [split [wish1 1] \n]
    set t "Index: doc/wish.1\n==================================================================\n"
    append t "--- doc/wish.1\n+++ doc/wish.1\n@@ -81,12 +81,15 @@\n"
    foreach l [lrange $old 80 85] { append t " $l\n" }
    foreach l [lrange $new 86 88] { append t "+$l\n" }
    foreach l [lrange $old 86 91] { append t " $l\n" }
    return $t
}

proc tcl {name seed n} { return "# $name --\n#\n[string map {"\n" "\n# "} [prose $seed 3]]\nproc ::tk::$name {args} {\n[string map {"\n" "\n    # "} "    # [prose [incr seed] $n]"]\n}\n" }
proc csrc {name seed n} { return "/*\n * $name --\n */\n\n#include \"tkInt.h\"\n\n[string map {. ;} [prose $seed $n]]" }
proc testfile {name seed n} { return "# $name --\n\npackage require tcltest 2.2\nnamespace import ::tcltest::*\n\n[string map {"\n" "\n# "} [prose $seed $n]]\ncleanupTests\nreturn\n" }

# (A GIF of 1 pixel: tests/red.gif is a binary file.)
set gif [binary decode base64 R0lGODlhAQABAIAAAP8AAAAAACH5BAAAAAAALAAAAAABAAEAAAICRAEAOw==]

# ------------------------------------------------------------- check-ins

proc commit {date user comment args} {
    f commit --no-warnings --nosync --date-override $date --user-override $user -m $comment {*}$args
}
proc tag {name checkin date user args} {
    f tag add {*}$args --date-override $date --user-override $user $name $checkin
}
# The hash of the checkout's check-in.
proc current {} {
    regexp -line {^checkout:\s+([0-9a-f]+)} [f info] -> h
    return $h
}

# A new repository: its ticket setup from CONF.
proc newRepo {repo date admin project conf} {
    # (The user of the commands that write without naming one.)
    set ::env(USER) $admin
    f init $repo --date-override $date --admin-user $admin --project-name $project
    if {$conf ne ""} {
        # (Import keeps the newer of two: the defaults of init are newer.)
        f sql -R $repo "DELETE FROM config WHERE name GLOB 'ticket-*'; DELETE FROM reportfmt"
        f configuration import $::here/data/$conf -R $repo
    }
    f settings autosync off -R $repo
    f hash-policy sha3 -R $repo
}
newRepo $R "2002-01-01 00:00:00" jan.nijtmans "Tk Source Code" tk-ticket.conf
foreach {login caps} {
    serhiy.storchaka ei  fvogel ei  dkf ei  marc_culler ei  kevin_walzer ei
    aku ei  erikleunissen u  randolf u  oehhar u  bll u  chrstphrchvz u
} {
    f user new $login "" secret -R $R
    f user capabilities $login $caps -R $R
}
f user capabilities developer ei -R $R
f open $R --force
f settings autosync off
# (Files are written again within a second at the same size: compared by
# their content.)
f settings mtime-changes off

# trunk, from 2002 to 2020.
foreach {path text} [list \
    README [readme 8.4.0] license.terms [license] changes.md "# Changes in Tk\n\n[prose 12 6]" \
    .fossil-settings/ignore-glob "*.o\n*.a\n*.so\n*.dll\nmacosx/configure\nunix/config.status\n" \
    doc/wm.n [wmn 0] doc/wish.1 [wish1 0] doc/3DBorder.3 ".TH Tk_Alloc3DBorderFromObj 3 8.1 Tk\n[prose 13 30]" \
    doc/bell.n ".TH bell n 8.4 Tk\n[prose 14 20]" doc/menu.n ".TH menu n 4.1 Tk\nA native menu is used where there is one.\n[prose 15 30]" \
    generic/tk.h [tkh 8.4.0] generic/tkButton.c [csrc tkButton.c 16 30] generic/tkFont.c [csrc tkFont.c 17 30] \
    generic/tkMenu.c [csrc tkMenu.c 18 30] generic/tkWindow.c [csrc tkWindow.c 19 30] \
    library/button.tcl [tcl button 20 20] library/tk.tcl [tcl tk 22 20] library/menu.tcl [tcl menu 24 20] \
    library/ttk/ttk.tcl [tcl ttk 26 10] library/ttk/button.tcl [tcl ttkbutton 28 10] \
    tests/all.tcl [testfile all.tcl 30 4] tests/unixButton.test [testfile unixButton.test 31 20] \
    tests/menu.test [testfile menu.test 32 20] \
    win/README "Tk for Windows\n\n[prose 33 10]" win/makefile.vc "# Visual C++ makefile\n[prose 34 10]" \
    unix/Makefile.in "# Makefile.in --\n[prose 35 12]" unix/configure.ac "AC_INIT(\[tk\])\n[prose 36 8]" \
    macosx/README "Tk for macOS\n\n[prose 37 8]"
] {
    write $path $text
}
write tests/red.gif $gif
f add --dotfiles .
commit "2002-01-10 10:00:00" jan.nijtmans "Initial import of Tk 8.4"
set n 1
foreach {date user comment edits} {
    2003-02-01 dkf "Fix crash in menubutton when the menu is destroyed" {generic/tk.h 8.4.2 generic/tkMenu.c 40}
    2004-05-11 dkf "Fix menubutton geometry on X11" {generic/tk.h 8.4.6 generic/tkButton.c 41}
    2005-12-01 jan.nijtmans "Fix [2128087]: wrong colours of menubutton menus" {generic/tk.h 8.4.12 generic/tkMenu.c 42}
    2006-06-01 dkf "Fix font fallbacks" {generic/tk.h 8.4.14 generic/tkFont.c 43}
    2008-03-01 dkf "Document wm attributes on all platforms" {generic/tk.h 8.5.2 doc/wm.n 1}
    2009-04-01 jan.nijtmans "Update the README for Windows builds" {generic/tk.h 8.5.7 win/README 44}
    2010-02-01 fvogel "Document the -use option of wish" {generic/tk.h 8.5.8 doc/wish.1 1}
    2010-09-01 dkf "Fix button bindings on the Mac" {generic/tk.h 8.5.9 library/button.tcl 45}
} {
    foreach {path v} $edits {
        switch -glob -- $path {
            generic/tk.h { write $path [tkh $v] }
            doc/wm.n { write $path [wmn $v] }
            doc/wish.1 { write $path [wish1 $v] }
            library/*.tcl { write $path [tcl [file rootname [file tail $path]] $v 22] }
            win/README { write $path "Tk for Windows\n\n[prose $v 11]" }
            default { write $path [csrc [file tail $path] $v 31] }
        }
    }
    commit "$date 10:00:00" $user $comment
    incr n
}

# core-8-5-branch: a branch closed long ago.
f update trunk
write generic/tkWindow.c [csrc tkWindow.c 50 30]
commit "2010-10-01 10:00:00" dkf "Start the 8.5 maintenance branch: fix a crash on exit" --branch core-8-5-branch
write generic/tkWindow.c [csrc tkWindow.c 51 30]
commit "2011-01-01 10:00:00" dkf "Fix the menubutton indicator on 8.5"
write generic/tkWindow.c [csrc tkWindow.c 52 30]
commit "2012-01-01 10:00:00" dkf "Last 8.5 fix: no more releases" --close

f update trunk
f mv README README.md
file rename README README.md
write README.md [readme 8.6b1]
commit "2011-06-01 10:00:00" jan.nijtmans "Rename README to README.md"
write generic/tk.h [tkh 8.6.0]
write doc/wm.n [wmn 1]
commit "2012-09-01 10:00:00" dkf "Tk 8.6.0"
set tk860 [current]
tag core-8-6-0 $tk860 "2012-09-02 10:00:00" dkf

# core-8-6-branch, from 8.6.0 on: fixes that name their tickets.
write generic/tkButton.c [csrc tkButton.c 60 31]
commit "2013-03-01 10:00:00" jan.nijtmans "Fix \[595d72d0a6\]: the active window lost on 8.6" --branch core-8-6-branch
write generic/tk.h [tkh 8.6.2]
commit "2014-08-01 10:00:00" dkf "Tk 8.6.2"
tag core-8-6-2 [current] "2014-08-02 10:00:00" dkf
write generic/tkMenu.c [csrc tkMenu.c 61 31]
commit "2016-05-01 10:00:00" fvogel "Fix \[34e934161e\]: the wish manual on 8.6"
write generic/tkMenu.c [csrc tkMenu.c 62 31]
commit "2023-05-01 10:00:00" fvogel "Fix menubutton menus on 8.6: \[595d72d0a6\] again"

# trunk to 2020, then main from its last check-in on (as Tk did).
f update trunk
foreach {date user comment path v} {
    2013-06-01 jan.nijtmans "Fix menubutton relief on Windows" generic/tk.h 8.7a0
    2015-03-01 fvogel "Fix [595d72d0a6]: the active window on trunk" generic/tkButton.c 63
    2017-01-01 fvogel "Fix menubutton menus on macOS" generic/tk.h 8.7a1
    2019-01-01 marc_culler "Fix [34e934161e] on trunk" generic/tkMenu.c 64
} {
    if {$path eq "generic/tk.h"} { write $path [tkh $v] } else { write $path [csrc [file tail $path] $v 31] }
    commit "$date 10:00:00" $user $comment
}
set trunkTip [current]
write generic/tk.h [tkh 8.7a3]
commit "2020-03-01 10:00:00" jan.nijtmans "Start main: trunk is closed from here on" --branch main
f amend $trunkTip --close --date-override "2020-03-01 10:01:00" --user-override jan.nijtmans

# main, 2020 to 2026.
foreach {date user comment edits} {
    2020-09-01 jan.nijtmans "Fix [595d72d0a6]: the active window, for 8.7" {generic/tkButton.c 70}
    2021-02-01 fvogel "Document the window manager protocols again" {doc/wm.n 2}
    2021-06-01 dkf "Fix menubutton text on Wayland" {generic/tk.h 8.7a5}
    2022-03-01 marc_culler "Fix the README for 8.7" {README.md 8.7a6}
    2023-01-10 dkf "Build on macOS in CI" {.github/workflows/mac-build.yml 1}
    2023-06-01 jan.nijtmans "Samples for the hash prefix tests" {tests/prefix/a.txt 2817 tests/prefix/b.txt 6898 tests/prefix/c.txt 7864}
    2024-02-01 fvogel "Fix [34e934161e]: the wish manual, for 9.0" {generic/tkMenu.c 71}
    2024-06-01 dkf "Fix menubutton crash with a destroyed font" {generic/tkFont.c 72}
    2024-09-24 jan.nijtmans "Tk 9.0.0" {generic/tk.h 9.0.0 doc/wm.n 3}
} {
    foreach {path v} $edits {
        switch -glob -- $path {
            generic/tk.h { write $path [tkh $v] }
            doc/wm.n { write $path [wmn $v] }
            README.md { write $path [readme $v] }
            tests/prefix/* { write $path "Sample $v for Go to\n" }
            *.yml { write $path "name: mac-build\non: \[push\]\njobs:\n  build:\n    runs-on: macos-$v\n" }
            default { write $path [csrc [file tail $path] $v 31] }
        }
        catch {f add $path}
    }
    commit "$date 10:00:00" $user $comment
}
set tk900 [current]
tag core-9-0-0 $tk900 "2024-09-24 11:00:00" jan.nijtmans

# The 9.0 branch and its releases: each release on a branch of its own
# with only the release check-in (core-9-0-2-rc...), as Tk's.
write generic/tkWindow.c [csrc tkWindow.c 80 30]
commit "2024-10-01 10:00:00" jan.nijtmans "Fix a crash on exit (9.0)" --branch core-9-0-branch
write generic/tk.h [tkh 9.0.1]
commit "2024-12-01 10:00:00" jan.nijtmans "Tk 9.0.1"
tag core-9-0-1 [current] "2024-12-01 11:00:00" jan.nijtmans
write .github/workflows/mac-build.yml "name: mac-build\non: \[push\]\njobs:\n  build:\n    runs-on: macos-14\n"
commit "2025-03-01 10:00:00" jan.nijtmans "CI: macOS 14"
commit "2025-03-02 10:00:00" jan.nijtmans "Tk 9.0.2" --branch core-9-0-2-rc --allow-empty --tag core-9-0-2
f update core-9-0-branch
write generic/tk.h [tkh 9.0.3]
commit "2025-06-01 10:00:00" jan.nijtmans "Tk 9.0.3"
tag core-9-0-3 [current] "2025-06-01 11:00:00" jan.nijtmans
write generic/tkMenu.c [csrc tkMenu.c 81 31]
commit "2025-08-01 10:00:00" fvogel "Fix menubutton menus (9.0)"
commit "2025-09-01 10:00:00" jan.nijtmans "Tk 9.0.4" --branch core-9-0-4-rc --allow-empty --tag core-9-0-4
f update core-9-0-branch
write generic/tkFont.c [csrc tkFont.c 82 31]
commit "2026-02-01 10:00:00" fvogel "Fix fonts on 9.0 (Fix crash with a font of no family)"

# main after 9.0.0: branches merged in and not.
f update main
write win/makefile.vc "# Visual C++ makefile\n[prose 90 10]"
commit "2024-10-15 10:00:00" dkf "Fix the Windows build after 9.0.0"
write generic/tkButton.c [csrc tkButton.c 91 31]
commit "2024-11-15 10:00:00" fvogel "Fix menubutton focus ring"
write tests/menu.test [testfile menu.test 92 21]
commit "2025-01-15 10:00:00" fvogel "Fix menu tests on Windows"
write library/ttk/button.tcl [tcl ttkbutton 93 11]
commit "2025-02-15 10:00:00" fvogel "Fix ttk::button bindings"
# (9.0.1: the branch's later check-ins are newer than the merge.)
f merge core-9-0-1
commit "2025-04-01 10:00:00" jan.nijtmans "Merge 9.0.1"

# tip-698: a small branch, merged; revised_text: a propagating tag.
write generic/tkWindow.c [csrc tkWindow.c 100 30]
commit "2025-04-10 10:00:00" dkf "TIP 698: start" --branch tip-698
foreach i {1 2 3} {
    write generic/tkWindow.c [csrc tkWindow.c [expr {100 + $i}] 30]
    commit "2025-04-1$i 10:00:00" dkf "TIP 698: step $i"
}
f update main
f merge tip-698
commit "2025-04-20 10:00:00" dkf "Merge TIP 698"
write library/ttk/ttk.tcl [tcl ttk 110 11]
commit "2025-05-01 10:00:00" fvogel "Start revised text" --branch revised_text
tag tip-466 [current] "2025-05-01 10:30:00" fvogel --propagate
foreach i {1 2} {
    write library/ttk/ttk.tcl [tcl ttk [expr {110 + $i}] 11]
    commit "2025-05-0[expr {1 + $i}] 10:00:00" fvogel "Revised text: step $i"
}

# A branch merged at its last check-in, one merged earlier with check-ins
# since, one with a CI tag on its last check-in.
f update main
write generic/tkMenu.c [csrc tkMenu.c 120 31]
commit "2025-06-01 10:00:00" marc_culler "Fix the menubutton on macOS" --branch bug-merged
write generic/tkMenu.c [csrc tkMenu.c 121 31]
commit "2025-06-02 10:00:00" marc_culler "Fix the menubutton on macOS, the tests"
f update main
f merge bug-merged
commit "2025-06-10 10:00:00" marc_culler "Merge bug-merged"
write generic/tkFont.c [csrc tkFont.c 130 31]
commit "2025-07-01 10:00:00" dkf "Fix font sizes" --branch bug-earlier
write generic/tkFont.c [csrc tkFont.c 131 31]
commit "2025-07-02 10:00:00" dkf "Fix font sizes, again"
f update main
f merge bug-earlier
commit "2025-07-10 10:00:00" dkf "Merge bug-earlier"
f update bug-earlier
write generic/tkFont.c [csrc tkFont.c 132 31]
commit "2025-07-20 10:00:00" dkf "Fix font sizes after the merge"
f update main
write unix/Makefile.in "# Makefile.in --\n[prose 140 12]"
commit "2025-08-01 10:00:00" chrstphrchvz "X11: the cursor from a file" --branch x11-xcursor-file
write unix/Makefile.in "# Makefile.in --\n[prose 141 12]"
commit "2025-08-02 10:00:00" chrstphrchvz "X11: the cursor from a file, the build"
write unix/configure.ac "AC_INIT(\[tk\])\n[prose 142 8]"
commit "2025-08-03 10:00:00" chrstphrchvz "X11: the cursor from a file, configure" --tag core-x11-xcursor-file
f update main
write macosx/README "Tk for macOS\n\n[prose 150 8]"
commit "2025-10-01 10:00:00" marc_culler "Fix the core of the menu on macOS" --branch menu-fix
write macosx/README "Tk for macOS\n\n[prose 151 8]"
commit "2025-10-02 10:00:00" marc_culler "Fix the core of the menu on macOS: given up" --close

# main to 2026-10.
f update main
set long "Fix the geometry of a menubutton whose menu is changed while it is posted:\
    the size was computed from the old entries, so the button kept its old width until\
    it was configured again, which looked wrong with long labels and with images (all platforms)."
foreach {date user comment edits} [list \
    2025-11-01 dkf "Fix the native menu bar on macOS" {macosx/README 160} \
    2026-01-15 fvogel $long {generic/tkButton.c 161} \
    2026-04-01 dkf "Fix \[4eef1fa86e\]: menubutton -direction flush" {generic/tkButton.c 162} \
    2026-08-30 jan.nijtmans "Fix crash in the font chooser" {generic/tkFont.c 163} \
    2026-10-04 serhiy.storchaka "Fix \[4eef1fa86e\]: the tests of menubutton -direction" {tests/unixButton.test 164} \
    2026-10-20 serhiy.storchaka "Fix the README of main" {README.md 9.1a0} \
] {
    foreach {path v} $edits {
        switch -glob -- $path {
            README.md { write $path [readme $v] }
            *.test { write $path [testfile [file tail $path] $v 21] }
            macosx/README { write $path "Tk for macOS\n\n[prose $v 8]" }
            default { write $path [csrc [file tail $path] $v 31] }
        }
    }
    commit "$date 10:00:00" $user $comment
}
# A tag cancelled later.
tag test-tag [current] "2026-10-21 10:00:00" dkf
f tag cancel --date-override "2026-10-22 10:00:00" --user-override dkf test-tag [current]

# The hashes of check-ins that tickets name, by their comments.
set hash [dict create]
foreach {key comment} {
    fix86 "Fix menubutton menus on 8.6: \[595d72d0a6\] again"
    main1 "Fix menubutton focus ring"
} {
    set h [lindex [f sql -R $R ".mode list" "SELECT b.uuid FROM blob b JOIN event e ON e.objid=b.rid WHERE e.type='ci' AND e.comment='[string map {' ''} $comment]'"] 0]
    dict set hash ci:$key $h
    # (The 10 digits links are usually written with.)
    dict set hash ci10:$key [string range $h 0 9]
}
f close --force
cd $dir
file delete -force $co

# ------------------------------------------------------------- artifacts

# Artifacts by name: their text names others as @NAME@, by hash.  Written
# in waves: first those that name none not written yet; each wave takes one
# "fossil md5sum" (the Z card) and one "fossil sha3sum".
set pending {}
set raw {}
proc artifact {name text} { lappend ::pending $name $text }
# A file's content as is (an attachment), not a card text.
proc blob {name bytes} { dict set ::raw $name $bytes }
proc card {text} { string map [list \\ \\\\ " " \\s \n \\n \r \\r \t \\t] $text }
proc D {date} { return "D [string map {{ } T} $date].000\n" }

proc ticket {uuid changes} {
    set i 0
    foreach {date user fields} $changes {
        set t [D $date]
        foreach name [lsort [dict keys $fields]] {
            append t "J $name [card [dict get $fields $name]]\n"
        }
        append t "K $uuid\nU $user\n"
        artifact tkt-$uuid-[incr i] $t
    }
}
# A comment as Tk's ticket page writes it.
proc says {user text {mimetype text/x-fossil-wiki}} {
    dict create icomment $text login $user username $user mimetype $mimetype
}
proc wikipage {name versions} {
    set i 0
    foreach {date user mimetype text} $versions {
        set t "[D $date]L [card $name]\n"
        if {$mimetype ne "text/x-fossil-wiki"} { append t "N $mimetype\n" }
        if {$i} { append t "P @wiki-$name-$i@\n" }
        set bytes [encoding convertto utf-8 $text]
        append t "U $user\nW [string length $bytes]\n$text\n"
        artifact wiki-$name-[incr i] $t
    }
}
# A technote of the time WHEN, ID (40 hex digits), as "fossil wiki create
# -t" writes one.
proc technote {date user when id comment text} {
    set bytes [encoding convertto utf-8 $text]
    set t "C [card $comment]\n[D $date]E [string map {{ } T} $when] $id\nN text/x-fossil-wiki\n"
    append t "U $user\nW [string length $bytes]\n$text\n"
    artifact technote-$id $t
}
proc attach {name target src user date {comment ""}} {
    set t "A [card $name] $target $src\n"
    if {$comment ne ""} { append t "C [card $comment]\n" }
    append t "[D $date]U $user\n"
    artifact att-$target-$name $t
}
proc post {name date user title text args} {
    set t [D $date]
    if {[dict exists $args -root]} { append t "G @[dict get $args -root]@\n" }
    if {$title ne ""} { append t "H [card $title]\n" }
    if {[dict exists $args -to]} { append t "I @[dict get $args -to]@\n" }
    set bytes [encoding convertto utf-8 $text]
    append t "N text/x-markdown\n"
    # (An edit: the post it replaces.)
    if {[dict exists $args -prev]} { append t "P @[dict get $args -prev]@\n" }
    append t "U $user\nW [string length $bytes]\n$text\n"
    artifact $name $t
}

# The artifacts given so far, into REPO.
proc writeArtifacts {R} {
    global pending raw hash dir
    set adir $dir/artifacts
    file delete -force $adir
    file mkdir $adir
    set files {}
    set n 0
    dict for {name bytes} $raw {
        set path $adir/[incr n]
        set ch [open $path wb]; puts -nonewline $ch $bytes; close $ch
        set sum [lindex [f sha3sum $path] 0]
        dict set hash $name $sum
        lappend files $path $sum
    }
    while {[llength $pending]} {
        set wave {}
        set later {}
        foreach {name text} $pending {
            set ok 1
            foreach {- ref} [regexp -all -inline {@([^@\n]+)@} $text] {
                if {![dict exists $hash $ref]} { set ok 0 }
            }
            if {$ok} { lappend wave $name $text } else { lappend later $name $text }
        }
        if {![llength $wave]} { error "artifacts naming unknown ones: [dict keys $later]" }
        set paths {}
        foreach {name text} $wave {
            set map {}
            foreach {- ref} [regexp -all -inline {@([^@\n]+)@} $text] { lappend map @$ref@ [dict get $hash $ref] }
            set text [string map $map $text]
            set path $adir/[incr n]
            set ch [open $path wb]; puts -nonewline $ch [encoding convertto utf-8 $text]; close $ch
            lappend paths $path
        }
        set md5 {}
        foreach line [split [f md5sum {*}$paths] \n] { lappend md5 [lindex $line 0] }
        foreach path $paths sum $md5 {
            set ch [open $path ab]; puts -nonewline $ch "Z $sum\n"; close $ch
        }
        set sums {}
        foreach line [split [f sha3sum {*}$paths] \n] { lappend sums [lindex $line 0] }
        foreach {name -} $wave path $paths sum $sums {
            dict set hash $name $sum
            lappend files $path $sum
        }
        set pending $later
    }
    # One bundle of them all, as "fossil bundle export" writes it.
    set code [lindex [f sql -R $R ".mode list" "SELECT value FROM config WHERE name='project-code'"] 0]
    set sql "ATTACH '$dir/all.bundle' AS b;\nCREATE TABLE b.bconfig(bcname TEXT, bcvalue ANY);\n"
    append sql "CREATE TABLE b.bblob(blobid INTEGER PRIMARY KEY, uuid TEXT NOT NULL, sz INT NOT NULL, delta ANY, notes TEXT, data BLOB);\n"
    append sql "INSERT INTO b.bconfig VALUES('project-code', '$code');\n"
    foreach {path sum} $files {
        append sql "INSERT INTO b.bblob(uuid, sz, delta, notes, data) VALUES('$sum', length(readfile('$path')), NULL, '', compress(readfile('$path')));\n"
    }
    file delete $dir/all.bundle
    set ch [open $dir/all.sql w]; puts $ch $sql; close $ch
    exec fossil sql --no-repository < $dir/all.sql 2>@1
    f bundle import $dir/all.bundle --publish -R $R
    file delete -force $adir $dir/all.bundle $dir/all.sql
    set pending {}
    set raw {}
    # (The ticket table of the imported setup: made by a rebuild.)
    f rebuild -R $R
}

# ------------------------------------------------------------- tickets

# A ticket ID of the number N: 40 hex digits, the first 10 unlike others'.
proc tid {n} {
    set x [expr {($n * 2654435761 + 0x5bd1e995) % 4294967296}]
    string range [format %08x%08x%08x%08x%08x $x [expr {$x ^ 0x9e3779b9}] $n [expr {$x * 3 % 4294967296}] $x] 0 39
}
proc new {fields args} {
    dict merge {status Open resolution "" priority {5 Medium} severity Minor type Bug
        subsystem {(unused)} foundin 8.6 assignee "" private_contact "" cmimetype text/x-fossil-plain} $fields {*}$args
}
set closed {status Closed resolution Fixed}

ticket 2225507fffffffffffffffffffffffffffffffff [list \
    "2009-03-02 09:00:00" randolf [new {title "Menubutton menus on Windows lose their colours"
        subsystem "13. Win Menus" priority "9 Immediate" severity Critical foundin "obsolete: 8.4.19"
        submitter randolf assignee aku comment "The menus of menubuttons are drawn in the system colours."}] \
    "2009-03-05 09:00:00" aku [says aku "You are right, it has the same cause as \[2128087\]: the colours of the\
        menu are taken from the menubutton when the menu is posted, not when it is configured, and the\
        fix of that one only covered the menus of menubars.  The menus of menubuttons need the same\
        change in the Windows code; it should not be hard to do, but it has to wait for the\
        changes to the menu code that were reverted in that merge."] \
    "2009-04-01 09:00:00" aku {severity Minor login aku username aku} \
    "2009-06-01 09:00:00" aku [dict merge $closed {closer aku closedate 2454983.875} [says aku "Fixed on trunk."]] \
]
ticket 077d49828b995ed700f9210c1c1789a90cff4d37 [list \
    "2020-05-02 09:00:00" chrstphrchvz [new {title "ttk::notebook tabs lost with -state hidden"
        type Bug subsystem "88. Themed Tk" foundin 8.6.10 submitter chrstphrchvz
        comment "Hidden tabs come back when the notebook is configured."}] \
    "2020-05-10 09:00:00" fvogel [says fvogel "The failing case now works:\n<verbatim>\n    package require Tk\n    pack \[::ttk::notebook .n\] -fill both -expand true\n    foreach tabs {Edit Check Close} {\n        ::ttk::entry .n.\[string tolower \$tabs\]\n        .n add .n.\[string tolower \$tabs\] -text \$tabs\n    }\n</verbatim>"] \
]
ticket 4c595d4d788ea5142731ae3a3395151c32a724d1 [list \
    "2021-01-10 09:00:00" fvogel [new {title "Menubutton with -indicatoron draws the indicator over the text"
        submitter fvogel comment "The indicator overlaps long texts."}] \
    "2021-01-11 09:00:00" dkf [says dkf "[prose 200 12]\n\n[prose 201 12]"] \
    "2021-01-12 09:00:00" fvogel [says fvogel "[prose 202 12]\n\n[prose 203 12]"] \
    "2021-01-13 09:00:00" dkf [says dkf "[prose 204 12]\n\n[prose 205 12]"] \
    "2021-01-20 09:00:00" fvogel [says fvogel "The indicator is placed from the old size.\n\nSame cause as \[80213d1b1c\]." text/x-markdown] \
]
ticket 80213d1b1c8458e1655b608d73b637d7d273879f [list \
    "2020-12-01 09:00:00" fvogel [new {title "Menubutton indicator too small with large fonts"
        submitter fvogel foundin 8.6.11 comment "The indicator does not follow the font."}] \
]
ticket 595d72d0a6000000000000000000000000000000 [list \
    "2013-02-01 09:00:00" erikleunissen [new {title "The active window is lost after a dialog closes"
        submitter erikleunissen foundin 8.6.0 severity Important comment "After tk_messageBox no window is active."}] \
    "2013-02-02 09:00:00" jan.nijtmans [says jan.nijtmans "A script that shows it is attached."] \
    "2013-03-01 09:00:00" jan.nijtmans [dict merge $closed {closer jan.nijtmans} [says jan.nijtmans "Fixed on core-8-6-branch."]] \
]
ticket 34e934161e000000000000000000000000000000 [list \
    "2016-04-01 09:00:00" erikleunissen [new {title "The wish manual does not document -use" type Patch
        submitter erikleunissen foundin 8.6.5 comment "A patch for the manual is attached."}] \
    "2016-04-02 09:00:00" fvogel [says fvogel "Thanks, the patch looks right."] \
    "2016-05-01 09:00:00" fvogel [dict merge $closed {closer fvogel} [says fvogel "Applied."]] \
]
ticket 4eef1fa86e61ce5f6fbfce23d90a6e422b2719b4 [list \
    "2026-03-20 09:00:00" oehhar [new {title "menubutton -direction flush does not work" submitter oehhar
        foundin 9.0.1 comment "The menu is placed below the button."}] \
    "2026-04-02 09:00:00" dkf [says dkf "Fixed on main." text/plain] \
    "2026-10-13 11:30:59" kevin_walzer [dict merge $closed {closer kevin_walzer closedate 2461326.9798543635} [says kevin_walzer "Fix merged to trunk. Thank you." text/plain]] \
]
# The kinds of tickets the tests look for: open ones of each priority and
# severity, closed ones of each resolution, ones named by others.
set n 0
foreach {date user fields} {
    2011-05-01 dkf {title "Crash in menubutton when its menu is destroyed" priority "9 Immediate" severity Critical status Closed resolution Fixed closer dkf foundin 8.5.19}
    2026-06-01 oehhar {title "Crash on exit with a menubutton in a dialog" priority "9 Immediate" severity Critical foundin 9.0.0}
    2026-05-01 randolf {title "Menubutton text is cut on Wayland" type Support priority 8 severity Minor foundin 9.0b2}
    2026-04-20 oehhar {title "Menubutton focus ring missing on X11" priority "5 Medium" severity Minor foundin 8.6.13 assignee fvogel}
    2026-04-10 randolf {title "Native menu look for menubutton on macOS" type RFE priority 2 severity Cosmetic foundin 9.1a0}
    2026-03-01 chrstphrchvz {title "Patch: menubutton -compound with images" type Patch priority "5 Medium" severity Important foundin 8.6.16}
    2025-12-01 dkf {title "Menubutton -textvariable not traced when the menu is torn off" status Pending priority "3 Low" severity Severe foundin 8.6b1}
    2024-01-01 randolf {title "Menubutton menus posted twice" status Closed resolution Duplicate closer dkf foundin 8.6.10}
    2023-01-01 oehhar {title "Menubutton should accept -command" status Closed resolution "Wont Fix" type RFE closer dkf foundin 8.7a5}
    2022-01-01 chrstphrchvz {title "Menubutton crash with a huge font" status Closed resolution "Works For Me" closer fvogel foundin 9.0}
    2025-09-01 jan.nijtmans {title "tk_getOpenFile ignores -initialdir on Windows" foundin 8.6}
    2025-08-01 fvogel {title "Menubutton regression on the 8.6 branch" foundin 8.6}
    2025-07-01 marc_culler {title "Revised text: tags lost after a replace" foundin "revised_text " subsystem "18. [text]"}
    2010-01-01 dkf {title "Menubutton bitmap drawn twice" status Closed resolution Fixed closer dkf foundin "obsolete: 8.5"}
    2019-01-01 fvogel {title "A ticket with a long title to show how the header of the details wraps when the window is narrow" foundin 8.6.9 subsystem "70. Event Loop"}
    2018-01-01 "" {title "Menubutton -width ignored for images" foundin 8.6.8 cmimetype text/plain}
} {
    set uuid [tid [incr n]]
    if {![dict exists $fields submitter]} { dict set fields submitter $user }
    set changes [list "$date 09:00:00" [expr {$user eq "" ? "anonymous" : $user}] [new $fields]]
    switch -glob -- [dict get $fields title] {
        "tk_getOpenFile*" { lappend changes "$date 12:00:00" fvogel [says fvogel "Call `tk_getOpenFile` with **-initialdir** a full path." text/x-markdown] }
        "Menubutton regression*" {
            lappend changes "$date 12:00:00" fvogel [says fvogel "Fixed on <b>8.6</b> in \[@ci10:fix86@\] and on main in \[@ci:main1@|the main fix\]; see \[/timeline?r=core-8-6-branch|the branch\]."]
        }
        "Menubutton focus ring*" { lappend changes "$date 12:00:00" bll [says bll "Seen here too."] }
        "Menubutton text is cut*" { lappend changes "$date 12:00:00" dkf [says dkf "Only with fractional scaling."] }
        "A ticket with a long title*" { lappend changes "$date 12:00:00" dkf [says dkf "[prose 210 3]"] }
    }
    ticket $uuid $changes
}

# A ticket changed every month of the last year, up to the day the
# repository is made (run.sh makes it again each month): the last year of
# Statistics has something in it.
set now [clock seconds]
set changes {}
for {set k 13} {$k >= 1} {incr k -1} {
    set date [clock format [clock add $now -$k months -timezone :UTC] -format "%Y-%m-%d 08:00:00" -timezone :UTC]
    if {![llength $changes]} {
        lappend changes $date oehhar [new {title "The nightly build fails now and then" submitter oehhar foundin 9.1a0
            comment "The build of main fails about once a month."}]
    } else {
        lappend changes $date oehhar [says oehhar "Failed again."]
    }
}
lappend changes [clock format [expr {$now - 86400}] -format "%Y-%m-%d 08:00:00" -timezone :UTC] oehhar [says oehhar "And again."]
ticket [tid 99] $changes

# Attachments: of 595d72d0a6 three whose content this repository lacks (as
# in a clone that never had them); of 34e934161e a patch that is applied
# already.
foreach {name sum} {
    active-window-repro.tcl 1111111111111111111111111111111111111111111111111111111111111111
    active-window.patch 2222222222222222222222222222222222222222222222222222222222222222
    repro.tcl 3333333333333333333333333333333333333333333333333333333333333333
} {
    attach $name 595d72d0a6000000000000000000000000000000 $sum erikleunissen "2013-02-01 10:00:00"
}
blob wish_manual.patch [wishPatch]
attach wish_manual.patch 34e934161e000000000000000000000000000000 @wish_manual.patch@ erikleunissen "2016-04-01 10:00:00" "The patch"

# ------------------------------------------------------------- wiki, forum

wikipage "Tk Source Code" [list "2020-01-01 10:00:00" jan.nijtmans text/x-fossil-wiki \
    "<h2>Tk</h2>\n\nThe source code of Tk.  See \[Migrating scripts to Tk 9\].\n"]
set mig1 "# Migrating scripts to Tk 9\n\n## Fonts\n\n[prose 220 6]\n## Images\n\n[prose 221 6]"
set mig2 "$mig1\n## Events\n\n[prose 222 8]"
set mig3 "$mig2\n## Menus\n\n[prose 223 8]\n## Text\n\n[prose 224 8]"
wikipage "Migrating scripts to Tk 9" [list \
    "2024-09-01 10:00:00" jan.nijtmans text/x-markdown $mig1 \
    "2024-10-01 10:00:00" fvogel text/x-markdown $mig2 \
    "2025-03-01 10:00:00" jan.nijtmans text/x-markdown $mig3]
wikipage "Fixing old binary attachments" [list "2025-05-01 10:00:00" dkf text/x-markdown \
    "# Fixing old binary attachments\n\n[prose 230 6]"]
wikipage "branch/core-9-0-branch" [list "2024-10-02 10:00:00" jan.nijtmans text/x-markdown \
    "The 9.0 maintenance branch.\n"]

post forum1 "2025-01-10 10:00:00" fvogel "Menubutton changes in Tk 9" "What changed for menubuttons in Tk 9?\n"
post forum2 "2025-01-11 10:00:00" dkf "" "See the wiki page about migrating.\n" -root forum1 -to forum1
post forum3 "2025-02-01 10:00:00" marc_culler "" "And on macOS 15?\n" -root forum1 -to forum2

writeArtifacts $R

# Where it came from, as a clone would have it (no password); the user
# whose check-ins are "mine".
f sql -R $R "REPLACE INTO config(name, value, mtime) VALUES('last-sync-url', 'https://core.tcl-lang.org/tk', now()), ('default-user', 'serhiy.storchaka', now()), ('project-description', 'The Tk toolkit (a small copy for the tests of Tktaalik)', now())"
# (Not left from the build.)
f unset mtime-changes -R $R
f sql -R $R "VACUUM"

# ------------------------------------------------------------- tips.fossil

set T $dir/tips.fossil
newRepo $T "2017-01-01 00:00:00" dkf "Tcl Improvement Proposals" tips-ticket.conf
ticket [tid 512] [list "2018-05-01 10:00:00" dkf {type Typo status Open tip_number 512 priority 3
    severity Minor foundin 8.6 title "TIP 512 documentation updates" comment "A typo in the text."}]
ticket [tid 513] [list "2018-06-01 10:00:00" dkf {type Typo status Closed resolution Fixed tip_number 513
    priority 3 severity Minor foundin 8.6 title "TIP 513 example fixed" comment "The example was wrong."}]
technote "2017-09-07 12:27:37" dkf "2017-05-13 00:00:00" 7f8340c80812ed8aef752458c8f3611948c35458 \
    "TIP 467 - Accepted" "<p>TIP 467 was accepted.</p>\n"
writeArtifacts $T
f sql -R $T "REPLACE INTO config(name, value, mtime) VALUES('last-sync-url', 'https://core.tcl-lang.org/tips', now())"
f sql -R $T "VACUUM"

# ------------------------------------------------------------- forum.fossil

# The thread of the Fossil forum's tests: replies to replies, edits of the
# first post and of replies (each name: its post in that thread).
set F $dir/forum.fossil
newRepo $F "2018-07-01 00:00:00" drh "Fossil forum" ""
set title "New thread for testing (title revised)"
post p7 "2018-07-24 23:36:39" drh "New thread for testing" "The first post.\n"
post p8 "2018-07-25 13:08:36" drh "" "A reply.\n" -root p7 -to p7
post p9 "2018-07-25 13:33:17" drh "" "A reply to a reply.\n" -root p7 -to p8
post p10 "2018-07-25 14:59:38" drh "" "Another reply.\n" -root p7 -to p7
post p12 "2018-07-25 15:33:05" drh "" "A reply to a reply, edited.\n" -root p7 -to p8 -prev p9
post p13 "2018-07-25 16:08:31" drh $title "The first post, edited.\n" -root p7 -prev p7
post p14 "2018-07-25 17:50:20" drh "" "Deeper.\n" -root p7 -to p12
post p15 "2018-07-25 17:50:52" drh "" "Deeper, edited.\n" -root p7 -to p12 -prev p14
post p17 "2018-07-25 22:30:03" drh "" "A reply to the edited first post.\n" -root p7 -to p13
post p18 "2018-07-25 22:44:40" drh "" "Another one deeper.\n" -root p7 -to p12
post p19 "2018-07-25 22:46:47" drh "" "Deepest.\n" -root p7 -to p18
post p20 "2018-07-25 22:47:54" drh "" "And another.\n" -root p7 -to p12
post p21 "2018-07-26 00:35:40" drh "" "Another one deeper, edited.\n" -root p7 -to p12 -prev p18
post p22 "2018-07-26 10:42:26" drh "" "Deepest again.\n" -root p7 -to p20
post q1 "2020-03-01 10:00:00" stephan "Exporting to git" "How does fossil export git name the branches?\n"
post q2 "2020-03-02 10:00:00" drh "" "See fossil help export.\n" -root q1 -to q1
writeArtifacts $F
f sql -R $F "REPLACE INTO config(name, value, mtime) VALUES('last-sync-url', 'https://fossil-scm.org/forum', now())"
f sql -R $F "VACUUM"

file delete -force $env(FOSSIL_HOME)
foreach r [list $R $T $F] { puts "[file size $r] bytes: $r" }
exit
