# Prize Draw — what the contract does (technical)

The engineering statement of [`pact/modules/prize-draw.pact`](../pact/modules/prize-draw.pact), the
contract deployed on Kadena mainnet. [`PRIZE-DRAW-WHAT-IT-DOES.md`](PRIZE-DRAW-WHAT-IT-DOES.md) says
the same things in plain language.

**How to read it.** Every property names the tests that fail if it is violated — the labels are
the first argument of `expect` / `expect-failure` / `expect-that` in
[`pact/tests/`](../pact/tests/), and `pact/tests/run-tests.sh` runs all seven suites. A statement
with no named test is marked as a claim. Functions are cited by name rather than line number, because names do not drift. Where the
words here and the code differ, the code is right — and please [tell us](../SECURITY.md).

Deployed identity: namespace `n_48867b242317a0216a67f8c7ca26696b5878e0e3`, module `prize-draw`,
chain 2, module hash `iOQQPMLIE-2igYcP1AX3qWqVeNImhjVRi4s33CVPiEU` since the second upgrade in place, of
2026-10-02 (block 7279034, request key `73n0HFjarozPhK6TMrtYTZyJHZ8SUoYTshBtMumNSdQ`). Before it:
`ROPuVZ3uzJ2LOLdW-18obFpmmg7XehIV_sQ5H7Taw-s` from the first upgrade of 2026-09-30 (block 7274939,
request key `qJ_h9Bl4iYHrTk_2PVc37a-Ua82e4lu11pOswqzwZfg`), and `r1ecwafNL89gBUcstQ5GY4edqGOXq3HMWied_rOOhaI`. The hash excludes comments;
[VERIFY.md](../VERIFY.md) checks the stored `(module …)` form byte for byte. The module imports one
other contract, the beacon verifier `n_48867b242317a0216a67f8c7ca26696b5878e0e3.drand`, by its full
name and pinned to its code hash `Y07t-duJmkXkcGth0TfBRg3ThbNR-uh9PdNUd1MKHBQ`; its source is
[`pact/vendor/drand.pact`](../pact/vendor/drand.pact), its governance is `(enforce false …)`, so it
can never be upgraded, and it holds no tables, no capabilities and no funds.

**What the upgrade changed.** Under the previous version a round was decided by the hash of a
Kadena block: anyone opened the draw at the draw instant, that fixed three candidate blocks, and
the first of them recorded in the `free.block-history` contract decided the round, with part of
the fee paid to whoever had recorded it. Two rounds were drawn that way — `pilot-1` round 1 by
block 7241467 and `grand-opening` round 1 by block 7266386
([games/](../games/)). Their rows keep a **block height** in the `decide-height` and
`deciding-block` fields, and the fee-split field `bounty-split` is kept on every row for the same
reason (§2). Under the current version those two fields hold a **drand round** for
every round opened after the upgrade; `preview`, `draw-status`, `draw` and `escape` refuse a
settled round, so the old values are never read as drand rounds. No schema changed. Pinned by
upgrade `OLD-1`..`OLD-14`, `PREVIEW-OLD-a`, `PREVIEW-OLD`, `NEW-1`..`NEW-4` (§10).

## 1. Shape

One module, many games. A game (a "raffle" in the code) is a row of terms and a schedule for its
next round (the `raffle` schema); a round is a row that froze those terms and that schedule at its
**first ticket** (the `raffle-round` schema). Settlement pays and decides only by values frozen
into the round; the only live values it reads are bookkeeping — the game's `active`,
`rounds-limit` and waiting bonus, to retire a finished game, and the revenue account. Pinned by unit
`TERMS-FROZEN-AT-OPEN`, `OPEN-*`, vision `VISION-1a`..`VISION-4b3`.

Roles and authority:

- **GOVERNANCE** — the admin keyset `<ns>.prize-draw-admin` (**2 of 3** keys): `initialize` once,
  upgrade, freeze. It also gates the load-time guard at the top of the file. 🔴 **Until the module
  is frozen, GOVERNANCE is also module admin:** after `acquire-module-admin`, one transaction signed
  by 2 of the 3 keys can move money out of any pool and rewrite any row of any table — a selling
  round's terms, a ticket's owner, the revenue account — with no new code and no change to the
  module hash (measured on mainnet by read-only dry run before the upgrade: a ticket's owner
  rewritten and 1 KDA moved out of the Grand Opening pot with two keys; one key refused). Pinned for
  pools by unit `TRUST-BOUNDARY-1`, `TRUST-BOUNDARY-2`; that a freeze ends it is not pinned by a
  public test (a claim, checked by hand in the REPL). The same 2 keys can redefine the admin
  keyset. The upgrade itself needs this keyset and nothing else: upgrade `UPG-1`, `UPG-1b`,
  `UPG-2`, `UPG-2b`.
- **OPERATOR** — `<ns>.prize-draw-operator` (**any 1 of** the same 3 keys): `create-raffle`,
  `set-terms`, `schedule-round`, `retire-raffle`, `seed-raffle`. Cannot move player money, cannot
  upgrade, cannot reach a live round's frozen terms or its pinned drand round. Pinned by unit
  `OPERATOR-CANNOT-UPGRADE`, `OPERATOR-1`, `AUTH-1`..`AUTH-3`, `POOL-ISOLATION-3`, `DECIDE-4`,
  vision `VISION-INFLUENCE-1i`..`VISION-INFLUENCE-1k`. **Any one of the three keys can also
  redefine the operator keyset** — replacing the other two — because redefining an existing keyset
  checks only that keyset's own rule (measured on mainnet by read-only dry run). Keysets live
  outside the module, so a freeze does not end this; a claim about the platform, not a property
  with a test here.
- **Buyers** — any account whose name does not start with `m:`. The first buyer of a round creates
  it and chooses nothing: the round's terms, instants and drand round are the game's as they stand.
  Pinned by unit `OPEN-*`, `BUY-N7`.
- **Anyone** — `draw`, `preview`, `draw-status`, `decidable`, `ticket-terms`, `escape`,
  `claim-escape`. The sender
  signs only for gas; every payout inside is installed by the contract for amounts it derives from
  stored rows. Pinned by unit `BEACON-3`, `ESCAPE-2`, vision `VISION-INFLUENCE-2d`.

There are no sealers, secrets, bonds, reveals, burns or recorders. The pinned drand beacon alone
decides.

**Pools.** One coin account per game, `m:<ns>.prize-draw:<id>`, guarded by a module guard
(`pool-guard`) — the permanent choice for a module meant to freeze. Every account a caller names
as a source or destination of money is refused if its name starts with `m:` (`validate-payer`),
because every module guard a module creates is the same authority. The check is by NAME: a
module-guarded account under any other name is not recognised (§11). Pinned by unit
`TRUST-BOUNDARY-1`, `DRAW-REFUSES-POOL-PAYEE`, `DRAW-REFUSES-MODULE-PAYEE`, `BUY-N7`,
`POOL-ISOLATION-1`..`POOL-ISOLATION-4`; that pool addresses survive the upgrade by upgrade `OLD-6`.
*That a foreign module composing this module's capabilities cannot spend a pool is pinned by an
internal attack suite that is not yet published; the public suites do not cover it.*

## 2. Terms and their bounds (`validate-terms`)

| term | bound | pinned by |
|---|---|---|
| price | ≥ 0.1, 12 decimals | unit `CREATE-*`, `TERMS-*` (the ≥ 0.1 bound; the 12-decimal limit is not pinned by a test) |
| rake (the fee) | 0 ≤ rake < 1, 12 decimals, taken on ticket sales only | unit `CREATE-6`, `ZERO-FEE-*` (the bounds; the 12-decimal limit is not pinned) |
| tiers | 1..10 shares, each > 0, summing to exactly 1.0 | unit `CREATE-9`..`CREATE-12` (the bounds); `TIERS-*` test how a fund is split |
| max-tickets | 0 (uncapped) or ≤ 1,000,000; a numbered game needs > 0 | unit `CREATE-13`, `CREATE-14`, `RIFA-*` (the lower bound, ≥ 0, is not pinned) |
| seed-cap | 0..100,000, 12 decimals | unit `CREATE-15` (the upper bound; the lower bound and the decimal limit are not pinned) |
| rounds-limit | ≥ 0; 0 runs forever | unit `CREATE-15b` (the bound); `ROUNDS-LIMIT-*`, `LIMIT2-*` (retiring) |
| max-fund | > 0, ≤ 100,000, and ≥ seed-cap + price | unit `CEIL-N1`..`CEIL-N4` |
| bounty-share (the crank share) | > 0, ≤ 1 of the fee, 12 decimals | unit `CRANK-N1`..`CRANK-N3`, `CRANK-P1`, `CRANK-P1c` |
| bounty-split | two integer weights, each ≥ 0, not both zero — **validated, stored, frozen into each round, and read by no settlement** (below) | unit `CRANK-N4`..`CRANK-N7`, `CRANK-N10`, `CRANK-N11`, `CRANK-P1b`, `LOP-0`, `LOP-1`, `LOP-2` |
| id | 1..32 chars, no `:` or `\|`, no character at or below the space (space, tab, newline, every C0 control), and a name coin will accept as this game's pool account (`validate-id`) | unit `CREATE-1`..`CREATE-3f` |

`bounty-split` is retained from the previous version, where it divided the crank share between the
block's recorder and the drawer. A drand round has no recorder, so the whole crank share now goes
to whoever sends the draw, whatever the weights say; the field stays because rows written before
the upgrade hold it and adding or removing a field on a live table fails at first access, not at
load. Pinned by unit `LOP-2`, `LOP-4`, `LOP-7`, `ZREC-2`, `ZREC-4`, `ALLREC-1`, `ALLREC-4`,
`BOUNTY2-1`, `BOUNTY2-Z2`, `BOUNTY2-R2`, `BOUNTY2-T2`, `BOUNTY-5`.

`set-terms` additionally requires max-fund ≥ waiting bonus + bound bonus + price (the bonus
invariant, §6) and a rounds-limit the waiting bonus can still reach. The rounds-limit half is
pinned by unit `STRAND-*`; the ceiling half is not pinned by any test (removing it leaves the unit,
vision, worst-case and revenue suites green — measured on this working tree) — a claim.
`MAX-ROUND-FUND` and `MAX-SEED-CAP` are deliberately wide rails; the operational ceiling is each
game's own `max-fund`.

### 2a. The schedule (`schedule-round`)

Dates are per **round**. The operator names the next round's three instants of the chain's clock —
sales open, sales close, draw — and that round's first ticket freezes them; until then the schedule
may be set again, and a schedule nobody buys into simply expires at its close. **Each round needs
its own `schedule-round`**: the first ticket consumes the schedule, and nothing re-arms it. The
draw instant also fixes which drand beacon decides the round (§3.2): `drand-round-for` is public
and pure, so anyone can compute a round's beacon from its published schedule.

Bounds, checked two-sided in seconds because `diff-time` wraps silently: `opens-at` strictly after
the scheduling block's time and at most `MAX-LEAD-SECONDS` (365 days) ahead; `closes-at − opens-at`
in 600 s..365 days; `draws-at − closes-at` in 0..7 days (so the draw instant is never before the
close); and a next round may not open before the round now selling closes. The chain's clock is the
**parent** block's timestamp, with about 30 s granularity on mainnet. Pinned by unit `SCHED-*`,
`SCHED-B*`, `SCHED-N*`, `TIME-PREV-*`, `EXPIRE-*`, vision `VISION-CAL-*` (including
`VISION-CAL-WRAP-*`: an instant past the int64 edge is refused on both sides).

## 3. A round's life

1. **First ticket** (`buy`). When no round is selling, a buy after the scheduled sales instant and
   before its close creates the round: terms and instants frozen from the game as they stand that
   moment, the whole waiting bonus bound to it, the schedule consumed, the drand round pinned
   (next step), `ROUND-OPENED` emitted before `TICKETS-BOUGHT`. Refused on a retired game, a spent
   rounds-limit, no schedule, before the sales instant, or a schedule that already closed. Every
   later ticket joins while `opens-at ≤ clock < closes-at`; 1..50 per transaction; intake (ticket
   money plus the bound bonus) never above the round's `max-fund`; numbered picks range-checked and
   unique per round. Pinned by unit `OPEN-*`, `OPEN-N*`, `EXPIRE-*`, `TBUY-*`, `BUY-*`, `CEIL-*`,
   `RIFA-*`, `NUMBER-UNIQUE-PER-ROUND`, `FUND-CAP-*`, `FSCHED-*`.

   **Every purchase states the round it was signed for.** `buy id account count picks expect`
   takes `expect`, which must equal `terms-digest` of the round the ticket lands in: a hash over
   the round's number and the ten values a round freezes for its buyers — price, fee, tiers,
   numbered, supply, prize ceiling, crank share (the four amounts floored to 12 decimals, so equal
   amounts have one digest however they were typed) and the three instants (through their text at
   microsecond precision). It is checked for a first ticket before its round row is inserted, and
   for every ticket against the round row before anything is paid; a mismatch aborts with "this is
   not the round, or not the terms, this ticket was signed for — read the game again" and writes
   nothing. So a re-term or a re-schedule that lands ahead of a purchase, a window re-opened at its
   close, and a late purchase that would have become the next round's first ticket all end in a
   refused purchase. `ticket-terms id` is the read-only view a client takes the digest from: the
   round a ticket bought now would land in, selected as `buy` selects it, with `on-sale` (by the
   clock, the game's `active` flag and its rounds-limit — not by tickets or ceiling left). The
   bonus is not in the digest: it can only be added. A digest computed inside the purchase
   transaction always matches and protects nothing — a client states the digest of what it showed.
   Pinned by unit `EXPECT-0`..`EXPECT-5`, `EXPECT-N1`..`EXPECT-N14`, `EXPECT-GOLD`, `EXPECT-DEC`,
   `EXPECT-SUBSEC`, `ONSALE-1`..`ONSALE-5c`, vision `VISION-EXPECT-1`..`VISION-EXPECT-7`, upgrade2
   `U2-GAP`, `U2-EXPECT`, `U2-EXPECT-b`, `U2-JOIN`, `U2-JOIN-N`, `U2-TERMS`.
2. **The pin.** At that first ticket the round writes `decide-height`, the number of the drand
   round that will decide it: `drand-round-for(draws-at) = round-at(draws-at +
   DRAND-MARGIN-SECONDS)`, with `DRAND-MARGIN-SECONDS` a constant of 180 s and `round-at` the
   verifier's function returning the drand round published at or before the instant it is given.
   drand `evmnet` publishes every 3 s, so the pinned beacon is published 177 to 180 s after the draw
   instant — after sales closed, after the draw instant, and after the last ticket could have been
   mined: a ticket needs the parent block's time before `closes-at`, and `closes-at ≤ draws-at`. The
   pin is written once and read by nothing that can change it: no re-schedule, re-term, later
   ticket, retire or draw of another round touches it. Two rounds that share a draw instant pin the
   same drand round and still get different seeds, because the round key is bound into the seed.
   Pinned by unit `DECIDE-1`, `DECIDE-1b`, `DECIDE-1c`, `DECIDE-2`, `DECIDE-3`, `DECIDE-4`,
   `DECIDE-4b`, `BUY-2`, `BUY-9`, `SCHED-3b`, `TWIN-1`..`TWIN-5`, `OPEN-N3`..`OPEN-N3c` (an
   unscheduled game reports that, never the verifier's genesis refusal), vision `VISION-1c`,
   `VISION-CAL-3b2`, `VISION-CAL-6b`, `VISION-INFLUENCE-0`, `VISION-INFLUENCE-1h`,
   `VISION-INFLUENCE-4f`, `VISION-INFLUENCE-5b`..`VISION-INFLUENCE-5d`, worst case `WORST-1c`,
   `WORST-2R2`, upgrade `UPG-3`, `NEW-1`.
3. **The beacon is due.** Nothing has to be opened or recorded. `decidable` is true from the
   second the chain's clock reaches `time-of-round(decide-height)` — the instant drand publishes the
   pinned round — while the round is still selling (that is, unsettled); it is false for a settled
   round and aborts for a round that does not exist. `draw-status` reports, for an unsettled round,
   the pinned drand round, when drand publishes it, whether that moment has passed, and
   `escape-from`, the instant after which the round could escape; for a settled round it refuses
   and points at `get-round`. Pinned by unit `DRAW-0`, `DRAW-0b`, `DRAW-1c`, `DECIDE-5`,
   `DECIDE-8`, `BEACON-N1`, `BEACON-N2`, `BEACON-N2b`, `BEACON-0`, `BEACON-0b`, `BEACON-1`,
   `BEACON-1b`, `BEACON-N3`, `BEACON-4`, `DRAWNOW-0`, `DRAWNOW-1`, `DRAW-STATUS-N1`,
   `DRAW-STATUS-2`, `EARLY-0`, worst case `WORST-2a`, `WORST-2d`, vision `VISION-BLOCK-0`..
   `VISION-BLOCK-1b`, `VISION-CAL-5b`, `VISION-CAL-6`, `VISION-SIMPLE-2`.
4. **Draw** (`draw id seq payee sig-hex`), anyone, once drand has published the beacon. It has no
   time check of its own and needs none: a beacon drand has not published yet does not exist, and
   nothing else verifies. `round-seed` calls the verifier's `verified-seed`, which **aborts** unless
   `sig-hex` is drand's genuine signature for exactly the pinned round — a signature for the
   previous or the next round, one hex digit altered, a truncated or lengthened one, a non-hex
   string, the point at infinity and a non-canonical encoding of the genuine point (a coordinate at
   or above the field modulus) are all refused, and a refused draw writes nothing; the upper-case
   spelling of the genuine signature gives the same seed as the lower-case one, so the hex case is
   not a re-roll. `k = min(tiers, tickets)` winning **tickets** are drawn without replacement
   (`draw-ranks`), so one account holding several tickets can win several prizes — uniform, and
   recomputable by anyone, with `preview` giving the same answer read-only from the moment the
   beacon is public. `fund = sales − fee + bonus` is paid to the winners inside the transaction:
   prizes 2..k take `floor(share × fund)` and prize 1 takes the exact remainder, so unfilled prizes
   merge into first place and nothing is left in the pool. `fee = rake × sales`, floored to 12
   decimals; `bounty-share` of the fee goes whole to `payee` — validated, never an `m:` account —
   and the rest of the fee to the revenue account. Payouts are aggregated per distinct account.
   Block height, previous block hash, clock and sender change nothing: two previews under different
   chain data agree, and whoever sends the draw chooses nothing. Pinned by unit `DRAW-1c`,
   `DRAW-3`..`DRAW-8`, `DRAW-N1`..`DRAW-N3`, `DRAND-0`..`DRAND-3b`, `DRAND-N1`..`DRAND-N8`,
   `DRAND-P-N1`..`DRAND-P-N6`, `EARLY-1`, `EARLY-2`, `PREVIEW-1`..`PREVIEW-8b`, `PREVIEW-N1`,
   `PREVIEW-N2`, `VERIFY-0`..`VERIFY-3`, `BLIND-1`..`BLIND-5`, `BEACON-2`, `BEACON-3`,
   `DRAWNOW-2`..`DRAWNOW-5`, `BOUNTY-1`..`BOUNTY-6`, `BOUNTY-FROM-FEE-NOT-FUND`, `LOP-*`,
   `ALIAS-1`..`ALIAS-6`, `SOLO-1`..`SOLO-2`, `ONE-BUDGET-PER-DISTINCT-WINNER`, `FULL-FUND-PAID`,
   `ALWAYS-A-WINNER`, `RANKS-DISTINCT-AND-IN-RANGE`, `RANKS-1`..`RANKS-3`, `TIERS-*`,
   `ZERO-FEE-*`, `ZREC-*`, `ALLREC-*`, `BOUNTY2-*`, `FRZ-*`, `TIME-PREV-2`..`TIME-PREV-2c` (each
   round verifies against its OWN pinned round), worst case `WORST-3`..`WORST-9`, `WORST-3d`..
   `WORST-3g`, vision `VISION-BLOCK-2`..`VISION-BLOCK-4c`, `VISION-5`..`VISION-9`,
   `VISION-SIMPLE-*`, `VISION-INFLUENCE-1a`..`VISION-INFLUENCE-1c`, `VISION-INFLUENCE-2`..
   `VISION-INFLUENCE-3b`, `VISION-INFLUENCE-4e`, revenue `REV-4`, `REV-4b`, frozen `FROZEN-4b`,
   `FROZEN-5`, `FROZEN-5b`, upgrade `NEW-2`, `NEW-3`.
5. **Escape** (`escape`), anyone, in exactly one case: nobody drew the round and
   `diff-time(now, time-of-round(decide-height)) > ESCAPE-AFTER-SECONDS` — strictly more than 90
   days (7,776,000 s) after the instant the pinned beacon was published. At exactly 90 days it is
   refused, and the message names the instant. Until an escape lands, a draw still settles the round
   normally, so an escape can never overturn a round anybody drew, and a drawn round can never
   escape. Buyers are booked their stake plus their exact per-ticket bonus share (`floor(bonus /
   tickets)` at 12 decimals), and paid by `claim-escape` — anyone may send it, one account per
   transaction, once, and it pays only the account that bought the tickets. Indivisible dust of the
   floor goes to revenue; no fee is taken. An escaped round counts against the game's rounds-limit.
   Pinned by unit `ESCAPE-0`, `ESCAPE-N1`..`ESCAPE-N8`, `ESCAPE-2`..`ESCAPE-8`,
   `ESCAPE-TAKES-NO-FEE`, `ESCAPE-PAYS-ONLY-STAKE`, `ESCAPE-COUNTS-AS-A-ROUND`, `ESCAPE-N0`,
   `PREVIEW-ESC`, `ESC2-A-*`, `ESC2-B-*`, `DECIDE-N4`, `DRAWNOW-N0`..`DRAWNOW-N4`,
   `NO-CLAIM-ON-A-DRAWN-ROUND`, worst case `WORST-ESC-0`..`WORST-ESC-5`, revenue `REV-6b`,
   `REV-7`, `REV-8`, vision `VISION-CAL-5e`, `VISION-INFLUENCE-1d`, `VISION-INFLUENCE-1e`,
   `VISION-INFLUENCE-4c`, `VISION-INFLUENCE-4d`, `VISION-SIMPLE-3c`, `VISION-SIMPLE-3d`.

Two rounds of one game can be live at once: once a round's sales close, the next round's first
ticket may open beside it while it still awaits its beacon. Both settle independently by
`(id, seq)`; `current` names the newer one. Pinned by unit `TIME-PREV-*`.

**A payee that cannot receive** (a well-formed account that does not exist) aborts the draw at
coin's transfer and writes nothing; the round is then drawn with a payee that can. Pinned by unit
`DRAW-REFUSES-MALFORMED-PAYEE`, `DRAW-REFUSES-BAD-CHARSET-PAYEE`, `DRAW-ABORTS-ON-UNPAYABLE-PAYEE`,
`WEDGE-1`, `WEDGE-2`.

**Recompute a draw.** Take the round key `<id>|<seq>` and the round's stored `decide-height` (the
drand round). Fetch that round's beacon from drand `evmnet` (chain hash
`04f1e9062b8a81f848fded9c12306733282b2727ecced50032187751166ec8c3`); its signature is 64 bytes, the
x and y coordinates of a BN254 G1 point, 32 bytes each. Then, exactly as `verified-seed` does after
verifying it: `hash` (blake2b-256, base64url) of the string
`drand|prize-draw|<id>|<seq>|<drand round>|<x>|<y>`, with x and y as decimal integers reduced
modulo the field prime `P`, decoded as an integer with `str-to-int 64`, then modulo
`DRAW-SEED-RANGE` (10^18) in `round-seed`. For each place *i* = 1..k: blake2b-256 of
`<seed>|<round key>|<i>` as an integer, modulo (tickets sold − *i* + 1), stepped past every ticket
position already drawn, in ascending order, gives the winning ticket's position, counting from 0 in
the order tickets were sold (`draw-candidate`, `lift`, `draw-ranks`). A drawn round's stored
`draw-seed` and `ranks` equal this recomputation. Pinned by unit `VERIFY-1`..`VERIFY-3`,
`PREVIEW-8`, `DRAWNOW-4b`, vision `VISION-BLOCK-4`, `VISION-BLOCK-4b`, `VISION-INFLUENCE-4e`.
The recipe for the two rounds drawn before the upgrade was different — blake2b-256 of
`prize-draw|<round key>|<deciding block hash>` — and is worked through in
[games/pilot-1.md](../games/pilot-1.md) and [games/grand-opening.md](../games/grand-opening.md).

## 4. Money conservation

`pool-status`: `balance ≥ waiting bonus + bound bonus + owed + pending`, with equality for module
flows. Pinned by unit `CONS-1`..`CONS-3`, `POOL-ISOLATION-*`, `ESCAPE-TAKES-NO-FEE`,
`ESCAPE-PAYS-ONLY-STAKE`, revenue `REV-5`, `REV-6`, worst case `WORST-7`, `WORST-3f`,
`WORST-ESC-5`, upgrade `NEW-4`. `pool-status` aborts for a game nothing has been paid into (coin
has no account yet); readers treat that as an empty pool.

## 5. Where the fee goes

`initialize` names the revenue account once; it must exist, and it may be any account except one
of this module's own pools — including another module's guarded account. On mainnet it is SPT's
funding account, `m:n_48867b242317a0216a67f8c7ca26696b5878e0e3.SPT:SPT-funding`. It is published as
the `INITIALIZED` event and readable ever after through `get-revenue`, which returns `""` before
setup rather than aborting. Pinned by revenue `REV-*`, unit `INIT-*`, vision
`VISION-INFLUENCE-1f`; that it survives the upgrade by upgrade `OLD-8`.

## 6. Invariants that prevent locked money

- **Bonus invariant:** `max-fund ≥ waiting bonus + bound bonus + price` at every step — `seed-raffle`
  counts bound bonus against the cap, `set-terms` keeps the ceiling above both, and a round's first
  ticket only moves bonus from waiting to bound. Pinned by unit `STRAND-*`, `SEED-*`, except the
  `set-terms` ceiling check (§2), which no test pins.
- **A bonus is one-way.** No function returns a bonus to whoever added it; it binds whole to the
  next round at its first ticket, and a one-off game refuses a bonus once its round has opened.
  Pinned by unit `SEED-BOUND-AT-OPEN`, `SEED-BOUND-AT-SETTLEMENT`, `SEED-REFUSED-AFTER-SALES-CLOSE`,
  `SEED-REFUSED-ON-LAST-ROUND`, `SEED-REFUSED-ON-RETIRED-RAFFLE`.
- **No auto-retire while a bonus waits or is bound:** the rounds-limit retires a game only when
  both are zero, and `retire-raffle` refuses while either is non-zero. Pinned by unit
  `ROUNDS-LIMIT-*`, `LIMIT2-*`, `STRAND-a1`, `STRAND-a3a`, `RETIRED-*`.
- **No game before `initialize`.** Pinned by unit `INIT-0`.
- **Every payout target is payable:** the draw's payee is validated before anything moves, and a
  payee coin cannot credit aborts the whole draw, which is then sent again with another payee
  (§3). Escape refunds go only to accounts that bought tickets, which `validate-payer` admitted at
  the buy. Pinned by unit `DRAW-REFUSES-*`, `DRAW-ABORTS-ON-UNPAYABLE-PAYEE`, `WEDGE-*`,
  `ESCAPE-N7`.
- **No round the current code cannot settle.** A round opened by the previous version and left
  unsettled would have been stuck (draw never opened: `decide-height` 0, which the verifier
  refuses, so neither draw nor escape) or escapable at once (draw opened: a block height read as a
  long-past drand round). The upgrade transaction's first form,
  [`ops/mainnet-deploy/upgrade-precondition.pact`](../ops/mainnet-deploy/upgrade-precondition.pact),
  aborts the whole transaction — leaving the old module exactly as it was — if any game holds
  pending sales, if any active game still has a schedule it could open a round from before the
  upgrade lands, or if it reads zero games; both games on mainnet were drawn and retired before
  it. Pinned by upgrade `PRE-1`..`PRE-3`, `PRE-OK`, `HAZARD-1`..`HAZARD-5`.

## 7. The fairness model, and its limits

Under the contract's rules nobody can choose a winner: the seed is fixed by a drand beacon that is
published 177 to 180 s after the draw instant, for a round number fixed at the first ticket, and
exactly one valid signature exists for that round. Whoever sends the draw, at whatever height, hash,
clock or sender, gets the winners the beacon fixed; a forged, altered, re-encoded or wrong-round
signature aborts; nothing the house, a buyer or a Kadena miner produces after the round's first
ticket goes into the seed. (The
admin override in §1 sits outside these rules until the module is frozen.) Pinned by vision
`VISION-BLOCK-*`, `VISION-INFLUENCE-*`, `VISION-CAL-5`..`VISION-CAL-6b`, unit `BLIND-*`,
`DRAND-*`, `TWIN-*`. What the contract cannot rule out is disclosed, each with what limits it:

- **drand stops publishing.** The pinned beacon then never exists and the round cannot be drawn.
  *What limits it:* after 90 days anyone escapes the round and every buyer is refunded stake plus
  bonus share, with no fee taken (§3.5). If the `evmnet` chain were retired for good, every game
  would have to be run on a redeployed contract pinned to a new verifier; the verifier's key is not
  admin-swappable, on purpose — whoever could swap the key could choose the outcome. Pinned by unit
  `ESC2-*`, `ESCAPE-*`, vision `VISION-INFLUENCE-1d`; the retirement case is a claim.
- **A threshold of drand's operators acting together** could learn a beacon before it is
  published. They still could not choose it: the signature for a round is unique. A claim about
  drand, not a property with a test.
- **A chain halt, or a reorg deeper than the margin, at a round's close.** A ticket is accepted
  while the parent block's time is before `closes-at` and is mined some real time later; the 180 s
  margin is what keeps the beacon unpublished until after that. A halt longer than the margin
  spanning a close, or a miner rewriting more than 180 s of the chain from before the close, exposes
  the one round open at that moment: a ticket could then be bought with the beacon public. The
  contract's comment cites a measurement of block gaps on chain 2 that is not in this repository.
  A claim about the chain, not a property with a test.
- **A losing buyer, once the escape opens.** A beacon is public the moment drand publishes it, so
  after 90 days a buyer who can see they lost could send the escape rather than the draw. *What
  limits it:* the escape opens only after the house's settlement program and every winner, each
  able to draw alone and each able to see the beacon, have left the round for a quarter; until an
  escape lands, the draw still settles. Pinned by unit `ESCAPE-N4`, `ESCAPE-2`, `ESC2-A-N2`,
  `ESC2-B-N1`, `ESC2-A-1`, `ESC2-B-1`.
- **The admin override**, until the freeze (§1): unchanged by the upgrade.

The crank share is bounded (`bounty-share` > 0 and ≤ 1 of the fee) and goes whole to the drawer;
`1.0` sends the whole fee to whoever draws and nothing to revenue (unit `ALLREC-2`, `ALLREC-7`).
The share is protected by operator key custody, not by the contract; the fee destination can be
changed only through the admin override.

**While the module is not frozen**, GOVERNANCE can publish a new version of it — as it did on
2026-09-30 — and, as module admin, move money out of any pool and rewrite any stored row (§1).
Every property on this page describes the contract as deployed and is subject to that. Freezing
ends that power permanently; the operator keyset's ability to redefine itself is not ended by a
freeze.

## 8. Constants (frozen with the module)

`DRAND-MARGIN-SECONDS` 180 · `ESCAPE-AFTER-SECONDS` 7,776,000 (90 days) · `MIN-SALES-SECONDS` 600 ·
`MAX-SALES-SECONDS` 31,536,000 · `MAX-DRAW-GAP-SECONDS` 604,800 · `MAX-LEAD-SECONDS` 31,536,000 ·
`EPOCH` 1970-01-01T00:00:00Z (means "not scheduled") · `MAX-TICKETS-PER-TX` 50 · `MAX-SUPPLY`
1,000,000 · `MAX-TIERS` 10 · `MIN-TICKET-PRICE` 0.1 · `MAX-ROUND-FUND` 100,000 · `MAX-SEED-CAP`
100,000 · `DRAW-SEED-RANGE` 10^18 · `PREC` 12. The two the draw and the escape rest on are read
back as literals by unit `DECIDE-3`; the calendar's by `SCHED-0b`.

In the verifier (sealed with it): drand chain `evmnet`, `CHAIN-HASH`
`04f1e9062b8a81f848fded9c12306733282b2727ecced50032187751166ec8c3`, scheme
`bls-bn254-unchained-on-g1`, `GENESIS` 1727521075 (2024-09-28T10:57:55Z), `PERIOD` 3 s, and the
group public key `PK-HEX`, all re-fetchable from `https://api.drand.sh/v2/chains/<CHAIN-HASH>/info`.
`round-at(t)` = 1 + ⌊(t − GENESIS) / 3⌋ and refuses an instant before genesis; `time-of-round` is
its inverse. That the pin equals `round-at(draws-at + 180 s)` is checked three ways that cannot
share a mistake by unit `DECIDE-1b`, `DECIDE-1c`, upgrade `UPG-3`.

## 9. Events

`INITIALIZED` (at setup, carrying the fee destination) · `RAFFLE-CREATED` · `RAFFLE-RETERMED` ·
`RAFFLE-RETIRED` · `RAFFLE-SCHEDULED` · `RAFFLE-SEEDED` · `ROUND-OPENED` (at the first ticket: the
three instants, frozen price, rake and bonus, and last the pinned drand round) · `TICKETS-BOUGHT` ·
`DRAWN` (the seed, the drand round that decided it, the ticket count, ranks, amounts and accounts)
· `WINNER-PAID` · `FEE-PAID` (the fee and the crank share carved out of it) · `BOUNTY-PAID` (one
role only, `draw`) · `ESCAPED` (the drand round nobody drew with, and the money booked) ·
`ESCAPE-PAID`. There is no `DRAW-OPENED` any more. Pinned by unit `OPEN-2`, `BUY-1b`, `DECIDE-1`,
`DRAW-5b`..`DRAW-5e`, `BOUNTY-4`, `CRANK-E1`, `CRANK-E2`, `SCHED-1b`, `ESCAPE-2b`, `ZERO-FEE-4`,
`LOP-6`, `LOP-7`, `ZREC-6`, `ALLREC-5`, `ALLREC-6`, vision `VISION-INFLUENCE-3`;
**`ESCAPE-PAID`, `RAFFLE-RETIRED` and `RAFFLE-SEEDED` are emitted but no public test names them**
— a claim, checked against the code.

## 10. Evidence

**Tests.** `pact/tests/run-tests.sh` runs seven suites — unit 447, vision 89, worst case 33,
revenue 11, frozen 12, upgrade 32 and upgrade2 10 printed assertions (634 in all; more assertion
forms exist, some inside `let` bodies that the REPL does not print) — after a static gate over every
file, a check that no `or`/`and`/`+` takes three operands, a check that no `expect-failure` was
written with too few arguments to assert why it failed, and a check that the frozen-module fixture
is this module with only its governance replaced. Each suite is scored by its exit code, not by
searching its output. CI runs the same command on every push. Every scenario that draws does so
with a **genuine drand `evmnet` beacon** kept in `pact/tests/fixtures/beacons.repl`, one per drand
round a scenario pins; the suites' clocks are therefore set in the past, because a beacon for a
future round does not exist yet, and a hand-typed or altered entry makes its draw abort rather
than pass.

**The upgrade suite**, `pact/tests/prize-draw-upgrade-testing.repl`, loads the exact previous
version (`pact/tests/fixtures/prize-draw-v1-mainnet.pact`, whose module form is
character-identical to the `describe-module` code chain 2 held before 2026-09-30) together with
its `free.block-history` dependency, plays the two games mainnet played to completion on it,
snapshots every row, upgrades in place to `pact/modules/prize-draw.pact` with the admin keyset,
and checks: every old row reads back unchanged through every view, pool addresses included
(`OLD-1`..`OLD-8`); a settled old round can be neither drawn, escaped, claimed, previewed nor
reported as awaiting a draw — even with drand's genuine beacon for the drand round its block
height happens to name, which the verifier does accept as a signature (`OLD-9`..`OLD-13`,
`PREVIEW-OLD-a`, `PREVIEW-OLD`); a retired old game opens no round (`OLD-14`); a new game on the
upgraded module pins a drand round, settles exactly as previewed, pays the crank share whole to
the drawer and conserves (`NEW-1`..`NEW-4`); the upgrade needs the admin keyset and nothing else
(`UPG-1`..`UPG-3`); and, on a fresh copy of the old contract under the mainnet namespace, the
upgrade transaction's first form loaded verbatim from `ops/mainnet-deploy/upgrade-precondition.pact`
passes on mainnet's shape (`PRE-OK`) and refuses a state with a round the old code opened — the
hazard it exists for (`HAZARD-1`..`HAZARD-5`).

**Gas** (the worst-case suite, Pact 5.4 REPL table gas model, measured on this working tree —
mined gas on mainnet runs higher, e.g. opening the pilot's draw under the previous version cost 212
against 125 in the REPL): schedule a round 145 · first ticket 798 · 50-ticket purchase 3,094 · draw
at ten prizes with the beacon verified in the transaction, drawer a winner, eleven transfers 4,174 ·
the same with a non-winning drawer, twelve transfers 4,321 · escape with 51 tickets and the dust
swept 391 · refund one account 376 — all far below the 150,000-per-transaction limit. The
verifier's header records one beacon verification at 1,082 to 1,965 gas depending on which
hash-to-curve branch the two field elements take, notes that the gas table prices the pairing in a
unit flagged for re-benching, and budgets ~21,000 per verify if that happens; the draw still fits
with that added (worst case `WORST-3d2`, `WORST-3`, `WORST-3d`, `WORST-1a2`, `WORST-1b2`,
`WORST-BUY-2b`, `WORST-ESC-1b`, `WORST-ESC-3b`).

**On mainnet** (chain 2), every figure read from the chain:

| what | block | request key | gas |
|---|---:|---|---:|
| deploy (previous version) | 7240922 | `5Bc0-gs7RFx-HBuIIVXVAZZ_05OWsNe1XhixZm8Dd1s` | 60,992 |
| initialize | 7240942 | `TP8zVpAtVFRwtbz0kvz_j2TafiL_JIVAKaXOeAX71H4` | 225 |
| the pilot, created | 7241405 | `FaV8hcyIGjsQsw0sDzl1wEH7F9FJU56VhuCO6assmQ8` | 443 |
| the pilot, draw opened (previous version) | 7241465 | `WkSe5S98FeBXXtmF35YwlNxBpFtvNRvp8LLLZIbVvlk` | 212 |
| the pilot, drawn and paid (previous version) | 7241470 | `GTevqUrZbdtq6A0c9bR9f0CH-H2WrtPjAadDk79EXMk` | 1,019 |
| the Grand Opening, created with its schedule and bonus | 7243001 | `PsZtiJ4On1jwiODmzHpLdZcMLWc90Ccsddk54if1CgM` | 776 |
| upgrade in place to the drand version (the precondition form plus the module) | 7274939 | `qJ_h9Bl4iYHrTk_2PVc37a-Ua82e4lu11pOswqzwZfg` | 101,271 |
| second upgrade in place: a purchase states its round (the module alone) | 7279034 | `73n0HFjarozPhK6TMrtYTZyJHZ8SUoYTshBtMumNSdQ` | 66,289 |

The two rounds drawn before the upgrade are worked through, with their deciding blocks
(7241467 and 7266386) and the previous version's seed recipe, in [games/](../games/). No round has
yet been drawn from a drand beacon on mainnet.

## 11. Known gaps and non-properties

- Static typechecking is not supported for this module (untyped `object` values in the payout
  aggregation and the views); every such path is exercised by the suites.
- Instants are shown to the second in the contract's messages; a sub-second instant is enforced
  exactly but printed truncated.
- A round freezes the game's terms as they stand at its first ticket, and the operator may still
  change a game nobody has bought into at any moment. Since the second upgrade a purchase signed
  for the earlier terms is then REFUSED (§3 step 1) rather than landed on the new ones; the
  protection is the abort, not a block on the change, so an operator re-terming repeatedly makes
  first-ticket purchases fail (its own game, nobody's money). It rests on the client stating the
  digest of what it displayed.
- **The `m:` refusal is by name.** `pool-guard` is public, so anyone can create a coin account under
  a name that does not start with `m:` and guard it with a game's module guard. Such an account can
  then be spent — by anyone, holding no key to it — only into tickets of ANY game, whose prizes and
  refunds go back to that same account. It moves nobody else's money; whoever guards their own
  account this way has locked it themselves. Not refused.
- `validate-id` refuses the space, the tab, the newline and every character at or below the space
  (the C0 controls). It accepts other invisible latin1 characters — DEL, the C1 controls, the
  non-breaking space — because coin accepts them in an account name.
- A prize split whose smaller shares round down can leave a place with **0**: prizes 2..k are
  floored to 12 decimals and prize 1 takes the exact remainder, so a share of `0.0000000000001`
  pays nothing, and `WINNER-PAID` is still emitted with 0. Pinned by unit `TIERS-5`.
- `preview` returns the winners, their places and their prizes — not the crank share or the fee,
  which `draw` also pays.
- **The escape cannot tell "drand stopped" from "nobody fetched the beacon".** drand beacons never
  expire, so the only signal the module has is time; 90 days is the design's answer (§7).
- **The margin is a constant, not a setting.** A round pins its beacon at its first ticket, so a
  changed margin could never reach a live round anyway; changing it means a new version.
- Unpinned by public tests (the code does it; no test fails without it): the `set-terms` ceiling
  check (measured, §2), the 12-decimal limits on price, rake and bonus cap, the ≥ 0 lower bounds of
  max-tickets and seed-cap, three events (§9), the end of module admin at a freeze, the load-time
  refusal of a verifier under the pinned name whose code hash differs (the test loader loads the
  vendored source under the mainnet name so the pin passes; no public test loads other bytes), and
  that the verifier's governance can never pass.
- One property rests on an internal attack suite that is not yet published: foreign-module access
  to a pool (§1).
- Not built: a numbered game in which an unsold number can win, a consolation for non-winners, and
  prizes that are goods.

## 12. Comments in the deployed file that are wrong or unresolvable

`prize-draw.pact` is kept byte for byte as it was sent in the upgrade transaction. Comments inside
its `(module …)` form are stored on chain with the code; the header above that form was sent in
the same transaction but is not stored. Either way, correcting a comment in place would make the
file differ from what was deployed, so none is edited. These are wrong, dated, or cite material an
outside reader cannot resolve; this page, not the comment, is right. The frozen-module test fixture
repeats every one of them, because it is this file with only its governance replaced.

| where in `prize-draw.pact` | what the comment says | the truth |
|---|---|---|
| header | "nobody — player, miner or house — can know the winner while a ticket can still be bought", and "nobody can choose it" | under the contract's rules; until the freeze the admin keys can override those rules (§1, and the box at the top of the [README](../README.md)), and a threshold of drand's operators could learn a beacon early, though not choose it (§7) |
| the note on `DRAND-MARGIN-SECONDS` | "MEASURED for the casino (roulette.pact, the same chain): over 120,001 consecutive chain-2 blocks the longest gap was 136.2 s", and "the same wait roulette launched with" | that measurement and that contract are not in this repository; §7 states the margin's role as a claim about the chain |
| the note on `ESCAPE-AFTER-SECONDS` | "The same ninety days as roulette" | a reference to another contract not in this repository; the bound itself is pinned (§3.5) |
| the load-time admin check | "requires the casino admin" | it requires this module's admin keyset, `<ns>.prize-draw-admin` |
| header | "GOVERNANCE can redeploy and can move pool money" | it can also rewrite any stored row as module admin (§1) |
| header | the fee is "frozen into each round at open so it can never reach money already staked" | true of the contract's own functions; until the freeze, module admin can rewrite a round's stored terms, its fee included (§1) |
| header | "no no-winner branch" | a refunded round has no winner; every *drawn* round has one |
| next to `pool-guard` | "Pinned by pact/attacks/prize-draw-poolguard-pin.repl" | that suite is internal and not in this repository |
| above `validate-payer` | a pool named as a bounty payee, "aborting the draw forever with the escape already closed" | the payee is chosen per call, so another payee draws the round; and nothing closes the escape short of a settlement — it opens 90 days after the beacon (§3.5) |
| in `preview` | "(review C-1)" | an internal review reference; the refusal it explains is pinned by upgrade `PREVIEW-OLD` and unit `PREVIEW-8b`, `PREVIEW-ESC` |
| above the `raffle-round` schema | "nothing in settlement ever reads a live raffle field" | it reads live bookkeeping to retire a finished game (§1) |
| `validate-id`'s error message | "id must not contain a space or a control character" | the C1 controls and some invisible latin1 are accepted (§11) |

The verifier's header in `pact/vendor/drand.pact` — also deployed verbatim and sealed — cites a
measurement document and a "fleet" from the game it was first written for, neither in this
repository; the construction it describes (Keccak-256 message, the RFC 9380 hash-to-curve, the
pairing check) is what the code does, and every draw in the suites exercises it against genuine
beacons.
