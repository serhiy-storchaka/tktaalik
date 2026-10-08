# Posting to a Fossil server's web forms, as a browser does: for what has
# no command (forum posts), and for users who may post on the website but
# not push to it.  curl does the HTTP (Tcl has no HTTPS of its own); it
# reads its options from stdin, so the password and the text are not on
# a command line, and keeps the login cookie in a private temporary
# directory, deleted at the end.
#
#   web::forumPost URL USER PASSWORD FIELDS
#       logs in to the repository at URL and posts to the forum: FIELDS
#       is a dict with content and mimetype, and title (a new thread) or
#       fpid (the hash of a post) and action: reply (the default), edit
#       (a new version of the post: its title too if it starts a thread)
#       or delete (an empty version; title "" if it starts a thread, no
#       content needed).  Returns {HASH HELD}: the new post or version
#       and whether it waits for a moderator.  Throws
#       {WEB LOGIN} (wrong user or password), {WEB DENIED} (the user may
#       not post), {WEB CURL} (no curl, or the server not reached) or
#       {WEB POST} (the server did not take the post).

namespace eval web {}

proc web::forumPost {url user password fields} {
    set url [string trimright $url /]
    set dir [TempDir]
    try {
        set jar [file join $dir cookies]
        lassign [Request $dir $url/login [dict create u $user p $password] $url/login] code to
        # Logged in: redirected (to the home page); else 401.
        if {$code == 401} { throw {WEB LOGIN} "The server did not take the user or the password." }
        if {$code != 302} { throw {WEB CURL} "The login page answered $code." }
        if {![dict exists $fields fpid]} {
            set page forume1
            set query ""
            set form [dict create title [dict get $fields title]]
        } else {
            set page forume2
            set fpid [dict get $fields fpid]
            set action [expr {[dict exists $fields action] ? [dict get $fields action] : "reply"}]
            # (Fossil's names: a deletion "nulls out" the post.)
            set name [dict get {reply reply edit edit delete nullout} $action]
            set query ?fpid=$fpid&$name
            set form [dict create fpid $fpid $name 1]
            if {$action eq "delete"} {
                dict set fields content ""
                dict set fields mimetype text/x-fossil-wiki
            }
            if {$action ne "reply" && [dict exists $fields title]} {
                dict set form title [dict get $fields title]
            }
        }
        # The form, for its token against cross-site requests.
        lassign [Request $dir $url/$page$query {} ""] code to
        if {$code != 200 || ![regexp {name="csrf" value="([^"]*)"} [Body $dir] -> csrf]} {
            throw {WEB DENIED} "$user may not post in this forum."
        }
        dict set form mimetype [dict get $fields mimetype]
        dict set form content [dict get $fields content]
        dict set form csrf $csrf
        dict set form submit 1
        lassign [Request $dir $url/$page $form $url/$page$query] code to
        if {$code != 302 || ![regexp {/forumpost/([0-9a-f]+)} $to -> hash]} {
            set why [regexp -inline {[^<>]*(?:closed|not allowed|error)[^<>]*} [Body $dir]]
            throw {WEB POST} [string trim "The server did not take the post (answer $code). [lindex $why 0]"]
        }
        # The post's page: its form has the full hash (the redirection
        # abbreviates it), and for a post held for moderation a button to
        # delete it (reject) instead of the ones to edit it.
        lassign [Request $dir $url/forumpost/$hash {} ""] code to
        set body [Body $dir]
        set held 0
        if {[regexp "name=\"fpid\" value=\"($hash\[0-9a-f\]*)\"" $body -> full]} {
            set form [string range $body [string first $full $body] end]
            set form [string range $form 0 [string first </form> $form]]
            set held [string match {*name="reject"*} $form]
            set hash $full
        }
        return [list $hash $held]
    } finally {
        file delete -force $dir
    }
}

# One request with the cookies kept in DIR: a POST of FORM (a dict) if not
# empty, else a GET.  The body goes to DIR/body.  {status redirection}.
proc web::Request {dir url form referer} {
    set curl [auto_execok curl]
    if {$curl eq ""} { throw {WEB CURL} "Posting needs curl, which was not found." }
    set config ""
    foreach {opt value} [list url $url cookie-jar $dir/cookies cookie $dir/cookies \
            output $dir/body write-out "%{http_code} %{redirect_url}" max-time 60] {
        append config "$opt = \"[Quote $value]\"\n"
    }
    if {$referer ne ""} { append config "referer = \"[Quote $referer]\"\n" }
    dict for {name value} $form {
        append config "data-urlencode = \"[Quote $name=$value]\"\n"
    }
    append config "silent\nshow-error\n"
    set chan [open |[list {*}$curl -K - 2>@1] r+]
    fconfigure $chan -encoding utf-8 -translation lf
    puts -nonewline $chan $config
    close $chan write
    set out [read $chan]
    if {[catch {close $chan}]} {
        throw {WEB CURL} "The server was not reached: [string trim [regsub {\d{3} ?\S*\s*$} $out ""]]"
    }
    if {![regexp {(\d{3}) ?(\S*)\s*$} $out -> code to]} {
        throw {WEB CURL} "curl: [string trim $out]"
    }
    list $code $to
}

proc web::Quote {text} {
    string map [list \\ \\\\ \" \\\" \n \\n \r \\r \t \\t \v \\v] $text
}

proc web::Body {dir} {
    set f [open $dir/body rb]
    set body [encoding convertfrom utf-8 [read $f]]
    close $f
    return $body
}

proc web::TempDir {} {
    foreach var {TMPDIR TEMP TMP} {
        if {[info exists ::env($var)] && [file isdirectory $::env($var)]} {
            set base $::env($var)
            break
        }
    }
    if {![info exists base]} { set base /tmp }
    set dir [file join $base tktaalik-web-[pid]-[clock clicks]]
    file mkdir $dir
    if {$::tcl_platform(platform) eq "unix"} { file attributes $dir -permissions 0700 }
    return $dir
}
