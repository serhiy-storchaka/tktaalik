# The diff window: which versions are compared (fossil diff -h, above the
# diff), the External diff button (gdiff) where the command has one.
# Only reads the repository.
source [file join [file dirname [info script]] common.tcl]
package require Tk
wm withdraw .
proc wait {w} {
    waitUntil {![dict exists $diffview::data($w) chan]}
    update
}
set w [diffview::run "test" -- -R $T(repo) --from core-9-0-1 --to core-9-0-2 .github/workflows/mac-build.yml]
wait $w
set from [string range [lindex [fossil::sql $T(repo) "SELECT b.uuid FROM tagxref x JOIN blob b ON b.rid=x.rid WHERE x.tagid=(SELECT tagid FROM tag WHERE tagname='sym-core-9-0-1') AND x.tagtype>0"] 0 0] 0 9]
check "versions: [$w.versions cget -text]" {[winfo ismapped $w.versions] && [string match "From $from *  →  to *" [$w.versions cget -text]]}
set text [$w.p.diff.u get 1.0 end]
check "not in the diff itself" {[string first "Fossil-Diff-From" $text] < 0 && [string first "Fossil-Diff" [lindex [lindex $diffview::data($w) 0] 0]] < 0}
check "the file list: [$w.p.files.t set 0 file]" {[$w.p.files.t set 0 file] eq ".github/workflows/mac-build.yml"}
check "External diff: a button, gdiff" {[winfo exists $w.bar.external] && [diffview::gdiffCommand $w] eq {fossil gdiff}}
destroy $w
# Another command (stash show): its gdiff variant.
set w [diffview::run "stash" -command {fossil stash show} -- 1]
check "stash show: [diffview::gdiffCommand $w]" {[diffview::gdiffCommand $w] eq {fossil stash gshow} && [winfo exists $w.bar.external]}
destroy $w
# A text shown: no versions, no external diff.
set w [diffview::show "x" "--- a\n+++ a\n@@ -1 +1 @@\n-x\n+y\n"]
update
check "a text: neither" {![winfo exists $w.bar.external] && ![winfo ismapped $w.versions]}
destroy $w
done
