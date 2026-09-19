# Prize Draw — what the contract does (technical)

The engineering statement of [`pact/modules/prize-draw.pact`](../pact/modules/prize-draw.pact), the
contract deployed on Kadena mainnet. [`PRIZE-DRAW-WHAT-IT-DOES.md`](PRIZE-DRAW-WHAT-IT-DOES.md) says
the same things in plain language.

**How to read it.** Every property names the tests that fail if it is violated — the labels are
the first argument of `expect` / `expect-failure` / `expect-that` in
[`pact/tests/`](../pact/tests/), and `pact/tests/run-tests.sh` runs them all. A statement with no
named test is marked as a claim. Functions are cited by name rather than line number, because
names do not drift. Where the words here and the code differ, the code is right — and please
[tell us](../SECURITY.md).

Deployed identity: namespace `n_48867b242317a0216a67f8c7ca26696b5878e0e3`, module `prize-draw`,
chain 2, module hash `r1ecwafNL89gBUcstQ5GY4edqGOXq3HMWied_rOOhaI` (the hash excludes comments;
[VERIFY.md](../VERIFY.md) checks the full source byte for byte).

## 1. Shape

One module, many games. A game (a "raffle" in the code) is a row of terms and a schedule for its
next round (the `raffle` schema); a round is a row that froze those terms and that schedule at its
**first ticket** (the `raffle-round` schema). Settlement never reads a live game term — every value
it uses was frozen into the round. Pinned by unit `TERMS-FROZEN-AT-OPEN`, `OPEN-*`, vision
`VISION-1..4`.

Roles and authority:

- **GOVERNANCE** — the admin keyset `<ns>.prize-draw-admin` (**2 of 3** keys): `initialize` once,
  upgrade, freeze. It also gates the load-time guard at the top of the file.
- **OPERATOR** — `<ns>.prize-draw-operator` (**any 1 of** the same 3 keys): `create-raffle`,
  `set-terms`, `schedule-round`, `retire-raffle`, `seed-raffle`. Cannot move player money, cannot
  upgrade, cannot reach a live round's frozen terms. Pinned by unit `OPERATOR-CANNOT-UPGRADE`,
  `AUTH-*`.
- **Buyers** — any non-module account. The first buyer of a round creates it and chooses nothing:
  the round's terms and instants are the game's as they stand. Pinned by unit `OPEN-*`.
- **Anyone** — `open-draw`, `draw`, `escape`, `claim-escape`, and recording blocks in
  `free.block-history`. The sender signs only for gas; every payout inside is installed by the
  contract for amounts it derives from stored rows.

There are no sealers, secrets, bonds, reveals or burns. The block alone decides.

**Pools.** One coin account per game, `m:<ns>.prize-draw:<id>`, guarded by a module guard
(`pool-guard`) — the permanent choice for a module meant to freeze. Every account a caller names
as a source or destination of money is refused if it is a module account (`validate-payer`),
because every module guard a module creates is the same authority. Pinned by unit
`TRUST-BOUNDARY-*`, `DRAW-REFUSES-POOL-PAYEE`, `POOL-ISOLATION-*`. *That a foreign module
composing this module's capabilities cannot spend a pool is pinned by an internal attack suite
that is not yet published; the public suites do not cover it.*

## 2. Terms and their bounds (`validate-terms`)

| term | bound | pinned by |
|---|---|---|
| price | ≥ 0.1, 12 decimals | unit `CREATE-*`, `TERMS-*` |
| rake (the fee) | 0 ≤ rake < 1, taken on ticket sales only | unit `CREATE-*`, `ZERO-FEE-*` |
| tiers | 1..10 shares, each > 0, summing to exactly 1.0 | unit `TIERS-*`, `TIERS-N` |
| max-tickets | 0 (uncapped) or ≤ 1,000,000; a numbered game needs > 0 | unit `RIFA-*`, `CREATE-*` |
| seed-cap | 0..100,000 | unit `SEED-N` |
| rounds-limit | ≥ 0; 0 runs forever | unit `ROUNDS-LIMIT-*`, `LIMIT2-*` |
| max-fund | > 0, ≤ 100,000, and ≥ seed-cap + price | unit `CEIL-*` |
| bounty-share | > 0, ≤ 1 of the fee | unit `CRANK-N*` |
| bounty-split | two integer weights [recorder drawer], each ≥ 0, not both zero | unit `CRANK-N*`, `BOUNTY2-*` |
| id | 1..32 chars, no `:` or `\|`, no character at or below the space (space, tab, newline, every C0 control), and a name coin will accept as this game's pool account (`validate-id`) | unit `CREATE-1..3f` |

`set-terms` additionally requires max-fund ≥ waiting bonus + bound bonus + price (the bonus
invariant, §6) and a rounds-limit the waiting bonus can still reach. Pinned by unit `STRAND-*`.
`MAX-ROUND-FUND` and `MAX-SEED-CAP` are deliberately wide rails; the operational ceiling is each
game's own `max-fund`.

### 2a. The schedule (`schedule-round`)

Dates are per **round**. The operator names the next round's three instants of the chain's clock —
sales open, sales close, draw — and that round's first ticket freezes them; until then the schedule
may be set again, and a schedule nobody buys into simply expires at its close. **Each round needs
its own `schedule-round`**: the first ticket consumes the schedule, and nothing re-arms it.

Bounds, checked two-sided in seconds because `diff-time` wraps silently: `opens-at` strictly after
the scheduling block's time and at most `MAX-LEAD-SECONDS` (365 days) ahead; `closes-at − opens-at`
in 600 s..365 days; `draws-at − closes-at` in 0..7 days; and a next round may not open before the
round now selling closes. The chain's clock is the **parent** block's timestamp, with about 30 s
granularity on mainnet. Pinned by unit `SCHED-*`, `TIME-PREV-*`, `EXPIRE-*`, vision `VISION-CAL-*`
(including `VISION-CAL-WRAP-*`: an instant past the int64 edge is refused on both sides).

## 3. A round's life

1. **First ticket** (`buy`). When no round is selling, a buy after the scheduled sales instant and
   before its close creates the round: terms and instants frozen from the game as they stand that
   moment, the whole waiting bonus bound to it, the schedule consumed, `ROUND-OPENED` emitted before
   `TICKETS-BOUGHT`. Refused on a retired game, a spent rounds-limit, no schedule, before the sales
   instant, or a schedule that already closed. Every later ticket joins while
   `opens-at ≤ clock < closes-at`; 1..50 per transaction; intake (ticket money plus the bound
   bonus) never above the round's `max-fund`; numbered picks range-checked and unique per round.
   Pinned by unit `OPEN-*`, `OPEN-N*`, `EXPIRE-*`, `TBUY-*`, `BUY-*`, `CEIL-*`, `RIFA-*`,
   `NUMBER-UNIQUE-PER-ROUND`.
2. **Open the draw** (`open-draw`), anyone, at or after `draws-at`. It writes
   `decide-height = height + DECIDE-DELAY (2)` exactly once — the first of three candidate blocks,
   none of which exists yet — and emits `DRAW-OPENED`. Until then nothing exists that could decide
   the round. Pinned by unit `ODRAW-*`, `DRAWNOW-*`, vision `VISION-BLOCK-*`.
3. **Decide.** The deciding height is the **lowest recorded** of `decide-height`, +1 and +2 in
   `free.block-history` (`decided-height`). That module is pinned by its code hash at import —
   `P3J_LK-Wivmuyw7SB7TzPmfj6t-GCtG3YnfHNAaU2UU`, the block record deployed on mainnet chain 2 — so
   the contract refuses to load against any other code under that name. A height is recordable only
   in the very next block, so the decider is final the moment it exists. Pinned by unit `DECIDE-*`,
   vision `VISION-INFLUENCE-*`. *That the contract refuses to load against an impostor block record
   is pinned by an internal must-fail suite that is not yet published.*
4. **Draw** (`draw`), anyone, the moment a candidate is recorded — there is no secret to protect,
   so no confirmations wait. `seed = hash(round key, block hash)` (`round-seed`); `k = min(tiers,
   tickets)` winning **tickets** are drawn without replacement (`draw-ranks`), so one account
   holding several tickets can win several prizes — uniform, and recomputable by anyone, with
   `preview` giving the same answer read-only. `fund = sales − fee + bonus` is paid to the winners
   inside the transaction: prizes 2..k take `floor(share × fund)` and prize 1 takes the exact
   remainder, so unfilled prizes merge into first place and nothing is left in the pool.
   `fee = rake × sales`; a `bounty-share` of the fee is split by the round's frozen weights between
   the block's recorder and whoever sent the draw; the rest of the fee goes to the revenue account.
   Payouts are aggregated per distinct account. Pinned by unit `DRAW-*`, `DRAWNOW-*`, `BOUNTY2-*`,
   `LOP-*`, `ALIAS-*`, `ONE-BUDGET-PER-DISTINCT-WINNER`, `FULL-FUND-PAID`, `ALWAYS-A-WINNER`,
   `ZREC-*`, `ALLREC-*`, worstcase `WORST-*`, vision `VISION-SIMPLE-*`.
5. **Escape** (`escape`), anyone, in exactly two cases: nobody opened the draw within
   `OPEN-DRAW-GRACE-SECONDS` (a day) of the draw instant, or no candidate was recorded (after
   `decide-height + 3`). Buyers are booked their stake plus their exact bonus share, and paid by
   `claim-escape` — anyone may send it, one account per transaction, and it pays only the account
   that bought the tickets. Indivisible dust goes to revenue; no fee is taken. Closed forever once
   a candidate is recorded. Pinned by unit `ESC2-*`, `ESCAPE-*`, `WEDGE-*`.

Two rounds of one game can be live at once: once a round's sales close, the next round's first
ticket may open beside it while it still awaits its draw. Both settle independently by
`(id, seq)`; `current` names the newer one. Pinned by unit `TIME-PREV-*`.

**Recompute a draw.** The seed is blake2b-256 of `prize-draw|<round key>|<deciding block hash>`,
read as a big-endian integer, modulo `DRAW-SEED-RANGE` (10^18); the round key is `<id>|<seq>`. For
each place *i* = 1..k: blake2b-256 of `<seed>|<round key>|<i>` as an integer, modulo
(tickets sold − *i* + 1), stepped past every ticket position already drawn, in ascending order,
gives the winning ticket's position, counting from 0 in the order tickets were sold. Worked
example on mainnet: [games/pilot-1.md](../games/pilot-1.md).

## 4. Money conservation

`pool-status`: `balance ≥ waiting bonus + bound bonus + owed + pending`, with equality for module
flows. Pinned by unit `CONS-*`, `POOL-ISOLATION-*`, `ESCAPE-TAKES-NO-FEE`, `ESCAPE-PAYS-ONLY-STAKE`,
revenue `REV-5/6`. `pool-status` aborts for a game nothing has been paid into (coin has no account
yet); readers treat that as an empty pool.

## 5. Where the fee goes

`initialize` names the revenue account once; it must exist, and it may be any account except one
of this module's own pools — including another module's guarded account. On mainnet it is SPT's
funding account, `m:n_48867b242317a0216a67f8c7ca26696b5878e0e3.SPT:SPT-funding`. It is published as
the `INITIALIZED` event and readable ever after through `get-revenue`, which returns `""` before
setup rather than aborting. Pinned by revenue `REV-*`, unit `INIT-*`.

## 6. Invariants that prevent locked money

- **Bonus invariant:** `max-fund ≥ waiting bonus + bound bonus + price` at every step — `seed-raffle`
  counts bound bonus against the cap, `set-terms` keeps the ceiling above both, and a round's first
  ticket only moves bonus from waiting to bound. Pinned by unit `STRAND-*`, `SEED-*`.
- **A bonus is one-way.** No function returns a bonus to whoever added it; it binds whole to the
  next round at its first ticket, and a one-off game refuses a bonus once its round has opened.
- **No auto-retire while a bonus waits or is bound:** the rounds-limit retires a game only when
  both are zero, and `retire-raffle` refuses while either is non-zero. Pinned by unit
  `ROUNDS-LIMIT-*`, `LIMIT2-*`, `STRAND-a1`, `STRAND-a3a`, `RETIRED-*`.
- **No game before `initialize`.** Pinned by unit `INIT-0`.
- **Every payout target is payable:** the draw's payee is validated; the block's recorder is paid
  only if the record names a non-empty, non-module account, else its share goes to the drawer. The
  module does not test that the recorder's account exists, and does not need to: block-history
  records the gas payer of the recording transaction, and a sender with no coin account cannot buy
  gas — an environment property, not a check in this module. Pinned by unit `NOSENDER-*`,
  `DRAW-REFUSES-*`, `DRAW-ABORTS-ON-UNPAYABLE-PAYEE`.

## 7. The fairness model, and its limits

Nobody can choose a winner: the seed is fixed by a block that did not exist when the round's
tickets were sold, at a height fixed by whoever opens the draw at the advertised instant, read from
an immutable record. What remains is disclosed rather than denied, each with what limits it:

- **A party recording blocks alone** could decline to record a candidate it dislikes and take the
  next — a best of three at most — or record none of the three and force a refund of the whole
  round. *What limits it:* recording is permissionless, two independent operators record mainnet
  chain 2 today, and a candidate recorded by either settles the round. A forced refund books the
  round's bonus to its buyers, so it costs the house the bonus rather than winning anything. Pinned
  by vision `VISION-INFLUENCE-*` and unit `ESC2-*` (the refund path).
- **A player who also mines** can discard a candidate block it mined whose hash loses, giving up
  the block reward (0.909283 KDA on chain 2 at height 7242783) for one more roll — measured at
  roughly double the chance even at a very small hashrate. It never chooses a winner. *What limits
  it:* the prize ceiling is published before any ticket is sold. A claim about the chain, not a
  property with a test.
- **The miner of the block after a candidate** can leave every record of it out of that block at no
  cost, so the next candidate decides. An independent recorder does not remove this: every
  recorder's record for a height goes through that same block. *What limits it:* it changes which
  block decides, never who wins, and all three candidates would have to be left out to force a
  refund. About 9% of mainnet heights go unrecorded, which is why the draw names three candidates.
  A claim about the chain, not a property with a test.

The settlement shares have no floor and no cap: `1.0 [1 0]` sends the whole crank share to the
recorder (unit `ALLREC-*`); `[0 1]` pays the recorder nothing (unit `ZREC-*`). The fee's
destination and these shares are protected by operator key custody, not by the contract.

**While the module is not frozen**, GOVERNANCE can publish a new version of it and can move money
out of any pool. Every property on this page describes the contract as deployed. Freezing ends that
power permanently.

## 8. Constants (frozen with the module)

`DECIDE-DELAY` 2 · `DECIDE-WINDOW` 3 · `MIN-SALES-SECONDS` 600 · `MAX-SALES-SECONDS` 31,536,000 ·
`MAX-DRAW-GAP-SECONDS` 604,800 · `MAX-LEAD-SECONDS` 31,536,000 · `OPEN-DRAW-GRACE-SECONDS` 86,400 ·
`EPOCH` 1970-01-01T00:00:00Z (means "not scheduled") · `MAX-TICKETS-PER-TX` 50 · `MAX-SUPPLY`
1,000,000 · `MAX-TIERS` 10 · `MIN-TICKET-PRICE` 0.1 · `MAX-ROUND-FUND` 100,000 · `MAX-SEED-CAP`
100,000 · `DRAW-SEED-RANGE` 10^18 · `PREC` 12.

## 9. Events

`INITIALIZED` (at setup, carrying the fee destination) · `RAFFLE-CREATED` · `RAFFLE-RETERMED` ·
`RAFFLE-RETIRED` · `RAFFLE-SCHEDULED` · `RAFFLE-SEEDED` · `ROUND-OPENED` (at the first ticket: the
three instants, frozen price, rake and bonus) · `TICKETS-BOUGHT` · `DRAW-OPENED` (the first candidate
height) · `DRAWN` (with the deciding block) · `WINNER-PAID` · `FEE-PAID` · `BOUNTY-PAID` (roles
`record` and `draw`) · `ESCAPED` · `ESCAPE-PAID`. Pinned by unit `CRANK-E*`, `OPEN-*`.

## 10. Evidence

**Tests.** `pact/tests/run-tests.sh` runs five suites — unit 444, vision 90, worst case 38,
revenue 10 and frozen 11 printed assertions (593 in all; 709 assertion forms in the files) — after
a static gate over every file and a check that no `expect-failure` was written with too few
arguments to assert why it failed. Each suite is scored by its exit code, not by searching its
output. CI runs the same command on every push.

**Gas** (the worst-case suite, REPL): schedule a round 145 · first ticket 796 · 50-ticket purchase
3,094 · open the draw 125 · draw at ten prizes with thirteen distinct payees 3,039 · escape 392 ·
refund one account 376 — all far below the 150,000-per-transaction limit.

**On mainnet** (chain 2), every figure read from the chain:

| what | block | request key | gas |
|---|---:|---|---:|
| deploy | 7240922 | `5Bc0-gs7RFx-HBuIIVXVAZZ_05OWsNe1XhixZm8Dd1s` | 60,992 |
| initialize | 7240942 | `TP8zVpAtVFRwtbz0kvz_j2TafiL_JIVAKaXOeAX71H4` | 225 |
| the pilot, created | 7241405 | `FaV8hcyIGjsQsw0sDzl1wEH7F9FJU56VhuCO6assmQ8` | — |
| the pilot, draw opened | 7241465 | `WkSe5S98FeBXXtmF35YwlNxBpFtvNRvp8LLLZIbVvlk` | 212 |
| the pilot, drawn and paid | 7241470 | `GTevqUrZbdtq6A0c9bR9f0CH-H2WrtPjAadDk79EXMk` | 1,019 |
| the Grand Opening, created with its schedule and bonus | 7243001 | `PsZtiJ4On1jwiODmzHpLdZcMLWc90Ccsddk54if1CgM` | 776 |

The pilot's stored seed, `968439115421315306`, is reproduced exactly by the recipe in §3 from the
hash of block 7241467 ([games/pilot-1.md](../games/pilot-1.md)). Its deciding block was mined 2 min
13 s after the draw instant, and the round was settled by the public settlement program without
anyone acting by hand.

## 11. Known gaps and non-properties

- Static typechecking is not supported for this module (untyped `object` values in the payout
  aggregation and the views); every such path is exercised by the suites.
- Instants are shown to the second in messages and events; a sub-second instant is enforced exactly
  but printed truncated.
- A round freezes the game's terms as they stand at its first ticket, so an operator re-term ordered
  earlier in the same block reaches that round. `ROUND-OPENED` carries the frozen price and rake,
  so a reader can see what the round actually froze.
- `pool-guard` is public, so anyone can create a coin account guarded by a game's module guard and
  then spend it only into that game's tickets, never out — a self-inflicted lock on the actor's own
  money, which moves nobody else's. Not refused.
- Two properties rest on internal attack suites that are not yet published: foreign-module access
  to a pool (§1) and the load-time refusal of an impostor block record (§3.3).
- Not built: a numbered game in which an unsold number can win, a consolation for non-winners, and
  prizes that are goods.
