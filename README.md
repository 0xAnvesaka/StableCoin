# Foundry-Stablecoin (Indian Stable Coin Algorithmically)

A Foundry-based educational stablecoin + invariant/fuzz harness.

## Quick start
1. Install Foundry: `curl -L https://foundry.paradigm.xyz | bash && foundryup`
2. Install deps: `git submodule update --init --recursive` (if you have libs)
3. Run tests: `forge test`
4. Run invariants: `forge test --match-test invariant_ -vv`

## Contracts
- `IRTEngine.sol` — core engine
- `IndianRupeeCoin.sol` — ERC20 reserve token (mintable by engine)


## Verifications & Deployments
- Use `forge script` to deploy and `forge verify-contract` to verify on Etherscan.

