#!/usr/bin/env python3
# Builds WavegooRoundsquare.ttf: block letters in the spirit of Joseph Churchward's
# Roundsquare (the Bugonia title font). Every glyph is a solid block, or a triangle for
# A / V / W, with round holes, slits and notches cut out of it; the cut-outs make the letter.
#
# Needs fonttools + shapely:   python -m venv env && env/bin/pip install fonttools shapely
# Run:                         env/bin/python roundsquare.py   (writes next to this file)
# Tweak a letter: edit its entry in GLYPHS below; units are 1/1000 em, caps are H tall.
import os
from shapely.geometry import Point, Polygon, box
from shapely.geometry.polygon import orient
from shapely.ops import unary_union
from shapely import affinity
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

H = 700        # cap height = block height
W = 640        # normal block width: nearly square, like Churchward's
S = 66         # slit width: thin cuts (any thinner and they vanish at menu sizes)
R = 118        # hole radius
SIDE = 64      # space either side of a glyph
cx = W / 2


def blk(w=W, h=H, y=0):
    return box(0, y, w, y + h)

def rect(x0, y0, x1, y1):
    return box(x0, y0, x1, y1)

def circ(x, y, r):
    return Point(x, y).buffer(r, 32)

def poly(*pts):
    return Polygon(pts)

def cut(base, *holes):
    return base.difference(unary_union(holes))

def hslit(x0, x1, y):          # horizontal slit centred on y
    return rect(x0, y - S / 2, x1, y + S / 2)

def vslit(x, y0, y1):          # vertical slit centred on x
    return rect(x - S / 2, y0, x + S / 2, y1)

def key(x, y, r, to):
    """Churchward's keyhole: a round hole with a thin slit running from it out to an edge.
    `to` is 'up', 'down', 'left' or 'right'; the slit runs well past the glyph's edge."""
    far = 5000
    slit = {"up": vslit(x, y, far), "down": vslit(x, -far, y),
            "left": hslit(-far, x, y), "right": hslit(x, far, y)}[to]
    return unary_union([circ(x, y, r), slit])

def rounded(w, h, rad, corners="tl tr bl br"):
    """block with the named corners rounded off"""
    parts = [rect(rad, 0, w - rad, h), rect(0, rad, w, h - rad)]
    spots = {"bl": (rad, rad), "br": (w - rad, rad), "tl": (rad, h - rad), "tr": (w - rad, h - rad)}
    for k, (x, y) in spots.items():
        parts.append(circ(x, y, rad) if k in corners.split() else rect(x - rad, y - rad, x + rad, y + rad))
    return unary_union(parts)


WM = W * 1.2       # wide blocks for M / W
WT = W * 1.08      # triangles for A / V
WD = W * 0.8       # digits
q = 150            # punctuation unit
r2 = R * 0.62      # small holes (B, 8)

GLYPHS = {
    "A": cut(poly((0, 0), (WT, 0), (WT / 2, H)), key(WT / 2, H * 0.3, R * 0.8, "down")),
    "B": cut(blk(), circ(W * 0.44, H * 0.73, R * 0.75), circ(W * 0.44, H * 0.27, R * 0.75), poly((W * 0.72, H / 2), (W + 1, H * 0.62), (W + 1, H * 0.38))),
    "C": cut(blk(), key(cx, H / 2, R * 1.2, "right")),
    "D": cut(rounded(W, H, W * 0.42, "tr br"), circ(W * 0.42, H / 2, R * 1.1)),
    "E": cut(blk(), hslit(W * 0.36, W + 1, H * 0.68), hslit(W * 0.36, W + 1, H * 0.32)),
    "F": cut(blk(), hslit(W * 0.36, W + 1, H * 0.68), rect(W * 0.36, -1, W + 1, H * 0.38)),
    "G": cut(blk(), circ(cx, H * 0.42, R * 1.05), hslit(cx, W + 1, H * 0.42 + R * 1.05 - S / 2)),
    "H": cut(blk(), vslit(cx, H * 0.62, H + 1), vslit(cx, -1, H * 0.38)),
    "I": blk(W * 0.3),
    "J": cut(blk(), rect(-1, H * 0.36, W * 0.6, H + 1)),
    "K": cut(blk(), poly((W * 0.4, H / 2), (W + 1, H * 0.95), (W + 1, H * 0.05))),
    "L": cut(blk(), rect(W * 0.36, H * 0.3, W + 1, H + 1)),
    "M": cut(blk(WM), poly((WM * 0.22, H + 1), (WM * 0.78, H + 1), (WM / 2, H * 0.34)), vslit(WM / 2, -1, H * 0.2)),
    "N": cut(blk(), vslit(W * 0.64, H * 0.28, H + 1), vslit(W * 0.36, -1, H * 0.72)),
    "O": cut(blk(), circ(cx, H / 2, R * 1.25)),
    "P": cut(blk(), circ(cx, H * 0.67, R * 0.85), rect(W * 0.38, -1, W + 1, H * 0.36)),
    "Q": cut(blk(), circ(cx, H * 0.55, R * 1.05), poly((W * 0.58, -1), (W + 1, -1), (W + 1, H * 0.3))),
    "R": cut(blk(), circ(cx, H * 0.67, R * 0.85), poly((W * 0.38, -1), (W + 1, -1), (W + 1, H * 0.06), (W * 0.62, H * 0.38), (W * 0.38, H * 0.38))),   # P with a slanted leg
    "S": cut(blk(), hslit(W * 0.32, W + 1, H * 0.66), hslit(-1, W * 0.68, H * 0.34)),
    "T": cut(blk(), rect(-1, -1, W * 0.33, H * 0.7), rect(W * 0.67, -1, W + 1, H * 0.7)),
    "U": cut(blk(), key(cx, H * 0.4, R * 0.95, "up")),
    "V": cut(poly((0, H), (WT, H), (WT / 2, 0)), key(WT / 2, H * 0.68, R * 0.78, "up")),
    "W": cut(blk(WM), poly((WM * 0.22, -1), (WM * 0.78, -1), (WM / 2, H * 0.66)), vslit(WM / 2, H * 0.8, H + 1)),
    "X": cut(blk(), poly((W * 0.26, H + 1), (W * 0.74, H + 1), (cx, H * 0.6)), poly((W * 0.26, -1), (W * 0.74, -1), (cx, H * 0.4)),
             poly((-1, H * 0.24), (-1, H * 0.76), (W * 0.36, H / 2)), poly((W + 1, H * 0.24), (W + 1, H * 0.76), (W * 0.64, H / 2))),   # notched on all four sides, so it never reads as M
    "Y": cut(blk(), poly((W * 0.2, H + 1), (W * 0.8, H + 1), (cx, H * 0.44)), rect(-1, -1, W * 0.33, H * 0.44), rect(W * 0.67, -1, W + 1, H * 0.44)),
    "Z": cut(blk(), hslit(-1, W * 0.68, H * 0.66), hslit(W * 0.32, W + 1, H * 0.34)),

    "0": cut(blk(WD), unary_union([circ(WD / 2, H * 0.64, R * 0.8), circ(WD / 2, H * 0.36, R * 0.8),
                                   rect(WD / 2 - R * 0.8, H * 0.36, WD / 2 + R * 0.8, H * 0.64)])),
    "1": unary_union([rect(WD * 0.3, 0, WD * 0.66, H), rect(0, H * 0.72, WD * 0.66, H)]),
    "2": cut(rounded(WD, H, WD * 0.32, "tr"), hslit(-1, WD * 0.64, H * 0.66), hslit(WD * 0.36, WD + 1, H * 0.34)),
    "3": cut(blk(WD), hslit(-1, WD * 0.62, H * 0.68), hslit(-1, WD * 0.62, H * 0.32)),
    "4": cut(blk(WD), rect(-1, -1, WD * 0.56, H * 0.34), vslit(WD * 0.42, H * 0.58, H + 1)),
    "5": cut(blk(WD), hslit(WD * 0.36, WD + 1, H * 0.66), hslit(-1, WD * 0.64, H * 0.34), rect(WD * 0.72, H * 0.66, WD + 1, H * 0.8)),
    "6": cut(blk(WD), hslit(WD * 0.38, WD + 1, H * 0.7), circ(WD / 2, H * 0.3, R * 0.75)),
    "7": cut(blk(WD), rect(-1, -1, WD * 0.58, H * 0.72)),
    "8": cut(blk(WD), circ(WD / 2, H * 0.72, r2 * 1.1), circ(WD / 2, H * 0.28, r2 * 1.1)),
    "9": cut(blk(WD), circ(WD / 2, H * 0.7, R * 0.75), hslit(-1, WD * 0.62, H * 0.3)),
    ".": blk(q, q),
    ",": unary_union([blk(q, q), poly((0, 1), (q, 1), (0, -H * 0.2))]),
    ":": unary_union([blk(q, q), blk(q, q, H * 0.46)]),
    ";": unary_union([blk(q, q), poly((0, 1), (q, 1), (0, -H * 0.2)), blk(q, q, H * 0.46)]),
    "-": blk(W * 0.5, q, H * 0.42),
    "_": blk(W * 0.8, q * 0.8, -H * 0.12),
    "=": unary_union([blk(W * 0.6, q * 0.8, H * 0.2), blk(W * 0.6, q * 0.8, H * 0.52)]),
    "+": unary_union([blk(W * 0.6, q * 0.8, H * 0.43 - q * 0.4 + 0.07 * H), rect(W * 0.3 - q * 0.4, H * 0.18, W * 0.3 + q * 0.4, H * 0.82)]),
    "!": unary_union([blk(q, H * 0.7, H * 0.3), blk(q, q)]),
    "?": unary_union([cut(blk(W * 0.8, H * 0.58, H * 0.42), rect(-1, H * 0.42 - 1, W * 0.42, H * 0.64)),
                      rect(W * 0.42, H * 0.22, W * 0.8, H * 0.43), blk(W * 0.38, q, 0)]),
    "'": blk(q, H * 0.3, H * 0.7),
    '"': unary_union([blk(q, H * 0.3, H * 0.7), rect(q * 1.7, H * 0.7, q * 2.7, H)]),
    "/": poly((0, -H * 0.05), (W * 0.18, -H * 0.05), (W * 0.62, H * 1.05), (W * 0.44, H * 1.05)),
    "(": cut(blk(W * 0.34, H * 1.1, -H * 0.05), rect(W * 0.17, H * 0.12, W * 0.35, H * 0.88)),
    ")": cut(blk(W * 0.34, H * 1.1, -H * 0.05), rect(-1, H * 0.12, W * 0.17, H * 0.88)),
    "·": blk(q, q, H * 0.4),
    "%": unary_union([blk(q, q, H - q), blk(q, q, 0).buffer(0), poly((0, 0), (W * 0.16, 0), (W * 0.6, H), (W * 0.44, H)),
                      affinity.translate(blk(q, q), W * 0.6 - q, 0), affinity.translate(blk(q, q, H - q), 0, 0)]),
    "&": cut(blk(W * 0.95), circ(W * 0.4, H * 0.72, R * 0.7), circ(W * 0.4, H * 0.28, R * 0.85), vslit(W * 0.78, H * 0.45, H + 1)),
    "#": cut(blk(W * 0.9), rect(W * 0.18, H * 0.18, W * 0.36, H * 0.38), rect(W * 0.54, H * 0.18, W * 0.72, H * 0.38),
             rect(W * 0.18, H * 0.62, W * 0.36, H * 0.82), rect(W * 0.54, H * 0.62, W * 0.72, H * 0.82)),
}
SPACE = int(W * 0.45)
NAMES = {".": "period", ",": "comma", ":": "colon", ";": "semicolon", "-": "hyphen", "_": "underscore",
         "=": "equal", "+": "plus", "!": "exclam", "?": "question", "'": "quotesingle", '"': "quotedbl",
         "/": "slash", "(": "parenleft", ")": "parenright", "·": "periodcentered", "%": "percent",
         "&": "ampersand", "#": "numbersign"}
DIGITS = {str(i): n for i, n in enumerate("zero one two three four five six seven eight nine".split())}


def gname(ch):
    return NAMES.get(ch) or DIGITS.get(ch) or ch


def draw(geom):
    pen = TTGlyphPen(None)
    polys = [geom] if geom.geom_type == "Polygon" else [g for g in geom.geoms if g.geom_type == "Polygon"]
    for p in polys:
        p = orient(p, sign=-1.0)          # TrueType: outer contours clockwise, holes counter-clockwise
        for ring in [p.exterior, *p.interiors]:
            pts = []
            for x, y in list(ring.coords)[:-1]:
                pt = (round(x), round(y))
                if not pts or pts[-1] != pt:
                    pts.append(pt)
            if len(pts) > 1 and pts[0] == pts[-1]:
                pts.pop()
            if len(pts) < 3:
                continue
            pen.moveTo(pts[0])
            for pt in pts[1:]:
                pen.lineTo(pt)
            pen.closePath()
    return pen.glyph()


def build(path):
    order = [".notdef", "space"]
    glyphs, metrics, cmap = {}, {}, {}

    nd = cut(blk(W * 0.7), rect(W * 0.12, H * 0.1, W * 0.58, H * 0.9))
    glyphs[".notdef"] = draw(affinity.translate(nd, SIDE, 0))
    metrics[".notdef"] = (int(W * 0.7) + 2 * SIDE, SIDE)
    glyphs["space"] = TTGlyphPen(None).glyph()
    metrics["space"] = (SPACE, 0)
    cmap[32] = "space"; cmap[0xA0] = "space"

    for ch, geom in GLYPHS.items():
        name = gname(ch)
        geom = geom.buffer(0)
        minx, _, maxx, _ = geom.bounds
        geom = affinity.translate(geom, SIDE - minx, 0)
        order.append(name)
        glyphs[name] = draw(geom)
        metrics[name] = (round(maxx - minx) + 2 * SIDE, SIDE)
        cmap[ord(ch)] = name
        if ch.isalpha():
            cmap[ord(ch.lower())] = name   # lowercase types as the same block caps

    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=820, descent=-200)
    fb.setupNameTable({"familyName": "Wavegoo Roundsquare", "styleName": "Regular"})
    fb.setupOS2(sTypoAscender=820, sTypoDescender=-200, sTypoLineGap=0, usWinAscent=820, usWinDescent=200,
                sCapHeight=H, sxHeight=H, achVendID="WGOO")
    fb.setupPost()
    fb.save(path)


if __name__ == "__main__":
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "WavegooRoundsquare.ttf")
    build(out)
    print("wrote", out)
