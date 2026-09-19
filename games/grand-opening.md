# The Grand Opening

The first public game on the Prize Draw contract. One round, ten winners, and a pot that starts at
**1,000 KDA** before anyone buys a ticket.

> **Game `grand-opening`** on Kadena mainnet (`mainnet01`), **chain 2**
> - Contract: `n_48867b242317a0216a67f8c7ca26696b5878e0e3.prize-draw`, module hash
>   `r1ecwafNL89gBUcstQ5GY4edqGOXq3HMWied_rOOhaI` — the code in [`pact/modules/`](../pact/modules/),
>   byte for byte ([VERIFY.md](../VERIFY.md))
> - The game's pot: `m:n_48867b242317a0216a67f8c7ca26696b5878e0e3.prize-draw:grand-opening` —
>   the contract holds every ticket payment and the opening bonus here; no key of ours does
> - Play at **[smartpacts.io/games](https://smartpacts.io/games/)** · results at
>   **[smartpacts.io/games/results](https://smartpacts.io/games/results/)**

## At a glance

| | |
|---|---|
| Ticket | **10 KDA** |
| Opening bonus | **1,000 KDA**, paid into the pot by Smart Pacts, from `k:1d6423d75f567e8180673d2183d358626310b21dbddde869c688e3a593f6b7d0`, in the transaction that creates the game — before any ticket |
| Winners | **10** — first place 40% of the pot, second 15%, third 10%, and seven more at 5% each |
| Fee | **5% of ticket money**. None is taken from the bonus |
| Tickets | No fixed number. Up to 50 per purchase |
| Prize ceiling | **50,000 KDA** of ticket money plus bonus — room for 4,900 tickets |
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
   (our settlement program does it within moments). That call names **three blocks of the chain
   that do not exist yet** as candidates.
2. The **first candidate to be recorded** in the public, permanent block record decides the round.
   The winners are a pure function of the round's key (`grand-opening|1`) and that block's hash —
   nobody, including us, has a choice to make once the candidates are named, and nothing can be
   drawn again.
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
Payment can only ever go to the buying account — if you lose access to it, nobody can redirect a
prize.

## Refunds — exactly two cases

A round is refunded, with **every ticket repaid its price plus an equal part of the bonus**, only if:

- **nobody opens the draw within a day** of 18:00 UTC on 27 September, or
- **none of the three candidate blocks is ever recorded.**

There is no other refund and no cancellation. A refund can only go to the account that bought the
tickets. Our settlement program sends it, and the contract lets **anyone** send it (`claim-escape`),
so it does not depend on us being there.

If **no ticket at all** is sold by the close, no round exists: the 1,000 KDA bonus stays in the
game's pot, where no key of ours can take it back, and we schedule a new date.

## Where the fee goes

The fee is 5% of ticket money. Half of it pays whoever keeps the draw running, equally: the
account that recorded the deciding block, and the account that settled the round. Both programs
are open source and anyone may run them — the block recorder,
[block-history](https://github.com/SmartPacts/block-history#run-your-own-recorder), and the
settler, [prize-draw-crank](https://github.com/SmartPacts/prize-draw-crank). Today one of the two
block recorders and the settler are ours, so when they do the work that share comes back to Smart
Pacts. The other half
goes to SPT's funding account (`m:n_48867b242317a0216a67f8c7ca26696b5878e0e3.SPT:SPT-funding`),
which anyone can read on chain. At 500 tickets, for example, the fee is 250 KDA: 62.5 to the
recorder, 62.5 to the settler and 125 to SPT funding.

## What protects you — and the limits

**What the contract guarantees:**

- **Nobody can choose the winner.** The decision is a block hash that does not exist when the
  draw is opened.
- **The money is held by the contract**, in the pot above, not by any person. The bonus was paid in
  before the first ticket and cannot be taken back out by the operator.
- **The terms are frozen by the first ticket.** Price, fee, prize split, ceiling and dates are
  copied into the round the moment its first ticket is sold, and nothing the operator can do
  changes them for that round afterwards (the admin key's power is stated below). Smart Pacts buys
  that first ticket at opening.
- **Everything is public and checkable** — every purchase, the draw, and every payment are
  transactions on Kadena mainnet.

**What could still tilt a draw, and what limits it:**

- **Whoever records blocks** could stay quiet about a candidate it dislikes, or record none of the
  three and force a refund. *What limits it:* recording is public and permissionless, two
  independent operators record every mainnet block today, and a candidate recorded by either one
  settles the round. A forced refund pays every ticket back with its part of the bonus, so it costs
  the house the round rather than winning it.
- **A player who also mines** could throw away a block it mined whose hash loses. That buys one more
  chance, never a choice of winner — measured at roughly double the chance even for a very small
  miner. *What limits it:* the prize ceiling is published before anyone buys.
- **The miner of the block right after a candidate** could leave that candidate unrecorded, so the
  next one decides instead. More recorders do not prevent this. *What limits it:* it changes which
  block decides, never who wins — the next candidate is just as unpredictable — and all three
  would have to be left out to force a refund. Roughly 9% of mainnet heights go unrecorded, which
  is why the draw names three candidates and not one.

**Who can change the contract.** The contract is **not frozen**. Until it is, its admin key — which
needs two of three separate devices to sign the same transaction — can publish a new version of
the contract and can take money out of any game's pot. Everything on this page describes the
contract as it is today. Freezing would end that power permanently; it has not happened.

## Check it yourself

Read-only calls, free, from any Kadena node on chain 2 (for example with `/local` or Chainweaver):

```lisp
(n_48867b242317a0216a67f8c7ca26696b5878e0e3.prize-draw.get-raffle "grand-opening")     ; the terms
(n_48867b242317a0216a67f8c7ca26696b5878e0e3.prize-draw.get-round "grand-opening" 1)    ; the round, once it opens
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
