# The Grand Opening

The first public game on the Prize Draw contract. One round, ten winners, and a pot that started at
**1,000 KDA** before anyone bought a ticket.

> **Finished.** Drawn and paid on Sunday 27 September 2026 at 18:03 UTC — 2,330 KDA to ten
> winners in one transaction. See [The result](#the-result).

> **Game `grand-opening`** on Kadena mainnet (`mainnet01`), **chain 2**
> - Contract: `n_48867b242317a0216a67f8c7ca26696b5878e0e3.prize-draw`, module hash
>   `r1ecwafNL89gBUcstQ5GY4edqGOXq3HMWied_rOOhaI` — the `(module …)` form in
>   [`pact/modules/`](../pact/modules/), byte for byte ([VERIFY.md](../VERIFY.md))
> - The game's pot: `m:n_48867b242317a0216a67f8c7ca26696b5878e0e3.prize-draw:grand-opening` —
>   the contract holds every ticket payment and the opening bonus here, not a key of ours — with
>   the one exception stated under [Who can change the contract](#who-can-change-the-contract)
> - Created on chain at block **7243001**, request key
>   `PsZtiJ4On1jwiODmzHpLdZcMLWc90Ccsddk54if1CgM` — the terms below and the 1,000 KDA bonus were
>   written in that one transaction
> - Round 1 opened at **15:39:19 UTC** on 19 September, block **7243060**, request key
>   `sU1JicJ5pkKvioHyd5qGlPBEOQ8dTBBmihARKEtVLEg` — the first 5 tickets, bought by our founder from their
>   personal account, which froze the
>   terms below into the round and bound the bonus to it
> - Play at **[smartpacts.io/games](https://smartpacts.io/games/)** · results at
>   **[smartpacts.io/games/results](https://smartpacts.io/games/results/)**

## The result

**140 tickets from 6 accounts**, so the pot was 1,000 + 9.5 × 140 = **2,330 KDA**. Everything
below happened on chain without anyone signing by hand: both transactions were sent by the
settlement program's account, `k:a19aabf8f29329c1f4a6833a03d0d4e4226c0cb385b6828123e872f273c20be7`.

All times UTC, Sunday 27 September 2026.

| When | What | Block | Request key |
|---|---|---:|---|
| 18:00:00 | Sales closed | — | — |
| 18:01:39 | Draw opened by the settlement program; candidates: blocks 7266386, 7266387, 7266388 | 7266384 | `asiHj1BaIORVnHiN5mPGGtexHgwlMIeAMlD3ALRQ4PE` |
| 18:02:08 | **Block 7266386 mined — the first candidate, and it was recorded, so it decided the round.** Hash `nWW4WUxevDx6180JVyCLNbia5hemX-fGwU0m_3wzIko` | 7266386 | — |
| 18:03:43 | Drawn and every prize paid, in one transaction | 7266389 | `IYbgjB68rWIGFLLOaoHFcbniqr3TzxES90c6PHXdYCQ` |

### The winners

The draw seed is **235687867729757000**. Ticket positions count from 0 in the order tickets were sold.

| Place | Ticket position | Account | Prize (KDA) |
|---|---:|---|---:|
| 1st | 86 | `k:1d6423d75f567e8180673d2183d358626310b21dbddde869c688e3a593f6b7d0` | 932 |
| 2nd | 108 | `k:3ab114faea8b2b67f69035c302da81b3099ae79213969ebcd6fde69861ed7403` | 349.5 |
| 3rd | 91 | `k:1d6423d75f567e8180673d2183d358626310b21dbddde869c688e3a593f6b7d0` | 233 |
| 4th | 115 | `k:3ab114faea8b2b67f69035c302da81b3099ae79213969ebcd6fde69861ed7403` | 116.5 |
| 5th | 46 | `k:3ab114faea8b2b67f69035c302da81b3099ae79213969ebcd6fde69861ed7403` | 116.5 |
| 6th | 37 | `k:3ab114faea8b2b67f69035c302da81b3099ae79213969ebcd6fde69861ed7403` | 116.5 |
| 7th | 35 | `k:3ab114faea8b2b67f69035c302da81b3099ae79213969ebcd6fde69861ed7403` | 116.5 |
| 8th | 40 | `k:3ab114faea8b2b67f69035c302da81b3099ae79213969ebcd6fde69861ed7403` | 116.5 |
| 9th | 106 | `k:3ab114faea8b2b67f69035c302da81b3099ae79213969ebcd6fde69861ed7403` | 116.5 |
| 10th | 14 | `k:d9b53147041c2f6bcee9f4756dfd56f51895b3ce46649b51b0c3889313da5b65` | 116.5 |

`k:3ab114…7403` held 75 of the 140 tickets and won seven places; `k:1d6423…b7d0` held 20 and won
two; `k:d9b531…5b65` held 18 and won one.

**Our founder took part like any other player**, from their personal account `k:1d6423…b7d0`: same
price, same rules, the same draw. That account also paid the 1,000 KDA opening bonus and receives
the settlement program's share. In total it put **1,200 KDA** into this game (the bonus plus 20
tickets) and received **1,182.5 KDA** back (1,165 in prizes plus the 17.5 settlement share) —
17.5 KDA less than it paid in.

### Where the money went

The pot held 2,400 KDA: 1,400 of ticket money plus the 1,000 bonus. The draw paid it all out in
one transaction, one transfer per account:

| To | Amount (KDA) | Why |
|---|---:|---|
| `k:1d6423d75f567e8180673d2183d358626310b21dbddde869c688e3a593f6b7d0` | 1,182.5 | 1st and 3rd place (932 + 233), plus the settler's share of the fee (17.5) |
| `k:3ab114faea8b2b67f69035c302da81b3099ae79213969ebcd6fde69861ed7403` | 1,048.5 | 2nd and 4th to 9th place (349.5 + 6 × 116.5) |
| `k:d9b53147041c2f6bcee9f4756dfd56f51895b3ce46649b51b0c3889313da5b65` | 116.5 | 10th place |
| `k:747ac0446a857c28c6caa0ed3f73a96bf4693495ce8612b60fe3a31d93da5997` | 17.5 | The recorder's share: our recorder, which recorded block 7266386 |
| `m:n_48867b242317a0216a67f8c7ca26696b5878e0e3.SPT:SPT-funding` | 35 | The other half of the fee, to SPT's funding account |

Total out: 2,400 KDA. The pot was left empty. The fee was 70 KDA (5% of 1,400); none was taken
from the bonus. The draw cost 1,955 gas and opening it 226.

### Recompute it yourself

```python
import hashlib
b = lambda s: int.from_bytes(hashlib.blake2b(s.encode(), digest_size=32).digest(), "big")
h = "nWW4WUxevDx6180JVyCLNbia5hemX-fGwU0m_3wzIko"   # block 7266386, chain 2
seed = b(f"prize-draw|grand-opening|1|{h}") % 10**18
print(seed)            # 235687867729757000 — the seed the contract stored
taken = []
for i in range(1, 11):
    c = b(f"{seed}|grand-opening|1|{i}") % (140 - i + 1)
    for r in sorted(taken):
        if c >= r: c += 1
    taken.append(c)
print(taken)           # [86, 108, 91, 115, 46, 37, 35, 40, 106, 14] — the stored ticket positions
```

The owner of each position is `(n_48867b242317a0216a67f8c7ca26696b5878e0e3.prize-draw.get-ticket
"grand-opening" 1 <position>)`, read-only from any node on chain 2.

## At a glance

| | |
|---|---|
| Ticket | **10 KDA** |
| Opening bonus | **1,000 KDA**, paid into the pot by our founder, from their personal account `k:1d6423d75f567e8180673d2183d358626310b21dbddde869c688e3a593f6b7d0`, in the transaction that creates the game — before any ticket |
| Winners | **10** — first place 40% of the pot, second 15%, third 10%, and seven more at 5% each |
| Fee | **5% of ticket money**. None is taken from the bonus |
| Tickets | No fixed number. Up to 50 per purchase |
| Prize ceiling | **50,000 KDA** of ticket money plus bonus — room for 4,900 tickets |
| Sales opened | **Saturday 19 September 2026, 15:36:15 UTC** (the first ticket was bought at 15:39:19) |
| Sales close, and the draw | **Sunday 27 September 2026, 18:00 UTC** |
| Rounds | **One.** This game runs once |
| Who may take part | **18 or older**, and allowed to take part where you are — see [Who may take part](#who-may-take-part) |

**The pot** is 95% of all ticket money plus the whole 1,000 KDA bonus:

`pot = 1,000 + 9.5 × tickets sold`

## What the prizes look like

| Tickets sold | Pot (KDA) | 1st | 2nd | 3rd | 4th to 10th, each |
|---:|---:|---:|---:|---:|---:|
| 100 | 1,950 | 780 | 292.5 | 195 | 97.5 |
| 500 | 5,750 | 2,300 | 862.5 | 575 | 287.5 |
| 1,000 | 10,500 | 4,200 | 1,575 | 1,050 | 525 |
| 4,900 (the ceiling) | 47,550 | 19,020 | 7,132.5 | 4,755 | 2,377.5 |

Examples, not predictions: the pot depends only on how many tickets are sold.

- **Fewer than ten tickets sold.** There are only as many winners as tickets, and the unfilled
  prizes merge into first place. The contract computes prizes 2 to 10 first and gives first place
  the exact remainder, so the whole pot is always paid out and nothing is left behind. If a single
  ticket is sold, it wins the entire pot, bonus included.
- **One account, several prizes.** The ten winners are ten different *tickets*. Someone holding
  several tickets can win several prizes, paid to them as one transfer.

## How the winner is chosen

1. At **18:00 UTC on 27 September** sales close. From that moment anyone may call `open-draw`
   (our settlement program does it within a couple of minutes — the pilot's landed 93 seconds after
   its instant). That call names **three blocks of the chain that do not exist yet** as
   candidates, starting two blocks after the one it lands in.
2. The **lowest of the three that is recorded** in the public, permanent block record decides the
   round. The winners are a pure function of the round's key (`grand-opening|1`) and that block's
   hash, and the contract never draws a round twice. Nobody can *pick* the winners; three parties
   can make a different candidate decide, as disclosed [below](#what-protects-you--and-the-limits).
3. The pilot round's deciding block arrived **2 minutes 13 seconds** after its announced instant, so
   expect the result a few minutes after 18:00 UTC.

**Recompute it yourself.** The seed is blake2b-256 of the text
`prize-draw|grand-opening|1|<deciding block hash>`, read as a big-endian integer, modulo 10^18. For
each place *i* = 1…10: take blake2b-256 of `<seed>|grand-opening|1|<i>` as an integer, modulo
(tickets sold − *i* + 1), then step past every ticket position already drawn, in ascending order.
That is the winning ticket's position, counting from 0 in the order tickets were sold. The results
page does both for you in your browser and compares them with what the round stored, and the
contract's own `draw-ranks` gives the same answer from any node.

## When you get paid

**Inside the draw itself.** The transaction that draws the winners pays them in the same moment,
to the account that bought each winning ticket. There is nothing to claim and nothing expires.
Under the contract's rules payment can only ever go to the buying account — if you lose access to
it, the rules let nobody redirect a prize. The admin override under [Who can change the
contract](#who-can-change-the-contract) is the one exception.

## Refunds — exactly two cases

A round is refunded, with **every ticket repaid its price plus an equal part of the bonus**, only if:

- **nobody opens the draw within a day** of 18:00 UTC on 27 September, or
- **none of the three candidate blocks is ever recorded.**

There is no other refund and no cancellation. A refund can only go to the account that bought the
tickets. Our settlement program sends it, and the contract lets **anyone** send it (`claim-escape`),
so it does not depend on us being there.

## Where the fee goes

The fee is 5% of ticket money. Half of it pays whoever keeps the draw running, equally: the
account that recorded the deciding block, and the account that settled the round. Both programs
are open source and anyone may run them — the block recorder,
[block-history](https://github.com/SmartPacts/block-history#run-your-own-recorder), and the
settler, [prize-draw-crank](https://github.com/SmartPacts/prize-draw-crank). Today one of the two
block recorders and the settler are ours; the settler pays what it earns to our founder's personal
account. The other half
goes to SPT's funding account (`m:n_48867b242317a0216a67f8c7ca26696b5878e0e3.SPT:SPT-funding`),
which anyone can read on chain. At 500 tickets, for example, the fee is 250 KDA: 62.5 to the
recorder, 62.5 to the settler and 125 to SPT funding.

## What protects you — and the limits

**What the contract guarantees:**

- **Its rules let nobody choose the winner.** The decision is a block hash that does not exist
  when the draw is opened.
- **The money is held by the contract**, in the pot above, not by any person. The bonus was paid in
  before the first ticket and cannot be taken back out by the operator.
- **The terms are frozen by the first ticket.** Price, fee, prize split, ceiling and dates are
  copied into the round the moment its first ticket is sold, and nothing the operator can do
  changes them for that round afterwards (the admin keys' power is stated below). Our founder bought
  the first 5 tickets at opening, from their personal account, in block 7243060.
- **Everything is public and checkable** — every purchase, the draw, and every payment are
  transactions on Kadena mainnet.

**What could still tilt a draw, and what limits it.** None of these lets anyone pick a winner; each
can only make a different candidate decide — one unpredictable result swapped for another.

- **Whoever records blocks** could stay quiet about a candidate it dislikes, or record none of the
  three and force a refund. *What limits it:* recording is public and permissionless, two
  independent operators try to record every mainnet block today (together they miss about 8–9% of
  heights), and a candidate recorded by either one
  settles the round. A forced refund pays every ticket back with its part of the bonus, so it costs
  the house the round rather than winning it.
- **A player who also mines** could throw away a block it mined whose hash loses. That buys one more
  roll, never a choice of winner — measured at roughly double a small ticket share's chance even
  for a very small miner, and more for a large one. *What limits it:* each discard costs the miner
  its block reward, and the prize ceiling is published before anyone buys — it caps what is at
  stake, it does not make discarding unprofitable.
- **The miner of the block right after a candidate** could leave that candidate unrecorded, so the
  next one decides instead. More recorders do not prevent this. *What limits it:* it swaps one
  unpredictable result for another, never for a chosen one, and all three would have to be left
  out to force a refund. Roughly 9% of mainnet heights go unrecorded, which
  is why the draw names three candidates and not one.

### Who can change the contract

The contract is **not frozen**. Until it is, any two of its three admin keys — held on separate
devices — can **override its rules in a single transaction**: move money out of any game's pot,
including this one, or rewrite any record the contract keeps, including who owns a ticket, which
would redirect a prize. It needs no new code, so the module hash and the check in
[VERIFY.md](../VERIFY.md) would not change; the transaction itself would be public on the chain.
They can also publish a new version of the contract. Everything on this page describes the
contract's rules as they are today. Freezing would end that power permanently; it has not happened.

Separately, any **one** of the three keys can redefine the operator keyset — the key that creates
games and sets their terms for future rounds. The operator cannot touch this game's pot or its
frozen terms.

## Check it yourself

Read-only calls, free, from any Kadena node on chain 2 (for example with `/local` or Chainweaver):

```lisp
(n_48867b242317a0216a67f8c7ca26696b5878e0e3.prize-draw.get-raffle "grand-opening")     ; the terms
(n_48867b242317a0216a67f8c7ca26696b5878e0e3.prize-draw.get-round "grand-opening" 1)    ; the round
(n_48867b242317a0216a67f8c7ca26696b5878e0e3.prize-draw.pool-status "grand-opening")    ; what the pot holds and owes
(coin.get-balance "m:n_48867b242317a0216a67f8c7ca26696b5878e0e3.prize-draw:grand-opening")
```

## Who may take part

You must be **18 or older**, or the age of majority where you live if that is higher; taking part
must be lawful for you where you are and where you live; and you take part for yourself, with money
that is yours. Buying a ticket is your confirmation that all of this is true. Games of chance are
restricted or prohibited in some places, and whether you may take part is your responsibility.

**What you pay is at risk.** Most tickets do not win. Take part only with money you can afford to
lose. Every purchase is final except in the two refund cases above. The full terms are at
[smartpacts.io/terms](https://smartpacts.io/terms/#games).

**To buy you need** a Kadena wallet — EckoWallet, Zelcore, a Ledger or a mobile wallet — holding
KDA on **chain 2**, plus a little more than the ticket price for the network fee. Kadena keeps a
separate balance on each chain, so KDA on another chain must be moved to chain 2 first.

## Contact

**contact@smartpacts.io** — for a purchase that looks wrong, include the account you used and the
transaction's request key. For a security problem, open a private security advisory on this
repository ([SECURITY.md](../SECURITY.md)).
