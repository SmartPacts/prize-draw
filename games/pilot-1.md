# The pilot (`pilot-1`)

The first round ever run on this contract on mainnet. Its only purpose was to prove the whole
mechanism with real KDA, real gas and real timing before any public game: create a game, sell a
ticket, open the draw, record the deciding block, draw, pay the winner, and pay the fee — with
nobody stepping in by hand once the ticket was sold.

> **Finished.** One round, drawn and paid on 2026-09-19. The game is retired: it was a one-off.
> Kadena mainnet (`mainnet01`), **chain 2**, contract
> `n_48867b242317a0216a67f8c7ca26696b5878e0e3.prize-draw`.

**The only ticket was ours.** Smart Pacts bought it from its own account to run the proof; nobody
else took part. It won the prize back, less the fee.

## Terms

| | |
|---|---|
| Ticket | 1 KDA |
| Fee | 5% of ticket money |
| Winners | One — winner takes the pot |
| Tickets | No fixed number |
| Bonus | None |
| Prize ceiling | 25 KDA |
| Rounds | One |
| Settlement share | Half of the fee, split equally between the block's recorder and the round's settler |

## What happened, on chain

All times UTC, 2026-09-19. Every line is a transaction you can look up by its request key.

| When | What | Block | Request key |
|---|---|---:|---|
| before 02:06 | Game created and its round scheduled: sales 02:06:42 → 02:26:42, draw at 02:26:42 | 7241405 | `FaV8hcyIGjsQsw0sDzl1wEH7F9FJU56VhuCO6assmQ8` |
| during sales | The one ticket, bought by `k:1d6423d75f567e8180673d2183d358626310b21dbddde869c688e3a593f6b7d0` | 7241426 | `_IvWrSM37fs5IfI0NuuK94kRsShtan8K-0nzNG4gE04` |
| after 02:26:42 | Draw opened by the settlement program; candidates: blocks 7241467, 7241468, 7241469 | 7241465 | `WkSe5S98FeBXXtmF35YwlNxBpFtvNRvp8LLLZIbVvlk` |
| 02:28:55 | **Block 7241467 mined — the first candidate, and it was recorded, so it decided the round** — 2 min 13 s after the draw instant. Hash `OP_bHMVUFdLdVAkssrfhbYijuCJgIkWpsMeeOosdeIQ` | 7241467 | — |
| 02:30:17 | Drawn and paid, by the settlement program | 7241470 | `GTevqUrZbdtq6A0c9bR9f0CH-H2WrtPjAadDk79EXMk` |

Both the draw and the payments happened without anyone at Smart Pacts acting: the settlement
program ([prize-draw-crank](https://github.com/SmartPacts/prize-draw-crank), account
`k:a19aabf8f29329c1f4a6833a03d0d4e4226c0cb385b6828123e872f273c20be7`) opened the draw 93 seconds
after its instant and drew the round as soon as its deciding block was on record. Its two transactions cost
0.0000123 KDA of gas in total (212 gas to open the draw, 1,019 to draw it).

## Where the money went

The round took in **1 KDA**. The draw paid it all out in one transaction:

| To | Amount (KDA) | Why |
|---|---:|---|
| `k:1d6423d75f567e8180673d2183d358626310b21dbddde869c688e3a593f6b7d0` | **0.95** | The prize: 1 KDA less the 5% fee |
| the same account | 0.0125 | The settler's share of the fee — this account is where our settlement program sends what it earns. Paid together with the prize as one transfer of 0.9625 |
| `k:6223803aea271b4b7484590d63905bb406f9d77a5297a2fc8d59b9af8c69ceed` | 0.0125 | The recorder's share: the recorder that recorded block 7241467 — the second recorder, operated independently on its own server |
| `m:n_48867b242317a0216a67f8c7ca26696b5878e0e3.SPT:SPT-funding` | 0.025 | The other half of the fee, to SPT's funding account |

Total out: 1.0000 KDA. The pot was left empty.

## Recompute it yourself

The seed is blake2b-256 of `prize-draw|pilot-1|1|<deciding block hash>`, read as a big-endian
integer, modulo 10^18:

```python
import hashlib
h = "OP_bHMVUFdLdVAkssrfhbYijuCJgIkWpsMeeOosdeIQ"   # block 7241467, chain 2
seed = int.from_bytes(hashlib.blake2b(f"prize-draw|pilot-1|1|{h}".encode(), digest_size=32).digest(), "big") % 10**18
print(seed)   # 968439115421315306 — the seed the contract stored
```

With one ticket sold there is one place to draw, and any number modulo 1 is 0, so the winner is
ticket position 0 — the only ticket. The same recipe, with more places and more tickets, decides
every game; see [the Grand Opening](grand-opening.md#how-the-winner-is-chosen).

Read-only, from any node on chain 2:

```lisp
(n_48867b242317a0216a67f8c7ca26696b5878e0e3.prize-draw.get-raffle "pilot-1")     ; the terms
(n_48867b242317a0216a67f8c7ca26696b5878e0e3.prize-draw.get-round "pilot-1" 1)    ; seed, deciding block, winner, amounts
```
