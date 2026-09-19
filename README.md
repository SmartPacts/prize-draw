# Prize Draw — raffles where the house cannot choose the winner

A Pact 5 smart contract for Kadena. Many raffles run as configuration rows on one state machine:
each has its own price, fee, prize split, supply and pool. A round exists from its first ticket,
sells on a calendar, and is decided by the hash of a block **that nobody picked and nobody could
predict when the round was sold**.

> ## 🟢 DEPLOYED — Kadena mainnet (mainnet01)
>
> - Namespace `n_48867b242317a0216a67f8c7ca26696b5878e0e3`, module `prize-draw`, **chain 2**
> - Module hash `r1ecwafNL89gBUcstQ5GY4edqGOXq3HMWied_rOOhaI`
> - The code on chain is **byte for byte** the file in `pact/modules/` — check it yourself with
>   [`VERIFY.md`](VERIFY.md), which takes about a minute.
> - **The contract is not frozen.** While it stays upgradeable, its admin keyset (2 of 3 keys) can
>   redeploy it, and can reach money sitting in raffle pools. Freezing ends that, and it has not
>   happened yet.
> - **Nothing is for sale here.** This repository is source code: no tickets are sold from it and
>   nothing in it is an offer or a solicitation. Tickets are sold at
>   [smartpacts.io/games](https://smartpacts.io/games/), where the first round ran on 2026-09-19 —
>   one ticket, drawn from block 7241467, paid inside the draw.

## Games on mainnet

| game | what it is |
|---|---|
| [**The Grand Opening**](games/grand-opening.md) | One round, ten winners, a pot that starts at 1,000 KDA; 10 KDA a ticket; draw Sunday 27 September 2026, 18:00 UTC |
| [**The pilot**](games/pilot-1.md) | Finished. The first mainnet round: one ticket, drawn from block 7241467 and paid by the settlement program, 2026-09-19 |

Each game's page carries its full terms, how its winners are chosen, and the read-only calls that
let you check it on chain yourself.

## Which file am I reading?

| | |
|---|---|
| `pact/modules/prize-draw.pact` | 🔴 **THE DEPLOYED CONTRACT.** This exact file, comments and all, is what runs on mainnet. |
| everything else | tests, vendored dependencies, and the documents about it |

Nothing else in this repository deploys. Unlike most Pact projects, there is no separate
"deploy bytes" variant to reconcile: the annotated source *is* the artifact, so verification is a
diff against the chain rather than an argument about equivalence.

## What is in here

```
pact/modules/     the contract
pact/tests/       the suite — 5 files, ~590 printed assertions, run-tests.sh runs everything
pact/vendor/      the dependencies the tests load: a snapshot of the block record, and Kadena's
                  coin + fungible interfaces (not ours — see NOTICE)
docs/             what the contract does — PRIZE-DRAW-SPEC.md, the engineering statement with the
                  tests behind every property, and PRIZE-DRAW-WHAT-IT-DOES.md, the same in plain
                  language, generated from the contract itself
games/            every game created on the contract, with its terms and transactions
verification/     the recorded identity of the deployed artifact
.github/          the static gate and the CI that runs all of it on every push
```

## Run the tests yourself

Needs [Pact 5.4ce](https://github.com/kda-community/pact-5) on your PATH and `python3`.

```
cd pact/tests && ./run-tests.sh
```

That is the same command CI runs, with no reduced subset — a CI that runs less than you do teaches
you to trust a green tick that means less than you think. It runs the static gate over every file,
checks that no `expect-failure` was written with too few arguments to assert *why* something
failed, proves the frozen-module fixture is this module with only its governance replaced, and then
runs the five suites, scoring each by **exit code** rather than by grepping the transcript.

## How a winner is chosen

A round's draw instant is set when it is scheduled and frozen by its first ticket. At that instant
anyone — not only us — calls `open-draw`, which names **three candidate blocks that have not been
mined yet**. The lowest of those that gets recorded in an immutable, raffle-blind block record
decides the round, and the winner is a pure function of the round's key and that block's hash.
There is no re-roll: no second attempt can be minted, and nobody has a choice to make after the
outcome is knowable.

**What can still tilt a draw, and what limits each one.** None of these selects a winner, and two
of the three are measured rather than hypothetical.

| the possibility | what limits it |
|---|---|
| A party recording blocks alone could stay silent about a candidate it dislikes, or record none of the three and force a refund | Recording is permissionless and the recorder is open source; **two independent operators record every mainnet block today**, and a candidate recorded by either settles the round. A forced refund pays every ticket back with its equal part of any bonus, so it costs the house the round rather than winning it |
| A player who also mines could discard a block it mined whose hash loses — **measured at roughly 2× even at tiny hashrate** (closed form, agreed within 0.5pp by a 400,000-run Monte Carlo) | It buys one more chance, never a choice of winner, weighed against a prize ceiling published before any ticket is sold |
| The miner of the block *after* a candidate can leave every record of it out, at no cost, so the next candidate decides. **More recorders do not prevent this one** — every recorder's attest travels through that same block | It changes *which* block decides, never who wins: the next candidate is equally unpredictable, and all three would have to be left out to force a refund. Roughly 9% of mainnet heights go unrecorded, which is why the draw uses three candidates and not one |

The honest summary: **influence over *which* block decides exists and is disclosed; influence over
*who wins* does not.** More independent recorders and more independent cranks make each row
harder, which is why both programs are public.

## Two admin tiers

| tier | predicate | what it may do |
|---|---|---|
| admin | **2 of 3** keys | upgrade the module, and freeze it permanently |
| operator | **any 1 of 3** | create raffles, set terms, schedule rounds, retire a raffle, add bonus |

Settling is **nobody's privilege**: opening a draw, drawing, and refunding a dead round are calls
anybody can make, and the contract gives the sender no say in the outcome. That is why a bot can do
it — see [SmartPacts/prize-draw-crank](https://github.com/SmartPacts/prize-draw-crank), which is
public so that anyone can run one.

## What this contract cannot do

- **It cannot pick a winner.** No key, ours included, chooses one; the decision is a block hash.
- **It cannot run a round with no winner.** Winners are drawn from the tickets actually sold, and
  the whole fund is paid out — unfilled prize tiers merge into first place.
- **It cannot make you claim a prize.** Winners are paid inside the draw transaction. There is no
  claim step and nothing expires.
- **It cannot take a fee larger than the sale.** The fee is a fraction below 1, frozen into each
  round when it opens, so re-terming a raffle can never reach money already staked.
- **It cannot be upgraded once frozen** — and freezing is one-way.

## Reporting a problem

See [SECURITY.md](SECURITY.md) — open a **GitHub security advisory** on this repository.

## Licence

Apache-2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
