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
foreach {user caps pw} {poster o23 secret trusted o234 secret2} {
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
[formattext::widget $f.editor] insert end "A reply with é."
set tkforum::webUser($url) poster
set tkforum::webPassword ""
set ::boxes {}
$f.b.post invoke; update
check "no password: asked for" {[winfo exists .forum.compose] && [string match "*password*" [lindex $::boxes end]]}
set tkforum::webPassword wrong
set ::boxes {}
$f.b.post invoke; update
check "asked first, naming the server: [lindex $::boxes 0]" {[string match "Post this reply on $url?" [lindex $::boxes 0]]}
check "wrong password: refused, the window stays" {[winfo exists .forum.compose] && [lindex $::boxes end] eq "Not logged in."}
set tkforum::webPassword secret
set n [lindex [fossil::sql $S "SELECT count(*) FROM forumpost"] 0 0]
set ::boxes {}
$f.b.post invoke; update
check "held for a moderator: [lindex $::boxes end]" {[string match "*waits for a moderator*" [lindex $::boxes end]]
    && ![winfo exists .forum.compose]}
set held [lindex [fossil::sql $S "SELECT (SELECT uuid FROM blob WHERE rid=fpid) FROM forumpost ORDER BY fpid DESC LIMIT 1"] 0 0]
check "on the server, private (held)" {[lindex [fossil::sql $S "SELECT count(*) FROM forumpost"] 0 0] == $n + 1
    && [private $held]}
check "the text, UTF-8 intact" {[string first "A reply with é." [lindex [fossil::sql $S "SELECT content([fossil::sqlstr $held])"] 0 0]] >= 0}

# While it is sent: the windows busy, the watch cursor.
rename web::forumPost web::RealPost
proc web::forumPost {args} {
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
$f.b.post invoke; update
set reply [lindex [sql "SELECT fpid FROM forumpost WHERE froot=$root AND fpid<>$root" $R] 0 0]
check "pulled here as a reply ($reply)" {$reply ne ""}
check "shown in the thread" {[winfo exists $d.reply$reply]}
check "busy while sent: $::busyDuring" {$::busyDuring eq {1 1 watch}}
check "not busy after" {![tk busy status .]}
check "public on the server" {![private [lindex [sql "SELECT uuid FROM blob WHERE rid=$reply" $R] 0 0]]}

# A new thread.
tkforum::compose; update
check "new thread window: a title field" {[winfo exists $f.title]}
[formattext::widget $f.editor] insert end "Second."
set ::boxes {}
$f.b.post invoke; update
check "no title: refused" {[winfo exists .forum.compose] && [string match "*title*" [lindex $::boxes end]]}
set title "Tktaalik test: été → posts"
set tkforum::postTitle $title
$f.b.post invoke; update
set new [lindex [sql "SELECT fpid FROM forumpost WHERE froot=fpid AND fpid<>$root" $R] 0 0]
check "the new thread pulled ($new)" {$new ne ""}
check "its title: [lindex [sql "SELECT comment FROM event WHERE objid=$new" $R] 0 0]" {
    [lindex [sql "SELECT comment FROM event WHERE objid=$new" $R] 0 0] eq "Post: $title"}
check "shown: the thread selected" {[$t selection] eq $new}

# Cancel: nothing sent.
set n [lindex [fossil::sql $S "SELECT count(*) FROM forumpost"] 0 0]
tkforum::compose; update
$f.b.cancel invoke; update
check "cancelled: nothing sent" {[lindex [fossil::sql $S "SELECT count(*) FROM forumpost"] 0 0] == $n}
done
