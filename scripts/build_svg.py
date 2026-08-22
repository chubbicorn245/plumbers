#!/usr/bin/env python3
"""Build the Art Plumber (frog) SVG and Solidity string constants.

BODY_GRID was extracted cell-for-cell from the source image
(frog.webp, 1024x1024 = 24x24 cells of ~42.7px) via extract_grid.py.

HEAD_GRID is the head plunger, drawn as a separate layer painted AFTER the
body: when present, its sucker covers the frog's ear bumps (row 6); when
absent, the ears show.

Regions / color slots (the on-chain "color match hunt" traits):
  headStick   - the plunger stick he hangs from
  headSucker  - the plunger sucker stuck on his head (covers the ears)
  heldStick   - the stick of the plunger he is holding
  heldSucker  - the sucker of the plunger he is holding
  suit        - the work suit
  boots       - the boots

Presence slots: head plunger and held plunger can each be absent, so the
SVG is three self-contained segments (body, head plunger, held plunger),
each carrying its own shading overlays.

Fixed (not part of the hunt): frog skin greens, eye, mouth, belt, background.

Shading is applied as translucent black/white overlay pixels so every slot
can be recolored with a single flat color and keep its pixel-art shading.
"""

import re

N = 24  # grid size / viewBox

# Body symbols:
#   F/G/H frog green dark/mid/light | E eye | M mouth | B belt
#   a/b/c/z suit base/shadow/light/zipper | g/m boot base/top
#   o/l held stick base/dark | p/j/n held sucker dark/mid/light
BODY_GRID = [
    "........................",  # 0
    "........................",  # 1
    "........................",  # 2
    "........................",  # 3
    "........................",  # 4
    "........................",  # 5
    "..........F.H...........",  # 6  <- ear bumps (covered by head sucker)
    ".........FGGGH..........",  # 7
    ".........FEGG...pjjjn...",  # 8
    ".........FMMMM...pjn....",  # 9
    ".........FGGGH....n.....",  # 10
    "..........FGH.....o.....",  # 11
    ".........bazac....l.....",  # 12
    ".......bbaazaacc..l.....",  # 13
    "......baaaazaaaaccG.....",  # 14
    "......babaazaacaaaG.....",  # 15
    "......babaazaac...l.....",  # 16
    "......baBBBBBBB...l.....",  # 17
    "......GGbaacaac...o.....",  # 18
    "........bacbaac...o.....",  # 19
    "........bac.bac.........",  # 20
    "........bc..bc..........",  # 21
    "........mm..mm..........",  # 22
    "........ggg.ggg.........",  # 23
]

# Head plunger layer: S stick | P/J/N sucker dark/mid/light.
# Row 6 overlaps the body's ear row on purpose - painted later, it covers
# the ears exactly as a suction cup stuck on the head would.
HEAD_GRID = [
    "...........S............",  # 0
    "...........S............",  # 1
    "...........S............",  # 2
    "...........S............",  # 3
    "...........N............",  # 4
    "..........PJN...........",  # 5
    ".........PJJJN..........",  # 6
]

# Default slot colors = the shared on-chain palette's OG entries
DEFAULTS = {
    "headStick": "3e3429",
    "headSucker": "c0744a",
    "heldStick": "3e3429",
    "heldSucker": "c0744a",
    "suit": "383982",
    "boots": "2e2423",
}
FIXED = {
    "skinDark": "58883f",
    "skin": "639847",
    "skinLight": "6ba34e",
    "mouth": "a3663b",
    "belt": "3b2d2d",
    "eye": "000000",
    "bg": "000000",
}

# symbol -> (region, shade); shade '' | 'dark' | 'darker' | 'light'
SYMBOLS = {
    "F": ("skinDark", ""), "G": ("skin", ""), "H": ("skinLight", ""),
    "E": ("eye", ""), "M": ("mouth", ""), "B": ("belt", ""),
    "a": ("suit", ""), "b": ("suit", "dark"), "c": ("suit", "light"),
    "z": ("suit", "darker"),
    "g": ("boots", ""), "m": ("boots", "dark"),
    "o": ("heldStick", ""), "l": ("heldStick", "dark"),
    "p": ("heldSucker", "dark"), "j": ("heldSucker", ""), "n": ("heldSucker", "light"),
    "S": ("headStick", ""),
    "P": ("headSucker", "dark"), "J": ("headSucker", ""), "N": ("headSucker", "light"),
}

# overlay strength per (region, shade), tuned to the source image's shades
SHADE_OPS = {
    ("suit", "dark"): ("000", ".12"),
    ("suit", "darker"): ("000", ".4"),
    ("suit", "light"): ("fff", ".04"),
    ("boots", "dark"): ("000", ".28"),
    ("heldStick", "dark"): ("000", ".2"),
    ("heldSucker", "dark"): ("000", ".1"),
    ("heldSucker", "light"): ("fff", ".08"),
    ("headSucker", "dark"): ("000", ".1"),
    ("headSucker", "light"): ("fff", ".08"),
}


def collect(grid):
    """regions[region] = pixel list; overlays[region] = {(color, op): pixels}."""
    regions, overlays = {}, {}
    for y, row in enumerate(grid):
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            region, shade = SYMBOLS[ch]
            regions.setdefault(region, []).append((x, y))
            if (region, shade) in SHADE_OPS:
                key = SHADE_OPS[(region, shade)]
                overlays.setdefault(region, {}).setdefault(key, []).append((x, y))
    return regions, overlays


def to_path(pixels):
    """Merge pixels into horizontal runs, then vertically, and emit one path d."""
    pixels = set(pixels)
    runs = []  # (x, y, w)
    for x, y in sorted(pixels, key=lambda p: (p[1], p[0])):
        if runs and runs[-1][1] == y and runs[-1][0] + runs[-1][2] == x:
            runs[-1][2] += 1
        else:
            runs.append([x, y, 1])
    merged = []  # (x, y, w, h) - vertical merge of identical runs
    for x, y, w in runs:
        for m in merged:
            if m[0] == x and m[2] == w and m[1] + m[3] == y:
                m[3] += 1
                break
        else:
            merged.append([x, y, w, 1])
    return "".join(
        f"M{x} {y}h{w}v{h}h-{w}z"
        for x, y, w, h in sorted(merged, key=lambda m: (m[1], m[0]))
    )


HEADER = (
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {N} {N}" '
    'shape-rendering="crispEdges">'
)


def overlay_paths(overlays, region_names):
    combined = {}
    for r in region_names:
        for key, px in overlays.get(r, {}).items():
            combined.setdefault(key, []).extend(px)
    return "".join(
        f'<path fill="#{col}" opacity="{op}" d="{to_path(px)}"/>'
        for (col, op), px in sorted(combined.items())
    )


def segments(colors):
    """Three self-contained drawing segments; the plunger ones are the
    presence slots and can be omitted without visual leftovers."""
    body_regions, body_overlays = collect(BODY_GRID)
    head_regions, head_overlays = collect(HEAD_GRID)
    body = (
        f'<path fill="#{colors["suit"]}" d="{to_path(body_regions["suit"])}"/>'
        f'<path fill="#{colors["boots"]}" d="{to_path(body_regions["boots"])}"/>'
        + "".join(
            f'<path fill="#{FIXED[n]}" d="{to_path(body_regions[n])}"/>'
            for n in ["skinDark", "skin", "skinLight", "mouth", "belt", "eye"]
        )
        + overlay_paths(body_overlays, ["suit", "boots"])
    )
    head = (
        f'<path fill="#{colors["headStick"]}" d="{to_path(head_regions["headStick"])}"/>'
        f'<path fill="#{colors["headSucker"]}" d="{to_path(head_regions["headSucker"])}"/>'
        + overlay_paths(head_overlays, ["headStick", "headSucker"])
    )
    held = (
        f'<path fill="#{colors["heldStick"]}" d="{to_path(body_regions["heldStick"])}"/>'
        f'<path fill="#{colors["heldSucker"]}" d="{to_path(body_regions["heldSucker"])}"/>'
        + overlay_paths(body_overlays, ["heldStick", "heldSucker"])
    )
    return head, held, body


def build(colors, head=True, held=True, comments=True):
    seg_head, seg_held, seg_body = segments(colors)
    parts = [HEADER]
    if comments:
        parts.append("<!-- BACKGROUND (fixed) -->")
    parts.append(f'<rect width="{N}" height="{N}" fill="#{FIXED["bg"]}"/>')
    if comments:
        parts.append("<!-- BODY: suit + boots color slots, then fixed frog "
                     "skin/eye/mouth/belt + shading (ears show at row 6) -->")
    parts.append(seg_body)
    if head:
        if comments:
            parts.append("<!-- HEAD PLUNGER (presence slot): stick he hangs from + "
                         "sucker on head; painted over the ears -->")
        parts.append(seg_head)
    if held:
        if comments:
            parts.append("<!-- HELD PLUNGER (presence slot): handle in his hand + its sucker -->")
        parts.append(seg_held)
    parts.append("</svg>")
    return ("\n" if comments else "").join(parts)


if __name__ == "__main__":
    import pathlib

    root = pathlib.Path(__file__).resolve().parent.parent
    (root / "art").mkdir(exist_ok=True)

    (root / "art" / "plumber.svg").write_text(build(DEFAULTS) + "\n")
    (root / "art" / "plumber-head-only.svg").write_text(build(DEFAULTS, held=False) + "\n")
    (root / "art" / "plumber-hand-only.svg").write_text(build(DEFAULTS, head=False) + "\n")
    (root / "art" / "plumber-plungerless.svg").write_text(
        build(DEFAULTS, head=False, held=False) + "\n"
    )
    match = dict(DEFAULTS, headSucker="e0a422", heldSucker="e0a422",
                 headStick="1f8a8a", heldStick="1f8a8a", suit="7a3fa8", boots="23233a")
    (root / "art" / "plumber-perfect-match-example.svg").write_text(build(match) + "\n")

    # Solidity string constants: template segments with one slot color each
    ph = {s: f"@{s}@" for s in DEFAULTS}
    seg_head, seg_held, seg_body = segments(ph)
    print("// --- Solidity constants (generated by scripts/build_svg.py) ---")
    print(f"// SVG_START:\n'{HEADER}<rect width=\"{N}\" height=\"{N}\" fill=\"#{FIXED['bg']}\"/>'")
    for name, seg in (("BODY", seg_body), ("HEAD", seg_head), ("HELD", seg_held)):
        print(f"// {name} segment, split at color slots:")
        for part in re.split(r"@(\w+)@", seg):
            print(f"  '{part}'" if part not in DEFAULTS else f"  <color: {part}>")
    print(f"\n// minified size, all segments: {len(build(DEFAULTS, comments=False))} bytes")
