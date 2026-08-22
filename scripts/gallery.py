#!/usr/bin/env python3
"""Generate art/gallery.html - a local preview of simulated mints.

Mimics ArtPlumberRenderer.traitsOf exactly: 7 seed nibbles -> 6 palette
colors + plunger presence, so what you see here is what the contract mints.
"""
import random
import pathlib
from build_svg import build, DEFAULTS

PALETTE = [
    ("Clay", "c0744a"), ("Ash Brown", "3e3429"), ("Workwear Blue", "383982"),
    ("Coal", "2e2423"), ("Fire Red", "b3282d"), ("Gold", "e0a422"),
    ("Pine", "2e7d4f"), ("Teal", "1f8a8a"), ("Purple", "7a3fa8"),
    ("Pink", "d1568e"), ("Sky", "4f8fdd"), ("Moss", "8a9a5b"),
    ("Bone", "e8e4d8"), ("Walnut", "5b3a24"), ("Safety Orange", "ff7f11"),
    ("Midnight", "23233a"),
]


def traits_of(seed):
    n = [(seed >> (4 * i)) & 0xF for i in range(7)]
    p = n[6]
    return {
        "headSucker": n[0], "heldSucker": n[1],
        "headStick": n[2], "heldStick": n[3],
        "suit": n[4], "boots": n[5],
        "head": p <= 11,
        "held": p <= 8 or 12 <= p <= 14,
    }


def card(title, svg, lines, badges):
    badge_html = "".join(f'<span class="badge">{b}</span>' for b in badges)
    info = "<br>".join(lines)
    return (
        f'<div class="card"><div class="art">{svg}</div>'
        f'<h3>{title}</h3><div class="badges">{badge_html}</div>'
        f'<p>{info}</p></div>'
    )


def roll_card(i, seed):
    t = traits_of(seed)
    colors = {k: PALETTE[t[k]][1] for k in DEFAULTS}
    svg = build(colors, head=t["head"], held=t["held"], comments=False)
    loadout = ("Double" if t["head"] and t["held"] else
               "Head Only" if t["head"] else
               "Hand Only" if t["held"] else "None")
    suckers = t["head"] and t["held"] and t["headSucker"] == t["heldSucker"]
    sticks = t["head"] and t["held"] and t["headStick"] == t["heldStick"]
    uniform = t["suit"] == t["boots"]
    badges = [f"Plungers: {loadout}"]
    if suckers:
        badges.append("SUCKERS MATCH")
    if sticks:
        badges.append("STICKS MATCH")
    if uniform:
        badges.append("UNIFORM MATCH")
    if suckers and sticks:
        badges.append("★ PERFECT PLUMBER")
    lines = []
    if t["head"]:
        lines.append(f"head sucker {PALETTE[t['headSucker']][0]} · stick {PALETTE[t['headStick']][0]}")
    if t["held"]:
        lines.append(f"held sucker {PALETTE[t['heldSucker']][0]} · stick {PALETTE[t['heldStick']][0]}")
    lines.append(f"suit {PALETTE[t['suit']][0]} · boots {PALETTE[t['boots']][0]}")
    return card(f"Art Plumber #{i}", svg, lines, badges)


CSS = """
body{background:#111;color:#ddd;font-family:ui-monospace,Menlo,monospace;margin:24px}
h1{font-weight:600} h2{margin-top:40px;color:#aaa;font-weight:500}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:16px}
.card{background:#1a1a1a;border:1px solid #2a2a2a;border-radius:10px;padding:12px;text-align:center}
.card svg{width:100%;height:auto;image-rendering:pixelated;border-radius:6px}
.card h3{margin:10px 0 6px;font-size:14px;color:#fff}
.card p{font-size:11px;color:#888;line-height:1.6;margin:6px 0 0}
.badges{min-height:20px}
.badge{display:inline-block;font-size:10px;background:#26263a;color:#9ad;border-radius:99px;padding:2px 8px;margin:2px}
.badge:first-child{background:#222;color:#999}
"""

if __name__ == "__main__":
    rng = random.Random(1)  # fixed so the gallery is reproducible
    root = pathlib.Path(__file__).resolve().parent.parent

    showcase = [
        ("The Original Frog (OG colors, double plunger)", DEFAULTS, True, True),
        ("Head Plunger Only (sucker covers the ears)", DEFAULTS, True, False),
        ("Hand Plunger Only (ears out)", DEFAULTS, False, True),
        ("Plungerless (ears out, rarest loadout 1/16)", DEFAULTS, False, False),
        ("Perfect Plumber example (suckers + sticks match)",
         dict(DEFAULTS, headSucker="e0a422", heldSucker="e0a422",
              headStick="1f8a8a", heldStick="1f8a8a", suit="7a3fa8", boots="23233a"),
         True, True),
    ]
    cards = [card(t, build(c, head=h, held=d, comments=False), [], [])
             for t, c, h, d in showcase]
    rolls = [roll_card(i + 1, rng.getrandbits(28)) for i in range(48)]

    html = (
        "<!doctype html><meta charset='utf-8'><title>Art Plumber gallery</title>"
        f"<style>{CSS}</style>"
        "<h1>Art Plumber &mdash; on-chain color match hunt</h1>"
        "<h2>Showcase</h2><div class='grid'>" + "".join(cards) + "</div>"
        "<h2>48 simulated mints (same rules the contract uses)</h2>"
        "<div class='grid'>" + "".join(rolls) + "</div>"
    )
    out = root / "art" / "gallery.html"
    out.write_text(html)
    print(f"wrote {out}")
