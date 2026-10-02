;; prize-draw.pact — Prize Draw raffles: many raffles, one module (Pact 5 / KDA-CE).
;;
;; WHAT THIS MODULE IS. One state machine — "winning ticket RANKS are drawn from
;; the tickets actually sold" — instantiated many times as CONFIG ROWS. Each row
;; is a raffle with its own price, fee, prize tiers, supply, bonus and its own
;; POOL ACCOUNT. The four launch products are all rows:
;;   weekly flagship        tiers [0.5 0.3 0.2], scheduled week by week, uncapped
;;   numbered rifa          numbered=true, max-tickets 100, buyers pick a number
;;   one-off special        rounds-limit 1, optionally seeded with a bonus
;;   winner-takes-all       tiers [1.0]
;; A product that changes the state machine is a DIFFERENT MODULE.
;;
;; ALWAYS A WINNER. A round exists only from its first ticket, so every round has
;; at least one, and the winning ranks are drawn from the tickets SOLD. There is
;; no no-winner branch, and a drawn round's fund never rolls over. k = min(tiers,
;; tickets) winners split the whole fund; unfilled tiers merge into tier 1, so the
;; entire fund is always paid out. Winners are paid INSIDE the draw transaction —
;; there is nothing to claim, ever.
;;
;; A ROUND RUNS BY THE CALENDAR, AND A DRAND BEACON DECIDES IT. The operator
;; schedules three instants for the next round — sales open, sales close, draw —
;; and the round's FIRST TICKET freezes them with every other term, and pins the
;; round to ONE drand beacon: the last one drand publishes within
;; DRAND-MARGIN-SECONDS of the draw instant (177 to 180 s after it). Sales are
;; enforced by the chain's clock, and the beacon does not exist until after the
;; last ticket could have been sold, so nobody — player, miner or house — can
;; know the winner while a ticket can still be bought. Once drand publishes it,
;; anyone submits the beacon with `draw`; it is verified on chain against drand's
;; pinned public key, so a forged one aborts. The draw is a pure function of the
;; round key and that beacon. There are no secrets, no bonds, no recorders and
;; nobody to wait for.
;;
;; WHY NOT A BLOCK HASH. The miner of a deciding block sees its hash before
;; publishing and can throw the block away and mine again; the party that records
;; a block can decline to. Both tilted every block-decided round. A drand value is
;; a threshold BLS signature: exactly one valid signature exists per round, so
;; nobody can choose it, and it is produced by no Kadena miner. drand can only
;; STOP publishing — it cannot steer a result.
;;
;; NOTHING RE-ROLLS. A draw whose seed depends on a value some caller can mint
;; again — a fresh attempt key, a second capture — is not a draw: the same beacon
;; then yields a different winner on every try, and whoever can decline to act
;; chooses the winner for the price of gas. There is no attempt and no retry
;; here, and no second source: the round, its pinned beacon round and the unique
;; signature for it are all fixed before anyone can know the outcome.
;;
;; THE ESCAPE is the last resort and still cannot steer a winner. A round escapes
;; only when nobody drew it for ESCAPE-AFTER-SECONDS after its beacon was due — the
;; condition under which drand has stopped or the game was abandoned. It returns
;; each buyer exactly their own stake plus their share of the bonus, selects no
;; winner, and takes no fee. 🔴 DISCLOSED: a beacon is public the moment drand
;; publishes it, so after the escape opens a buyer who can see they lost could
;; escape rather than draw. Opening only after ninety days is what makes that
;; require the house AND every winner to ignore a round for a quarter, when any
;; one of them can draw it alone at any time.
;;
;; 🔴 THIS VERSION REPLACED A BLOCK-DECIDED ONE IN PLACE, and the tables carry
;; that history. Rounds drawn before it hold a BLOCK HEIGHT in `decide-height` and
;; `deciding-block`; rounds opened after it hold a DRAND ROUND there (see the
;; round schema). No schema changed, because a field added to a live table loads
;; clean and aborts at its first access. The upgrade is sound only while NO round
;; the old code opened is unsettled: with decide-height 0 (draw never opened) it
;; could neither draw nor escape; with a block height (draw opened) this code reads
;; a long-past drand round, so it could escape at once, taken by a buyer who can
;; see they lost. The upgrade transaction's FIRST form refuses both
;; (ops/mainnet-deploy/upgrade-precondition.pact).
;;
;; FEES ARE MODULAR. The fee is per raffle, re-settable for
;; FUTURE rounds, and frozen into each round at open so it can never reach money
;; already staked. There is NO fixed ceiling — only 0 <= fee < 1, so a fat finger
;; cannot make the fee exceed sales. Each raffle discloses its own fee.
;;
;; POOL ISOLATION. Every raffle's pool is the principal of its own MODULE guard,
;; m:<namespace>.prize-draw:<id> — a distinct account per raffle that only this
;; module, on its own call stack, can spend. There is no pool CAPABILITY: a weak
;; true-bodied cap is composable by any foreign module, so a capability-guarded
;; pool can be emptied by a stranger holding no key of ours.
;;
;; SURFACE. No PRIVATE capability and no exported function moves money with a
;; caller-chosen account and amount: every transfer is inlined into the function
;; that owns it and every amount is derived from stored rows. OPERATOR (create,
;; re-term, schedule, retire, seed) is separate from GOVERNANCE (upgrade, freeze).
;; While the module stays upgradeable, GOVERNANCE can redeploy and can move pool
;; money. The player terms must say so — not "no function exists".
;;
;; CONSERVATION, per raffle (pool-status exposes it):
;;   balance(pool id) >= seed-bucket + bound + owed + pending
;; Equality holds for module flows; the check is >= because anyone may donate
;; KDA straight to a pool account and such surplus is unrecoverable by design.
;;
;; BONUS INVARIANT: max-fund >= seed-bucket + bound + price, re-checked at every
;; step that can lower the left side or raise the right (`seed-raffle`,
;; `set-terms`); a round's first ticket only moves bonus from bucket to bound.
;; So a waiting bonus always fits the next round's ceiling with room for a
;; ticket. Broken, a bonus can sit where no round can ever sell.
;;
;; ONE-WAY DOORS, RECORDED.
;; - The pool principal is m:<ns>.prize-draw:<id> and embeds this module's NAME.
;;   Redeploying under any other name orphans every pool: never rename it.
;; - A pool's guard is fixed when the pool is FIRST FUNDED (every inflow is
;;   transfer-create), but its address is DERIVED from `pool-guard` on every call.
;;   An upgrade that changed `pool-guard` would point this module at new, empty
;;   accounts and orphan every funded pool: live rounds could neither draw nor
;;   escape. Never change it, exactly as never rename the module.
;; - That guard is a module guard, the permanent choice for a module meant to
;;   freeze (see `pool-guard`). Freezing needs no new pool accounts; what it ends is
;;   governance's reach into them while the module is upgradeable (GOVERNANCE).
;; - Freeze only after `initialize` has run. No raffle can be created before it,
;;   and once frozen nothing could ever run it: the module would be inert.

(namespace (read-msg 'ns))

; Load-time admin gate: deploying or upgrading this file requires the casino admin.
(enforce-guard (keyset-ref-guard (format "{}.prize-draw-admin" [(read-msg 'ns)])))

; The winner is decided by the drand beacon pinned at the round's first ticket.
; A round refunds only if nobody draws it within ESCAPE-AFTER-SECONDS of that
; beacon. Each raffle has its own isolated pool.
(module prize-draw GOVERNANCE

  @doc "Prize Draw raffles. Many raffles as config rows on one always-a-winner state \
  \machine: ranks drawn from the tickets actually sold, the whole fund paid to \
  \k = min(tiers, tickets) winners inside the draw transaction."

  (use coin)
  ;; What decides a round is ONE drand beacon, verified by a module that can never
  ;; be upgraded: `drand` is sealed (its governance is `enforce false`), holds no
  ;; tables, no capabilities and no funds, and pins drand's evmnet public key. It
  ;; is named FULLY and PINNED to its code hash, so this module refuses to load
  ;; against any other bytes under that name — a verifier that accepted a chosen
  ;; signature would choose the winner — and a wrong hash fails with "hash not
  ;; blessed". The module is dependency-free, so the REPL computes the same hash
  ;; for it as mainnet does and ONE source pins correctly everywhere it is
  ;; deployed under that name. `verified-seed` ABORTS unless the signature
  ;; verifies, so no caller can proceed on an unchecked beacon.
  (use n_48867b242317a0216a67f8c7ca26696b5878e0e3.drand "Y07t-duJmkXkcGth0TfBRg3ThbNR-uh9PdNUd1MKHBQ"
    [ verified-seed round-at time-of-round ])

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; CONSTANTS ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ; Decimal precision of every computed payout.
  (defconst PREC:integer 12)

  ; A round's DRAW SEED lands in [0, this); the winning ranks are derived from it
  ; by the public pure function `draw-ranks`.
  (defconst DRAW-SEED-RANGE:integer 1000000000000000000)

  ; Ticket price floor — an anti-dust bound, not a policy.
  (defconst MIN-TICKET-PRICE:decimal 0.1)

  ; A round's schedule is three instants of the chain's clock — the PARENT block's
  ; timestamp, so a boundary takes effect on the first block whose parent was
  ; stamped past it, about 30 s of granularity. These bound what the operator may
  ; schedule; `add-time` and `diff-time` do not check overflow, so every instant is
  ; bounded on both sides and only the operator can set one.
  (defconst MIN-SALES-SECONDS:decimal 600.0)
  (defconst MAX-SALES-SECONDS:decimal 31536000.0)     ; 365 days: the house sets the window
  (defconst MAX-DRAW-GAP-SECONDS:decimal 604800.0)    ; 7 days: stakes wait until the draw
  (defconst MAX-LEAD-SECONDS:decimal 31536000.0)      ; a round may be scheduled a year ahead
  ; 🔴 THE WAIT BETWEEN THE DRAW INSTANT AND THE BEACON, AND WHY IT IS
  ; LOAD-BEARING. The chain's clock is the PARENT block's time, so a ticket is
  ; accepted while the parent's time is before closes-at and can still be mined a
  ; whole block interval later in real time. If the pinned beacon were published
  ; inside that gap, anyone watching drand could read the outcome and THEN buy.
  ; The draw instant is never before the close, and the beacon comes this long
  ; after the draw instant. MEASURED for the casino (roulette.pact, the same
  ; chain): over 120,001 consecutive chain-2 blocks the longest gap was 136.2 s
  ; and none passed 150 s; 180 s is the same wait roulette launched with. drand
  ; publishes every 3 s and the pinned round is the last one at or before the
  ; margin, so the beacon comes 177 to 180 s after the draw instant. It is a
  ; CONSTANT here, not a setting: a round pins its beacon at its first ticket and
  ; a later change could never reach it anyway, and a constant needs no stored
  ; field. A network halt longer than this — or a miner rewriting more than this
  ; much of the chain from before the close, a deep reorg — exposes the one round
  ; open at that moment: disclosed, not claimed away.
  (defconst DRAND-MARGIN-SECONDS:decimal 180.0)
  ; 🔴 HOW LONG EVERYONE MUST LEAVE A ROUND UNDRAWN BEFORE IT CAN ESCAPE. Ninety
  ; days, and the length IS the safety argument. The module cannot tell "the
  ; beacon is unobtainable" from "nobody fetched it" — drand beacons never expire
  ; — and once a beacon is public a losing buyer can see they lost. So an escape
  ; opens only when the house's crank AND every winner, each able to draw alone
  ; and each able to see the beacon, have left the round for a quarter: the
  ; condition under which drand has really stopped or the game was abandoned,
  ; which is when a refund is the right answer. Until an escape lands, a draw
  ; still settles the round normally. The same ninety days as roulette.
  (defconst ESCAPE-AFTER-SECONDS:decimal 7776000.0)
  ; "Not scheduled." A raffle's next-round instants hold this until `schedule-round`.
  (defconst EPOCH:time (time "1970-01-01T00:00:00Z"))

  ; Prize tiers per raffle. Bounds the draw transaction (k transfers).
  (defconst MAX-TIERS:integer 10)

  ; Gas bound on one buy, and the largest supply a numbered raffle may declare.
  (defconst MAX-TICKETS-PER-TX:integer 50)
  (defconst MAX-SUPPLY:integer 1000000)

  ; ABSOLUTE bound on what one round can hold (a relative cap grows with the
  ; pot; this one does not).
  ; The rail is deliberately WIDE: everything the house tunes has to stay tunable,
  ; so the loss limit lives in the per-raffle ceiling, which the operator changes
  ; at any time for FUTURE rounds while a round already selling keeps the ceiling
  ; it froze at open. The rail only stops a ceiling nobody could ever justify.
  ; The ABSOLUTE rail, frozen with the module: no raffle may ever set a prize
  ; ceiling above this. The operational ceiling is per raffle (`max-fund`), set
  ; by the operator and frozen into each round at open — the pot ceiling is meant
  ; to stay adjustable, and OPERATOR (not GOVERNANCE) gates it so it still is
  ; after the module freezes.
  ; It is a business limit on what ONE round can hold, sized as a business risk.
  (defconst MAX-ROUND-FUND:decimal 100000.0)

  ; Ceiling on a raffle's one-way bonus bucket. Same wide rail, same reasoning.
  (defconst MAX-SEED-CAP:decimal 100000.0)

  (defconst STATE-KEY:string "state")

  ; The two keysets live beside the module in the namespace it was deployed
  ; into, so one source deploys unchanged into a devnet `free` and a mainnet
  ; principal namespace. Read once, at load.
  (defconst ADMIN-KS:string    (format "{}.prize-draw-admin"    [(read-msg 'ns)]))
  (defconst OPERATOR-KS:string (format "{}.prize-draw-operator" [(read-msg 'ns)]))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; CAPABILITIES ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (defcap GOVERNANCE ()
    @doc "Upgrade and freeze. The trust boundary: while the module is \
    \upgradeable this key can redeploy it and reach pool money."
    (enforce-guard (keyset-ref-guard ADMIN-KS)))

  (defcap OPERATOR ()
    @doc "Day-to-day: create, re-term, schedule, retire and seed raffles. Cannot \
    \upgrade, cannot move player money, cannot reach a live round's frozen terms."
    (enforce-guard (keyset-ref-guard OPERATOR-KS)))

  ; THERE IS NO POOL CAPABILITY, and adding one would be the drain: a weak
  ; true-bodied cap is composable by ANY foreign module, so a capability guard
  ; built from it guards nothing. Beside a module-guarded pool such a cap
  ; authorises nothing at all — but it stays foreign-composable, and a capability
  ; that grants nothing is exactly the thing a later reader mistakes for a guard.
  ; On a module that freezes, it must not exist. Per-raffle
  ; isolation is carried by the DISTINCT principals (m:<namespace>.prize-draw:<id>),
  ; which no code can confuse, not by a capability anyone can hold.

  (defcap INITIALIZED:bool     (revenue:string) @event true)
  (defcap RAFFLE-CREATED:bool (id:string price:decimal rake:decimal
                               tiers:[decimal]
                               max-tickets:integer numbered:bool seed-cap:decimal
                               rounds-limit:integer max-fund:decimal
                               bounty-share:decimal bounty-split:[integer]) @event true)
  (defcap RAFFLE-RETERMED:bool (id:string price:decimal rake:decimal
                               tiers:[decimal]
                               max-tickets:integer seed-cap:decimal
                               rounds-limit:integer max-fund:decimal
                               bounty-share:decimal bounty-split:[integer]) @event true)
  (defcap RAFFLE-RETIRED:bool  (id:string) @event true)
  (defcap RAFFLE-SCHEDULED:bool (id:string opens-at:time closes-at:time draws-at:time) @event true)
  (defcap RAFFLE-SEEDED:bool   (id:string funder:string amount:decimal bucket:decimal) @event true)
  (defcap ROUND-OPENED:bool    (id:string seq:integer opens-at:time closes-at:time draws-at:time
                                price:decimal rake:decimal seed-in:decimal
                                drand-round:integer) @event true)
  (defcap TICKETS-BOUGHT:bool  (id:string seq:integer account:string count:integer
                                from-rank:integer numbers:[integer]) @event true)
  (defcap DRAWN:bool           (id:string seq:integer draw-seed:integer drand-round:integer
                                tickets:integer ranks:[integer] amounts:[decimal]
                                accounts:[string]) @event true)
  (defcap WINNER-PAID:bool     (id:string seq:integer account:string amount:decimal) @event true)
  (defcap FEE-PAID:bool        (id:string seq:integer fee:decimal bounties:decimal) @event true)
  (defcap BOUNTY-PAID:bool     (id:string seq:integer role:string account:string amount:decimal) @event true)
  (defcap ESCAPED:bool         (id:string seq:integer drand-round:integer booked:decimal) @event true)
  (defcap ESCAPE-PAID:bool     (id:string seq:integer account:string amount:decimal) @event true)

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; SCHEMAS ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ; Module state, written once at initialize.
  (defschema state
    revenue:string)             ; where fees go; verified to exist at initialize

  ; One row per raffle: its terms (which each round freezes at its first ticket),
  ; its schedule for the next round, its bonus bucket and its conservation ledger.
  (defschema raffle
    price:decimal               ; ticket price of FUTURE rounds
    rake:decimal                ; fee rate of FUTURE rounds, 0 <= rake < 1
    tiers:[decimal]             ; prize shares, > 0 each, summing to 1.0
    max-tickets:integer         ; 0 = uncapped supply; numbered raffles need > 0
    numbered:bool               ; buyers pick their number (immutable per raffle)
    seed-cap:decimal            ; ceiling on the bonus bucket
    max-fund:decimal            ; prize ceiling of FUTURE rounds, operator-set
    rounds-limit:integer        ; 0 = runs forever; else retires after N rounds,
                                ; but never while a bonus waits or is live
    ; What whoever sends the draw is paid, out of the FEE and never the prize:
    ; `bounty-share` of the fee. Each round freezes it at open.
    ; `bounty-split` is RETAINED FROM THE BLOCK-DECIDED VERSION and no longer
    ; read by any settlement: it divided the share between the block's recorder
    ; and the drawer, and a drand round has no recorder. It stays because rows
    ; written before this version hold it and a schema change on a live table
    ; fails late. It is still validated (weights not all zero) so every row keeps
    ; one shape.
    bounty-share:decimal
    bounty-split:[integer]
    ; The NEXT round's schedule, set by `schedule-round` and consumed by that
    ; round's first ticket, which freezes it. EPOCH means "not scheduled".
    next-opens-at:time
    next-closes-at:time
    next-draws-at:time
    ; Rounds that have SOLD at least one ticket — every round, since a round
    ; exists only from its first ticket. It rises there and never falls.
    rounds-used:integer
    rounds-done:integer
    active:bool                 ; false = no NEW round opens; live rounds finish
    round-seq:integer
    current:string              ; key of the most recent round ("" = none yet)
    seed-bucket:decimal         ; one-way bonus, bound WHOLE into the next round
    bound:decimal               ; bonus moved OUT of the bucket into live rounds
    owed:decimal                ; escaped rounds' unclaimed stakes
    pending:decimal)            ; sales of rounds not yet drawn or escaped

  ; One row per round. Every settlement input is frozen here at open; nothing in
  ; settlement ever reads a live raffle field.
  (defschema raffle-round
    raffle-id:string
    seq:integer
    opens-at:time               ; frozen: sales open here (chain time)
    closes-at:time              ; frozen: sales close here
    draws-at:time               ; frozen: the beacon comes 177 to 180 s later
    price:decimal               ; frozen
    rake:decimal                ; frozen
    tiers:[decimal]             ; frozen
    numbered:bool               ; frozen
    max-tickets:integer         ; frozen
    max-fund:decimal            ; frozen prize ceiling of THIS round
    bounty-share:decimal        ; frozen
    bounty-split:[integer]      ; frozen, retained, unread (see the raffle schema)
    seed-in:decimal             ; bonus bound to THIS round at open
    sales:decimal
    tickets:integer             ; the draw's sample space [0, tickets)
    ; 🔴 TWO FIELDS KEEP THEIR BLOCK-ERA NAMES. A schema change on a live table
    ; fails late (the upgrade loads clean and the first access of a new field
    ; aborts), so the drand version reuses these instead of adding fields:
    decide-height:integer       ; THE PINNED DRAND ROUND. Written once, at the
                                ; round's first ticket, from its frozen draws-at,
                                ; and read by nothing that can change it. Rounds
                                ; drawn before this version hold a block height.
    deciding-block:integer      ; the drand round that decided it, written at the
                                ; draw; -1 until then. A block height on rounds
                                ; drawn before this version.
    state:string                ; "selling" | "drawn" | "escaped"
    draw-seed:integer           ; -1 until drawn
    ranks:[integer]
    amounts:[decimal]
    accounts:[string]
    escape-unit:decimal)        ; per-ticket bonus share, set only on escape

  ; One row per ticket. Immutable once written.
  (defschema ticket
    account:string
    number:integer)             ; the picked number, or -1 in quantity mode

  ; Per (round, account): the site's "my tickets" read and the escape's payout
  ; unit — one refund transaction per account, not per ticket.
  (defschema holding
    count:integer
    paid:bool)

  ; Numbered raffles only: uniqueness of a picked number within a round.
  (defschema number-row
    rank:integer)

  (deftable state-table:{state})
  (deftable raffles:{raffle})
  (deftable rounds:{raffle-round})
  (deftable tickets:{ticket})
  (deftable holdings:{holding})
  (deftable picked-numbers:{number-row})

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; HELPERS ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; All pure or read-only. None of them moves money.

  ; The chain's clock: the PARENT block's timestamp, a consensus value that lags
  ; the wall clock by about one block and never runs backwards.
  (defun now-time:time () (at 'block-time (chain-data)))
  ; An instant in a message, unquoted: `format` renders a time with quotes.
  (defun iso:string (t:time) (format-time "%Y-%m-%dT%H:%M:%SZ" t))

  (defun round-key:string (id:string seq:integer) (format "{}|{}" [id seq]))
  (defun ticket-key:string (rk:string rank:integer) (format "{}|{}" [rk rank]))
  (defun holding-key:string (rk:string account:string) (format "{}|{}" [rk account]))
  (defun number-key:string (rk:string number:integer) (format "{}|#{}" [rk number]))

  ; Deliberately NOT a capability guard. Pact has no private capabilities, so any
  ; foreign module may compose one of ours and thereby satisfy a capability guard
  ; built from it — measured, the whole pool leaves in one unsigned transaction.
  ; A module guard is enforced by coin with this module OFF the stack, so a
  ; foreign spend falls through to module admin and fails against governance.
  ; Pinned by pact/attacks/prize-draw-poolguard-pin.repl. This module is intended to
  ; FREEZE, and a compose regression against a frozen module would be unfixable
  ; forever, so the fork-independent guard is the permanent choice here even
  ; though create-module-guard is deprecated.
  (defun pool-guard:guard (id:string)
    @doc "The guard of raffle `id`'s pool: a MODULE guard named for the raffle, \
    \so each raffle's pool is a distinct principal (m:<module>:<id>) that no \
    \other raffle can spend. Deliberately NOT a capability guard."
    (create-module-guard id))

  (defun pool-account:string (id:string)
    @doc "Raffle `id`'s pool account (an m: principal)."
    (create-principal (pool-guard id)))

  ; Pact enforces a module guard by asking only whether the NAMING MODULE is on
  ; the call stack — it does not check WHICH guard was named. So every pool
  ; is protected by the identical predicate, and any function here that debits a
  ; caller-supplied sender would let one raffle's pool pay for another's. Measured
  ; without this refusal: a stranger named raffle A's pool as the payer of raffle
  ; B, moved 50 KDA out of it with no signature from A or anyone else, and left A
  ; insolvent — `pool-status` ok went false and stayed false.
  ; No real buyer, funder or bounty payee is ever a module account, so refusing
  ; the whole prefix is exact rather than approximate. It also covers the
  ; narrower case of a pool named as a bounty payee, which coin refuses at the
  ; transfer, aborting the draw forever with the escape already closed.
  (defun validate-payer:string (account:string role:string)
    @doc "EVERY account a caller NAMES as a source or destination of money this \
    \module moves goes through here. It is `validate-account` plus one refusal \
    \that is load-bearing: an `m:` principal is a MODULE-guarded account, and \
    \every raffle pool is one."
    (validate-account account)
    (enforce (!= "m:" (take 2 account))
      (format "the {} must not be a module account" [role]))
    account)

  ; The beacon a round is pinned to: the drand round published DRAND-MARGIN-SECONDS
  ; after its draw instant (`round-at` returns the round published at or before
  ; the instant it is given, so at most one drand period earlier than that).
  (defun drand-round-for:integer (draws-at:time)
    @doc "The drand round that decides a round drawing at `draws-at`. Pure and \
    \public: anyone can compute a round's beacon from its published schedule."
    (round-at (add-time draws-at DRAND-MARGIN-SECONDS)))

  ; Both inputs are fixed before they are jointly knowable: the round key and its
  ; pinned drand round at the round's first ticket, the signature by drand after
  ; the last ticket could have been sold. `verified-seed` ABORTS unless the
  ; signature is the genuine one for exactly that drand round, and it binds the
  ; round key into the seed, so one beacon gives unrelated seeds to different
  ; rounds and to other games that use drand.
  (defun round-seed:integer (rk:string dr:integer sig-hex:string)
    @doc "This round's draw seed from its pinned drand beacon: verified against \
    \drand's public key (a forged or wrong-round signature aborts), bound to the \
    \round key, reduced to [0, DRAW-SEED-RANGE). Read-only."
    (mod (verified-seed (format "prize-draw|{}" [rk]) dr sig-hex) DRAW-SEED-RANGE))

  (defun decidable:bool (id:string seq:integer)
    @doc "Can this round be drawn now? Read-only, and true only when the round is \
    \still selling and the chain's clock has passed the moment drand publishes \
    \its pinned beacon."
    (with-read rounds (round-key id seq)
      { "decide-height" := dr, "state" := st }
      (and (= st "selling") (>= (now-time) (time-of-round dr)))))

  (defun draw-status:object (id:string seq:integer)
    @doc "Where a SELLING round stands on its way to a draw: its pinned drand \
    \round, when drand publishes it, whether that moment has passed on the \
    \chain's clock, and `escape-from`, the instant AFTER which the round could \
    \escape if nobody draws it (at exactly that instant it cannot yet). \
    \Read-only. For a settled round, read `get-round`."
    (with-read rounds (round-key id seq)
      { "decide-height" := dr, "state" := st, "tickets" := n, "draws-at" := da }
      (enforce (= st "selling") "this round is settled — read get-round for its result")
      (let ((due (time-of-round dr)))
        { "state": st
        , "tickets": n
        , "draws-at": da
        , "drand-round": dr
        , "beacon-at": due
        , "beacon-due": (>= (now-time) due)
        , "escape-from": (add-time due ESCAPE-AFTER-SECONDS) })))

  (defun draw-candidate:integer (dseed:integer rkey:string i:integer m:integer)
    @doc "One uniform candidate in [0, m) — a domain-separated re-hash of the \
    \draw seed. Modulo bias <= m / 2^256."
    (mod (str-to-int 64 (hash (format "{}|{}|{}" [dseed rkey i]))) m))

  (defun lift:integer (c:integer taken:[integer])
    @doc "Order-statistics insertion: shift candidate `c` past each already-drawn \
    \rank in ASCENDING order, so the result is uniform over the ranks not taken."
    (fold (lambda (v:integer r:integer) (if (>= v r) (+ v 1) v)) c taken))

  (defun draw-ranks:[integer] (dseed:integer rkey:string n:integer k:integer)
    @doc "The winning ranks: k distinct ranks drawn WITHOUT replacement from \
    \[0, n), exact and total. Pure and public — anyone recomputes a draw from \
    \the round's stored draw-seed and ticket count and compares with `ranks`."
    (enforce (>= n 1) "no tickets to draw from")
    (enforce (and (>= k 1) (<= k n)) "k must be 1..n")
    (fold (lambda (acc:[integer] i:integer)
            (+ acc [ (lift (draw-candidate dseed rkey (+ i 1) (- n i)) (sort acc)) ]))
          []
          (enumerate 0 (- k 1))))

  (defun tier-amounts:[decimal] (fund:decimal tiers:[decimal] k:integer)
    @doc "Split `fund` across k tiers. Tiers 2..k take floor(share * fund); tier \
    \1 takes the EXACT remainder, so unfilled tiers merge into tier 1 and the \
    \whole fund is always paid out with no dust left anywhere."
    (enforce (and (>= k 1) (<= k (length tiers))) "k must be 1..tiers")
    (let* ((tail (if (= k 1) []
                     (map (lambda (i:integer) (floor (* (at i tiers) fund) PREC))
                          (enumerate 1 (- k 1)))))
           (rest (fold (+) 0.0 tail)))
      (+ [ (- fund rest) ] tail)))

  (defun merge-payee:[object] (acc:[object] p:object)
    @doc "Fold step: sum amounts per DISTINCT account, so the draw installs one \
    \transfer budget per account (Pact 5's install identity is (sender, \
    \receiver) — two installs to the same pair collide whatever the amount)."
    (let ((a (at 'account p)))
      (if (contains a (map (lambda (o:object) (at 'account o)) acc))
          (map (lambda (o:object)
                 (if (= (at 'account o) a)
                     { "account": a, "amount": (+ (at 'amount o) (at 'amount p)) }
                     o))
               acc)
          (+ acc [p]))))

  (defun validate-id:string (id:string)
    @doc "Raffle ids feed every round key, every table key AND this raffle's pool \
    \account name, so everything those three require is refused here, at the one \
    \place a raffle is named."
    (enforce (and (>= (length id) 1) (<= (length id) 32)) "id must be 1..32 chars")
    (enforce (not (contains ":" id)) "id must not contain ':'")
    (enforce (not (contains "|" id)) "id must not contain '|'")
    ; The id also names this raffle's pool, m:<module>:<id>. A name coin will not
    ; accept makes the raffle unusable and the id unusable with it: `create-raffle`
    ; succeeds because it writes no coin account, every later inflow aborts on the
    ; account name, and the id can never be taken again because its row is written.
    ; Nobody loses money — no money can get in — but on a module that FREEZES a
    ; malformed name tolerated once is tolerated forever, so it is refused where it
    ; happens. `validate-account` is coin's own check, asked of the very name the
    ; pool will use, so this can never drift from what coin requires; the charset
    ; enforce above it exists only to say WHY in this module's own words.
    (enforce (is-charset CHARSET_LATIN1 id)
      "id must use latin1 characters only — this raffle's pool account could not exist otherwise")
    ; An id is a permanent pool-account name and a label players read, and coin accepts a space,
    ; a tab or a newline inside an account name — so the refusal has to be ours. Every character
    ; at or below the space is refused, which is the space itself, the tab, the newline, the
    ; carriage return and every other C0 control. Ordering, not an escape: Pact's lexer has no
    ; \uXXXX form, so a control character cannot be written as a literal to compare against.
    ; Latin1 letters above ASCII stay legal — coin accepts them, and CREATE-3b pins that. The
    ; exotic latin1 blanks (a non-breaking space, DEL) are accepted for the same reason: coin
    ; takes them, and refusing them here would need an unwritable literal.
    ; 🔴 BOUNDED BY THE 1..32 LENGTH ENFORCE ABOVE — keep it there. That enforce is what stops
    ; `str-to-list` walking an unbounded string: a 10,000-character id costs 4 gas because the
    ; length refuses it first, while the worst legal id costs 24.
    (enforce (= 0 (length (filter (lambda (c:string) (<= c " ")) (str-to-list id))))
      "id must not contain a space or a control character")
    (validate-account (pool-account id))
    id)

  (defun validate-terms:string (price:decimal rake:decimal
                                tiers:[decimal] max-tickets:integer
                                seed-cap:decimal rounds-limit:integer
                                max-fund:decimal
                                bounty-share:decimal bounty-split:[integer])
    @doc "Every bound a raffle's terms must satisfy, checked in one place so the \
    \create and re-term paths can never diverge."
    (enforce-unit price)
    (enforce (>= price MIN-TICKET-PRICE)
      (format "price must be >= {}" [MIN-TICKET-PRICE]))
    (enforce-unit rake)
    ; No policy ceiling — each raffle discloses its own fee. Only the correctness
    ; bound: a fee of 1.0 or more would take the whole fund or more.
    (enforce (and (>= rake 0.0) (< rake 1.0)) "fee must be >= 0 and < 1")
    (let ((k (length tiers)))
      (enforce (and (>= k 1) (<= k MAX-TIERS))
        (format "tiers must be 1..{} entries" [MAX-TIERS]))
      (enforce (= k (length (filter (lambda (s:decimal) (> s 0.0)) tiers)))
        "every tier share must be > 0")
      (enforce (= 1.0 (fold (+) 0.0 tiers)) "tier shares must sum to exactly 1.0"))
    (enforce (and (>= max-tickets 0) (<= max-tickets MAX-SUPPLY))
      (format "max-tickets must be 0 (uncapped) or <= {}" [MAX-SUPPLY]))
    (enforce-unit seed-cap)
    (enforce (and (>= seed-cap 0.0) (<= seed-cap MAX-SEED-CAP))
      (format "bonus cap must be 0..{}" [MAX-SEED-CAP]))
    (enforce (>= rounds-limit 0) "rounds-limit must be >= 0")
    ; The per-raffle prize ceiling. Bounded by the module's absolute rail, and
    ; required to leave room for at least one ticket above the bonus cap: the
    ; ceiling caps stakes plus bonus (see `buy`), so a bonus within one ticket of
    ; it would refuse every ticket. `seed-raffle` holds waiting plus bound bonus to
    ; the cap and `set-terms` holds the ceiling above both, so the bonus invariant
    ; in the header survives every later change of terms.
    (enforce-unit max-fund)
    (enforce (and (> max-fund 0.0) (<= max-fund MAX-ROUND-FUND))
      (format "prize-fund ceiling must be > 0 and <= {}" [MAX-ROUND-FUND]))
    (enforce (>= max-fund (+ seed-cap price))
      "the prize-fund ceiling must exceed the bonus cap by at least one ticket, or no ticket could be sold")
    ; The crank share: what whoever sends the draw is paid, as a part of the fee.
    ; `bounty-split` is retained and unread (see the raffle schema); it is still
    ; checked to the shape it always had, [recorder drawer] weights not all zero,
    ; so every row written before and after this version has one shape.
    (enforce-unit bounty-share)
    (enforce (and (> bounty-share 0.0) (<= bounty-share 1.0))
      "the crank share must be more than 0 and at most 1 of the fee")
    (enforce (= (length bounty-split) 2)
      "bounty-split must hold two weights: [recorder drawer]")
    (enforce (= 2 (length (filter (lambda (w:integer) (>= w 0)) bounty-split)))
      "every bounty weight must be 0 or more")
    (enforce (> (+ (at 0 bounty-split) (at 1 bounty-split)) 0)
      "the bounty weights must not all be zero")
    "ok")

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; ADMIN / SETUP ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (defun initialize:string (revenue:string)
    @doc "Admin, once: record where fees are paid. The account must already \
    \exist — its balance is read here, so a wrong address fails now rather than \
    \bricking the first draw."
    (with-capability (GOVERNANCE)
      (validate-account revenue)
      ; Every draw pays this account inside the draw transaction, on a module
      ; that FREEZES. A coin account is CREDITED without its guard, so another
      ; module's guarded account is a fine destination — it is how fees reach
      ; the token's funding account. Only this module's OWN pools are refused:
      ; a pool named here would make every draw a pool-pays-itself transfer,
      ; which coin refuses, and the round would then have no exit at all.
      (let ((own (take (- (length (pool-account "-")) 1) (pool-account "-"))))
        (enforce (!= own (take (length own) revenue))
          "revenue must not be one of this module's pools"))
      (let ((bal (get-balance revenue)))
        (enforce (>= bal 0.0) "revenue account must exist"))
      (insert state-table STATE-KEY { "revenue": revenue })
      ;; The one write in this module that published nothing. Where the fees go is the one
      ;; number a player cannot otherwise check against this contract, and after the freeze no
      ;; view or event can ever be added — so it is published here and readable by `get-revenue`.
      (emit-event (INITIALIZED revenue)))
    "prize-draw initialized")

  (defun create-raffle:string (id:string price:decimal rake:decimal
                               tiers:[decimal]
                               max-tickets:integer numbered:bool
                               seed-cap:decimal rounds-limit:integer
                               max-fund:decimal
                               bounty-share:decimal bounty-split:[integer])
    @doc "Operator: define a raffle, whose terms take effect for rounds opened \
    \from now on. `tiers` is the prize split ([1.0] = winner takes all); \
    \`max-tickets` 0 means uncapped; `numbered` = buyers pick their number from a \
    \fixed supply; `rounds-limit` 1 makes it a one-off."
    (validate-id id)
    (validate-terms price rake tiers max-tickets seed-cap rounds-limit
                    max-fund bounty-share bounty-split)
    (enforce (or (not numbered) (> max-tickets 0))
      "a numbered raffle needs a fixed supply (max-tickets > 0)")
    ; `draw` and `escape` read the revenue account that `initialize` writes. Every
    ; pool starts with a raffle, so refusing the raffle keeps the first money, a
    ; bonus or a stake, out of every pool until the module can settle it. After a
    ; freeze nothing could ever set the account, and money let in before it would
    ; be locked for good.
    (let ((rev (with-default-read state-table STATE-KEY { "revenue": "" } { "revenue" := r } r)))
      (enforce (!= rev "") "prize-draw is not initialized — no raffle may be created until it is"))
    (with-capability (OPERATOR)
      ; the raffle row first, so a duplicate id fails on the raffle rather than
      ; on its coin account and the error names the real problem
      (insert raffles id
        { "price": price, "rake": rake
        , "tiers": tiers, "max-tickets": max-tickets, "numbered": numbered
        , "seed-cap": seed-cap, "max-fund": max-fund
        , "rounds-limit": rounds-limit
        , "bounty-share": bounty-share, "bounty-split": bounty-split
        , "next-opens-at": EPOCH, "next-closes-at": EPOCH, "next-draws-at": EPOCH
        , "rounds-used": 0, "rounds-done": 0
        , "active": true, "round-seq": 0, "current": ""
        , "seed-bucket": 0.0, "bound": 0.0
        , "owed": 0.0, "pending": 0.0 })
      ; The pool account is NOT created here. Its principal is derived from this
      ; module and the id, so a stranger can precompute and create it — and a
      ; duplicate create would then make the id unusable forever. Every inflow
      ; uses transfer-create instead, which makes a pre-existing (necessarily
      ; correctly-guarded) account a no-op rather than a lost id.
      (emit-event (RAFFLE-CREATED id price rake tiers max-tickets
                                  numbered seed-cap rounds-limit max-fund
                                  bounty-share bounty-split)))
    (format "raffle {} created" [id]))

  ; `numbered` is fixed for the life of the raffle, so it is not a parameter here.
  (defun set-terms:string (id:string price:decimal rake:decimal
                           tiers:[decimal]
                           max-tickets:integer seed-cap:decimal
                           rounds-limit:integer max-fund:decimal
                           bounty-share:decimal bounty-split:[integer])
    @doc "Operator: change a raffle's terms for FUTURE rounds only. A live round \
    \froze its own copies at its first ticket, so nothing here can reach money \
    \that is already staked."
    (validate-terms price rake tiers max-tickets seed-cap rounds-limit
                    max-fund bounty-share bounty-split)
    (with-read raffles id
      { "numbered" := numbered, "seed-bucket" := bucket, "rounds-used" := rused
      , "bound" := bound }
      (enforce (or (not numbered) (> max-tickets 0))
        "a numbered raffle needs a fixed supply (max-tickets > 0)")
      ; The bonus invariant (header). The ceiling caps stakes plus bonus, and a
      ; bonus bound to a live round is not back in the bucket until that round
      ; settles. So the ceiling must clear the bonus waiting AND the bonus bound,
      ; with room for one ticket.
      (enforce (>= max-fund (+ (+ bucket bound) price))
        "the prize ceiling must exceed the bonus already waiting, and any bound to a live round, by at least one ticket, or no ticket could be sold")
      ; A waiting bonus needs one more round to be openable under the NEW limit.
      ; If a live round then takes the last slot, the draw keeps the raffle
      ; active rather than strand the bonus (see `draw`).
      ; `or` is a two-argument special form in Pact 5: a third operand is a
      ; runtime arity error that the static gate and a bare load cannot see.
      (enforce (or (= bucket 0.0) (or (= rounds-limit 0) (< rused rounds-limit)))
        "this rounds-limit would strand the bonus waiting for the next round")
      (with-capability (OPERATOR)
        (update raffles id
          { "price": price, "rake": rake
          , "tiers": tiers, "max-tickets": max-tickets
          , "seed-cap": seed-cap, "max-fund": max-fund
          , "rounds-limit": rounds-limit
          , "bounty-share": bounty-share, "bounty-split": bounty-split })
        (emit-event (RAFFLE-RETERMED id price rake tiers
                                     max-tickets seed-cap rounds-limit max-fund
                                     bounty-share bounty-split))))
    (format "raffle {} re-termed for future rounds" [id]))

  ; Dates are per ROUND, so they are not raffle terms: this names the NEXT round's
  ; three instants, and that round's first ticket freezes them like every other
  ; term. A round already selling keeps its own. Every bound below is two-sided
  ; because `add-time` and `diff-time` do not check overflow, and only the
  ; operator can set an instant at all.
  ; A schedule that opens before the round now selling closes could never take
  ; a ticket — no round can start until the current one stops selling — and is
  ; refused here rather than discovered at the first buyer. The refusal grants
  ; nothing; it only moves an error from a buyer to the operator who can fix it.
  (defun schedule-round:string (id:string opens-at:time closes-at:time draws-at:time)
    @doc "Operator: set when the NEXT round sells and draws — sales open at \
    \`opens-at`, close at `closes-at`, and the round is decided by the last \
    \drand beacon published within DRAND-MARGIN-SECONDS after `draws-at`. Frozen into the round by its first ticket; until then it \
    \may be set again, and a schedule nobody buys into simply expires."
    (with-read raffles id { "active" := active, "current" := current }
      (enforce active "this raffle is retired — no new rounds open")
      (let ((t (now-time)))
        (enforce (> (diff-time opens-at t) 0.0)
          "sales cannot open in the past or at this block's own time")
        (if (= current "")
            true
            (with-read rounds current { "state" := cst, "closes-at" := cca }
              (enforce (or (!= cst "selling")
                           (> (diff-time opens-at cca) 0.0))
                (format "the next round cannot open before the current one closes at {}" [(iso cca)]))))
        (enforce (<= (diff-time opens-at t) MAX-LEAD-SECONDS)
          (format "sales cannot open more than {} seconds ahead" [MAX-LEAD-SECONDS]))
        (enforce (>= (diff-time closes-at opens-at) MIN-SALES-SECONDS)
          (format "sales must stay open at least {} seconds" [MIN-SALES-SECONDS]))
        (enforce (<= (diff-time closes-at opens-at) MAX-SALES-SECONDS)
          (format "sales may stay open at most {} seconds" [MAX-SALES-SECONDS]))
        (enforce (>= (diff-time draws-at closes-at) 0.0)
          "the draw cannot come before sales close")
        (enforce (<= (diff-time draws-at closes-at) MAX-DRAW-GAP-SECONDS)
          (format "the draw must come within {} seconds of sales closing" [MAX-DRAW-GAP-SECONDS])))
      (with-capability (OPERATOR)
        (update raffles id
          { "next-opens-at": opens-at, "next-closes-at": closes-at, "next-draws-at": draws-at })
        (emit-event (RAFFLE-SCHEDULED id opens-at closes-at draws-at))))
    (format "raffle {} next round: sells {} to {}, draws at {}" [id (iso opens-at) (iso closes-at) (iso draws-at)]))

  (defun retire-raffle:string (id:string)
    @doc "Operator: stop NEW rounds of this raffle; a round already selling runs \
    \to its draw. There is no un-retire — create a new raffle instead."
    ; A bonus in the bucket is bound to the NEXT round at its first ticket.
    ; Retiring with one waiting would leave money that no round can ever bind and
    ; no path can ever return — permanently, once this module freezes. Refuse
    ; where it happens.
    (with-read raffles id { "seed-bucket" := bucket, "bound" := bound }
      (enforce (= bucket 0.0)
        "this raffle holds a bonus that no future round could pay — let it bind first")
      ; A live round's bonus sits in `bound` until that round is drawn or escapes
      ; with the bonus booked to its buyers. Wait for every round holding a bonus
      ; to settle.
      (enforce (= bound 0.0)
        "a live round still holds this raffle's bonus — let it settle before retiring"))
    (with-capability (OPERATOR)
      (update raffles id { "active": false })
      (emit-event (RAFFLE-RETIRED id)))
    (format "raffle {} retired" [id]))

  ; Binding the bonus WHOLE to the next round to open is what keeps it away from
  ; a round already selling or drawing, and away from any round whose outcome
  ; could be known. The cap counts the bonus waiting plus any bound to a live
  ; round.
  (defun seed-raffle:string (id:string funder:string amount:decimal)
    @doc "Operator: add a bonus to this raffle's prize fund; `funder` signs the \
    \transfer. ONE-WAY — no path returns it to the house, and it is bound WHOLE \
    \to the NEXT round when that round opens at its first ticket."
    (validate-payer funder "funder")
    (enforce (> amount 0.0) "amount must be positive")
    (enforce-unit amount)
    (with-read raffles id
      { "seed-bucket" := bucket, "seed-cap" := cap, "active" := active
      , "rounds-used" := rused, "rounds-limit" := rlimit, "bound" := bound }
      (enforce active "this raffle is retired — a bonus here could never be paid out")
      ; The bonus binds into the next round to OPEN, which `buy` allows only
      ; while (or (= rlimit 0) (< rused rlimit)) — the same condition, checked
      ; here so a bonus is never added to a raffle whose limit is already spent.
      ; A bonus added while the last allowed round is live finds no round to
      ; bind it when that round settles; the draw then leaves the raffle active
      ; instead of retiring it, and the operator raising the limit pays it out.
      (enforce (or (= rlimit 0) (< rused rlimit))
        "this raffle is on its last round — a bonus here could never be paid out")
      (let ((new-bucket (+ bucket amount)))
        ; The cap covers bonus bound to live rounds too, so waiting plus live
        ; bonus never passes a ceiling the raffle may later be given (the bonus
        ; invariant).
        (enforce (<= (+ new-bucket bound) cap)
          "bonus would exceed this raffle's cap, counting the bonus bound to live rounds")
        (with-capability (OPERATOR)
          (transfer-create funder (pool-account id) (pool-guard id) amount)
          (update raffles id { "seed-bucket": new-bucket })
          (emit-event (RAFFLE-SEEDED id funder amount new-bucket)))))
    (format "raffle {} seeded" [id]))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; BUY ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ; A round exists from its FIRST TICKET. The first buy after the scheduled sales
  ; instant creates the round from the raffle's terms and schedule as they stand
  ; that moment, freezing both, binding the waiting bonus and consuming the
  ; schedule; every later buy joins it. A scheduled round nobody buys into is
  ; simply never a round, and the operator can change terms and dates freely
  ; until the first ticket is sold.
  (defun buy:string (id:string account:string count:integer picks:[integer])
    @doc "Buy tickets: pass an empty `picks` list to take the next `count` stubs, \
    \or a list of unsold numbers (in a numbered raffle) with `count` equal to its \
    \length, and sign coin.TRANSFER of count * price to this raffle's pool. Odds \
    \are your tickets over all tickets sold, and winners are paid at the draw — \
    \there is nothing to claim. The first ticket after the scheduled sales \
    \instant opens the round."
    (enforce (and (>= count 1) (<= count MAX-TICKETS-PER-TX))
      (format "count must be 1..{}" [MAX-TICKETS-PER-TX]))
    (enforce (or (= (length picks) 0) (= (length picks) count))
      "picks must be empty or hold exactly `count` entries")
    (validate-payer account "buyer")
    (with-read raffles id
      { "current" := current, "numbered" := numbered, "round-seq" := seq
      , "active" := active, "rounds-limit" := rlimit, "rounds-used" := rused
      , "price" := gprice, "rake" := grake, "tiers" := gtiers
      , "max-tickets" := gmax, "max-fund" := gfund
      , "bounty-share" := gbshare, "bounty-split" := gbsplit
      , "next-opens-at" := noa, "next-closes-at" := nca, "next-draws-at" := nda
      , "seed-bucket" := bucket, "bound" := bound }
      (enforce (or (= (length picks) 0) numbered)
        "this raffle does not use picked numbers")
      (enforce (or (= (length picks) count) (not numbered))
        "this raffle requires you to pick your numbers")
      ; The read is let-bound, not evaluated inside an enforce argument: an
      ; unbound read there works on KDA-CE and fails on an upstream-lineage node.
      ; `if` is lazy, so nothing is read before a raffle's first round.
      (let* ((t (now-time))
             (live (if (= current "") false
                       (let ((pr (read rounds current)))
                         (and (= (at 'state pr) "selling") (< t (at 'closes-at pr))))))
             (rk (if live current (round-key id (+ seq 1)))))
        ; ---- the FIRST ticket of a round: create it from the schedule --------
        (if live "joining the live round"
            (let ((new-seq (+ seq 1)))
              (enforce active "this raffle is retired — no new rounds open")
              ; counted against rounds that sold, which is every round.
              (enforce (or (= rlimit 0) (< rused rlimit))
                "this raffle has run its last round")
              ; A buyer who arrives after the live round closed sees THAT, not a
              ; missing schedule: the round is over and the next one is not set.
              (enforce (!= noa EPOCH)
                (if (= current "")
                    "this raffle has no round scheduled — the operator sets when the next one sells"
                    "sales are closed for this round — the next round is not scheduled yet"))
              (enforce (>= t noa)
                (format "sales have not opened yet — they open at {}" [(iso noa)]))
              ; The schedule expired unsold: it is never a round, and the raffle
              ; waits for the operator to schedule again.
              (enforce (< t nca)
                (format "the scheduled round closed at {} with no ticket sold — the operator must schedule again" [(iso nca)]))
              ; The round's beacon, pinned now from the frozen draw instant and
              ; bound only after every schedule check above, so an unscheduled
              ; raffle (EPOCH) reports that, never drand's genesis refusal.
              (let ((dr (drand-round-for nda)))
                (insert rounds rk
                  { "raffle-id": id, "seq": new-seq
                  , "opens-at": noa, "closes-at": nca, "draws-at": nda
                  , "price": gprice, "rake": grake, "tiers": gtiers
                  , "numbered": numbered, "max-tickets": gmax
                  , "max-fund": gfund
                  , "bounty-share": gbshare, "bounty-split": gbsplit
                  , "seed-in": bucket
                  , "sales": 0.0, "tickets": 0
                  , "decide-height": dr
                  , "state": "selling"
                  , "draw-seed": -1, "deciding-block": -1
                  , "ranks": [], "amounts": [], "accounts": []
                  , "escape-unit": 0.0 })
                (update raffles id
                  { "round-seq": new-seq, "current": rk
                  , "seed-bucket": 0.0, "bound": (+ bound bucket)
                  ; consumed: the round after this one needs its own schedule
                  , "next-opens-at": EPOCH, "next-closes-at": EPOCH, "next-draws-at": EPOCH })
                (emit-event (ROUND-OPENED id new-seq noa nca nda gprice grake bucket dr))
                "opened")))
        ; ---- every ticket, first or later: the ROUND's frozen terms ----------
        (with-read rounds rk
          { "seq" := rseq, "opens-at" := oa, "closes-at" := ca, "price" := price
          , "max-tickets" := rmax, "sales" := sales, "tickets" := n0
          , "state" := rstate, "seed-in" := rseed, "max-fund" := rfund }
          (enforce (= rstate "selling") "this round is no longer selling")
          (enforce (>= t oa) (format "sales have not opened yet — they open at {}" [(iso oa)]))
          (enforce (< t ca) "sales are closed for this round")
          (enforce (or (= rmax 0) (<= (+ n0 count) rmax))
            "not enough tickets left in this raffle")
          (let* ((total (* price (dec count)))
                 (new-sales (+ sales total))
                 ; The ceiling caps what the round TAKES IN: stakes plus the bonus
                 ; it bound at open. So the prize, which is that net of the fee,
                 ; can never exceed it either.
                 (intake (+ new-sales rseed)))
            (enforce (<= intake rfund)
              "this round has reached its maximum prize fund")
            ; picked numbers: range-checked and unique within the round
            (if (= (length picks) 0) "auto"
                (let ((ok (map (lambda (idx:integer)
                                 (let ((num (at idx picks)))
                                   (enforce (and (>= num 0) (< num rmax))
                                     "a picked number is outside this raffle")
                                   (insert picked-numbers (number-key rk num)
                                     { "rank": (+ n0 idx) })
                                   num))
                               (enumerate 0 (- count 1)))))
                  (format "picked {}" [ok])))
            (transfer-create account (pool-account id) (pool-guard id) total)
            (map (lambda (i:integer)
                   (insert tickets (ticket-key rk (+ n0 i))
                     { "account": account
                     , "number": (if (= (length picks) 0) -1 (at i picks)) }))
                 (enumerate 0 (- count 1)))
            ; carry `paid` forward rather than writing a literal false —
            ; a literal would clear a settled escape claim and re-open it
            (with-default-read holdings (holding-key rk account)
              { "count": 0, "paid": false } { "count" := held, "paid" := was-paid }
              (write holdings (holding-key rk account)
                { "count": (+ held count), "paid": was-paid }))
            (update rounds rk
              { "sales": (+ sales total), "tickets": (+ n0 count) })
            ; The FIRST ticket of a round is the moment that round becomes one
            ; the rounds-limit counts.
            (with-read raffles id { "pending" := p, "rounds-used" := rused2 }
              (update raffles id
                { "pending": (+ p total)
                , "rounds-used": (if (= n0 0) (+ rused2 1) rused2) }))
            (emit-event (TICKETS-BOUGHT id rseq account count n0 picks))
            (format "bought {} ticket(s) in {} round {}" [count id rseq]))))))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; DRAW ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ; Winners never act. There is no attempt and no retry: the beacon is the one
  ; drand round pinned at the round's first ticket, and exactly one valid
  ; signature exists for it, so the winner this returns is the one `preview`
  ; returned to anyone who asked, from the moment drand published it. Anyone may
  ; send it, and whoever does chooses nothing: a wrong or forged signature
  ; aborts inside `verified-seed`. No time check is needed either — the beacon
  ; for a round drand has not published yet does not exist, so nothing can
  ; verify early.
  (defun draw:string (id:string seq:integer payee:string sig-hex:string)
    @doc "Permissionless: settle the round from its pinned drand beacon \
    \(`sig-hex`, the beacon's signature as drand publishes it). k = \
    \min(tiers, tickets) winners are PAID IN THIS TRANSACTION, the fee is \
    \taken, and the crank share goes to `payee`."
    (validate-payer payee "bounty payee")
    (let* ((rk (round-key id seq))
           (pool (pool-account id))
           (revenue (at 'revenue (read state-table STATE-KEY))))
      (with-read rounds rk
        { "state" := st, "decide-height" := dh
        , "sales" := sales, "tickets" := n, "rake" := rake, "tiers" := tiers
        , "seed-in" := seed-in, "bounty-share" := bshare }
        (enforce (= st "selling") "this round is already settled")
        (let* ((dseed (round-seed rk dh sig-hex))
               (fee (floor (* rake sales) PREC))
               ; One role ends a round and is paid out of the FEE, never the prize
               ; fund: whoever sends this draw. Floored to PREC so an unfloored
               ; value never reaches a transfer.
               (draw-bounty (floor (* fee bshare) PREC))
               (to-revenue (- fee draw-bounty))
               (fund (+ (- sales fee) seed-in))
               (k (if (< n (length tiers)) n (length tiers)))
               (ranks (draw-ranks dseed rk n k))
               (amounts (tier-amounts fund tiers k))
               (accounts (map (lambda (r:integer)
                                (at 'account (read tickets (ticket-key rk r))))
                              ranks))
               ; Every outflow of this transaction — winners, the crank share
               ; and the fee — aggregated per DISTINCT account. Pact 5's managed
               ; install identity is (sender, receiver) and EXCLUDES the amount,
               ; so two installs to one account collide however different the
               ; amounts are. The drawer may also be a winner, and a winner may
               ; hold several winning ranks, so aggregating all of them together
               ; is the only shape that survives every aliasing case. Without it
               ; such a round would abort here on every attempt.
               (outflows (filter (lambda (o:object) (> (at 'amount o) 0.0))
                           ; `+` is BINARY in Pact 5, exactly like `or` and `and`.
                           (+ (map (lambda (i:integer)
                                     { "account": (at i accounts)
                                     , "amount":  (at i amounts) })
                                   (enumerate 0 (- k 1)))
                              [ { "account": payee,    "amount": draw-bounty }
                              , { "account": revenue,  "amount": to-revenue } ])))
               (payees (fold (lambda (acc:[object] o:object) (merge-payee acc o))
                             [] outflows)))
          ; ---- pay: exactly one transfer per DISTINCT account ---------------
          ; Authorised by the pool's MODULE guard: coin enforces it, and it
          ; passes only because prize-draw is on the call stack right here.
          (map (lambda (o:object)
                 (let ((a (at 'account o)) (amt (at 'amount o)))
                   (install-capability (TRANSFER pool a amt))
                   (transfer pool a amt)
                   "paid"))
               payees)
          ; ---- events report the LOGICAL amounts, not the aggregated ones ---
          (map (lambda (i:integer)
                 (emit-event (WINNER-PAID id seq (at i accounts) (at i amounts))))
               (enumerate 0 (- k 1)))
          (if (> draw-bounty 0.0)
              (let ((e (emit-event (BOUNTY-PAID id seq "draw" payee draw-bounty))))
                "draw share paid")
              "no draw share")
          (emit-event (FEE-PAID id seq fee draw-bounty))
          (update rounds rk
            { "state": "drawn", "draw-seed": dseed, "deciding-block": dh
            , "ranks": ranks, "amounts": amounts, "accounts": accounts })
          (with-read raffles id
            { "pending" := pending, "rounds-done" := done
            , "bound" := bound, "rounds-limit" := rlimit, "active" := active
            , "seed-bucket" := bucket }
            ; The rounds-limit retires a raffle by itself, but NEVER while a bonus is
            ; still waiting in the bucket or bound to another live round. Retired,
            ; that bonus could never be bound again, and after the freeze nothing
            ; could reach it. Left active, the raffle still opens no round while its
            ; limit is spent; the operator raising the limit is what pays the bonus
            ; out. `escape` applies the same rule.
            (let* ((now-done (+ done 1))
                   (now-bound (- bound seed-in)))
              (update raffles id
                { "pending": (- pending sales), "rounds-done": now-done
                , "bound": now-bound
                , "active": (if (and (> rlimit 0) (>= now-done rlimit))
                                (if (and (= bucket 0.0) (= now-bound 0.0)) false active)
                                active) })))
          (emit-event (DRAWN id seq dseed dh n ranks amounts accounts))
          (format "{} round {}: seed {} ranks {} pay {}" [id seq dseed ranks amounts])))))

  ; This is the fairness claim made checkable by a stranger: from the moment drand
  ; publishes a round's pinned beacon, anyone can pass it here and see exactly
  ; who wins before the draw transaction is sent. It is unavailable before that
  ; — until then the outcome genuinely is not determined, and saying otherwise
  ; would be a lie.
  (defun preview:object (id:string seq:integer sig-hex:string)
    @doc "READ-ONLY: exactly what `draw` will do with this beacon, computable by \
    \anyone from the moment drand publishes the round's pinned beacon. A wrong \
    \or forged signature aborts, as it does in `draw`. If a draw ever disagrees \
    \with what this returned, the module is broken. A SETTLED round is refused: \
    \its result is in `get-round`, and anyone can recompute it with the public \
    \`round-seed` and `draw-ranks`."
    (let ((rk (round-key id seq)))
      (with-read rounds rk
        { "state" := st, "decide-height" := dr, "tickets" := n, "tiers" := tiers
        , "sales" := sales, "rake" := rake, "seed-in" := seed-in }
        ; Refused where it happens (review C-1): the two rounds decided by a block
        ; before drand hold a block height here, which is also a real past drand
        ; round, so answering would name winners who did not win. A settled round
        ; has nothing left to preview.
        (enforce (= st "selling") "this round is settled — read get-round for its result")
        (let* ((dseed (round-seed rk dr sig-hex))
               (k (if (< n (length tiers)) n (length tiers)))
               (ranks (draw-ranks dseed rk n k))
               (fee (floor (* rake sales) PREC))
               (fund (+ (- sales fee) seed-in)))
          { "state": st, "drand-round": dr
          , "draw-seed": dseed, "ranks": ranks
          , "amounts": (tier-amounts fund tiers k)
          , "accounts": (map (lambda (r:integer)
                               (at 'account (read tickets (ticket-key rk r))))
                             ranks) }))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; ESCAPE ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ; ONE WAY IN: nobody drew the round within ESCAPE-AFTER-SECONDS of the moment
  ; drand was due to publish its pinned beacon. Until an escape lands a draw still
  ; settles the round normally, so the escape can never overturn a round anybody
  ; drew. Every round has at least one ticket, so the refund is always a real
  ; division: stake plus an exact per-ticket share of the bonus.
  (defun escape:string (id:string seq:integer)
    @doc "Last resort, permissionless: a round escapes when nobody has drawn it \
    \for ninety days after its drand beacon was due — drand stopped, or the game \
    \was abandoned. It books every buyer their own stake plus their exact share \
    \of the bonus, selects no winner and takes no fee."
    (let ((rk (round-key id seq)))
      (with-read rounds rk
        { "state" := st, "decide-height" := dr
        , "sales" := sales, "tickets" := n, "seed-in" := seed-in }
        (enforce (= st "selling") "this round is settled")
        ; a frozen module states its own preconditions: a round exists only from
        ; its first ticket, so this cannot fail, and the division below is safe.
        (enforce (> n 0) "this round has no tickets")
        (enforce (> (diff-time (now-time) (time-of-round dr)) ESCAPE-AFTER-SECONDS)
          (format "this round can still be drawn — it may escape only if nobody draws it by {}"
                  [(iso (add-time (time-of-round dr) ESCAPE-AFTER-SECONDS))]))
          (let* ((pot seed-in)
                 (unit (floor (/ pot (dec n)) PREC))
                 (booked (+ sales (* unit (dec n))))
                 ; What is left after flooring the per-ticket rate — strictly less
                 ; than one unit per ticket, so no buyer can be paid it. Leaving it
                 ; in the bucket permanently blocks `retire-raffle` and the
                 ; `set-terms` wind-down, which both refuse a non-zero bucket:
                 ; measured, 0.000000000002 was enough to make a raffle
                 ; un-retirable forever. Indivisible dust leaves as revenue.
                 (dust (- pot (* unit (dec n))))
                 (rev (at 'revenue (read state-table STATE-KEY))))
            (with-read raffles id
              { "owed" := owed, "pending" := pending, "seed-bucket" := bucket
              , "bound" := bound
              , "rounds-done" := done, "rounds-limit" := rlimit, "active" := active }
              (let* ((now-done (+ done 1))
                     (now-bound (- bound seed-in)))
                (update raffles id
                  { "owed": (+ owed booked)
                  , "pending": (- pending sales)
                  , "bound": now-bound
                  ; an escaped round consumed one of a one-off's rounds — without
                  ; this a "run once" raffle quietly opens another
                  , "rounds-done": now-done
                  ; never retire while a bonus waits or is live — see `draw`
                  , "active": (if (and (> rlimit 0) (>= now-done rlimit))
                                  (if (and (= bucket 0.0) (= now-bound 0.0)) false active)
                                  active) })))
            (if (> dust 0.0)
                (let ((x (install-capability (TRANSFER (pool-account id) rev dust))))
                  (transfer (pool-account id) rev dust)
                  "dust swept")
                "no dust")
            ; The escape takes NO FEE — the dust above is not one. It is the floor
            ; remainder of a rate no buyer can be paid at, swept so it cannot wedge
            ; the raffle's wind-down.
            (update rounds rk { "state": "escaped", "escape-unit": unit })
            (emit-event (ESCAPED id seq dr booked))
            (format "{} round {} escaped: nobody drew it" [id seq])))))

  (defun claim-escape:string (id:string seq:integer account:string)
    @doc "Permissionless push: pay one account its stake back, plus its share of \
    \the bonus, from an ESCAPED round. Anyone may crank it, one account per \
    \transaction; the money can only ever go to the account that bought the \
    \tickets."
    (let* ((rk (round-key id seq))
           (hk (holding-key rk account)))
      (with-read rounds rk
        { "state" := st, "price" := price, "escape-unit" := unit }
        (enforce (= st "escaped") "this round did not escape — nothing to claim")
        (with-read holdings hk { "count" := count, "paid" := paid }
          (enforce (not paid) "already paid")
          (let ((amount (* (dec count) (+ price unit))))
            (install-capability (TRANSFER (pool-account id) account amount))
            (transfer (pool-account id) account amount)
            (update holdings hk { "count": count, "paid": true })
            (with-read raffles id { "owed" := owed }
              (update raffles id { "owed": (- owed amount) }))
            (emit-event (ESCAPE-PAID id seq account amount))
            (format "paid {} to {}" [amount account]))))))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; VIEWS ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (defun get-raffle:object (id:string)
    @doc "A raffle's terms, schedule, bonus bucket and ledger." (read raffles id))

  (defun get-round:object (id:string seq:integer)
    @doc "A round: frozen terms, sales, its pinned drand round and the draw result."
    (read rounds (round-key id seq)))

  (defun get-ticket:object (id:string seq:integer rank:integer)
    @doc "One ticket." (read tickets (ticket-key (round-key id seq) rank)))

  (defun get-holding:object (id:string seq:integer account:string)
    @doc "How many tickets an account holds in a round — the site's 'my tickets'."
    (with-default-read holdings (holding-key (round-key id seq) account)
      { "count": 0, "paid": false } { "count" := c, "paid" := p }
      { "count": c, "paid": p }))

  (defun get-number:object (id:string seq:integer number:integer)
    @doc "Which rank holds a picked number in a numbered raffle."
    (read picked-numbers (number-key (round-key id seq) number)))

  (defun get-revenue:string ()
    @doc "Where this contract's fees are paid, recorded once at setup. Returns an empty string \
    \before setup has run, so a reader never has to handle an abort."
    (with-default-read state-table STATE-KEY { "revenue": "" } { "revenue" := r } r))

  (defun list-raffles:[string] ()
    @doc "Every raffle id. A full scan — read-only, never on a money path."
    (keys raffles))

  ; The check is >= because anyone may donate KDA straight to a pool account, and
  ; such surplus is unrecoverable by design.
  (defun pool-status:object (id:string)
    @doc "One raffle's solvency. `ok` must always be true: the pool holds at \
    \least its bonus, its unclaimed escape money and its undrawn sales."
    (let ((bal (get-balance (pool-account id))))
      (with-read raffles id
        { "seed-bucket" := seed, "owed" := owed, "pending" := pending
        , "bound" := bound }
        { "pool": (pool-account id), "balance": bal, "bonus": seed
        , "owed": owed, "pending": pending, "bound": bound
        , "ok": (>= bal (+ seed (+ bound (+ owed pending)))) })))
)

(if (read-msg "init")
    [ (create-table state-table)
      (create-table raffles)
      (create-table rounds)
      (create-table tickets)
      (create-table holdings)
      (create-table picked-numbers) ]
    "upgrade complete")
