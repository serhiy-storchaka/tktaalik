# The Unversioned files window (fossil uv, on a scratch copy): list, find,
# view, export, add, edit, rename, touch, remove.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set R $W/tk.fossil
fossil::run remote https://example.invalid/tk -R $R
set ::boxes {}
set ::answer ok
proc tk_getOpenFile {args} { return $::openFiles }
proc tk_chooseDirectory {args} { return $::saveDir }
set ::browsed {}
set ::viewed {}
rename diffview::show realShow
proc diffview::show {title text args} { lappend ::viewed [list $title $text]; set ::viewedArgs $args }
# Answer the next name dialog.
proc answer {name {done ok}} {
    after 200 [list apply {{name done} {
        set tkuv::dlgName $name
        set tkuv::dlgDone $done
    }} $name $done]
}
# Add: the name (or folder) dialog, then the time one (empty: now).
proc answerAdd {name {time ""}} {
    answer $name
    after 700 [list apply {{time} {
        set tkuv::dlgName $time
        set tkuv::dlgDone ok
    }} $time]
}
proc readFile {name} { set f [open $name rb]; set d [read $f]; close $f; return $d }
file mkdir $T(tmp)/in
foreach {name text} {readme.txt "Read me\n" "release notes.html" "<p>1.0</p>\n" crlf.txt "a\r\nb\r\n"} {
    set f [open $T(tmp)/in/$name wb]; puts -nonewline $f $text; close $f
}
set f [open $T(tmp)/in/tk.zip wb]; puts -nonewline $f "PK\0\0zip"; close $f

tktaalik::main tickets [list $R]
update
set entries {}
for {set i 0} {$i <= [.menubar.repository index end]} {incr i} {
    if {[.menubar.repository type $i] eq "command"} { lappend entries [.menubar.repository entrycget $i -label] }
}
check "in the Repository menu: $entries" {"Unversioned files\u2026" in $entries}
tkuv::window; update
set t .uv.list.t
check "none: $tkuv::status" {[llength [$t children {}]] == 0 && $tkuv::status eq "No unversioned files"}
check "buttons off" {[.uv.b.view instate disabled] && [.uv.b.remove instate disabled] && [.uv.b.add instate !disabled]}

# Add one, under a name with a folder; cancelled first.
set ::openFiles [list $T(tmp)/in/readme.txt]
answer "" cancel
tkuv::add; update
check "cancelled" {[llength [$t children {}]] == 0}
answerAdd doc/readme.txt
set ::boxes {}
tkuv::add; update
check "asked: [lindex $::boxes 0]" {[lindex $::boxes 0] eq "Add doc/readme.txt?"}
check "added: [$t children {}]" {[$t children {}] eq "doc/readme.txt" && [$t selection] eq "doc/readme.txt"}
check "size, date, hash: [$t item doc/readme.txt -values]" {[$t set doc/readme.txt size] eq "8 bytes" && [$t set doc/readme.txt stored] eq "8 bytes" && [regexp {^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$} [$t set doc/readme.txt date]] && [string length [$t set doc/readme.txt hash]] == 16}
# Several, in a folder.
set ::openFiles [list $T(tmp)/in/tk.zip "$T(tmp)/in/release notes.html" $T(tmp)/in/crlf.txt]
answerAdd releases/ "2025-01-02 03:04:05"
tkuv::add; update
check "the time given (--mtime): [$t set releases/tk.zip date]" {[$t set releases/tk.zip date] eq "2025-01-02 03:04:05"}
check "added: [$t children {}]" {[$t children {}] eq {doc/readme.txt releases/crlf.txt releases/release_notes.html releases/tk.zip} && [llength [$t selection]] == 3}
check "status: $tkuv::status" {[string match "4 files, *uv sync*" $tkuv::status]}
set db [fossil::sql $R "SELECT name FROM unversioned WHERE hash IS NOT NULL ORDER BY name"]
check "in the repository" {[llength $db] == 4}

# Find: a part, a pattern.
set tkuv::filter NOTES; tkuv::showList
check "find a part: [$t children {}]" {[$t children {}] eq "releases/release_notes.html"}
set tkuv::filter *.zip; tkuv::showList
check "find a pattern: [$t children {}], $tkuv::status" {[$t children {}] eq "releases/tk.zip" && [string match "1 of 4 files*" $tkuv::status]}
set tkuv::filter ""; tkuv::showList

# View: text, not binary.
$t selection set [list doc/readme.txt]; update
check "one selected: View on" {[.uv.b.view instate !disabled] && [.uv.b.edit instate !disabled]}
tkuv::view
check "viewed: [lindex $::viewed end]" {[lindex $::viewed end] eq [list doc/readme.txt "Read me\n"]}
check "kept above this window: $::viewedArgs" {$::viewedArgs eq {-transient .uv}}
$t selection set [list releases/tk.zip]; update
set ::boxes {}
set n [llength $::viewed]
tkuv::view
check "binary: not viewed ([lindex $::boxes 0])" {[llength $::viewed] == $n && [string match "*not a text file*" [lindex $::boxes 0]]}

# Export: one to a file (binary intact), several to a folder.
set ::saveTo $T(tmp)/out.zip
tkuv::export
check "exported one" {[readFile $::saveTo] eq "PK\0\0zip"}
set ::saveDir $T(tmp)/outdir
$t selection set [list doc/readme.txt releases/tk.zip]; update
check "two selected: View off, Export on" {[.uv.b.view instate disabled] && [.uv.b.export instate !disabled]}
tkuv::export
check "exported two: $tkuv::status" {[readFile $T(tmp)/outdir/doc/readme.txt] eq "Read me\n" && [file exists $T(tmp)/outdir/releases/tk.zip]}

# Edit a text file (CRLF kept).
$t selection set [list releases/crlf.txt]; update
whenOpen .uv.edit {
    .uv.edit.f.t insert end "c\n"
    set tkuv::dlgDone ok
}
tkuv::edit; update
fossil::run uv export releases/crlf.txt $T(tmp)/crlf.out -R $R
set out [readFile $T(tmp)/crlf.out]
check "edited, CRLF kept: [string map [list \r <CR> \n <LF>] $out]" {$out eq "a\r\nb\r\nc\r\n"}
# Not changed: nothing stored.
set before [fossil::sql $R "SELECT hash FROM unversioned WHERE name='doc/readme.txt'"]
$t selection set [list doc/readme.txt]; update
whenOpen .uv.edit {set tkuv::dlgDone ok}
set ::boxes {}
tkuv::edit; update
check "unchanged: not asked, not stored" {![llength $::boxes] && [fossil::sql $R "SELECT hash FROM unversioned WHERE name='doc/readme.txt'"] eq $before}

# Rename.
$t selection set [list doc/readme.txt]; update
answer README.txt
tkuv::renameFile; update
check "renamed: [$t children {}]" {"README.txt" in [$t children {}] && "doc/readme.txt" ni [$t children {}] && [$t selection] eq "README.txt"}
check "same content" {[lindex [fossil::run uv cat README.txt -R $R] 1] eq "Read me"}

# Touch: a date.
$t selection set [list README.txt releases/tk.zip]; update
answer "2020-01-02 03:04:05"
tkuv::touch; update
check "touched: [$t set README.txt date], [$t set releases/tk.zip date]" {[$t set README.txt date] eq "2020-01-02 03:04:05" && [$t set releases/tk.zip date] eq "2020-01-02 03:04:05"}
answer "yesterday"
set ::boxes {}
tkuv::touch; update
check "a bad date: [lindex $::boxes 0]" {[string match "The time*" [lindex $::boxes 0]]}

# Browse.
$t selection set [list releases/release_notes.html]; update
tkuv::browse
check "browse: [lindex $::browsed end]" {[lindex $::browsed end] eq "https://example.invalid/tk/uv/releases/release_notes.html"}
# Names Fossil does not take: said before anything is done.
foreach bad {"a b.txt" releases/ ../x /abs} {
    $t selection set [list README.txt]; update
    answer $bad
    set ::boxes {}
    tkuv::renameFile; update
    check "rename to [list $bad]: [lindex $::boxes 0]" {[llength $::boxes] == 1 && "README.txt" in [$t children {}]}
}

# Remove two (cancelled first): gone from the list, also with a row kept
# for the sync.
$t selection set [list README.txt releases/tk.zip]; update
set ::answer cancel
tkuv::remove; update
check "cancelled: [llength [$t children {}]]" {[llength [$t children {}]] == 4}
set ::answer ok
tkuv::remove; update
check "removed: [$t children {}]" {[$t children {}] eq {releases/crlf.txt releases/release_notes.html}}
check "in the repository: rows without a hash" {[fossil::sql $R "SELECT count(*) FROM unversioned WHERE hash IS NULL"] == 3}
check "never synced" {[llength [fossil::sql $R "SELECT 1 FROM config WHERE name GLOB 'uv-sync*'"]] == 0}

# Images: in a window of their own (kept above this one); one Tk cannot
# show (a JPEG without Img): View disabled, a double-click opens it on the
# server instead.
set img [image create photo -width 30 -height 12]
$img put red -to 0 0 30 12
$img write $T(tmp)/in/shot.png -format png
image delete $img
set f [open $T(tmp)/in/photo.jpg wb]; puts -nonewline $f "\xff\xd8\xff\xe0 not really"; close $f
fossil::run uv add $T(tmp)/in/shot.png --as pics/shot.png -R $R
fossil::run uv add $T(tmp)/in/photo.jpg --as pics/photo.jpg -R $R
tkuv::reload; update
$t selection set [list pics/shot.png]; update
check "an image: View on" {[.uv.b.view instate !disabled]}
set n [llength $::viewed]
tkuv::view; update
set iw [imageview::windowFor .uv [lindex [dict get $tkuv::files pics/shot.png] 2]]
check "the image window: [expr {[winfo exists $iw] ? [wm title $iw] : "none"}], above [expr {[winfo exists $iw] ? [wm transient $iw] : ""}]" \
    {[winfo exists $iw] && [string match "pics/shot.png*30*12" [wm title $iw]] && [wm transient $iw] eq ".uv"
     && [llength $::viewed] == $n}
tkuv::view; update
check "again: the same window" {[llength [lsearch -all -glob [winfo children .uv] .uv.image*]] == 1}
destroy $iw
$t selection set [list pics/photo.jpg]; update
if {[catch {package require img::jpeg}]} {
    check "a JPEG without Img: View disabled" {[.uv.b.view instate disabled]}
    set ::browsed {}
    tkuv::view; update
    check "a double-click opens it on the server: [lindex $::browsed end]" \
        {[string match "*/uv/pics/photo.jpg" [lindex $::browsed end]] && ![llength [lsearch -all -glob [winfo children .uv] .uv.image*]]}
} else {
    check "a JPEG with Img: View on" {[.uv.b.view instate !disabled]}
}

# Another repository: follows it.
tktaalik::openPath $T(repo); update
check "other repository: [wm title .uv]" {[llength [$t children {}]] == 0 && [string match "Unversioned files*" [wm title .uv]]}
done
