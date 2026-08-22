#!/usr/bin/env python3
"""Build the Art Plumber SVG (and Solidity string constants) from the 32x32 pixel grid.

The grid below was extracted pixel-for-pixel from the source image
(2026-08-21 16.31.14.jpg, 1280x1280 = 32x32 cells of 40px).

Regions / color slots (the on-chain "color match hunt" traits):
  headStick   - the plunger stick he hangs from
  headSucker  - the plunger sucker stuck on his head
  heldStick   - the stick of the plunger he is holding
  heldSucker  - the sucker of the plunger he is holding
  suit        - the work suit
  boots       - the boots

Presence slots: the head plunger and the held plunger can each be absent.
The SVG is therefore built from three self-contained segments (head plunger,
held plunger, body), each carrying its own shading overlays, so a segment
can be dropped without leaving stray shading pixels.

Fixed (not part of the hunt): skin, face (eye/mouth), belt, background.

Shading is applied as translucent black/white overlay pixels so every slot
can be recolored with a single flat color and keep its pixel-art shading.
"""

# Symbols: . bg | b stick/belt | c/d/e sucker light/dark/mid | f/g/h skin dark/mid/light
#          i/j/k suit dark/mid/zipper | l/m boot dark/mid | E eye | M mouth
GRID = [
    "................................",  # 0
    "................................",  # 1
    "...............b................",  # 2
    "...............b................",  # 3
    "...............b................",  # 4
    "...............b................",  # 5
    "...............b................",  # 6
    "...............b................",  # 7
    "...............b................",  # 8
    "...............b................",  # 9
    "...............b................",  # 10
    "...............c................",  # 11
    "..............dec...............",  # 12
    ".............deeec..............",  # 13
    ".............fgggh..............",  # 14
    ".............fgggh..............",  # 15
    "............fgEgg...deeec.......",  # 16
    "............fggggh...dec........",  # 17
    ".............fgMMh....c.........",  # 18
    "..............fgh.....b.........",  # 19
    ".............ijkjj....b.........",  # 20
    "...........iijjkjjjj..b.........",  # 21
    "..........ijjjjkjjjjjjg.........",  # 22
    "..........ijijjkjjjjjjg.........",  # 23
    "..........ijijjkjjj...b.........",  # 24
    "..........ijbbbbbbb...b.........",  # 25
    "..........ggijjjjjj...b.........",  # 26
    "............ijjijjj...b.........",  # 27
    "............ijj.ijj.............",  # 28
    "............ij..ij..............",  # 29
    "............ll..ll..............",  # 30
    "............mmm.mmm.............",  # 31
]

# Default palette = the original artwork's colors
DEFAULTS = {
    "headStick": "3e3429",
    "headSucker": "c0744a",
    "heldStick": "3e3429",
    "heldSucker": "c0744a",
    "suit": "383982",
    "boots": "2e2423",
}
FIXED = {
    "skinDark": "d8b18a",
    "skin": "eec399",
    "skinLight": "fcd1a7",
    "belt": "3e3429",
    "face": "000000",
    "bg": "000000",
}


def classify(x, y, ch):
    """Map a grid symbol at (x, y) to (region, shade). shade: '' | 'dark' | 'darker' | 'light'."""
    if ch == ".":
        return None
    if ch == "b":
        # the belt row also contains the held stick passing it at x=22
        if y == 25 and x <= 18:
            return ("belt", "")
        return ("headStick", "") if x == 15 else ("heldStick", "")
    if ch in "cde":
        region = "headSucker" if y <= 13 else "heldSucker"
        return (region, {"c": "light", "d": "dark", "e": ""}[ch])
    if ch == "f":
        return ("skinDark", "")
    if ch == "g":
        return ("skin", "")
    if ch == "h":
        return ("skinLight", "")
    if ch in "ijk":
        return ("suit", {"i": "dark", "j": "", "k": "darker"}[ch])
    if ch == "l":
        return ("boots", "dark")
    if ch == "m":
        return ("boots", "")
    if ch in "EM":
        return ("face", "")
    raise ValueError(ch)


def collect():
    """regions[region] = pixel list; overlays[region] = {(color, opacity): pixels}."""
    regions = {}
    overlays = {}
    # overlay strength per (region, shade) tuned to reproduce the original shades
    dark_op = {
        ("headSucker", "dark"): ".1", ("heldSucker", "dark"): ".1",
        ("suit", "dark"): ".12", ("suit", "darker"): ".4",
        ("boots", "dark"): ".28",
    }
    for y, row in enumerate(GRID):
        for x, ch in enumerate(row):
            c = classify(x, y, ch)
            if not c:
                continue
            region, shade = c
            regions.setdefault(region, []).append((x, y))
            if shade in ("dark", "darker"):
                key = ("000", dark_op[(region, shade)])
            elif shade == "light":
                key = ("fff", ".08")
            else:
                continue
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
    # vertical merge: same x and w, consecutive y
    merged = []  # (x, y, w, h)
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
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" '
    'shape-rendering="crispEdges">'
)


def overlay_paths(overlays, region_names):
    """Combined translucent shading paths for a group of regions."""
    combined = {}
    for r in region_names:
        for key, px in overlays.get(r, {}).items():
            combined.setdefault(key, []).extend(px)
    return "".join(
        f'<path fill="#{col}" opacity="{op}" d="{to_path(px)}"/>'
        for (col, op), px in sorted(combined.items())
    )


def segments(colors):
    """The three self-contained drawing segments. Each can be independently
    included/omitted (that is the presence trait) without visual leftovers."""
    regions, overlays = collect()
    head = (
        f'<path fill="#{colors["headStick"]}" d="{to_path(regions["headStick"])}"/>'
        f'<path fill="#{colors["headSucker"]}" d="{to_path(regions["headSucker"])}"/>'
        + overlay_paths(overlays, ["headStick", "headSucker"])
    )
    held = (
        f'<path fill="#{colors["heldStick"]}" d="{to_path(regions["heldStick"])}"/>'
        f'<path fill="#{colors["heldSucker"]}" d="{to_path(regions["heldSucker"])}"/>'
        + overlay_paths(overlays, ["heldStick", "heldSucker"])
    )
    body = (
        f'<path fill="#{colors["suit"]}" d="{to_path(regions["suit"])}"/>'
        f'<path fill="#{colors["boots"]}" d="{to_path(regions["boots"])}"/>'
        + "".join(
            f'<path fill="#{FIXED[n]}" d="{to_path(regions[n])}"/>'
            for n in ["skinDark", "skin", "skinLight", "belt", "face"]
        )
        + overlay_paths(overlays, ["suit", "boots"])
    )
    return head, held, body


def build(colors, head=True, held=True, comments=True):
    seg_head, seg_held, seg_body = segments(colors)
    parts = [HEADER]
    if comments:
        parts.append("<!-- BACKGROUND (fixed) -->")
    parts.append(f'<rect width="32" height="32" fill="#{FIXED["bg"]}"/>')
    if comments:
        parts.append("<!-- BODY: suit + boots color slots, then fixed skin/face/belt + shading -->")
    parts.append(seg_body)
    if head:
        if comments:
            parts.append("<!-- HEAD PLUNGER (presence slot): stick he hangs from + sucker on head -->")
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

    # previews: original colors in all presence variants, plus a match example
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
    print(f"// SVG_START:\n'{HEADER}<rect width=\"32\" height=\"32\" fill=\"#{FIXED['bg']}\"/>'")
    for name, seg in (("HEAD", seg_head), ("HELD", seg_held), ("BODY", seg_body)):
        print(f"// {name} segment, split at color slots:")
        import re
        for part in re.split(r"@(\w+)@", seg):
            print(f"  '{part}'" if not part.isidentifier() or part not in DEFAULTS
                  else f"  <color: {part}>")
    print(f"\n// minified size, all segments: {len(build(DEFAULTS, comments=False))} bytes")
