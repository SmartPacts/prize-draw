# Prize Draw — raffles decided by a block that did not exist when their tickets were sold

A Pact 5 smart contract for Kadena. Many raffles run as configuration rows on one state machine:
each has its own price, fee, prize split, supply and pool. A round exists from its first ticket,
sells on a calendar, and is decided by the hash of a block **that did not exist when the round was
sold**. Nobody can pick the winner under the contract's rules; what can still tilt a draw is below.

> ## 🟢 DEPLOYED — Kadena mainnet (mainnet01)
>
> - Namespace `n_48867b242317a0216a67f8c7ca26696b5878e0e3`, module `prize-draw`, **chain 2**
> - Module hash `r1ecwafNL89gBUcstQ5GY4edqGOXq3HMWied_rOOhaI`
> - The module on chain is **byte for byte** the `(module …)` form in `pact/modules/prize-draw.pact`
>   — check it yourself with [`VERIFY.md`](VERIFY.md), which takes about a minute.
> - 🔴 **The contract is not frozen.** Until it is, any **2 of its 3 admin keys** hold *module
>   admin*: in one transaction, with no new code and no change to the module hash, they can move
>   money out of any pool and rewrite any record the contract keeps — a selling round's terms, who
>   owns a ticket, where fees go. They can also publish a new version. Freezing ends all of that;
>   it has not happened.
> - **Nothing is for sale here.** This repository is source code: no tickets are sold from it and
>   nothing in it is an offer or a solicitation. Tickets are sold at
>   [smartpacts.io/games](https://smartpacts.io/games/).

## Games on mainnet

| game | what it is |
|---|---|
| [**The Grand Opening**](games/grand-opening.md) | Selling. One round, ten winners, a pot that started at 1,000 KDA; 10 KDA a ticket; draw Sunday 27 September 2026, 18:00 UTC |
| [**The pilot**](games/pilot-1.md) | Finished. The first mainnet round: one ticket, drawn from block 7241467 and paid by the settlement program, 2026-09-19 |

Each game's page carries its full terms, how its winners are chosen, and the read-only calls that
let you check it on chain yourself.

## Which file am I reading?

| | |
|---|---|
| `pact/modules/prize-draw.pact` | 🔴 **THE DEPLOYED CONTRACT.** Its `(module …)` form, comments and all, is the code stored on mainnet. The lines before it (header comments, the `namespace` line and a load-time admin check) and after it ran once, in the deploy transaction, and are not stored. |
| everything else | tests, vendored dependencies, and the documents about it |

Nothing else in this repository deploys. Unlike most Pact projects, there is no separate
"deploy bytes" variant to reconcile: the annotated source *is* the artifact, so verification is a
diff against the chain rather than an argument about equivalence. One exception is designed in: a
**freeze** is itself a deploy, of this module with its governance body replaced
(`pact/tests/fixtures/prize-draw-frozen.pact` is exactly that). After a freeze, the module hash
changes and [`VERIFY.md`](VERIFY.md) §1 reports a mismatch against this file — which is how you
would recognise one.

The file is kept exactly as it was deployed, comments included, so a comment is never corrected in
place. Where one is wrong, [`docs/PRIZE-DRAW-SPEC.md`](docs/PRIZE-DRAW-SPEC.md) §12 says so.

## What is in here

```
pact/modules/     the contract
pact/tests/       five suites (593 printed assertions) and the loader they share; run-tests.sh
                  runs everything
pact/vendor/      the dependencies the tests load: a snapshot of our block record, and Kadena's
                  coin + fungible interfaces (not ours — see NOTICE)
docs/             what the contract does — PRIZE-DRAW-SPEC.md, the engineering statement with the
                  tests behind every property, and PRIZE-DRAW-WHAT-IT-DOES.md, the same in plain
                  language
games/            every game created on the contract, with its terms and transactions
verification/     the recorded identity of the deployed artifact
.github/          the static gate, the checkers, and the CI that runs all of it on every push
```

## Run the tests yourself

Needs [Pact 5.4ce](https://github.com/kda-community/pact-5) on your PATH (or `PACT=/path/to/pact`)
and `python3`.

```
cd pact/tests && ./run-tests.sh
```

That is the same command CI runs, with no reduced subset — a CI that runs less than you do teaches
you to trust a green tick that means less than you think. It runs the static gate over every file,
checks that `or`, `and` and `+` are always given exactly two operands (Pact 5 refuses more only
when the line runs), checks that no `expect-failure` was written with too few arguments to assert
*why* something failed, proves the frozen-module fixture is this module with only its governance
replaced, and then runs the five suites, scoring each by **exit code** rather than by grepping the
transcript.

## How a winner is chosen

A round's draw instant is set when it is scheduled and frozen by its first ticket. At that instant
anyone — not only us — calls `open-draw`, which names **three candidate blocks that have not been
mined yet**, starting two blocks after the one it lands in. The lowest of those that gets recorded
in an immutable, raffle-blind block record decides the round, and the winners are a pure function
of the round's key and that block's hash. The contract never draws a round twice, and nobody can
pick the winner.

**What can still tilt a draw, and what limits each one.** None of these lets anyone *pick* a
winner. Each can only make a different candidate decide — swapping one unpredictable result for
another, like a second roll of the same dice. Two of the three are measured, not hypothetical.

| the possibility | what limits it |
|---|---|
| A party recording blocks alone could stay silent about a candidate it dislikes, or record none of the three and force a refund | Recording is permissionless and the recorder is open source; **two independent operators try to record every mainnet block today** (together they miss about 8–9% of chain 2's heights), and a candidate recorded by either settles the round. A forced refund pays every ticket back with its equal part of any bonus, so it costs the house the round rather than winning it |
| A player who also mines could discard a block it mined whose hash loses and let another decide — **measured: a small ticket share's chance of winning roughly doubles even at tiny hashrate, and grows with hashrate** (a miner with 61.5% of blocks, the largest on mainnet when measured, would triple a 10% share's chance); closed form, agreed within 0.5pp by a 400,000-run Monte Carlo — the measurement is not in this repository | It never lets the miner choose a winner, and each discard costs it the block reward (0.909 KDA on chain 2). The prize ceiling, published before any ticket is sold, caps what is at stake — it does not make discarding unprofitable |
| The miner of the block *after* a candidate can leave every record of it out, at no cost, so the next candidate decides. **More recorders do not prevent this one** — every recorder's record travels through that same block | It swaps one unpredictable result for another, never for a chosen one, and all three candidates would have to be left out to force a refund. About 9% of mainnet heights go unrecorded, which is why the draw uses three candidates and not one |

The honest summary: **nobody can pick a winner; three parties can make a different candidate
decide, and that is disclosed with what limits it.** More independent recorders and more
independent settlement programs make each row harder, which is why both programs are public.
Separately, and above all of this, the admin keys can override the contract's rules until it is
frozen — see the box at the top.

## Two admin tiers

| tier | predicate | what it may do |
|---|---|---|
| admin | **any 2 of 3** keys | upgrade the module and freeze it permanently; **until frozen, hold module admin** — move pool money and rewrite any record in one transaction; redefine the admin keyset itself |
| operator | **any 1 of 3** | create raffles, set terms, schedule rounds, retire a raffle, add bonus — and **redefine the operator keyset itself**: any one of the three keys can replace the other two. Keysets live outside the module, so a freeze does not end this |

Neither tier can make the contract's own code choose a winner. The operator cannot move pool
money or change a round that is already selling.

Settling is **nobody's privilege**: opening a draw, drawing, and refunding a round that can never
be drawn are calls anybody can make, and the contract gives the sender no say in the outcome. That
is why a bot can do it — see [SmartPacts/prize-draw-crank](https://github.com/SmartPacts/prize-draw-crank),
which is public so that anyone can run one.

## What this contract's code does not do

Every line below describes the deployed code. Until the contract is frozen, the admin keys can
override any of it (the box at the top).

- **It does not pick a winner.** No function lets anyone choose one; the decision is a block hash.
- **Every drawn round has a winner.** Winners are drawn from the tickets actually sold, and the
  whole fund is paid out — unfilled prize tiers merge into first place. A round that is refunded
  instead (the two cases in the spec) has none.
- **It does not make you claim a prize.** Winners are paid inside the draw transaction. There is no
  claim step and nothing expires.
- **It does not take a fee larger than the sale.** The fee is a fraction below 1, frozen into each
  round when it opens, so re-terming a raffle can never reach money already staked.
- **It cannot be upgraded once frozen** — and freezing is one-way.

## Reporting a problem

See [SECURITY.md](SECURITY.md) — open a **GitHub security advisory** on this repository.

## Licence

Apache-2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
