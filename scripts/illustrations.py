#!/usr/bin/env python3
"""Generates the Cans headphone illustrations (original artwork, MIT; no Sony marks).

Drawn from Sony's own "Location and function of parts" diagrams and real photos:
  WH-1000XM4: broad flat padded band; long flat slider strips running down into
              swivel yokes that wrap the cup's top-rear; oval cups with visible side
              depth, a circular touch panel on the outer face, and a copper-ringed
              external NC mic near the top rim.
  WH-1000XM5: slimmer seamless band with capped ends; a slim cylindrical stem down to
              each cup; rounded-rectangle ("pebble") cups that read as slabs, with a
              rounded-square touch plate and pinhole mics.
Plain SVG (gradients only, no filters) so Xcode keeps it as vector data.
Usage: scripts/illustrations.py
"""
import math, os

ROOT = os.path.join(os.path.dirname(__file__), "..", "Resources", "Assets.xcassets")
W, H = 400, 350


def superellipse(cx, cy, a, b, n, rot=0.0, steps=96):
    """Closed path of |x/a|^n + |y/b|^n = 1, rotated by rot degrees. n=2 is an ellipse."""
    r = math.radians(rot)
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = a * math.copysign(abs(c) ** (2 / n), c)
        y = b * math.copysign(abs(s) ** (2 / n), s)
        pts.append((cx + x * math.cos(r) - y * math.sin(r), cy + x * math.sin(r) + y * math.cos(r)))
    return "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in pts) + " Z"


DEFS = '''<defs>
  <radialGradient id="face" cx="0.36" cy="0.3" r="0.8">
    <stop offset="0" stop-color="#5C5F65"/><stop offset="0.4" stop-color="#36383D"/>
    <stop offset="0.8" stop-color="#222326"/><stop offset="1" stop-color="#17181A"/>
  </radialGradient>
  <linearGradient id="side" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#1A1B1E"/><stop offset="0.6" stop-color="#2A2C30"/><stop offset="1" stop-color="#111214"/>
  </linearGradient>
  <radialGradient id="panel" cx="0.4" cy="0.35" r="0.75">
    <stop offset="0" stop-color="#4B4E54"/><stop offset="1" stop-color="#26282B"/>
  </radialGradient>
  <linearGradient id="band" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#5A5D63"/><stop offset="0.4" stop-color="#303236"/><stop offset="1" stop-color="#18191C"/>
  </linearGradient>
  <linearGradient id="pad" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#3C3E43"/><stop offset="1" stop-color="#1D1E21"/>
  </linearGradient>
  <radialGradient id="leather" cx="0.4" cy="0.3" r="0.8">
    <stop offset="0" stop-color="#4E5055"/><stop offset="0.55" stop-color="#2B2D31"/><stop offset="1" stop-color="#141517"/>
  </radialGradient>
  <radialGradient id="well" cx="0.45" cy="0.4" r="0.7">
    <stop offset="0" stop-color="#2A2B2E"/><stop offset="1" stop-color="#09090A"/>
  </radialGradient>
  <linearGradient id="slider" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#2B2D31"/><stop offset="0.45" stop-color="#4A4D53"/><stop offset="1" stop-color="#1D1E21"/>
  </linearGradient>
  <linearGradient id="metal" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#5E6166"/><stop offset="0.4" stop-color="#C9CDD2"/>
    <stop offset="0.6" stop-color="#8E9297"/><stop offset="1" stop-color="#4A4D52"/>
  </linearGradient>
  <linearGradient id="copper" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#EBC08F"/><stop offset="0.5" stop-color="#BB7B4B"/><stop offset="1" stop-color="#7C4A29"/>
  </linearGradient>
  <radialGradient id="floor" cx="0.5" cy="0.5" r="0.5">
    <stop offset="0" stop-color="#000" stop-opacity="0.55"/><stop offset="0.6" stop-color="#000" stop-opacity="0.16"/>
    <stop offset="1" stop-color="#000" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#9CC2E6" stop-opacity="0"/><stop offset="0.5" stop-color="#9CC2E6" stop-opacity="0.7"/>
    <stop offset="1" stop-color="#9CC2E6" stop-opacity="0"/>
  </linearGradient>
</defs>'''


def model(xm5):
    n = 3.4 if xm5 else 2.0                      # cup outline: pebble vs oval
    near = dict(cx=138, cy=226, a=60 if xm5 else 64, b=80 if xm5 else 82, rot=-8)
    far = dict(cx=298, cy=210, a=46 if xm5 else 48, b=64 if xm5 else 64, rot=12)
    band_w = 20 if xm5 else 30
    band = "M112,112 C92,40 166,16 220,20 C284,25 330,62 316,120" if xm5 else \
           "M110,104 C92,38 166,14 220,18 C284,23 332,58 318,112"
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}">',
         f'<!-- Original illustration of a WH-1000X{"M5" if xm5 else "M4"} made for Cans (MIT). No Sony marks. -->',
         DEFS]
    a = s.append

    a('<ellipse cx="208" cy="330" rx="165" ry="12" fill="url(#floor)"/>')
    a('<ellipse cx="146" cy="324" rx="72" ry="8" fill="url(#floor)"/>')

    # ---------- far cup: cushion side toward us ----------
    f = far
    a(f'<path d="{superellipse(f["cx"]+6, f["cy"]+3, f["a"]+1, f["b"]+1, n, f["rot"])}" fill="#0B0C0D"/>')  # slab back
    a(f'<path d="{superellipse(f["cx"]+3, f["cy"]+1, f["a"], f["b"], n, f["rot"])}" fill="url(#side)"/>')
    a(f'<path d="{superellipse(f["cx"]-3, f["cy"], f["a"]-3, f["b"]-3, n, f["rot"])}" fill="url(#leather)"/>')  # cushion
    a(f'<path d="{superellipse(f["cx"]-3, f["cy"], f["a"]-7, f["b"]-7, n, f["rot"])}" fill="none" stroke="#5B5D62" '
      f'stroke-width="0.8" stroke-dasharray="2.2 2.2" opacity="0.6"/>')
    a(f'<path d="{superellipse(f["cx"]-5, f["cy"]+2, f["a"]-22, f["b"]-26, n, f["rot"])}" fill="url(#well)"/>')  # opening
    for i in range(-3, 4):
        for j in range(-5, 6):
            x, y = f["cx"] - 5 + i * 5, f["cy"] + 2 + j * 5
            if ((x - (f["cx"] - 5)) / (f["a"] - 25)) ** 2 + ((y - (f["cy"] + 2)) / (f["b"] - 29)) ** 2 < 1:
                a(f'<circle cx="{x}" cy="{y}" r="0.7" fill="#3B3D41" opacity="0.6"/>')
    a(f'<path d="M{f["cx"]+f["a"]-4},{f["cy"]-26} q12,32 0,66" stroke="url(#rim)" stroke-width="2" fill="none" stroke-linecap="round"/>')

    # ---------- headband ----------
    a(f'<path d="{band}" stroke="#0A0B0C" stroke-width="{band_w+5}" fill="none" stroke-linecap="round"/>')
    a(f'<path d="{band}" stroke="url(#band)" stroke-width="{band_w}" fill="none" stroke-linecap="round"/>')
    if not xm5:
        # padded underside with stitching (XM4)
        a('<path d="M120,98 C104,46 166,32 219,35 C274,39 316,68 306,104" stroke="url(#pad)" stroke-width="11" fill="none" stroke-linecap="round"/>')
        a('<path d="M122,92 C108,52 166,40 219,43 C270,46 308,72 300,100" stroke="#57595F" stroke-width="0.8" fill="none" stroke-dasharray="2.4 2.4" opacity="0.6"/>')
    else:
        a('<path d="M118,106 C100,48 166,30 219,33 C274,37 314,68 306,114" stroke="#3F4247" stroke-width="1.1" fill="none" opacity="0.8"/>')
    a('<path d="M116,70 C136,36 176,26 216,26" stroke="#A9ADB3" stroke-width="3" fill="none" stroke-linecap="round" opacity="0.8"/>')
    a('<path d="M216,26 C240,27 258,32 272,40" stroke="#A9ADB3" stroke-width="1.5" fill="none" stroke-linecap="round" opacity="0.45"/>')
    a('<path d="M330,72 C336,90 334,106 324,120" stroke="url(#rim)" stroke-width="2.2" fill="none" stroke-linecap="round"/>')

    if xm5:
        # capped band ends + slim cylindrical stems down to the cups
        for (x, y, rot, length) in [(112, 112, -6, 44), (312, 118, 10, 36)]:
            a(f'<g transform="rotate({rot} {x} {y})">'
              f'<rect x="{x-8}" y="{y-6}" width="16" height="12" rx="5" fill="#26282B"/>'
              f'<rect x="{x-3}" y="{y+4}" width="6" height="{length}" rx="3" fill="url(#metal)"/>'
              f'<rect x="{x-5}" y="{y+length}" width="10" height="7" rx="3" fill="#232427"/></g>')
    else:
        # long flat slider strips into swivel yokes
        for (x, y, rot, length) in [(110, 104, -8, 40), (318, 112, 12, 30)]:
            a(f'<g transform="rotate({rot} {x} {y})">'
              f'<rect x="{x-6}" y="{y}" width="12" height="{length}" rx="2" fill="url(#slider)"/>'
              f'<rect x="{x-6}" y="{y+6}" width="12" height="0.8" fill="#5A5D63" opacity="0.7"/></g>')
        # swivel yoke arms wrapping the top-rear of each cup
        # swivel yoke: from the slider foot, hugging the top-rear edge of the near cup
        yoke = "M112,142 C124,146 150,142 176,152"
        a(f'<path d="{yoke}" stroke="#0B0C0D" stroke-width="7.5" fill="none" stroke-linecap="round"/>')
        a(f'<path d="{yoke}" stroke="#2A2C30" stroke-width="5.5" fill="none" stroke-linecap="round"/>')
        a(f'<path d="{yoke}" stroke="#5A5D63" stroke-width="0.9" fill="none" stroke-linecap="round" opacity="0.7"/>')

    # ---------- near cup: outer face toward us ----------
    c = near
    # cushion bulging out behind the shell (visible depth)
    a(f'<path d="{superellipse(c["cx"]+24, c["cy"]+4, c["a"]-2, c["b"]-2, n, c["rot"])}" fill="#0B0C0D"/>')
    a(f'<path d="{superellipse(c["cx"]+21, c["cy"]+3, c["a"]-4, c["b"]-4, n, c["rot"])}" fill="url(#leather)"/>')
    a(f'<path d="{superellipse(c["cx"]+21, c["cy"]+3, c["a"]-8, c["b"]-8, n, c["rot"])}" fill="none" stroke="#5B5D62" '
      f'stroke-width="0.8" stroke-dasharray="2.2 2.2" opacity="0.55"/>')
    # shell side wall (slab thickness), then the outer face
    a(f'<path d="{superellipse(c["cx"]+9, c["cy"]+2, c["a"]+1, c["b"]+1, n, c["rot"])}" fill="url(#side)"/>')
    a(f'<path d="{superellipse(c["cx"]+1, c["cy"], c["a"]+1, c["b"]+1, n, c["rot"])}" fill="#0C0D0E"/>')
    a(f'<path d="{superellipse(c["cx"], c["cy"], c["a"], c["b"], n, c["rot"])}" fill="url(#face)"/>')
    # touch panel: circle on XM4, rounded-square plate on XM5
    if xm5:
        a(f'<path d="{superellipse(c["cx"]-2, c["cy"]+4, c["a"]-20, c["b"]-26, 3.0, c["rot"])}" fill="url(#panel)" opacity="0.9"/>')
        a(f'<path d="{superellipse(c["cx"]-2, c["cy"]+4, c["a"]-20, c["b"]-26, 3.0, c["rot"])}" fill="none" stroke="#5E6167" stroke-width="0.8" opacity="0.7"/>')
    else:
        a(f'<circle cx="{c["cx"]-2}" cy="{c["cy"]+6}" r="{c["a"]-18}" fill="url(#panel)" opacity="0.85"/>')
        a(f'<circle cx="{c["cx"]-2}" cy="{c["cy"]+6}" r="{c["a"]-18}" fill="none" stroke="#1B1C1F" stroke-width="1.2"/>')
    # specular along the top edge + cool rim on the left
    a(f'<path d="M{c["cx"]-c["a"]+12},{c["cy"]-c["b"]*0.55} C{c["cx"]-c["a"]*0.4},{c["cy"]-c["b"]*0.98} '
      f'{c["cx"]+c["a"]*0.35},{c["cy"]-c["b"]*1.0} {c["cx"]+c["a"]*0.66},{c["cy"]-c["b"]*0.7}" stroke="#ADB1B7" '
      f'stroke-width="3.2" fill="none" stroke-linecap="round" opacity="0.7"/>')
    a(f'<path d="M{c["cx"]-c["a"]+2},{c["cy"]-8} C{c["cx"]-c["a"]-3},{c["cy"]+30} {c["cx"]-c["a"]+12},{c["cy"]+c["b"]-18} '
      f'{c["cx"]-c["a"]*0.3},{c["cy"]+c["b"]-4}" stroke="url(#rim)" stroke-width="2.4" fill="none" stroke-linecap="round"/>')
    # microphones
    if xm5:
        for dx, dy in [(0.2, -0.86), (0.42, -0.8), (0.72, 0.5)]:
            a(f'<circle cx="{c["cx"]+c["a"]*dx:.1f}" cy="{c["cy"]+c["b"]*dy:.1f}" r="1.6" fill="#0A0A0B" stroke="#55585E" stroke-width="0.6"/>')
    else:
        a(f'<g transform="rotate(20 {c["cx"]+30} {c["cy"]-c["b"]+14})">'
          f'<rect x="{c["cx"]+22}" y="{c["cy"]-c["b"]+11}" width="16" height="5" rx="2.5" fill="url(#copper)"/>'
          f'<rect x="{c["cx"]+24}" y="{c["cy"]-c["b"]+12.5}" width="12" height="2" rx="1" fill="#1A1B1D"/></g>')
    s.append('</svg>')
    return "\n".join(s)


for name, xm5 in [("HeadphonesXM4.imageset/xm4.svg", False), ("HeadphonesXM5.imageset/xm5.svg", True)]:
    with open(os.path.join(ROOT, name), "w") as fh:
        fh.write(model(xm5) + "\n")
print("wrote xm4.svg, xm5.svg")
