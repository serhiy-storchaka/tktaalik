# The application icon (_NET_WM_ICON).
source [file join [file dirname [info script]] common.tcl]
if {[auto_execok xprop] eq "" || [auto_execok xwininfo] eq ""} {
    puts "== $T(name): skipped (needs xprop and xwininfo)"
    exit 0
}
tktaalik::main tickets [list $T(repo)]
update
proc wrapper {w} { regexp {Parent window id: (0x[0-9a-f]+)} [exec xwininfo -id [winfo id $w] -tree] -> p; return $p }
set id [wrapper .]
set p [exec xprop -len 99999999 -id $id _NET_WM_ICON]
set sizes [lmap {- w h} [regexp -all -inline {Icon \(([0-9]+) x ([0-9]+)\)} $p] {string cat ${w}x$h}]
check "_NET_WM_ICON: $sizes" {$sizes eq {256x256 128x128 64x64 48x48 32x32 24x24 16x16}}
toplevel .x; update
check "default for new toplevels" {[catch {exec xprop -len 99999999 -id [wrapper .x] _NET_WM_ICON} r] == 0 && [string match "*Icon (256 x 256)*" $r]}
done
