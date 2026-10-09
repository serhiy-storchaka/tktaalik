# install.sh: the application, the command, the menu launcher and icons
# under a prefix (here a temporary one); the installed copy runs; --destdir
# for packages; --uninstall.
source [file join [file dirname [info script]] common.tcl]
if {$tcl_platform(platform) eq "windows"} {
    # (On Windows a shortcut to Wish runs it: docs/configuration.md.)
    puts "== $T(name): skipped (install.sh is for Unix desktops)"
    exit 0
}
set top [file dirname $T(dir)]
set p $T(tmp)/prefix
set wish [info nameofexecutable]
set code [catch {exec sh $top/install.sh --prefix $p --wish $wish 2>@1} out]
check "installed: [lindex [split $out \n] 0]" {!$code}
set app $p/share/tktaalik
check "the application" {[file executable $app/tktaalik] && [file exists $app/LICENSE]}
foreach {dir glob} {lib *.tcl icons *.png docs *.md} {
    set n [llength [glob -nocomplain -directory $app/$dir $glob]]
    set want [llength [glob -directory $top/$dir $glob]]
    check "$dir: $n files" {$n == $want}
}
set f [open $p/bin/tktaalik]; set cmd [read $f]; close $f
check "the command runs it with that wish" {[file executable $p/bin/tktaalik] && [string first "exec \"$wish\" \"$app/tktaalik\" \"\$@\"" $cmd] >= 0}
set f [open $p/share/applications/tktaalik.desktop]; set desktop [read $f]; close $f
check "the menu launcher" {[string first "Exec=\"$p/bin/tktaalik\" %f" $desktop] >= 0}
check "the icon, every size" {[llength [glob -nocomplain $p/share/icons/hicolor/*/apps/tktaalik.png]] == 7}
# The installed copy runs: its manual and icons found where it is.
set out [exec -ignorestderr $wish << "set ::tktaalik_test 1
source $app/tktaalik
puts \[list \$help::dir \$icons::dir \[file exists \$help::dir/index.md\] \[file exists \$icons::dir/tktaalik-64.png\] \$tktaalik::version\]
exit"]
lassign $out hdir idir hok iok version
check "runs from there: $hdir" {$hdir eq "$app/docs" && $hok && $iok && $version eq $tktaalik::version}
# A second install replaces it (no stale files).
set stale [open $app/lib/stale.tcl w]; close $stale
exec sh $top/install.sh --prefix $p --wish $wish 2>@1
check "reinstalled without old files" {![file exists $app/lib/stale.tcl]}
# For packages: written under DESTDIR, pointing to PREFIX.
set d $T(tmp)/stage
exec sh $top/install.sh --prefix /usr --destdir $d 2>@1
set f [open $d/usr/bin/tktaalik]; set cmd [read $f]; close $f
check "--destdir: files under it, paths of the prefix" {[file exists $d/usr/share/tktaalik/tktaalik] && [string first "\"/usr/share/tktaalik/tktaalik\"" $cmd] >= 0 && ![file exists /usr/share/tktaalik/stale.tcl]}
# Uninstall: nothing of it left.
exec sh $top/install.sh --prefix $p --uninstall 2>@1
set left [concat [glob -nocomplain $p/share/tktaalik $p/bin/tktaalik $p/share/applications/tktaalik.desktop] \
    [glob -nocomplain $p/share/icons/hicolor/*/apps/tktaalik.png]]
check "uninstalled: [llength $left] left" {![llength $left]}
check "a relative prefix refused" {[catch {exec sh $top/install.sh --prefix rel 2>@1} msg] && [string match "*absolute*" $msg]}
done
