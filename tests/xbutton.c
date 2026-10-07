/* Press and release a mouse button through XTEST (for tests on Xvfb). */
#include <stdio.h>
#include <stdlib.h>
#include <X11/Xlib.h>
#include <X11/extensions/XTest.h>
int main(int argc, char **argv) {
    Display *d;
    if (argc != 2) { fprintf(stderr, "usage: xbutton N\n"); return 2; }
    d = XOpenDisplay(NULL);
    if (!d) { fprintf(stderr, "no display\n"); return 1; }
    XTestFakeButtonEvent(d, atoi(argv[1]), True, CurrentTime);
    XTestFakeButtonEvent(d, atoi(argv[1]), False, CurrentTime);
    XFlush(d);
    XCloseDisplay(d);
    return 0;
}
