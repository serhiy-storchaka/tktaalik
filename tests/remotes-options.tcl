# The Remotes window: the default by URL, Save as (with the password),
# Forget passwords, Copy link; on a scratch copy.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set ::boxes {}
set ::answer ok
tktaalik::main tickets [list $W/co]
update
tkremotes::window; update
set r .remotes.list.t
proc pw {} { lsort [concat {*}[fossil::sql $::W/tk.fossil "SELECT name FROM config WHERE name GLOB 'sync-pw*'"]] }
check "no remote: Copy link disabled" {![$r exists default] && [.remotes.b.link instate disabled]}

# Add without a name: the default remote.
whenOpen .remotes.add {
    set tkremotes::addName ""
    set tkremotes::addUrl https://u:secret@example.invalid/tk
    set tkremotes::addDone ok
}
tkremotes::add; update
check "the default by URL: [$r set default url]" {[$r exists default] && [$r set default url] eq "https://u@example.invalid/tk"}
check "asked first: [lindex $::boxes end]" {[string match "Make https://*the default remote?" [lindex $::boxes end]]}

# Save as: a copy by the name, with its password.
$r selection set default; update
whenOpen .remotes.add {
    set tkremotes::addName saved
    set tkremotes::addDone ok
}
tkremotes::saveAs; update
check "saved: [$r set saved url], passwords [pw]" {[$r exists saved] && [$r set saved url] eq [$r set default url] && "sync-pw:saved" in [pw]}

# Forget passwords: the URLs stay.
set ::answer cancel
tkremotes::scrub; update
check "cancelled: passwords kept" {[llength [pw]]}
set ::answer ok
tkremotes::scrub; update
check "forgotten: [pw]" {![llength [pw]] && [$r exists saved] && [$r exists default]}

# Copy link: the checkout on the default remote.
check "Copy link enabled" {[.remotes.b.link instate !disabled]}
clipboard clear
tkremotes::copyLink
set hash [string range [lindex [fossil::checkoutSql $W/co "SELECT uuid FROM blob WHERE rid=(SELECT value FROM vvar WHERE name='checkout')"] 0 0] 0 15]
check "link: [clipboard get]" {[string match "https://example.invalid/tk/info/$hash*" [clipboard get]]}
done
