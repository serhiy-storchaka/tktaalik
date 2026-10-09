# Help > About: at the end of every Help menu; the version, Tcl/Tk and
# Fossil, the license, the project's page (in the browser).
source [file join [file dirname [info script]] common.tcl]
start tickets
set ok 1
foreach tab {timeline tickets branches files wiki search} {
    tktaalik::show $tab; update
    set m [.menubar entrycget [.menubar index Help] -menu]
    set last [labels $m]
    if {[lindex $last end] ne "About Tktaalik" || [$m type [expr {[$m index end] - 1}]] ne "separator"} {
        set ok 0; puts "  $tab: $last"
    }
}
check "About last in every Help menu" {$ok}
$m invoke [$m index "About Tktaalik"]; update
check "the window" {[winfo exists .about] && [wm title .about] eq "About Tktaalik"}
set texts [join [lmap w [winfo children .about.f] {
    expr {[winfo class $w] eq "TLabel" ? [$w cget -text] : ""}}] |]
check "version: [.about.f.name cget -text]" {[.about.f.name cget -text] eq "Tktaalik $tktaalik::version"}
set used [.about.f.used cget -text]
check "Tcl/Tk and Fossil: [string map {\n " | "} $used]" {[string first "Tk [package provide Tk]" $used] >= 0 && [string first "Fossil [tktaalik::fossilVersion]" $used] >= 0}
check "license" {[string match "*BSD 2-Clause*" $texts]}
check "an icon" {[.about.f.icon cget -image] ne ""}
event generate .about.f.url <Button-1>; update
check "the page in the browser: $::browsed" {[lindex $::browsed end] eq "https://github.com/serhiy-storchaka/tktaalik"}
set img [.about.f.icon cget -image]
# (Key events go to the focus: on Windows not yet the new window's.)
focus -force .about; update
event generate .about <Escape>; update
check "Escape closes it, the icon freed" {![winfo exists .about] && $img ni [image names]}
$m invoke [$m index "About Tktaalik"]; update
.about.b.close invoke; update
check "Close" {![winfo exists .about]}
done
