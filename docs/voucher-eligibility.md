# How voucher eligibility works

Wallets that sent an Ethereum mainnet transaction before November 2021
mint their first two plumbers free; everyone else pays 0.003 ETH per
token. The voucher is what proves a wallet is in that first group — it
is a **discount, not a gate**, and minting without one is a normal
full-price mint, not an error. This document explains the whole
mechanism — why it's built this way, what exactly gets signed, how the
contract checks it, and what can and cannot be faked.

## Why a voucher at all

The EVM has no opcode for "list this address's transactions" or even
"what was this address's nonce last year" — a contract can only see
*current* state. And this contract doesn't deploy on Ethereum mainnet
anyway: from Robinhood Chain, mainnet state (current or historical) is
simply unreachable. So every activity-gated mint on any chain works from
off-chain data somehow. There are two honest ways to do it:

| | Merkle snapshot | Signed vouchers (this repo) |
|---|---|---|
| Eligibility computed | once, up front, for every wallet ever | on demand, per wallet that shows up |
| Off-chain artifact | a tree over tens of millions of addresses, hosted forever | a backend holding one signing key |
| On-chain cost | ~26 hashes + ~832 bytes proof calldata | one `ecrecover` (~3k gas) + 65 bytes |
| Trust anchor | the snapshot builder (auditable after the fact) | the signer key (trusted while minting is live) |

Vouchers were chosen for the on-the-fly property: no giant snapshot to
build, host, and serve proofs from.

## The eligibility rule, precisely

> A wallet is eligible **iff its nonce was greater than zero at Ethereum
> mainnet block 13,527,858.**

An account's nonce counts the transactions it has *sent*. Block
13,527,858 is the last mainnet block mined before 2021-11-01 00:00 UTC —
its timestamp is 23:59:20 Oct 31, and block 13,527,859's is 00:00:07
Nov 1 (both verifiable on any explorer). So "nonce > 0 at that block" is
exactly "sent at least one mainnet transaction before November 2021".

The check is one RPC call against an archive-capable node:

```sh
cast nonce <wallet> --block 13527858 --rpc-url <archive mainnet rpc>
```

Because it reads frozen history, the answer can never change — nothing
anyone does today can make a wallet retroactively eligible.

## What gets signed: the EIP-712 voucher

The backend signs a typed-data message ([EIP-712](https://eips.ethereum.org/EIPS/eip-712)),
not a bare hash. The structure:

```
Domain: {
  name:              "Art Plumber",
  version:           "1",
  chainId:           <the chain this contract is deployed on>,
  verifyingContract: <this contract's address>
}
Message: MintVoucher { wallet: <the eligible wallet> }
```

The digest the signer actually signs is
`keccak256("\x19\x01" ‖ domainSeparator ‖ keccak256(abi.encode(TYPEHASH, wallet)))`
— and the contract exposes it directly as `voucherDigest(wallet)`, so a
backend, a test, and the chain can never disagree about what a valid
voucher is. Any standard `signTypedData` implementation (viem, ethers)
produces a matching signature:

```ts
const signature = await account.signTypedData({
  domain: { name: "Art Plumber", version: "1", chainId, verifyingContract },
  types: { MintVoucher: [{ name: "wallet", type: "address" }] },
  primaryType: "MintVoucher",
  message: { wallet },
});
```

## How the contract verifies it

`mint(quantity, signature)` calls `_isValidVoucher(msg.sender, signature)`,
which is deliberately boring:

1. Signature must be exactly 65 bytes (`r ‖ s ‖ v`).
2. `s` must be in the lower half of the curve order (EIP-2) — rejects
   malleated variants of a valid signature.
3. `ecrecover(voucherDigest(msg.sender), v, r, s)` must return the
   immutable `signer` address (and not the zero address, which is what
   `ecrecover` returns for garbage).

No new dependencies — it's ~15 lines over the EVM's built-in `ecrecover`
precompile.

## Security properties

- **Unforgeable.** Producing a valid voucher without the signer key is
  breaking ECDSA/secp256k1.
- **Wallet-bound.** The wallet address is inside the signed message and
  is checked against `msg.sender` — a stolen voucher is useless to
  anyone but the wallet it names.
- **Replay-proof.** The domain pins chain id and contract address, so a
  voucher for one deployment verifies nowhere else — not on another
  chain, not on a redeploy, not on a copycat contract.
- **Reusable but bounded.** Vouchers aren't consumed; the same wallet
  can reuse one across mints. That's fine because `freeMintedBy` is
  enforced on-chain — a voucher stops earning discounts once the
  wallet's 2 free tokens are gone, and every token after that is full
  price. There is no per-wallet cap, so a voucher's entire power is
  those first two tokens.
- **Fails soft.** An absent, malformed, forged, or borrowed voucher does
  not revert the mint. `_freeAllotment` simply returns 0 and the wallet
  is quoted full price. Since `msg.value` must match the quote exactly,
  an OG whose backend hands them a bad signature gets a `WRONG_PRICE`
  revert rather than being silently charged.
- **Ungameable criterion.** Eligibility reads state frozen in 2021;
  there is no transaction anyone can send today to alter it.

## What you are trusting

Honesty requires naming the trust anchor: **whoever holds the signer key
is the allowlist.**

- If the key leaks, an attacker can sign vouchers for fresh wallets
  (each still capped at 3 tokens, but wallets are free). The signer is
  immutable — recovery means redeploying. Keep the key in a secret
  manager or deployment-platform env, never in the repo.
- The backend trusts whatever RPC it uses for the nonce check. Use a
  reputable keyed provider in production; a lying RPC means wrongly
  signed vouchers.
- If the backend goes down, no *new* wallets can get vouchers (existing
  holders of a voucher can still mint). The mint's availability is the
  backend's availability.

## Verifying a voucher by hand

With a deployed, verified contract and a voucher in hand:

```sh
# the digest the signer should have signed for this wallet
cast call <contract> "voucherDigest(address)(bytes32)" <wallet> --rpc-url <rpc>

# recover the signer from digest + signature; must equal signer()
cast call <contract> "signer()(address)" --rpc-url <rpc>
```

A wrong domain (name, version, chain id, or contract address) in the
backend shows up immediately here: the recovered address won't match.
