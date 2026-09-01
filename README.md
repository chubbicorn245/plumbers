# Art Plumber

A fully on-chain pixel-art NFT: a little frog plumber who hangs from one
plunger and holds another. No IPFS, no servers — the ERC-721 contract itself
generates the SVG and the metadata JSON, so the art lives as long as the
chain does.

| Original | Head only | Hand only | Plungerless | Perfect match |
|---|---|---|---|---|
| ![](art/plumber.svg) | ![](art/plumber-head-only.svg) | ![](art/plumber-hand-only.svg) | ![](art/plumber-plungerless.svg) | ![](art/plumber-perfect-match-example.svg) |

## The base character

**The frog is the base.** Every token is this exact same frog — same
pose, same pixels — re-dressed by its mint seed: only the six slot colors
and the plunger loadout vary. `art/plumber.svg` ("Original" above) shows
the base in OG colors, which are palette indices 0–3: Clay suckers,
Ash Brown sticks, Workwear Blue suit, Coal boots, Double plunger. The
frog's skin greens, eye, mouth, and belt are part of the base and never
change. The base pixel grids live in `scripts/build_svg.py`
(`BODY_GRID` + `HEAD_GRID`); to change the base art, edit those grids,
run the script, and copy the printed constants into
`ArtPlumberRenderer.sol`. (A v1 human plumber preceded the frog and
exists only in git history.)

## The on-chain color match hunt

Every mint locks a random seed. That seed — and nothing else — decides the
token's look. **The full derivation — seed → nibbles → palette → SVG,
plunger presence, and how to verify it with `cast` — is documented in
[docs/how-it-works.md](docs/how-it-works.md).** The short version: seven
nibbles (4-bit values) of the seed are read:

| Seed nibble | Slot | What it determines |
|---|---|---|
| 0 | `headSucker` | color of the plunger **sucker** stuck on his head (covers his ears) |
| 1 | `heldSucker` | color of the **sucker** of the plunger he is holding |
| 2 | `headStick` | color of the plunger **stick** he hangs from |
| 3 | `heldStick` | color of the **other stick** (the held plunger's handle) |
| 4 | `suit` | color of his work suit |
| 5 | `boots` | color of his boots |
| 6 | plunger presence | which plungers appear (see below) |

All six color slots draw from the **same 16-color palette**, so any two
slots can roll the same color — that's a **match**, and matches are what
collectors hunt for:

| Trait | Condition | Odds |
|---|---|---|
| Suckers Match | both suckers on the art, same color | ~3.5% |
| Sticks Match | both sticks on the art, same color | ~3.5% |
| Uniform Match | suit == boots | 6.25% |
| **Perfect Plumber** | Double Plunger + Suckers Match + Sticks Match | ~0.22% (1 in 455) |

Matches are also readable on-chain via `matchesOf(tokenId)`, so games,
reward contracts, or burns can verify a hunter's pull trustlessly.

### Plunger presence (nibble 6)

Each plunger is itself a trait slot — sometimes it appears, sometimes it
doesn't:

| Roll (0–15) | Plungers trait | Odds |
|---|---|---|
| 0–8 | Double (head + hand) | 56.25% |
| 9–11 | Head Only | 18.75% |
| 12–14 | Hand Only | 18.75% |
| 15 | None (plungerless) | 6.25% |

Color traits of an absent plunger are omitted from the metadata, and sucker/
stick matches only count when both parts are actually on the art — so a
Perfect Plumber is always a Double. When the head plunger is present its
sucker covers the frog's ear bumps; otherwise the ears show.

### How randomness is determined (and why the hunt rewards skill)

There is no oracle and no off-chain randomness. The seed is computed
on-chain at mint, from three public ingredients:

```solidity
seedOf[id] = keccak256(abi.encodePacked(block.prevrandao, msg.sender, id));
```

- `block.prevrandao` — a value the chain exposes each block,
- `msg.sender` — the minter's address,
- `id` — the sequential token id being minted.

This is **not casino-grade randomness, by design**. Everything that goes
into the seed is public, so a skilled hunter can compute rolls before
minting:

- On Ethereum L1, `prevrandao` is fixed once the block is being built, so
  a hunter can simulate their mint each block and only send the
  transaction when the roll is good.
- On Arbitrum-lineage L2s (including Robinhood Chain), `prevrandao` is a
  constant — the seed reduces to `keccak256(you, tokenId)`. That means
  you can precompute, for your own address, **which future token ids roll
  matches**, then watch `totalSupply` and race to land your mint on
  exactly that id.

We consider that the game: the casual minter gets a surprise pull; the
hunter who reads the contract, precomputes their ids, and wins the timing
race earns their Perfect Plumber. Skill is rewarded, and nothing is
hidden — everyone has access to the same math. (If a future drop ever
needs snipe-proof odds instead, the fix is a commit-reveal mint or a VRF;
`ArtPlumber.mint()` is the only function that would change.)

### The palette

| # | Name | Hex | | # | Name | Hex |
|---|---|---|---|---|---|---|
| 0 | Clay | `#c0744a` | | 8 | Purple | `#7a3fa8` |
| 1 | Ash Brown | `#3e3429` | | 9 | Pink | `#d1568e` |
| 2 | Workwear Blue | `#383982` | | 10 | Sky | `#4f8fdd` |
| 3 | Coal | `#2e2423` | | 11 | Moss | `#8a9a5b` |
| 4 | Fire Red | `#b3282d` | | 12 | Bone | `#e8e4d8` |
| 5 | Gold | `#e0a422` | | 13 | Walnut | `#5b3a24` |
| 6 | Pine | `#2e7d4f` | | 14 | Safety Orange | `#ff7f11` |
| 7 | Teal | `#1f8a8a` | | 15 | Midnight | `#23233a` |

Indices 0–3 are the original artwork's colors, so the OG combo is mintable.
Skin, face, belt and background are fixed and not part of the hunt.

## How the art stays small on-chain

- 24×24 grid extracted cell-for-cell from the source image
  (`scripts/extract_grid.py`).
- Pixels are merged into runs and drawn as `<path>` subpaths
  (`M11 0h1v4h-1z`), not one rect per pixel — the full SVG is ~1.7 KB.
- Each recolorable part is one flat `fill`; shading is layered on top as
  fixed translucent black/white pixels, so any palette color keeps the
  original pixel-art depth.
- The SVG is three self-contained segments (body, head plunger, held
  plunger), each carrying its own shading, so absent plungers leave no
  stray pixels.

## Repo layout

```
src/ArtPlumberRenderer.sol  seed -> traits -> SVG -> tokenURI (all pure, no deps)
src/ArtPlumber.sol          ERC-721 + mint + seed storage (self-contained, no deps)
test/ArtPlumber.t.sol       foundry tests (no forge-std needed)
scripts/extract_grid.py     pixel-grid extractor for new source images
scripts/build_svg.py        regenerates the SVG segments from the pixel grid
scripts/gallery.py          builds art/gallery.html with simulated mints
art/*.svg                   previews of the variants
```

## Mint price and the OG free mint

The collection is **2000** plumbers, and **anyone can mint**. What the
eligibility check buys you is a discount, not entry:

| Wallet | Free tokens | Every token after that | Total it may mint |
|---|---|---|---|
| **OG** (mainnet tx before Nov 2021) | 2 | 0.003 ETH | unlimited |
| **Everyone else** | 0 | 0.003 ETH | unlimited |

**There is no per-wallet cap.** One wallet may mint as much of the 2000
as it likes; the free two are the only per-wallet limit in the contract.
`MAX_PER_TX` (20) bounds a single `mint()` call — minting is a loop, and
an unbounded quantity would exceed the block gas limit — so larger hauls
just take more transactions.

Free tokens are always spent first, so a single call can be part free
and part paid: an OG minting 5 at once sends `3 * MINT_PRICE`.

`msg.value` must match **exactly**, so quote it from the contract rather
than computing it in the frontend:

```solidity
priceFor(address wallet, uint256 quantity, bytes signature) -> uint256
```

`freeMintedBy(wallet)` reports how much of the 2-token free allowance a
wallet has used. It is tracked separately from `mintedBy`, so a wallet
that paid before it had a voucher can still claim its free tokens later.

### Proving OG status

A contract can't read mainnet history (least of all from another chain),
so the check happens off-chain and is attested with a signed voucher.
**The full mechanism — what gets signed, how the contract verifies it,
the security properties, and the trust model — is documented in
[docs/voucher-eligibility.md](docs/voucher-eligibility.md).** The short
version:

1. **Check:** a wallet qualifies iff its nonce at mainnet block
   `13527858` — the last block before 2021-11-01 00:00 UTC — is nonzero.
   One `eth_getTransactionCount` call against an archive-capable RPC.
2. **Sign:** a backend holding the `signer` key signs an EIP-712 voucher
   (domain `{name: "Art Plumber", version: "1", chainId, contract}`,
   message `MintVoucher(address wallet)`). `voucherDigest(wallet)` on the
   contract returns the exact digest; standard `signTypedData` matches it.
3. **Mint:** `mint(quantity, signature)` takes 1-20 tokens and verifies
   the voucher with `ecrecover` (no new dependencies). The voucher is
   bound to one wallet, this chain, and this contract — it can't be
   borrowed or replayed — and stays reusable by its wallet until the free
   allowance is gone. **An absent or invalid voucher is not an error:**
   it simply earns no discount, and the wallet pays full price for every
   token.

The `signer` and `payout` addresses are immutable constructor arguments:
no owner, no rotation. `withdraw()` is callable by anyone but only ever
sends the proceeds to `payout`. If the signer key is compromised or lost
the contract must be redeployed, so keep it in a secret manager.

## Build, test, deploy

```sh
forge build
forge test

# local dry run (sign a voucher for the minter, then mint with it)
anvil &
forge create src/ArtPlumber.sol:ArtPlumber --private-key <deploy-key> --broadcast \
  --constructor-args <signer-address> <payout-address>

# OG wallet, 3 tokens: 2 free + 1 paid = 0.003 ETH
cast send <addr> "mint(uint256,bytes)" 3 <voucher-signature> \
  --value 0.003ether --private-key <minter-key>

# no voucher, 3 tokens: full price = 0.009 ETH
cast send <addr> "mint(uint256,bytes)" 3 0x --value 0.009ether \
  --private-key <minter-key>

cast call <addr> "tokenURI(uint256)(string)" 1
```

Both contracts are dependency-free, so you can also paste
`src/ArtPlumberRenderer.sol` + `src/ArtPlumber.sol` straight into Remix.

### Deploy to Robinhood Chain testnet

Robinhood Chain is an Arbitrum Orbit L2 with ETH as the gas token; the
testnet is standard Foundry territory:

```sh
# network
export RH_RPC_URL=https://rpc.testnet.chain.robinhood.com   # chain id 46630
# fund the deployer with testnet ETH first:
#   https://faucet.testnet.chain.robinhood.com

# one-time: generate the eligibility signer key; keep the private key in a
# secret manager (the backend signs vouchers with it, and it can't be rotated)
cast wallet new

export PRIVATE_KEY=<deployer key>
export SIGNER_ADDRESS=<address from cast wallet new>
export PAYOUT_ADDRESS=<where withdraw() sends mint proceeds>

forge create --rpc-url $RH_RPC_URL --private-key $PRIVATE_KEY --broadcast \
  src/ArtPlumber.sol:ArtPlumber --constructor-args $SIGNER_ADDRESS $PAYOUT_ADDRESS
```

Note: keep `--constructor-args` last — it swallows any flags placed after
it. Sanity-check the deployment before wiring anything to it:

```sh
cast call <addr> "signer()(address)" --rpc-url $RH_RPC_URL   # = SIGNER_ADDRESS
```

### Verify on the explorer

The explorer (`https://explorer.testnet.chain.robinhood.com`) is a
Blockscout instance — Robinhood Chain's Etherscan equivalent — and takes
standard Foundry verification:

```sh
forge verify-contract <addr> src/ArtPlumber.sol:ArtPlumber \
  --chain-id 46630 \
  --verifier blockscout \
  --verifier-url https://explorer.testnet.chain.robinhood.com/api/ \
  --constructor-args $(cast abi-encode "constructor(address,address)" $SIGNER_ADDRESS $PAYOUT_ADDRESS)
```

Once verified, the explorer shows the source, lets anyone read
`voucherDigest`/`matchesOf`/`tokenURI` directly, and renders the
Read/Write tabs. (Mainnet, when it's time, is the same flow with the
mainnet RPC/explorer URLs and chain id.)

### Export the ABI for the mint site

The website needs the ABI to call `mint(uint256,bytes)` (payable) and
the views with wagmi/viem — in particular `priceFor`, which gives the
exact `msg.value` for a wallet's next mint:

```sh
forge inspect ArtPlumber abi --json > artplumber-abi.json
```

For nice TypeScript inference, paste it into the site as a const:

```ts
// lib/abi/art-plumber.ts
export const artPlumberAbi = [ /* contents of artplumber-abi.json */ ] as const;
```

Regenerate after any contract change — wagmi's type inference only sees
what's in that file.

### Before a real deployment

Two of the constructor arguments are **immutable decisions** — get them
right once, there is no owner and no second chance short of redeploying:

- [ ] **Generate the eligibility signer key** (`cast wallet new`) and
      store the private key somewhere real (secret manager / deployment
      platform env, not a laptop `.env`) — it signs every voucher and
      can't be rotated.
- [ ] **Pick the payout address** — `withdraw()` can only ever send the
      mint proceeds there.
- [ ] **Confirm the constants** in `ArtPlumber.sol`: `MAX_SUPPLY` (2000),
      `MAX_PER_TX` (20 per call — a gas guard, not an allocation limit;
      there is no per-wallet cap at all), `FREE_ALLOWANCE` (2 free tokens
      per OG wallet), and `MINT_PRICE` (0.003 ETH per paid token). All
      four are permanent once deployed. Note that with no wallet cap a
      single buyer can take the entire supply — that is intended.
- [ ] **Testnet dry run** — the sections above walk the exact Robinhood
      testnet flow: faucet → deploy → verify on Blockscout → mint with a
      real voucher. Cheap insurance before anything real.

Also worth knowing:
- Marketplace compatibility: `tokenURI` returns the standard
  `data:application/json;base64,` URI with a base64 SVG image — the
  documented OpenSea on-chain metadata format (same pattern as
  Loot/Nouns), so the art renders there with no server.
- The mint seed uses `block.prevrandao + minter + id`. That's fine for a
  fun hunt, but it is influenceable by validators/sequencers — if real
  value rides on the odds, switch to commit-reveal or VRF.
- To change the art, edit the grid in `scripts/build_svg.py`, run it, and
  copy the printed segment constants into `ArtPlumberRenderer.sol`
  (tests will catch a mismatch in the slot geometry).
