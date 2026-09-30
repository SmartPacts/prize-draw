# Prize Draw — raffles decided by a public randomness beacon that did not exist when their tickets were sold

A Pact 5 smart contract for Kadena. Many raffles run as configuration rows on one state machine:
each has its own price, fee, prize split, supply and pool. A round exists from its first ticket,
sells on a calendar, and is decided by a drand beacon **that did not exist when the round was
sold**, verified on chain. Nobody can pick the winner under the contract's rules; what could still
affect a draw is below.

> ## 🟢 DEPLOYED — Kadena mainnet (mainnet01)
>
> - Namespace `n_48867b242317a0216a67f8c7ca26696b5878e0e3`, module `prize-draw`, **chain 2**
> - Module hash `ROPuVZ3uzJ2LOLdW-18obFpmmg7XehIV_sQ5H7Taw-s` (upgraded in place 2026-09-30; before that
>   `r1ecwafNL89gBUcstQ5GY4edqGOXq3HMWied_rOOhaI`)
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
| [**The Grand Opening**](games/grand-opening.md) | Finished. One round, 140 tickets, drawn from block 7266386 on 2026-09-27: 2,330 KDA paid to ten winners by the settlement program |
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
pact/tests/       six suites and the loader they share; run-tests.sh runs everything. One suite
                  replays the previous mainnet version and the upgrade over it
pact/vendor/      the dependencies the tests load: the drand beacon verifier (a copy of the module
                  on chain), the block record the previous version read, and Kadena's coin +
                  fungible interfaces (not ours — see NOTICE)
docs/             what the contract does — PRIZE-DRAW-SPEC.md, the engineering statement with the
                  tests behind every property, and PRIZE-DRAW-WHAT-IT-DOES.md, the same in plain
                  language
games/            every game created on the contract, with its terms and transactions
ops/              the first form of the 2026-09-30 upgrade transaction, byte for byte: it refused to
                  land while any round was unsettled (the upgrade suite proves it both ways)
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
replaced, and then runs the six suites, scoring each by **exit code** rather than by grepping the
transcript.

## How a winner is chosen

A round's draw instant is set when it is scheduled and frozen by its first ticket. That first
ticket also pins the round to **one drand beacon**: the one drand's public `evmnet` network
publishes 180 seconds after the draw instant (177 to 180, since drand publishes every 3 seconds).
Sales close at or before the draw instant, on the chain's own clock, so that beacon does not exist
while a ticket can still be bought. Once drand publishes it, anyone — not only us — sends it with
`draw`; the contract verifies the signature against drand's published key through a sealed,
hash-pinned verifier module, and a forged, altered or wrong-round beacon is refused. The winners
are a pure function of the round's key and that beacon; the contract never draws a round twice, and
nobody can pick the winner.

**What can still affect a draw, and what limits each one.** None of these lets anyone *pick* a
winner.

| the possibility | what limits it |
|---|---|
| drand stops publishing, so the pinned beacon never exists | The round is not stuck: 90 days after the beacon was due, anyone can trigger its refund, and every ticket gets its price back plus its equal part of any bonus. Until a refund lands, the round can still be drawn normally |
| Enough of drand's independent operators work together to learn a beacon before it is published | They still could not choose it: each beacon has exactly one valid signature. The same trust is placed in drand by every service that uses it |
| The Kadena network stalls for longer than 180 seconds right at a round's close, or a miner rewrites that much of the chain, so a ticket is accepted after the beacon is public | The 180-second wait is longer than any gap between blocks measured on this chain (the longest was 136 seconds over 120,001 blocks). It cannot be ruled out, so it is stated |
| Once the 90-day refund opens, a buyer who can see they lost could send the refund instead of the draw | It needs the house's settlement program and every winner, each able to draw alone at any time, to leave the round untouched for a quarter |

Before 2026-09-30 the contract decided a round from the hash of a Kadena block instead; the two
rounds drawn that way are described on their [game pages](games/) with the block that decided each.
The change was an in-place upgrade, recorded in [`VERIFY.md`](VERIFY.md) §5.

The honest summary: **nobody can pick a winner, and what could stop or expose a draw is disclosed
with what limits it.** Separately, and above all of this, the admin keys can override the
contract's rules until it is frozen — see the box at the top.

## Two admin tiers

| tier | predicate | what it may do |
|---|---|---|
| admin | **any 2 of 3** keys | upgrade the module and freeze it permanently; **until frozen, hold module admin** — move pool money and rewrite any record in one transaction; redefine the admin keyset itself |
| operator | **any 1 of 3** | create raffles, set terms, schedule rounds, retire a raffle, add bonus — and **redefine the operator keyset itself**: any one of the three keys can replace the other two. Keysets live outside the module, so a freeze does not end this |

Neither tier can make the contract's own code choose a winner. The operator cannot move pool
money or change a round that is already selling.

Settling is **nobody's privilege**: drawing, and refunding a round that nobody drew for 90 days,
are calls anybody can make, and the contract gives the sender no say in the outcome. That
is why a bot can do it — see [SmartPacts/prize-draw-crank](https://github.com/SmartPacts/prize-draw-crank),
which is public so that anyone can run one.

## What this contract's code does not do

Every line below describes the deployed code. Until the contract is frozen, the admin keys can
override any of it (the box at the top).

- **It does not pick a winner.** No function lets anyone choose one; the decision is a drand beacon
  that has exactly one valid signature, verified on chain.
- **Every drawn round has a winner.** Winners are drawn from the tickets actually sold, and the
  whole fund is paid out — unfilled prize tiers merge into first place. A round that is refunded
  instead (the one case in the spec: nobody drew it for 90 days) has none.
- **It does not make you claim a prize.** Winners are paid inside the draw transaction. There is no
  claim step and nothing expires.
- **It does not take a fee larger than the sale.** The fee is a fraction below 1, frozen into each
  round when it opens, so re-terming a raffle can never reach money already staked.
- **It cannot be upgraded once frozen** — and freezing is one-way.

## Reporting a problem

See [SECURITY.md](SECURITY.md) — open a **GitHub security advisory** on this repository.

## Licence

Apache-2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
