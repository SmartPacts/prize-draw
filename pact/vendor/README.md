# Vendored snapshots — GENERATED, never hand-edited

Prize Draw's draw depends on the shared RNG engine, which lives in another repository.
These files are snapshots taken from it so the REPL suite can run standalone.
**Editing one here changes nothing on chain and silently forks the test from the
real engine.** Fix the source, then re-run `ts/scripts/sync-vendor.sh`.

| File | Snapshot of | Source repo | Commit | Taken |
|---|---|---|---|---|
| `block-history.pact` | the immutable per-chain block record (`pact/modules/block-history.pact`) — the record the draw reads its block hash from: v2.0.0, attested-only, immutable, deployed on all 20 mainnet chains in `free` on 2026-09-11, hash `P3J_LK-Wivmuyw7SB7TzPmfj6t-GCtG3YnfHNAaU2UU` | github.com/SmartPacts/block-history (public) | `9fd87de1ee1d4fef7ecd4c1eb3a79aaf759c2421` | 2026-09-11 |
| `fixtures/coin.pact` | Kadena `coin` v6 test fixture (`test/fixtures/coin.pact`) | SmartPacts/casino-private | `64ec832f9b69c62032327ef644cdbb01c59036e2` | 2026-09-07 |
| `fixtures/fungible-v2.pact` | Kadena `fungible-v2` interface | SmartPacts/casino-private | `64ec832f9b69c62032327ef644cdbb01c59036e2` | 2026-09-07 |
| `fixtures/fungible-xchain-v1.pact` | Kadena `fungible-xchain-v1` interface | SmartPacts/casino-private | `64ec832f9b69c62032327ef644cdbb01c59036e2` | 2026-09-07 |

sha256:
```
e99c51f0781b1d0c43882c42189efd745791d10060679abf32706e0bfae3f437  fixtures/coin.pact
8006386f7e9279737ab848e3dd90b7b3e0cf73ce49fde570892fc702eb04e850  fixtures/fungible-v2.pact
f47bf73860d19ea4851be57b081fdfd7a411419c3c2e6cacd0eaac950e24fa25  fixtures/fungible-xchain-v1.pact
```
6102283fd93f7d38130f5ec0cc7a44e3b7bf625d01676ddf43aa7f77ac9e4d3a  block-history.pact
