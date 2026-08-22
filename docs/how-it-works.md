# How a token's look is determined

Everything about an Art Plumber — every color and which plungers appear —
comes from a single 32-byte **seed** locked at mint. Nothing else feeds the
art: no metadata server, no reveal step, no admin function. Same seed,
same frog, forever.

## 1. The seed

Minting runs (in `ArtPlumber.mint()`):

```solidity
seedOf[id] = keccak256(abi.encodePacked(block.prevrandao, msg.sender, id));
```

- `block.prevrandao` — a per-block value from the chain. On Ethereum L1
  it changes every block; on Arbitrum-lineage L2s (including Robinhood
  Chain) it is a **constant**, so there the seed is effectively
  `keccak256(minter, tokenId)`.
- `msg.sender` — two people minting in the same block get different rolls.
- `id` — one wallet minting twice in the same block gets different rolls.

All three ingredients are public, so the roll is **predictable to anyone
willing to do the work**: on L1 you can simulate your mint each block and
only submit on a good roll; on constant-`prevrandao` L2s you can
precompute which future token ids give your address a match and race to
mint on exactly that id. This is intentional — the hunt rewards hunters
who read the contract and win the timing race, and everyone has access
to the same math. See "How randomness is determined" in the README.

The seed is stored once and can never change. Anyone can read it:

```sh
cast call <addr> "seedOf(uint256)(bytes32)" 42
```

## 2. Reading the seed: nibbles

The renderer (`ArtPlumberRenderer.traitsOf`) reads the **seven lowest
nibbles** of the seed. A nibble is 4 bits, i.e. one hex character, and
holds a value 0–15. Nibble 0 is the *lowest* 4 bits — which means it is
the **rightmost hex character** of the seed. So if your seed ends in

```
0x…????????? 9 A 6 4 0 7 5
   nibble:   6 5 4 3 2 1 0
```

you can read your whole frog straight off the last seven hex characters,
right to left:

| Nibble | Read from seed | Slot | Determines |
|---|---|---|---|
| 0 | last hex char | `headSucker` | color of the plunger **sucker on his head** (covers his ears) |
| 1 | 2nd from last | `heldSucker` | color of the **sucker** of the plunger in his hand |
| 2 | 3rd from last | `headStick` | color of the **stick he hangs from** |
| 3 | 4th from last | `heldStick` | color of the **other stick** (held plunger's handle) |
| 4 | 5th from last | `suit` | color of his **work suit** |
| 5 | 6th from last | `boots` | color of his **boots** |
| 6 | 7th from last | plunger presence | **which plungers appear** (section 4) |

## 3. How color is determined

Each color nibble is used directly as an index into the **shared 16-color
palette** (`ArtPlumberRenderer.PALETTE`, 3 bytes of RGB per entry):

| Index | Name | Hex | Index | Name | Hex |
|---|---|---|---|---|---|
| 0 | Clay | `#c0744a` | 8 | Purple | `#7a3fa8` |
| 1 | Ash Brown | `#3e3429` | 9 | Pink | `#d1568e` |
| 2 | Workwear Blue | `#383982` | 10 | Sky | `#4f8fdd` |
| 3 | Coal | `#2e2423` | 11 | Moss | `#8a9a5b` |
| 4 | Fire Red | `#b3282d` | 12 | Bone | `#e8e4d8` |
| 5 | Gold | `#e0a422` | 13 | Walnut | `#5b3a24` |
| 6 | Pine | `#2e7d4f` | 14 | Safety Orange | `#ff7f11` |
| 7 | Teal | `#1f8a8a` | 15 | Midnight | `#23233a` |

In the SVG, each slot is painted as **one flat fill color**
(`<path fill="#e0a422" d="…"/>`). Shading is not part of the color:
fixed translucent black/white pixels are layered on top (suit folds at
12% black, the zipper at 40% black, sucker highlights at 8% white, …),
so every palette color keeps the same pixel-art depth.

Because all six slots index the **same** palette, two slots can roll the
same index. Colors are compared by index, and equality is what the hunt
is about:

| Trait | Condition (indices) | Odds |
|---|---|---|
| Suckers Match | `headSucker == heldSucker` *and both shown* | 9/256 ≈ 3.5% |
| Sticks Match | `headStick == heldStick` *and both shown* | 9/256 ≈ 3.5% |
| Uniform Match | `suit == boots` | 1/16 = 6.25% |
| Perfect Plumber | Suckers Match AND Sticks Match | 9/4096 ≈ 0.22% |

These flags are computed in `suckersMatch` / `sticksMatch` /
`uniformMatch` / `perfectPlumber` and exposed on-chain via
`ArtPlumber.matchesOf(tokenId)`.

### What is NOT determined by the seed

Fixed for every token, hardcoded in the SVG template: the frog's three
skin greens (`#58883f`, `#639847`, `#6ba34e`), the black eye, the mouth
(`#a3663b`), the belt (`#3b2d2d`), and the black background.

## 4. How appearance (presence) is determined

Nibble 6 decides the **plunger loadout**:

| Nibble 6 value | Plungers trait | Odds |
|---|---|---|
| 0–8 | Double — head + hand | 9/16 = 56.25% |
| 9–11 | Head Only | 3/16 = 18.75% |
| 12–14 | Hand Only | 3/16 = 18.75% |
| 15 | None — plungerless | 1/16 = 6.25% |

The SVG is assembled from three **self-contained segments**, in this
order:

1. **Body** — always drawn: suit, boots, frog skin (including the ear
   bumps on top of the head), eye, mouth, belt, and the body's shading.
2. **Head plunger** — only if present: the stick he hangs from + the
   sucker, with their own shading. Painted *after* the body, the sucker
   sits over the ear row — so **plunger on = ears covered, plunger off =
   ears out**.
3. **Held plunger** — only if present: handle + sucker (his green hand
   grips the handle either way; without the plunger it's a raised fist).

Each segment carries its own shading overlays, so skipping a segment
leaves zero stray pixels.

Presence also gates the metadata and the hunt:

- Color traits of an absent plunger are **omitted** from `tokenURI`
  (the colors are still rolled in the seed, they're just not on the art).
- Sucker/stick matches require **both** parts visible, so a Perfect
  Plumber is always a Double.

## 5. Worked example

Say token 7's seed ends in `…9a64075`:

| Nibble | Value | Meaning |
|---|---|---|
| 0 | `5` | head sucker: Gold |
| 1 | `7` | held sucker: Teal |
| 2 | `0` | head stick: Clay |
| 3 | `4` | held stick: Fire Red |
| 4 | `6` | suit: Pine |
| 5 | `a` (10) | boots: Sky |
| 6 | `9` | plungers: **Head Only** |

Result: a Pine-suited frog with Sky boots hanging from a Clay stick by a
Gold sucker (ears covered), right fist raised and empty. The Teal/Fire
Red held-plunger colors were rolled but aren't shown and don't appear in
the metadata — and no sucker/stick match is possible on this token since
only one plunger is visible. No match traits fire (`suit` 6 ≠ `boots` 10).

## 6. Verifying it yourself

```sh
# the seed
cast call <addr> "seedOf(uint256)(bytes32)" <id>

# decoded traits (palette indices + presence booleans)
cast call <addr> "traitsOf(uint256)((uint8,uint8,uint8,uint8,uint8,uint8,bool,bool))" <id>

# match flags: (suckers, sticks, uniform, perfect)
cast call <addr> "matchesOf(uint256)(bool,bool,bool,bool)" <id>

# the raw SVG, straight from the chain
cast call <addr> "svgOf(uint256)(string)" <id>
```

Code pointers: seed → traits in `ArtPlumberRenderer.traitsOf`,
traits → SVG in `ArtPlumberRenderer.svg`, traits → metadata JSON in
`ArtPlumberRenderer.tokenURI`.
