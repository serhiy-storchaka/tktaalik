#!/usr/bin/env python3
# Draws Tktaalik's icons into icons/NAME-SIZE.png (16, 24 and 32 pixels),
# antialiased: drawn 8 times larger and scaled down.  Needs Pillow.
#
#   tools/make-icons.py             write all icons
#   tools/make-icons.py --preview F also write a preview sheet to F
#
# The application: tktaalik (16 to 256 pixels, and tktaalik.ico).  Buttons: search, save,
# clear, help.  Tickets: st-* (status), pr-*
# (priority), sv-* (severity).  Timeline: k-* (event kinds).
import math, os, sys
from PIL import Image, ImageDraw

# ---------------------------------------------------------------- buttons

INK = (60, 60, 60, 255)
ACCENT = (40, 110, 60, 255)
def canvas(n): return Image.new('RGBA', (n*8, n*8), (0,0,0,0))
def done(img, n): return img.resize((n, n), Image.LANCZOS)
def search(n):
    S = n*8; im = canvas(n); d = ImageDraw.Draw(im); w = max(S//10, 8)
    r = S*0.30; cx = cy = S*0.40
    d.ellipse([cx-r, cy-r, cx+r, cy+r], outline=INK, width=w)
    a = math.radians(45); x0 = cx + r*math.cos(a); y0 = cy + r*math.sin(a)
    d.line([x0, y0, S*0.90, S*0.90], fill=INK, width=int(w*1.5))
    return done(im, n)
def star(n):
    S = n*8; im = canvas(n); d = ImageDraw.Draw(im); w = max(S//14, 6)
    cx, cy, R, r = S*0.42, S*0.46, S*0.38, S*0.16
    pts = []
    for k in range(10):
        a = math.radians(-90 + 36*k); rad = R if k % 2 == 0 else r
        pts.append((cx + rad*math.cos(a), cy + rad*math.sin(a)))
    d.polygon(pts, outline=INK, fill=(250, 210, 80, 255), width=w)
    # a plus at the lower right
    px, py, L, pw = S*0.78, S*0.78, S*0.17, max(S//9, 8)
    d.ellipse([px-L*1.25, py-L*1.25, px+L*1.25, py+L*1.25], fill=(255,255,255,255))
    d.line([px-L, py, px+L, py], fill=ACCENT, width=pw)
    d.line([px, py-L, px, py+L], fill=ACCENT, width=pw)
    return done(im, n)
def cross(n):
    S = n*8; im = canvas(n); d = ImageDraw.Draw(im); w = max(S//8, 8)
    m = S*0.24
    d.line([m, m, S-m, S-m], fill=INK, width=w)
    d.line([m, S-m, S-m, m], fill=INK, width=w)
    return done(im, n)
def help_(n):
    S = n*8; im = canvas(n); d = ImageDraw.Draw(im); w = max(S//12, 6)
    m = S*0.08
    d.ellipse([m, m, S-m, S-m], outline=INK, width=w)
    # the question mark: an arc, a stem, a dot
    cx = S/2; r = S*0.15
    d.arc([cx-r, S*0.24, cx+r, S*0.24+2*r], start=180, end=420, fill=INK, width=w)
    a = math.radians(60); sx = cx + r*math.cos(a); sy = S*0.24 + r + r*math.sin(a)
    d.line([sx, sy, cx, S*0.60], fill=INK, width=w)
    dr = w*0.75
    d.ellipse([cx-dr, S*0.72-dr, cx+dr, S*0.72+dr], fill=INK)
    return done(im, n)

# ---------------------------------------------------------------- tickets

def C(h): return tuple(int(h[i:i+2],16) for i in (1,3,5)) + (255,)
GREEN, AMBER, PURPLE, GRAY, RED, ORANGE, YELLOW, BLUE, DARK = map(C, ['#1a7f37','#bf8700','#8250df','#6e7781','#cf222e','#e16f24','#d4a72c','#0969da','#3d444d'])
WHITE=(255,255,255,255)
def ring(d,S,col,w): m=S*0.12; d.ellipse([m,m,S-m,S-m], outline=col, width=w)
def disc(d,S,col): m=S*0.12; d.ellipse([m,m,S-m,S-m], fill=col)
def check(d,S,col,w): d.line([S*0.30,S*0.52,S*0.44,S*0.66,S*0.71,S*0.36], fill=col, width=w, joint='curve')
def xmark(d,S,col,w,m=0.35): d.line([S*m,S*m,S*(1-m),S*(1-m)], fill=col, width=w); d.line([S*m,S*(1-m),S*(1-m),S*m], fill=col, width=w)
def ticket_icon(name, n):
    S=n*8; im=canvas(n); d=ImageDraw.Draw(im); w=max(int(S*0.09),6)
    if name=='st-open':
        ring(d,S,GREEN,w); r=S*0.12; d.ellipse([S/2-r,S/2-r,S/2+r,S/2+r], fill=GREEN)
    elif name=='st-pending':
        ring(d,S,AMBER,w); d.line([S/2,S*0.28,S/2,S/2,S*0.66,S*0.62], fill=AMBER, width=w, joint='curve')
    elif name=='st-fixed':
        disc(d,S,PURPLE); check(d,S,WHITE,w)
    elif name=='st-closed':
        ring(d,S,PURPLE,w); check(d,S,PURPLE,w)
    elif name=='st-duplicate':
        a=S*0.16; b=S*0.58; d.rectangle([a+S*0.18,a,b+S*0.18,b], outline=GRAY, width=w); d.rectangle([a,a+S*0.18,b,b+S*0.18], outline=GRAY, width=w, fill=WHITE)
    elif name=='st-rejected':
        ring(d,S,RED,w); d.line([S*0.27,S*0.73,S*0.73,S*0.27], fill=RED, width=w)
    elif name=='st-invalid':
        ring(d,S,GRAY,w); xmark(d,S,GRAY,w)
    elif name=='st-worksforme':
        ring(d,S,GRAY,w); check(d,S,GRAY,w)
    elif name=='st-outofdate':
        m=S*0.24; d.polygon([(m,S*0.14),(S-m,S*0.14),(S/2,S/2)], outline=GRAY, width=w); d.polygon([(m,S*0.86),(S-m,S*0.86),(S/2,S/2)], fill=GRAY, outline=GRAY, width=w)
    elif name=='st-postponed':
        ring(d,S,BLUE,w); d.line([S*0.42,S*0.33,S*0.42,S*0.67], fill=BLUE, width=w); d.line([S*0.58,S*0.33,S*0.58,S*0.67], fill=BLUE, width=w)
    elif name=='st-deleted':
        disc(d,S,RED); xmark(d,S,WHITE,w,0.33)
    elif name.startswith('pr-'):
        col={'pr-9':RED,'pr-8':RED,'pr-7':ORANGE,'pr-6':YELLOW,'pr-5':GRAY,'pr-low':BLUE}[name]
        def chev(y,up=True):
            if up: d.line([S*0.22,y+S*0.18,S/2,y-S*0.06,S*0.78,y+S*0.18], fill=col, width=int(w*1.3), joint='curve')
            else: d.line([S*0.22,y-S*0.12,S/2,y+S*0.12,S*0.78,y-S*0.12], fill=col, width=int(w*1.3), joint='curve')
        if name=='pr-9': chev(S*0.28); chev(S*0.56)
        elif name in ('pr-8','pr-7','pr-6'): chev(S*0.40)
        elif name=='pr-5': d.line([S*0.25,S/2,S*0.75,S/2], fill=col, width=int(w*1.3))
        else: chev(S*0.50, False)
    elif name=='sv-critical':
        r=S*0.40; pts=[(S/2+r*math.cos(math.radians(22.5+45*k)), S/2+r*math.sin(math.radians(22.5+45*k))) for k in range(8)]
        d.polygon(pts, fill=RED); d.line([S/2,S*0.28,S/2,S*0.56], fill=WHITE, width=w); r2=w*0.7; d.ellipse([S/2-r2,S*0.70-r2,S/2+r2,S*0.70+r2], fill=WHITE)
    elif name=='sv-severe':
        d.polygon([(S/2,S*0.12),(S*0.90,S*0.86),(S*0.10,S*0.86)], fill=ORANGE); d.line([S/2,S*0.38,S/2,S*0.62], fill=WHITE, width=w); r2=w*0.7; d.ellipse([S/2-r2,S*0.74-r2,S/2+r2,S*0.74+r2], fill=WHITE)
    elif name=='sv-major':
        disc(d,S,YELLOW); d.line([S/2,S*0.28,S/2,S*0.56], fill=WHITE, width=w); r2=w*0.7; d.ellipse([S/2-r2,S*0.70-r2,S/2+r2,S*0.70+r2], fill=WHITE)
    elif name=='sv-minor':
        r=S*0.20; d.ellipse([S/2-r,S/2-r,S/2+r,S/2+r], fill=BLUE)
    elif name=='sv-cosmetic':
        c=S/2; pts=[]
        for k in range(8):
            a=math.radians(-90+45*k); rad=S*0.40 if k%2==0 else S*0.13
            pts.append((c+rad*math.cos(a), c+rad*math.sin(a)))
        d.polygon(pts, fill=PURPLE)
    return done(im, n)

# --------------------------------------------------------------- timeline

PALE = C('#fff4c2')

def kind_icon(name, n):
    S=n*8; im=Image.new('RGBA',(S,S),(0,0,0,0)); d=ImageDraw.Draw(im); w=max(int(S*0.09),6)
    if name=='k-checkin':
        # a commit: a ring on a line
        d.line([S*0.04,S/2,S*0.96,S/2], fill=DARK, width=w)
        r=S*0.22; d.ellipse([S/2-r,S/2-r,S/2+r,S/2+r], fill=WHITE, outline=DARK, width=w)
    elif name=='k-ticket':
        # a ticket stub with notches on both sides and a perforation
        a,b=S*0.24,S*0.76
        d.rounded_rectangle([S*0.08,a,S*0.92,b], radius=S*0.06, fill=GREEN)
        r=S*0.09
        for x in (S*0.08,S*0.92): d.ellipse([x-r,S/2-r,x+r,S/2+r], fill=(0,0,0,0))
        for y in range(int(a+S*0.08), int(b-S*0.04), int(S*0.12)):
            d.rectangle([S*0.64-w*0.35,y,S*0.64+w*0.35,y+S*0.06], fill=WHITE)
    elif name=='k-tag':
        # a tag: a pentagon with a hole
        d.polygon([(S*0.08,S*0.24),(S*0.60,S*0.24),(S*0.94,S/2),(S*0.60,S*0.76),(S*0.08,S*0.76)], fill=AMBER)
        r=S*0.07; d.ellipse([S*0.60-r,S/2-r,S*0.60+r,S/2+r], fill=WHITE)
    elif name=='k-wiki':
        # a page with a folded corner and lines
        a,b,f=S*0.20,S*0.80,S*0.22
        d.polygon([(a,S*0.08),(b-f,S*0.08),(b,S*0.08+f),(b,S*0.92),(a,S*0.92)], fill=WHITE, outline=BLUE, width=w)
        d.polygon([(b-f,S*0.08),(b-f,S*0.08+f),(b,S*0.08+f)], fill=BLUE)
        for y in (0.45,0.60,0.75): d.line([a+S*0.13,S*y,b-S*0.13,S*y], fill=BLUE, width=int(w*0.8))
    elif name=='k-forum':
        # a speech bubble
        d.rounded_rectangle([S*0.08,S*0.14,S*0.92,S*0.70], radius=S*0.14, fill=PURPLE)
        d.polygon([(S*0.26,S*0.64),(S*0.48,S*0.64),(S*0.24,S*0.90)], fill=PURPLE)
        for x in (0.32,0.50,0.68):
            r=w*0.75; d.ellipse([S*x-r,S*0.42-r,S*x+r,S*0.42+r], fill=WHITE)
    elif name=='k-technote':
        # a sticky note with a pin
        d.polygon([(S*0.14,S*0.18),(S*0.86,S*0.18),(S*0.86,S*0.66),(S*0.62,S*0.90),(S*0.14,S*0.90)], fill=PALE, outline=ORANGE, width=w)
        d.polygon([(S*0.86,S*0.66),(S*0.62,S*0.66),(S*0.62,S*0.90)], fill=ORANGE)
        r=S*0.09; d.ellipse([S/2-r,S*0.18-r,S/2+r,S*0.18+r], fill=ORANGE)
        for y in (0.42,0.56): d.line([S*0.28,S*y,S*0.72,S*y], fill=ORANGE, width=int(w*0.8))
    return im.resize((n,n), Image.LANCZOS)

# ------------------------------------------------------- the application

# Tiktaalik, crawling out of the water: a fossil on a sand tile.
SAND, EDGE, WATER, FOAM, BONE, RIB = map(C, ['#efdcb2','#a8844e','#3a86c0','#cfe6f5','#4b3a28','#d9bd85'])
def bez(p0,p1,p2,t):
    return tuple((1-t)**2*a+2*(1-t)*t*b+t*t*c for a,b,c in zip(p0,p1,p2))
def app_icon(n):
    K=8 if n<=64 else 4
    S=n*K; im=Image.new('RGBA',(S,S),(0,0,0,0)); d=ImageDraw.Draw(im)
    P=lambda x,y:(x*S,y*S)
    r=S*0.18; m=S*0.03
    # the tile: sand, with the water below on the left
    tile=Image.new('RGBA',(S,S),(0,0,0,0)); td=ImageDraw.Draw(tile)
    td.rounded_rectangle([m,m,S-m,S-m], radius=r, fill=SAND)
    mask=Image.new('L',(S,S),0); ImageDraw.Draw(mask).rounded_rectangle([m,m,S-m,S-m], radius=r, fill=255)
    # the fish: a spine from the tail (in the water) to the snout (on the
    # shore), its outline by thickness: a long body, a broad flat head
    p0,p1,p2=(0.07,0.80),(0.40,0.50),(0.93,0.52)
    def at(t):
        x,y=bez(p0,p1,p2,t)
        dx,dy=[2*(1-t)*(b-a)+2*t*(c-b) for a,b,c in zip(p0,p1,p2)]
        L=math.hypot(dx,dy)
        return x,y,-dy/L,dx/L
    def width(t):
        if t<0.62: return 0.012+0.088*math.sin(t/0.62*math.pi/2)
        if t<0.80: return 0.100
        return 0.100-(t-0.80)/0.20*0.075
    up,lo=[],[]
    N=80
    for k in range(N+1):
        t=k/N; x,y,nx,ny=at(t); w=width(t)
        up.append(P(x-nx*w,y-ny*w)); lo.append(P(x+nx*w*0.8,y+ny*w*0.8))
    # the tail fin
    x,y,nx,ny=at(0.02)
    td.polygon([P(x+0.02,y-0.02),P(x-0.05,y-0.10),P(x-0.06,y+0.04)], fill=BONE)
    # the front fin, a limb propped on the shore, with a splayed tip
    x,y,nx,ny=at(0.70)
    sx,sy=x+nx*0.05,y+ny*0.05
    fx,fy=sx+0.05,0.80
    td.line([P(sx,sy),P(sx+0.07,sy+0.10),P(fx,fy)], fill=BONE, width=int(S*0.055), joint='curve')
    td.polygon([P(fx-0.05,fy+0.035),P(fx+0.09,fy+0.035),P(fx+0.03,fy-0.04)], fill=BONE)
    # the pelvic fin
    x,y,nx,ny=at(0.40)
    td.polygon([P(x+nx*0.04-0.04,y+ny*0.04),P(x+nx*0.04+0.05,y+ny*0.04+0.01),P(x+nx*0.13,y+ny*0.13)], fill=BONE)
    td.polygon(up+lo[::-1], fill=BONE)
    if n>=32:
        # the fossil: a spine and ribs
        for t in [0.26+0.065*i for i in range(7)]:
            x,y,nx,ny=at(t); w=width(t)*0.6
            td.line([P(x-nx*w,y-ny*w),P(x+nx*w*0.75,y+ny*w*0.75)], fill=RIB, width=max(int(S*0.017),2))
        td.line([P(*at(t/40)[:2]) for t in range(8,31)], fill=RIB, width=max(int(S*0.013),2))
    # the eye, on top of the flat head
    x,y,nx,ny=at(0.86); er=0.03 if n>=32 else 0.045
    ex,ey=x-nx*0.045,y-ny*0.045
    td.ellipse([*P(ex-er,ey-er),*P(ex+er,ey+er)], fill=SAND)
    # the water over the tail, up to a curved beach
    def surf(x): return 0.70+0.022*math.sin(x*30)+x*0.10
    wave=[P(0,surf(0))]+[P(0.60*k/40,surf(0.60*k/40)) for k in range(41)]
    wave+=[P(0.60+0.12*math.sin(k/20*math.pi/2),surf(0.60)+(1-surf(0.60))*(1-math.cos(k/20*math.pi/2))) for k in range(21)]
    wave+=[P(1,1),P(0,1)]
    wave=[(x,y) for x,y in wave]
    td.polygon(wave[:-2]+[P(0.72,1),P(0,1)], fill=WATER)
    if n>=48:
        td.line([P(0.03+0.52*k/30,surf(0.03+0.52*k/30)) for k in range(31)], fill=FOAM, width=max(int(S*0.018),2))
    tile.putalpha(Image.composite(tile.getchannel('A'), Image.new('L',(S,S),0), mask))
    d=ImageDraw.Draw(tile)
    d.rounded_rectangle([m,m,S-m,S-m], radius=r, outline=EDGE, width=max(int(S*0.025),2))
    return tile.resize((n,n), Image.LANCZOS)

# ------------------------------------------------------------------ main

BUTTONS = {'search': search, 'save': star, 'clear': cross, 'help': help_}
TICKETS = ['st-open', 'st-pending', 'st-fixed', 'st-closed', 'st-duplicate',
           'st-rejected', 'st-invalid', 'st-worksforme', 'st-outofdate',
           'st-postponed', 'st-deleted',
           'pr-9', 'pr-8', 'pr-7', 'pr-6', 'pr-5', 'pr-low',
           'sv-critical', 'sv-severe', 'sv-major', 'sv-minor', 'sv-cosmetic']
KINDS = ['k-checkin', 'k-ticket', 'k-tag', 'k-wiki', 'k-forum', 'k-technote']
SIZES = (16, 24, 32)
APP_SIZES = (16, 24, 32, 48, 64, 128, 256)

def draw(name, n):
    if name in BUTTONS:
        return BUTTONS[name](n)
    if name in TICKETS:
        return ticket_icon(name, n)
    return kind_icon(name, n)

def main():
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'icons')
    out = os.environ.get('ICONS_DIR', out)
    os.makedirs(out, exist_ok=True)
    names = list(BUTTONS) + TICKETS + KINDS
    sheet = Image.new('RGBA', (len(names) * 36, len(SIZES) * 36), (255, 255, 255, 255))
    for i, name in enumerate(names):
        for j, n in enumerate(SIZES):
            img = draw(name, n)
            img.save(os.path.join(out, f'{name}-{n}.png'))
            sheet.paste(img, (i * 36 + 2, j * 36 + 2), img)
    apps = {n: app_icon(n) for n in APP_SIZES}
    for n, img in apps.items():
        img.save(os.path.join(out, f'tktaalik-{n}.png'))
    # For Windows (shortcuts): all sizes, each as drawn, in one file.
    apps[256].save(os.path.join(out, 'tktaalik.ico'), format='ICO',
                   sizes=[(n, n) for n in APP_SIZES],
                   append_images=[apps[n] for n in APP_SIZES if n != 256])
    if sys.argv[1:2] == ['--preview']:
        sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(sys.argv[2])
    print(len(names) * len(SIZES) + len(APP_SIZES), 'icons and tktaalik.ico in', os.path.normpath(out))

if __name__ == '__main__':
    main()
