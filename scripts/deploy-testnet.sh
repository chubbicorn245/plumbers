#!/usr/bin/env bash
#
# Deploy ArtPlumber to Robinhood Chain testnet.
#
# The constructor arguments are IMMUTABLE: there is no owner and no setters,
# so `signer` and `payout` can never be changed. This script validates
# everything it can and shows you the exact deployment before spending, since
# the only way to fix a mistake is to deploy again at a new address.
#
#   PRIVATE_KEY=0x...      deployer key (needs testnet ETH; ~0.00004 is plenty)
#   SIGNER_ADDRESS=0x...   address whose vouchers grant the OG free mint
#   PAYOUT_ADDRESS=0x...   the only address withdraw() can ever send to
#
#   ./scripts/deploy-testnet.sh
#
set -euo pipefail

RPC_URL="${RPC_URL:-https://rpc.testnet.chain.robinhood.com}"
EXPLORER="${EXPLORER:-https://explorer.testnet.chain.robinhood.com}"
EXPECTED_CHAIN_ID=46630

die() { echo "error: $*" >&2; exit 1; }

is_address() { [[ "$1" =~ ^0x[0-9a-fA-F]{40}$ ]]; }

: "${PRIVATE_KEY:?set PRIVATE_KEY to the deployer key}"
: "${SIGNER_ADDRESS:?set SIGNER_ADDRESS (generate with: cast wallet new)}"
: "${PAYOUT_ADDRESS:?set PAYOUT_ADDRESS (where withdraw() sends proceeds)}"

is_address "$SIGNER_ADDRESS" || die "SIGNER_ADDRESS is not an address: $SIGNER_ADDRESS"
is_address "$PAYOUT_ADDRESS" || die "PAYOUT_ADDRESS is not an address: $PAYOUT_ADDRESS"

# The contract rejects these, but failing here costs no gas.
[ "$SIGNER_ADDRESS" != "0x0000000000000000000000000000000000000000" ] || die "SIGNER_ADDRESS is the zero address"
[ "$PAYOUT_ADDRESS" != "0x0000000000000000000000000000000000000000" ] || die "PAYOUT_ADDRESS is the zero address"

chain_id=$(cast chain-id --rpc-url "$RPC_URL")
[ "$chain_id" = "$EXPECTED_CHAIN_ID" ] \
  || die "RPC reports chain $chain_id, expected $EXPECTED_CHAIN_ID — wrong network"

deployer=$(cast wallet address --private-key "$PRIVATE_KEY")
balance=$(cast balance "$deployer" --rpc-url "$RPC_URL")
[ "$balance" != "0" ] \
  || die "deployer $deployer has no testnet ETH — fund it at https://faucet.testnet.chain.robinhood.com"

echo "About to deploy ArtPlumber — these choices are PERMANENT:"
echo
echo "  network   Robinhood Chain testnet (chain $chain_id)"
echo "  deployer  $deployer"
echo "  balance   $(cast from-wei "$balance") ETH"
echo "  signer    $SIGNER_ADDRESS   (cannot be rotated; a leak means redeploying)"
echo "  payout    $PAYOUT_ADDRESS   (the only address withdraw() can ever pay)"
echo
echo "  supply    $(grep -o 'MAX_SUPPLY = [0-9]*' src/ArtPlumber.sol | grep -o '[0-9]*')"
echo "  price     $(grep -o 'MINT_PRICE = [0-9.]* ether' src/ArtPlumber.sol)"
echo "  free      $(grep -o 'FREE_ALLOWANCE = [0-9]*' src/ArtPlumber.sol | grep -o '[0-9]*') per OG wallet, no per-wallet cap"
echo
read -r -p 'Type "deploy" to continue: ' confirm
[ "$confirm" = "deploy" ] || die "aborted"

forge create --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --broadcast \
  --json src/ArtPlumber.sol:ArtPlumber \
  --constructor-args "$SIGNER_ADDRESS" "$PAYOUT_ADDRESS" > .deploy.json

address=$(python3 -c 'import json;print(json.load(open(".deploy.json"))["deployedTo"])')
rm -f .deploy.json
echo
echo "deployed to $address"

# Read the immutables back off-chain state, so a wrong constructor arg is
# caught now rather than at the first mint.
on_signer=$(cast call "$address" "signer()(address)" --rpc-url "$RPC_URL")
on_payout=$(cast call "$address" "payout()(address)" --rpc-url "$RPC_URL")
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
[ "$(lower "$on_signer")" = "$(lower "$SIGNER_ADDRESS")" ] || die "on-chain signer is $on_signer, expected $SIGNER_ADDRESS"
[ "$(lower "$on_payout")" = "$(lower "$PAYOUT_ADDRESS")" ] || die "on-chain payout is $on_payout, expected $PAYOUT_ADDRESS"
echo "verified on-chain: signer and payout match"

echo
echo "verifying source on Blockscout..."
forge verify-contract "$address" src/ArtPlumber.sol:ArtPlumber \
  --chain-id "$EXPECTED_CHAIN_ID" \
  --verifier blockscout \
  --verifier-url "$EXPLORER/api/" \
  --constructor-args "$(cast abi-encode 'constructor(address,address)' "$SIGNER_ADDRESS" "$PAYOUT_ADDRESS")" \
  || echo "verification failed — deployment is fine, re-run forge verify-contract later"

cat <<EOF

Done.

  explorer  $EXPLORER/address/$address

Add to the website's .env.local (and the Vercel project):

  NEXT_PUBLIC_ART_PLUMBER_ADDRESS=$address
  ELIGIBILITY_SIGNER_PRIVATE_KEY=<the private key for $SIGNER_ADDRESS>
EOF
