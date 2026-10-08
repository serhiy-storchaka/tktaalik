# Forum: new threads and replies sent through the web forms of a server
# (web::forumPost), here a "fossil server" of its own on localhost: a
# trusted user's posts are taken at once and pulled, an untrusted user's
# wait for a moderator, a wrong password is refused; nothing else touched.
source [file join [file dirname [info script]] common.tcl]
if {[auto_execok curl] eq ""} {
    puts "== $T(name): skipped (no curl)"
    exit 0
}
set S $T(tmp)/server.fossil
exec fossil init -A admin $S
# (No backoffice: a process the server forks and leaves running.)
exec fossil settings backoffice-disable 1 -R $S
foreach {user caps pw} {poster o23 secret trusted o234 secret2 other o234 secret4 pusher o234i secret6} {
    exec fossil user new $user "" $pw -R $S
    exec fossil user capabilities $user $caps -R $S
}
set server ""
# The server stopped at the end: the watcher, fossil and the processes
# fossil forked, all found before any is killed.
proc stop {} {
    if {$::server eq ""} return
    set pids {}
    set todo $::server
    while {[llength $todo]} {
        set todo [lassign $todo pid]
        lappend pids $pid
        if {![catch {exec pgrep -P $pid} children]} { lappend todo {*}$children }
    }
    catch {exec kill {*}$pids}
    set ::server ""
}
rename exit RealExit
proc exit {{code 0}} {
    stop
    RealExit $code
}
# A free port: tried until the server answers.
for {set i 0} {$i < 20} {incr i} {
    set port [expr {20000 + int(rand() * 20000)}]
    # (Watched: stopped as soon as this test ends, however it ends.)
    set server [exec sh -c {fossil server --localhost --port "$1" "$2" & s=$!
        while kill -0 "$3" 2>/dev/null; do sleep 1; done; kill $s} sh $port $S [pid] >& $T(tmp)/server.log &]
    set url http://127.0.0.1:$port
    set up 0
    for {set j 0} {$j < 50 && !$up} {incr j} {
        after 100
        set up [expr {![catch {exec curl -s -o /dev/null $url/}]}]
    }
    if {$up} break
    stop
}
check "the server is up ($url)" {$up}
if {!$up} done
set first [lindex [web::forumPost $url trusted secret2 {title "First thread" content "Hello." mimetype text/x-markdown}] 0]
set others [lindex [web::forumPost $url other secret4 [list fpid $first content "Not yours." mimetype text/plain]] 0]
set R $T(tmp)/clone.fossil
exec fossil clone $url $R
exec fossil settings autosync off -R $R
# The server URL with a user, and the password Fossil remembers (as it
# does when told to at its prompt: obscured).
regexp -- {-> ([0-9a-f]+) } [exec fossil test-obscure secret2] -> obscured
exec fossil sql -R $R << "REPLACE INTO config(name, value, mtime) VALUES
    ('last-sync-url', [fossil::sqlstr [string map [list http:// http://trusted@] $url]], now()),
    ('last-sync-pw', [fossil::sqlstr $obscured], now());"
check "Fossil saved the password, read back" {[fossil::savedPassword $R] eq "secret2"}
start forum $R
set t .forum.main.list.t
set d .forum.main.thread.text
waitUntil {[llength [$t children {}]]}
set root [lindex [sql "SELECT rid FROM blob WHERE uuid=[fossil::sqlstr $first]" $R] 0 0]
$t selection set $root; update
waitUntil {[winfo exists $d.reply$root]}
proc private {hash} {
    llength [fossil::sql $::S "SELECT 1 FROM private WHERE rid=(SELECT rid FROM blob WHERE uuid GLOB '$hash*')"]
}

# A reply by an untrusted user: held.
$d.reply$root invoke; update
set f .forum.compose.f
check "reply window: to whom, server and user fields" {[winfo exists $f.to] && ![winfo exists $f.title]
    && [winfo exists $f.login.password]}
check "the user of the server URL, the saved password: $tkforum::webUser($url)" {
    $tkforum::webUser($url) eq "trusted" && $tkforum::webPassword eq "secret2"}
update
check "may not push (asked at once): via web only, the default" {[winfo ismapped $f.b.web]
    && ![winfo ismapped $f.b.repo] && [$f.b.web cget -default] eq "active"}
[formattext::widget $f.editor] insert end "A reply with é."
set tkforum::webUser($url) poster
set tkforum::webPassword ""
set ::boxes {}
$f.b.web invoke; update
check "no password: asked for" {[winfo exists .forum.compose] && [string match "*password*" [lindex $::boxes end]]}
set tkforum::webPassword wrong
set ::boxes {}
$f.b.web invoke; update
check "via web: asked first, naming the server: [lindex $::boxes 0]" {[string match "Post this reply on $url?" [lindex $::boxes 0]]}
check "wrong password: refused, the window stays" {[winfo exists .forum.compose] && [lindex $::boxes end] eq "Not logged in."}
set tkforum::webPassword secret
# Not known yet (another user): via repository asks, then says no.
tkforum::showButtons; update
check "not known: both buttons" {[winfo ismapped $f.b.repo] && [winfo ismapped $f.b.web]}
set ::boxes {}
$f.b.repo invoke; update
check "via repository, may not push: said, the button gone: $::boxes" {[string match "poster may not push*" [lindex $::boxes end]]
    && ![winfo ismapped $f.b.repo] && [winfo exists .forum.compose]}
set n [lindex [fossil::sql $S "SELECT count(*) FROM forumpost"] 0 0]
set ::boxes {}
$f.b.web invoke; update
check "asked first, naming the server: [lindex $::boxes 0]" {[string match "Post this reply on $url?" [lindex $::boxes 0]]}
check "held for a moderator: [lindex $::boxes end]" {[string match "*waits for a moderator*" [lindex $::boxes end]]
    && ![winfo exists .forum.compose]}
set held [lindex [fossil::sql $S "SELECT (SELECT uuid FROM blob WHERE rid=fpid) FROM forumpost ORDER BY fpid DESC LIMIT 1"] 0 0]
check "on the server, private (held)" {[lindex [fossil::sql $S "SELECT count(*) FROM forumpost"] 0 0] == $n + 1
    && [private $held]}
check "the text, UTF-8 intact" {[string first "A reply with é." [lindex [fossil::sql $S "SELECT content([fossil::sqlstr $held])"] 0 0]] >= 0}

# While it is sent: the windows busy, the watch cursor.
rename web::forumPost web::RealPost
set ::webCalls 0
proc web::forumPost {args} {
    incr ::webCalls
    set ::busyDuring [list [tk busy status .forum.compose] [tk busy status .] \
        [tk busy cget .forum.compose -cursor]]
    web::RealPost {*}$args
}
# A reply by a trusted user: public, pulled, shown.
$d.reply$root invoke; update
check "the password kept for the session" {$tkforum::webPassword eq "secret"}
[formattext::widget $f.editor] insert end "A trusted reply."
set tkforum::webUser($url) trusted
set tkforum::webPassword secret2
$f.b.web invoke; update
set reply [lindex [sql "SELECT fpid FROM forumpost JOIN event ON objid=fpid
    WHERE froot=$root AND fpid<>$root AND user='trusted'" $R] 0 0]
check "pulled here as a reply ($reply)" {$reply ne ""}
check "shown in the thread" {[winfo exists $d.reply$reply]}
check "busy while sent: $::busyDuring" {$::busyDuring eq {1 1 watch}}
check "not busy after" {![tk busy status .]}
check "public on the server" {![private [lindex [sql "SELECT uuid FROM blob WHERE rid=$reply" $R] 0 0]]}

# Edit and Delete: on one's own posts only.
set orid [lindex [sql "SELECT rid FROM blob WHERE uuid=[fossil::sqlstr $others]" $R] 0 0]
check "Edit and Delete on one's own posts" {[winfo exists $d.edit$reply] && [winfo exists $d.delete$reply]
    && [winfo exists $d.edit$root]}
check "not on another user's ($orid)" {[winfo exists $d.reply$orid] && ![winfo exists $d.edit$orid]
    && ![winfo exists $d.delete$orid]}
# Edit a reply: its text and format in the window, no title; a new version.
$d.edit$reply invoke; update
set e [formattext::widget $f.editor]
check "edit: the text and the format" {[$e get 1.0 end-1c] eq "A trusted reply."
    && $tkforum::format eq "Markdown" && ![winfo exists $f.title] && [$f.b.web cget -text] eq "Save via web"}
$e delete 1.0 end
$e insert end "An edited reply."
set ::boxes {}
$f.b.web invoke; update
check "edit: asked first: [lindex $::boxes 0]" {[string match "Save this edit on *" [lindex $::boxes 0]]}
set edited [lindex [sql "SELECT fpid FROM forumpost WHERE fprev=$reply" $R] 0 0]
check "edit: a new version, pulled ($edited)" {$edited ne ""}
check "edit: shown, edited" {[string first "An edited reply." [$d get 1.0 end]] >= 0
    && [string first "A trusted reply." [$d get 1.0 end]] < 0 && [winfo exists $d.edit$edited]}
# Edit the thread's first post: its title too.
$d.edit$root invoke; update
check "edit the first post: its title" {[winfo exists $f.title] && $tkforum::postTitle eq "First thread"}
set tkforum::postTitle "First thread, renamed"
$f.b.web invoke; update
set rootv [lindex [sql "SELECT fpid FROM forumpost WHERE fprev=$root" $R] 0 0]
check "edit the first post: the new title ($rootv)" {$rootv ne ""
    && [string first "First thread, renamed" [$d get 1.0 end]] >= 0}
# Delete the edited reply: an empty version; no Edit on it after.
$d.delete$edited invoke; update
check "delete: no text, the button says so" {![winfo exists $f.editor] && [$f.b.web cget -text] eq "Delete via web"}
set ::boxes {}
$f.b.web invoke; update
check "delete: asked first: [lindex $::boxes 0]" {[string match "Delete this post on *" [lindex $::boxes 0]]}
set gone [lindex [sql "SELECT fpid FROM forumpost WHERE fprev=$edited" $R] 0 0]
check "delete: an empty version, pulled ($gone)" {$gone ne ""
    && [string trim [lindex [tkforum::parse [lindex [sql "SELECT content(uuid) FROM blob WHERE rid=$gone" $R] 0 0]] 1]] eq ""}
check "delete: shown deleted, no Edit" {[string first "(deleted)" [$d get 1.0 end]] >= 0
    && ![winfo exists $d.edit$gone] && [winfo exists $d.reply$gone]}

# With the right to push: made here as Fossil makes it, for the next push
# or sync; nothing sent, not through the web form.
proc onServer {hash} {
    lindex [fossil::sql $::S "SELECT count(*) FROM blob WHERE uuid=[fossil::sqlstr $hash]
        AND rid NOT IN (SELECT rid FROM private)"] 0 0
}
$d.reply$rootv invoke; update
set tkforum::webUser($url) pusher
set tkforum::webPassword secret6
tkforum::checkPush; update
check "may push: via repository too, the default" {[winfo ismapped $f.b.repo] && [winfo ismapped $f.b.web]
    && [$f.b.repo cget -default] eq "active" && [$f.b.repo cget -text] eq "Post via repository"}
[formattext::widget $f.editor] insert end "A pushed reply."
set calls $::webCalls
$f.b.repo invoke; update
set pushed [lindex [sql "SELECT b.uuid FROM blob b JOIN event e ON e.objid=b.rid
    WHERE e.type='f' AND e.user='pusher'" $R] 0 0]
check "push: stored here ($pushed)" {$pushed ne ""}
proc queued {hash} {
    llength [fossil::sql $::R "SELECT 1 FROM blob b JOIN unclustered u ON u.rid=b.rid
        WHERE b.uuid=[fossil::sqlstr $hash] AND b.rid NOT IN (SELECT rid FROM private)"]
}
check "push: public here, for the next push; not sent" {[queued $pushed] && ![onServer $pushed]}
check "push: not through the web form" {$::webCalls == $calls}
set prid [lindex [sql "SELECT rid FROM blob WHERE uuid=[fossil::sqlstr $pushed]" $R] 0 0]
check "push: shown, with Edit" {[winfo exists $d.edit$prid]}
check "push: the cards Fossil makes" {[regexp "^D \\S+\nG \[0-9a-f\]+\nI \[0-9a-f\]+\nN text/x-markdown\nU pusher\nW 15\nA pushed reply.\nZ \[0-9a-f\]{32}\n\$" \
    [lindex [sql "SELECT content(uuid) FROM blob WHERE rid=$prid" $R] 0 0]]}
# Edit and delete it the same way.
$d.edit$prid invoke; update
set e [formattext::widget $f.editor]
$e delete 1.0 end
$e insert end "A pushed edit."
$f.b.repo invoke; update
set pedit [lindex [sql "SELECT b.uuid FROM forumpost f JOIN blob b ON b.rid=f.fpid WHERE f.fprev=$prid" $R] 0 0]
check "push: the edit, here ($pedit)" {$pedit ne "" && [queued $pedit] && ![onServer $pedit]
    && [string match "*\nP $pushed\n*" [lindex [sql "SELECT content([fossil::sqlstr $pedit])" $R] 0 0]]}
set perid [lindex [sql "SELECT rid FROM blob WHERE uuid=[fossil::sqlstr $pedit]" $R] 0 0]
$d.delete$perid invoke; update
$f.b.repo invoke; update
set pdel [lindex [sql "SELECT b.uuid FROM forumpost f JOIN blob b ON b.rid=f.fpid WHERE f.fprev=$perid" $R] 0 0]
check "push: the deletion, here ($pdel)" {$pdel ne "" && [queued $pdel] && ![onServer $pdel]
    && [string match "*\nW 0\n\nZ *" [lindex [sql "SELECT content([fossil::sqlstr $pdel])" $R] 0 0]]}
check "push: never the web form" {$::webCalls == $calls}

# A new thread.
tkforum::compose; update
check "new thread window: a title field" {[winfo exists $f.title]}
[formattext::widget $f.editor] insert end "Second."
set ::boxes {}
$f.b.web invoke; update
check "no title: refused" {[winfo exists .forum.compose] && [string match "*title*" [lindex $::boxes end]]}
set title "Tktaalik test: été → posts"
set tkforum::postTitle $title
$f.b.web invoke; update
set new [lindex [sql "SELECT fpid FROM forumpost WHERE froot=fpid AND fpid<>$root" $R] 0 0]
check "the new thread pulled ($new)" {$new ne ""}
check "its title: [lindex [sql "SELECT comment FROM event WHERE objid=$new" $R] 0 0]" {
    [lindex [sql "SELECT comment FROM event WHERE objid=$new" $R] 0 0] eq "Post: $title"}
check "shown: the thread selected" {[$t selection] eq $new}

# A repository without a server: stored here, as its default user.
set L $T(tmp)/local.fossil
file copy $R $L
exec fossil remote off -R $L
exec fossil user new localme "" x -R $L
exec fossil user default localme -R $L
tkforum::setRepository $L ""
waitUntil {[llength [$t children {}]]}
tkforum::compose; update
check "no server: via repository only" {[winfo ismapped $f.b.repo] && ![winfo ismapped $f.b.web]}
check "no server: no password asked" {![winfo exists $f.login.password]
    && [string match "As localme*" [$f.login.lu cget -text]]}
set tkforum::postTitle "A local thread"
[formattext::widget $f.editor] insert end "Here only."
set ::boxes {}
$f.b.repo invoke; update
check "no server: asked first: [lindex $::boxes 0]" {[string match "Start the thread \"A local thread\" in local.fossil?" [lindex $::boxes 0]]}
set lroot [lindex [sql "SELECT objid FROM event WHERE type='f' AND user='localme'" $L] 0 0]
check "no server: stored here ($lroot)" {$lroot ne "" && [$t selection] eq $lroot}
check "no server: not sent" {![onServer [lindex [sql "SELECT uuid FROM blob WHERE rid=$lroot" $L] 0 0]]}
tkforum::setRepository $R ""
waitUntil {[llength [$t children {}]]}

# Cancel: nothing sent.
set n [lindex [fossil::sql $S "SELECT count(*) FROM forumpost"] 0 0]
tkforum::compose; update
$f.b.cancel invoke; update
check "cancelled: nothing sent" {[lindex [fossil::sql $S "SELECT count(*) FROM forumpost"] 0 0] == $n}
done
