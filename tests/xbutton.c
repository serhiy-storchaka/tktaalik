/* Press and release a mouse button through XTEST (for tests on Xvfb),
   with a key held if one is given (a keysym name: Control_L). */
#include <stdio.h>
#include <stdlib.h>
#include <X11/Xlib.h>
#include <X11/extensions/XTest.h>
int main(int argc, char **argv) {
    Display *d;
    KeyCode key = 0;
    if (argc != 2 && argc != 3) { fprintf(stderr, "usage: xbutton N ?KEYSYM?\n"); return 2; }
    d = XOpenDisplay(NULL);
    if (!d) { fprintf(stderr, "no display\n"); return 1; }
    if (argc == 3) {
        KeySym sym = XStringToKeysym(argv[2]);
        if (sym == NoSymbol || !(key = XKeysymToKeycode(d, sym))) {
            fprintf(stderr, "no key %s\n", argv[2]);
            return 1;
        }
        XTestFakeKeyEvent(d, key, True, CurrentTime);
    }
    XTestFakeButtonEvent(d, atoi(argv[1]), True, CurrentTime);
    XTestFakeButtonEvent(d, atoi(argv[1]), False, CurrentTime);
    if (key) XTestFakeKeyEvent(d, key, False, CurrentTime);
    XFlush(d);
    XCloseDisplay(d);
    return 0;
}
