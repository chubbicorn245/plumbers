# Deployments

One file per network, each a JSON array of deployments in order —
**the last entry is current**. Redeploys append rather than overwrite, so a
superseded address stays recoverable.

`scripts/deploy-testnet.sh` writes these automatically. The first record was
added by hand, because the script did not do this yet when it deployed and
the address survived only in the operator's terminal scrollback.

`signer` and `payout` are deliberately not recorded here: they are the
operator's own wallets, and anyone who needs them can read them off the
contract (`cast call <addr> "signer()(address)"`). Nothing in this directory
is a secret — every value is already public on-chain.
