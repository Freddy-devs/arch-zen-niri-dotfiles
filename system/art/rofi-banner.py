# Cabecera del lanzador: lluvia de código + circuito + prompt de terminal, paleta TokyoNight plana.
import random, sys
from html import escape
random.seed(7)
W, H = 568, 130
BG, BLUE, PURPLE, CYAN, OVER, TEXT = "#16161e", "#7aa2f7", "#bb9af7", "#7dcfff", "#565f89", "#c0caf5"
o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
     f'<rect width="{W}" height="{H}" fill="{BG}"/>']

# lluvia de código: columnas de hex/binario muy tenues
glyphs = "0101010123456789ABCDEF{}<>/$#;=*"
font = "JetBrainsMono Nerd Font Mono"
for col in range(0, W, 13):
    start = random.randint(-6, 4); length = random.randint(4, 11)
    for row in range(start, start + length):
        y = row * 13 + 10
        if 0 < y < H:
            head = row == start + length - 1
            op = 0.55 if head else 0.06 + 0.22 * (row - start) / length
            c = CYAN if head else OVER
            o.append(f'<text x="{col}" y="{y}" font-family="{font}" font-size="10" fill="{c}" opacity="{op:.2f}">{escape(random.choice(glyphs))}</text>')

# pistas de circuito a la derecha
def trace(pts, color, op):
    d = "M" + " L".join(f"{x},{y}" for x, y in pts)
    o.append(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="1.4" opacity="{op}"/>')
    x, y = pts[-1]
    o.append(f'<circle cx="{x}" cy="{y}" r="3" fill="{BG}" stroke="{color}" stroke-width="1.4" opacity="{op + .2}"/>')
trace([(568, 18), (500, 18), (482, 36), (430, 36)], BLUE, .55)
trace([(568, 30), (520, 30), (505, 45), (505, 70), (470, 70)], PURPLE, .5)
trace([(568, 52), (540, 52), (528, 64), (528, 84)], CYAN, .45)
trace([(568, 8), (455, 8), (440, 22), (390, 22)], OVER, .6)
# chip
o.append(f'<rect x="440" y="52" width="26" height="26" rx="4" fill="{BG}" stroke="{BLUE}" stroke-width="1.4" opacity=".7"/>')
for i in range(4):
    o.append(f'<line x1="{444+i*6}" y1="48" x2="{444+i*6}" y2="52" stroke="{BLUE}" stroke-width="1.2" opacity=".6"/>')
    o.append(f'<line x1="{444+i*6}" y1="78" x2="{444+i*6}" y2="82" stroke="{BLUE}" stroke-width="1.2" opacity=".6"/>')
o.append(f'<rect x="447" y="59" width="12" height="12" rx="2" fill="{PURPLE}" opacity=".55"/>')

# prompt de terminal
o.append(f'<rect x="14" y="14" width="262" height="56" rx="8" fill="{BG}" opacity=".88" stroke="{OVER}" stroke-opacity=".35"/>')
for i, c in enumerate(["#f7768e", "#e0af68", "#9ece6a"]):
    o.append(f'<circle cx="{28+i*12}" cy="27" r="3.5" fill="{c}" opacity=".85"/>')
o.append(f'<text x="26" y="54" font-family="{font}" font-size="13" font-weight="bold" xml:space="preserve">'
         f'<tspan fill="{BLUE}">freddy</tspan><tspan fill="{OVER}">@</tspan><tspan fill="{PURPLE}">arch-zen</tspan>'
         f'<tspan fill="{CYAN}"> ~ </tspan><tspan fill="{TEXT}">$ ./launch</tspan></text>')
o.append(f'<rect x="250" y="43" width="8" height="14" fill="{CYAN}" opacity=".9"/>')
o.append("</svg>")
open(sys.argv[1], "w").write("\n".join(o))
