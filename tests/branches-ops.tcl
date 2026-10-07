# Operations on the history (lib/histops.tcl), from the Branches and
# Timeline tabs, on a scratch copy: a check-in as an archive, the common
# ancestor, closing a branch with its dry run, making a private branch
# public, bundles (export, import private, remove), merged:@current, the
# Timeline's Update checkout.  Nothing is pushed.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set R $W/tk.fossil
set co $W/co
set ::confirms {}
proc tagwrite::confirm {args} { lappend ::confirms $args; return 1 }
set ::outputs {}
proc tkbranches::showOutput {title message text {ok ""} {option {}}} { lappend ::outputs [list $title $message $text]; expr {$ok ne ""} }
# A copy for the bundle to go into, as it is now.
file copy $R $T(tmp)/other.fossil
start branches $co 1300x900

# An archive of a tag's check-in: ZIP with a top folder, only generic/*.
set ::saveTo $T(tmp)/tk.zip
whenOpen .tagwrite {
    set histops::archive(name) tkx
    set histops::archive(include) generic/*
    after 800 { set ::count $histops::archive(count); set tagwrite::answer 1 }
}
histops::archive $R core-9-0-2 core-9-0-2
check "archive saved: [file size $T(tmp)/tk.zip] bytes, $::count" {[file exists $T(tmp)/tk.zip] && [regexp {^\d+ files$} $::count]}
set list [exec fossil zip core-9-0-2 "" --list --name tkx --include=generic/* -R $R]
check "only generic/*, under tkx/" {[llength [split [string trim $list] \n]] == [lindex $::count 0]}
set ::saveTo $T(tmp)/tk.tar.gz
whenOpen .tagwrite { set histops::archive(format) tarball; set tagwrite::answer 1 }
histops::archive $R core-9-0-2 core-9-0-2
check "tarball saved" {[file exists $T(tmp)/tk.tar.gz] && [file size $T(tmp)/tk.tar.gz] > 1000}

# The common ancestor: fossil merge-base in the checkout, SQL without one.
set a [histops::mergeBase $R $co core-8-6-branch main]
set b [histops::mergeBase $R "" core-8-6-branch main]
proc isAncestor {anc of} {
    llength [sql "WITH RECURSIVE x(rid) AS (SELECT x.rid FROM tagxref x JOIN event e ON e.objid=x.rid WHERE x.tagtype>0 AND x.tagid=(SELECT tagid FROM tag WHERE tagname='sym-$of') ORDER BY e.mtime DESC LIMIT 1) , y(rid) AS (SELECT rid FROM x UNION SELECT p.pid FROM plink p JOIN y ON p.cid=y.rid) SELECT 1 FROM y JOIN blob b ON b.rid=y.rid WHERE b.uuid='$anc'"]
}
check "merge-base: [string range $a 0 9] (fossil), [string range $b 0 9] (SQL)" {$a ne "" && $b ne "" && [isAncestor $a main] && [isAncestor $a core-8-6-branch] && [isAncestor $b main] && [isAncestor $b core-8-6-branch]}

# Close a branch: the dry run in the confirmation.
exec fossil branch new zz-close main --nosync -R $R
tkbranches::reload; update
set tkbranches::view all; tkbranches::showList; update
.branches.main.list.t selection set [list zz-close]; update
tkbranches::tagBranches close
set out [lindex $::outputs end]
check "close: the dry run shown" {[string match "*Dry run:*" [lindex $out 2]] && [string match "*closed*" [lindex $out 2]]}
check "closed" {[dict get $tkbranches::branches(zz-close) closed]}

# A private branch made public.
exec fossil branch new zz-private main --private --nosync -R $R
set tip [lindex [sql "SELECT x.rid FROM tagxref x WHERE x.tagtype>0 AND x.value='zz-private' AND x.tagid=(SELECT tagid FROM tag WHERE tagname='branch')"] 0 0]
check "private at first" {[llength [sql "SELECT 1 FROM private WHERE rid=$tip"]]}
histops::publish $R zz-private "the private branch zz-private"
check "public now" {![llength [sql "SELECT 1 FROM private WHERE rid=$tip"]]}
set c [lindex $::confirms end]
check "publish asked first, with its dry run" {[string match "Make the private branch zz-private public?*" [lindex $c 1]] && [string match "*Dry run*" [lindex $c 2]] && [lindex $c 3] eq "-note"}

# A bundle of a new branch: exported, imported (private) into the other
# repository, then removed from it.
cd $co
set f [open $co/zz-bundle.txt w]; puts $f bundle; close $f
exec fossil add zz-bundle.txt
exec fossil commit --branch zz-bundle -m "A bundle test" --nosync --no-prompt
cd $T(dir)
set ci [lindex [sql "SELECT b.uuid FROM tagxref x JOIN blob b ON b.rid=x.rid WHERE x.tagtype>0 AND x.value='zz-bundle' AND x.tagid=(SELECT tagid FROM tag WHERE tagname='branch')"] 0 0]
set ::saveTo $T(tmp)/zz.bundle
# (Self-contained: the other repository lacks what deltas would need.)
whenOpen .tagwrite { set histops::bundle(standalone) 1; set tagwrite::answer 1 }
histops::exportBundle $R zz-bundle
check "bundle exported" {[file exists $T(tmp)/zz.bundle]}
set O $T(tmp)/other.fossil
check "not in the other repository yet" {![llength [sql "SELECT 1 FROM blob WHERE uuid='$ci'" $O]]}
set ::openFrom $T(tmp)/zz.bundle
whenOpen .tagwrite { set ::importList [.tagwrite.f.t get 1.0 end]; set tagwrite::answer 1 }
histops::importBundle $O
check "import showed the bundle's contents" {[string length [string trim $::importList]] > 0}
set rid [lindex [sql "SELECT rid FROM blob WHERE uuid='$ci'" $O] 0 0]
check "imported, private" {$rid ne "" && [llength [sql "SELECT 1 FROM private WHERE rid=$rid" $O]]}
histops::purgeBundle $O
check "removed again" {![llength [sql "SELECT 1 FROM blob WHERE uuid='$ci' AND size>=0" $O]]}

# merged:@current: the checkout is on zz-bundle, not a merge target.
tkbranches::reload; update
set tkbranches::query merged:@current
tkbranches::search; update
set shown [.branches.main.list.t children {}]
check "merged:@current: main in, zz-close out ([llength $shown])" {"main" in $shown && "zz-close" ni $shown && "zz-bundle" in $shown}

# The Timeline: Update checkout to a check-in (main's tip), dry run first.
tktaalik::show timeline; update
set main [lindex [sql "SELECT x.rid FROM tagxref x JOIN event e ON e.objid=x.rid WHERE x.tagtype>0 AND x.value='main' AND x.tagid=(SELECT tagid FROM tag WHERE tagname='branch') ORDER BY e.mtime DESC LIMIT 1"] 0 0]
set tktimeline::rows($main) [dict create uuid [lindex [sql "SELECT uuid FROM blob WHERE rid=$main"] 0 0]]
tktimeline::updateTo $main
set now [lindex [fossil::checkoutSql $co "SELECT value FROM vvar WHERE name='checkout'"] 0 0]
check "Timeline: updated to main's tip" {$now == $main}
done
