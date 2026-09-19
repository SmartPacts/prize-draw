# Vendored snapshots — copies, never hand-edited

The contract depends on two things this folder holds copies of, so the REPL suite can run on its
own: our **block record** (`block-history`, the public record of block hashes the draw reads) and
Kadena's **coin** contract and **fungible** interfaces. **Editing a copy here changes nothing on
chain and silently forks the tests from the real code.**

| File | Snapshot of | Source | Commit | Taken |
|---|---|---|---|---|
| `block-history.pact` | the immutable per-chain block record (`pact/modules/block-history.pact`) — v2.0.0, attested-only, deployed on all 20 mainnet chains in `free` on 2026-09-11, hash `P3J_LK-Wivmuyw7SB7TzPmfj6t-GCtG3YnfHNAaU2UU` | github.com/SmartPacts/block-history (public) | `9fd87de1ee1d4fef7ecd4c1eb3a79aaf759c2421` | 2026-09-11 |
| `fixtures/coin.pact` | Kadena `coin` v6 test fixture | our private test tree (not public) | `64ec832f9b69c62032327ef644cdbb01c59036e2` | 2026-09-07 |
| `fixtures/fungible-v2.pact` | Kadena `fungible-v2` interface | our private test tree (not public) | `64ec832f9b69c62032327ef644cdbb01c59036e2` | 2026-09-07 |
| `fixtures/fungible-xchain-v1.pact` | Kadena `fungible-xchain-v1` interface | our private test tree (not public) | `64ec832f9b69c62032327ef644cdbb01c59036e2` | 2026-09-07 |

The coin and fungible copies come from a repository that is not public, so check them by the
sha256 below. The coin fixture is **not** the `coin` mainnet runs — which is why a locally computed
module hash never equals the one on chain ([VERIFY.md](../../VERIFY.md) §2). The block record's copy
can be compared with its public repository at the commit above, and with the chain.

sha256:
```
e99c51f0781b1d0c43882c42189efd745791d10060679abf32706e0bfae3f437  fixtures/coin.pact
8006386f7e9279737ab848e3dd90b7b3e0cf73ce49fde570892fc702eb04e850  fixtures/fungible-v2.pact
f47bf73860d19ea4851be57b081fdfd7a411419c3c2e6cacd0eaac950e24fa25  fixtures/fungible-xchain-v1.pact
6102283fd93f7d38130f5ec0cc7a44e3b7bf625d01676ddf43aa7f77ac9e4d3a  block-history.pact
```
