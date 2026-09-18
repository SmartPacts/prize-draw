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
;; A ROUND RUNS BY THE CALENDAR, AND THE BLOCK ALONE DECIDES IT. The operator
;; schedules three instants for the next round — sales open, sales close, draw —
;; and the round's FIRST TICKET freezes them with every other term. Sales are
;; enforced by the chain's clock. At or after the draw instant, anyone opens the
;; draw, which fixes the candidate blocks as the next ones on the chain; until
;; then nothing exists that could decide the round, so nobody, the house
;; included, can know the winner before the advertised moment. The candidates
;; are read from block-history — an immutable, money-free, raffle-blind record
;; whose `attest` takes no arguments, so a recorder chooses neither the key
;; (block-height - 1) nor the value (prev-block-hash) and can only publish or
;; stay silent. The draw is then a pure function of the round key and the
;; deciding block's hash. There are no secrets, no bonds and nobody to wait for.
;;
;; NOTHING RE-ROLLS. A draw whose seed depends on a value some caller can mint
;; again — a fresh attempt key, a second capture — is not a draw: the same block
;; hash then yields a different winner on every try, and whoever can decline to
;; act chooses the winner for the price of gas. There is no attempt and no retry
;; here. The bounded window of DECIDE-WINDOW candidate heights cannot re-roll
;; either: the decider is the LOWEST RECORDED one, final the moment it exists.
;;
;; 🔴 WHAT CAN STILL TILT A DRAW, DISCLOSED (founder decision, ADR-C19). Nobody
;; can choose a winner. Three parties can buy themselves a slightly better chance:
;; - a party recording blocks ALONE sees each candidate's outcome as it is mined
;;   and can decline to record one it dislikes and take the next — the best of
;;   three, or a refund of the whole round by recording none — and only while no
;;   independent recorder attests (two record on mainnet today);
;; - a miner holding tickets can discard a candidate block it mined whose hash
;;   loses, paying the block reward for one more roll;
;; - the miner of the block AFTER a candidate can leave every attest of it out of
;;   that block for nothing, so the next candidate decides instead — the one
;;   channel an independent recorder does NOT remove, since every recorder's
;;   attest for a height goes through that same block.
;; Each is bounded to the three candidates plus a refund; none selects. The
;; player terms must say all three.
;;
;; THE ESCAPE is the last resort and still cannot steer a winner. A round escapes
;; when nobody opened its draw within a day of its draw instant, or when NO
;; candidate in its window was recorded — permanent once the last candidate's one
;; recording block has passed, and immediate from then. It returns each buyer
;; exactly their own stake plus their share of the bonus, selects no winner, and
;; takes no fee.
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

; The winner is decided by the LOWEST RECORDED of DECIDE-WINDOW candidate blocks
; fixed at the round's draw instant. A round refunds only if no candidate is
; ever recorded or nobody opened its draw. Each raffle has its own isolated pool.
(module prize-draw GOVERNANCE

  @doc "Prize Draw raffles. Many raffles as config rows on one always-a-winner state \
  \machine: ranks drawn from the tickets actually sold, the whole fund paid to \
  \k = min(tiers, tickets) winners inside the draw transaction."

  (use coin)
  ;; There is no randomness engine, and one would add no entropy here: this
  ;; module would be its sole committer and the committed value is public by
  ;; design, while its per-attempt round key is exactly the variable that makes a
  ;; draw re-rollable, and its `finalize` would sit in a module governed by a
  ;; DIFFERENT keyset — still upgradeable after this one freezes. What decides a
  ;; round instead is ONE named future block, written down by a module that can
  ;; never be upgraded. block-history is that record: immutable, attested-only,
  ;; and deployed in namespace `free` on every mainnet chain. It is named FULLY
  ;; and PINNED to its code hash. Unqualified, `use` resolves in THIS module's
  ;; namespace and fails anywhere but `free`, with "Cannot find module:
  ;; <ns>.block-history". The pin makes this module refuse to load against any
  ;; code but the genuine one: a wrong hash fails with "hash not blessed". The
  ;; REPL computes the same hash for free.block-history as mainnet does, so ONE
  ;; source pins correctly on every network where it is deployed in `free`. A
  ;; hash cannot tell a same-code copy whose deploy transaction planted rows from
  ;; a clean one; the pin leans on the deployed instances having been verified
  ;; clean.
  (use free.block-history "P3J_LK-Wivmuyw7SB7TzPmfj6t-GCtG3YnfHNAaU2UU"
    [ hash-of has-attested get-attested ])

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
  ; If nobody opens the draw within this of the draw instant, the round can be
  ; escaped: every stake goes back and no fee is taken. The crank opens it at
  ; the draw instant; this grace exists so a round whose draw nobody ever opened
  ; is not stuck. From the grace on, opening and escaping both stay possible
  ; until one of them lands — the house's cost of a dead crank.
  (defconst OPEN-DRAW-GRACE-SECONDS:decimal 86400.0)
  ; "Not scheduled." A raffle's next-round instants hold this until `schedule-round`.
  (defconst EPOCH:time (time "1970-01-01T00:00:00Z"))

  ; Prize tiers per raffle. Bounds the draw transaction (k transfers).
  (defconst MAX-TIERS:integer 10)

  ; Gas bound on one buy, and the largest supply a numbered raffle may declare.
  (defconst MAX-TICKETS-PER-TX:integer 50)
  (defconst MAX-SUPPLY:integer 1000000)

  ; ABSOLUTE bound on what one round can hold — the miner-grind control (a
  ; relative cap grows with the pot; this one does not).
  ; The rail is deliberately WIDE: everything the house tunes has to stay tunable,
  ; so the loss limit lives in the per-raffle ceiling, which the operator changes
  ; at any time for FUTURE rounds while a round already selling keeps the ceiling
  ; it froze at open. The rail only stops a ceiling nobody could ever justify.
  ; The ABSOLUTE rail, frozen with the module: no raffle may ever set a prize
  ; ceiling above this. The operational ceiling is per raffle (`max-fund`), set
  ; by the operator and frozen into each round at open — the pot ceiling is meant
  ; to stay adjustable, and OPERATOR (not GOVERNANCE) gates it so it still is
  ; after the module freezes.
  ;
  ; 🔴 IT IS A DISCLOSED LOSS LIMIT, NOT A SAFETY BOUND. The miner of a candidate
  ; block can throw it away for the price of one block reward, which on mainnet
  ; is of the order of a single KDA, so no ceiling near that makes grinding
  ; unprofitable. What a ceiling bounds is how much ONE round can lose to that,
  ; not whether it can happen. Size it as a business risk.
  (defconst MAX-ROUND-FUND:decimal 100000.0)

  ; Ceiling on a raffle's one-way bonus bucket. Same wide rail, same reasoning.
  (defconst MAX-SEED-CAP:decimal 100000.0)

  ; The first candidate block is this many blocks after the block in which the
  ; draw was opened, so it postdates that block; 2 is margin. The height is chosen
  ; by whoever opens the draw and that confers no advantage: the hash of a block
  ; that does not yet exist is unknown to everyone.
  (defconst DECIDE-DELAY:integer 2)

  ; The deciding block is the LOWEST RECORDED of decide-height and the
  ; DECIDE-WINDOW - 1 heights after it. On mainnet a block goes unrecorded when
  ; the next one arrives within ~15 s, because miners refresh the block they are
  ; building only that often — no recorder can beat it. A second, independent
  ; recorder narrows the gap and cannot close it: measured on mainnet, one
  ; recorder narrows the gap and cannot close it. MEASURED on mainnet chain 2 over
  ; 2,400 consecutive heights with TWO recorders running: 91.0 % of heights on
  ; record. Pinned to a SINGLE height, 9.04 % of rounds would die unrecorded —
  ; about one in eleven. Misses are ANTI-correlated: 213 lone misses, 2 adjacent
  ; pairs, and not one run of three, so three candidates took the dead rate to
  ; 0 of 2,398 windows.
  ; The decider is final the moment it is recorded, because a height can be
  ; recorded only in the very next block: once a higher candidate is on record,
  ; every lower one's only chance has passed.
  ; 🔴 A party recording ALONE sees each candidate's outcome as it is mined and
  ; can decline to record one it dislikes and take the next, or none and take
  ; the refund: a best of three plus a refund, at most. An independent recorder
  ; removes that choice — whoever records first decides — and two record on
  ; mainnet today. The miner of block h + 1 keeps a choice no recorder can take
  ; away: it can leave every attest of h out of its block. Disclosed, never
  ; denied.
  (defconst DECIDE-WINDOW:integer 3)

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
    (enforce false "prize-draw is frozen: governance can never pass again"))

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
                                price:decimal rake:decimal seed-in:decimal) @event true)
  (defcap TICKETS-BOUGHT:bool  (id:string seq:integer account:string count:integer
                                from-rank:integer numbers:[integer]) @event true)
  (defcap DRAW-OPENED:bool     (id:string seq:integer decide-height:integer) @event true)
  (defcap DRAWN:bool           (id:string seq:integer draw-seed:integer deciding-block:integer
                                tickets:integer ranks:[integer] amounts:[decimal]
                                accounts:[string]) @event true)
  (defcap WINNER-PAID:bool     (id:string seq:integer account:string amount:decimal) @event true)
  (defcap FEE-PAID:bool        (id:string seq:integer fee:decimal bounties:decimal) @event true)
  (defcap BOUNTY-PAID:bool     (id:string seq:integer role:string account:string amount:decimal) @event true)
  (defcap ESCAPED:bool         (id:string seq:integer decide-height:integer booked:decimal) @event true)
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
    ; What the two roles that END a round are paid, out of the FEE and never
    ; the prize: `bounty-share` of the fee, divided by these weights, in the
    ; order [recorder drawer]. Each round freezes both at open.
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
    draws-at:time               ; frozen: the draw may be opened from here
    price:decimal               ; frozen
    rake:decimal                ; frozen
    tiers:[decimal]             ; frozen
    numbered:bool               ; frozen
    max-tickets:integer         ; frozen
    max-fund:decimal            ; frozen prize ceiling of THIS round
    bounty-share:decimal        ; frozen
    bounty-split:[integer]      ; frozen [recorder drawer]
    seed-in:decimal             ; bonus bound to THIS round at open
    sales:decimal
    tickets:integer             ; the draw's sample space [0, tickets)
    decide-height:integer       ; the FIRST of DECIDE-WINDOW candidate heights.
                                ; Written once, by `open-draw` at or after the draw
                                ; instant, and read by nothing that can change it. 0 until then.
    deciding-block:integer      ; the candidate that actually decided it, written
                                ; at the draw; -1 until then
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

  (defun now:integer () (at 'block-height (chain-data)))
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

  ; Both inputs are fixed before they are jointly knowable: the round key at the
  ; round's first ticket, the block hash by mining, at a height fixed by
  ; `open-draw` before the block existed.
  (defun round-seed:integer (rk:string bhash:string)
    @doc "This round's draw seed: a domain-separated hash of the round key and \
    \the hash of the block that decided this round. Pure and public."
    (mod (str-to-int 64 (hash (format "prize-draw|{}|{}" [rk bhash])))
         DRAW-SEED-RANGE))

  ; Final the moment it is non-negative — and that finality is INHERITED, not
  ; proved here. `free.block-history` writes {block-height - 1 -> prev-block-hash},
  ; so a height can be recorded only in the block immediately after it; by the time
  ; a higher candidate is on record, every lower one's single chance has already
  ; passed. This module pins that record to its code hash (see the `use` above),
  ; which is what makes the inherited property safe to rely on.
  (defun decided-height:integer (dh:integer)
    @doc "The height that decides a round whose window starts at `dh`: the LOWEST \
    \RECORDED of dh .. dh + DECIDE-WINDOW - 1, or -1 while none of them is. \
    \Read-only."
    (fold (lambda (acc:integer h:integer)
            (if (and (= acc -1) (has-attested h)) h acc))
          -1
          (enumerate dh (+ dh (- DECIDE-WINDOW 1)))))

  (defun decidable:bool (id:string seq:integer)
    @doc "Can this round be drawn now? Read-only, and true only when the round is \
    \still selling, its draw is open, and a candidate block is on record."
    (with-read rounds (round-key id seq)
      { "decide-height" := dh, "state" := st }
      (and (= st "selling")
           (and (!= dh 0) (!= (decided-height dh) -1)))))

  (defun draw-status:object (id:string seq:integer)
    @doc "Where a round stands on its way to a draw: whether the draw is open, \
    \its candidate heights, and which of them is on record. Read-only."
    (with-read rounds (round-key id seq)
      { "decide-height" := dh, "state" := st, "tickets" := n, "draws-at" := da }
      { "state": st
      , "tickets": n
      , "draws-at": da
      , "draw-open": (!= dh 0)
      , "decide-height": dh
      , "candidates": (if (= dh 0) [] (enumerate dh (+ dh (- DECIDE-WINDOW 1))))
      , "block-recorded": (if (= dh 0) false (!= (decided-height dh) -1))
      , "deciding-block": (if (= dh 0) -1 (decided-height dh)) }))

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
    ; The crank share and its weights. Weights are a RATIO, not percentages:
    ; [1 1] splits evenly, [3 1] gives the recorder three quarters, [0 1] pays
    ; the recorder nothing. ANY distribution is allowed; the only structural rule
    ; is that the weights cannot both be zero, because they are a divisor.
    ; 🔴 What a zero recorder weight gives up: recording is what fixes the draw,
    ; and an INDEPENDENT recorder is what removes the house's best-of-three
    ; (see DECIDE-WINDOW). Paying nothing here leaves that control resting
    ; entirely on recorders that run for other reasons.
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
    \`opens-at`, close at `closes-at`, and the candidate blocks are fixed at or \
    \after `draws-at`. Frozen into the round by its first ticket; until then it \
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
              (insert rounds rk
                { "raffle-id": id, "seq": new-seq
                , "opens-at": noa, "closes-at": nca, "draws-at": nda
                , "price": gprice, "rake": grake, "tiers": gtiers
                , "numbered": numbered, "max-tickets": gmax
                , "max-fund": gfund
                , "bounty-share": gbshare, "bounty-split": gbsplit
                , "seed-in": bucket
                , "sales": 0.0, "tickets": 0
                , "decide-height": 0
                , "state": "selling"
                , "draw-seed": -1, "deciding-block": -1
                , "ranks": [], "amounts": [], "accounts": []
                , "escape-unit": 0.0 })
              (update raffles id
                { "round-seq": new-seq, "current": rk
                , "seed-bucket": 0.0, "bound": (+ bound bucket)
                ; consumed: the round after this one needs its own schedule
                , "next-opens-at": EPOCH, "next-closes-at": EPOCH, "next-draws-at": EPOCH })
              (emit-event (ROUND-OPENED id new-seq noa nca nda gprice grake bucket))
              "opened"))
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

  ; The candidates are anchored to the round's draw instant, not to its close:
  ; between close and draw nothing exists that could decide the round, so nobody,
  ; the house included, can know the winner before the advertised moment. Anyone
  ; may send this, and whoever does chooses nothing that matters: the height it
  ; fixes is DECIDE-DELAY blocks in the future, whose hash nobody has.
  (defun open-draw:string (id:string seq:integer)
    @doc "Permissionless: at or after the round's draw instant, fix its three \
    \candidate blocks, starting DECIDE-DELAY blocks after the one this lands in. \
    \From here the lowest recorded candidate decides, and anyone may draw."
    (let ((rk (round-key id seq)))
      (with-read rounds rk
        { "state" := st, "decide-height" := dh, "draws-at" := da }
        (enforce (= st "selling") "this round is not selling")
        (enforce (= dh 0) "the draw is already open")
        (enforce (>= (now-time) da) (format "the draw opens at {}" [(iso da)]))
        (let ((h (+ (now) DECIDE-DELAY)))
          (update rounds rk { "decide-height": h })
          (emit-event (DRAW-OPENED id seq h))
          (format "{} round {}: candidate blocks {} to {}" [id seq h (+ h (- DECIDE-WINDOW 1))])))))

  ; Winners never act. There is no attempt and no retry: the deciding block is
  ; the lowest recorded of DECIDE-WINDOW candidates fixed at the draw instant,
  ; final the moment it exists, so the winner this returns is the one `preview`
  ; returned to anyone who asked, from the moment that block was recorded.
  (defun draw:string (id:string seq:integer payee:string)
    @doc "Permissionless: settle the round from the hash of the block that \
    \decided it. k = min(tiers, tickets) winners are PAID IN THIS TRANSACTION, \
    \the fee is taken, and two crank shares go to whoever recorded the deciding \
    \block and to `payee`."
    (validate-payer payee "bounty payee")
    (let* ((rk (round-key id seq))
           (pool (pool-account id))
           (revenue (at 'revenue (read state-table STATE-KEY))))
      (with-read rounds rk
        { "state" := st, "decide-height" := dh
        , "sales" := sales, "tickets" := n, "rake" := rake, "tiers" := tiers
        , "seed-in" := seed-in, "bounty-share" := bshare, "bounty-split" := bsplit }
        (enforce (= st "selling") "this round is already settled")
        (enforce (!= dh 0) "the draw has not been opened yet")
        ; The deciding block is the LOWEST RECORDED candidate in the window, final
        ; from the moment it exists (see DECIDE-WINDOW).
        (let ((d0 (decided-height dh)))
          (enforce (!= d0 -1) "no deciding block is recorded for this round"))
        (let* ((d (decided-height dh))
               (bhash (hash-of d))
               ; The attester is the gas payer of the transaction that wrote the
               ; block, so it is an account that exists and can receive. The
               ; deployed block-history is attested-only: every row is an engine
               ; value, so there is no trusted input left to exclude.
               (recorder (at 'by (get-attested d)))
               (dseed (round-seed rk bhash))
               (fee (floor (* rake sales) PREC))
               (bounty-pool (floor (* fee bshare) PREC))
               ; Two roles end a round and each is paid out of the FEE, never the
               ; prize fund: whoever recorded the deciding block, and whoever sent
               ; this draw. block-history records the gas payer, so on a chain the
               ; attester always exists — an empty one only fires in a REPL that
               ; forgot to set a sender. But it is not a value this module chose,
               ; so it gets the same treatment as any other payout target: no
               ; record share for an empty attester, and none for a module-guarded
               ; one, which could not receive a transfer and would abort a draw
               ; whose escape is already closed. The draw share absorbs whatever
               ; the record share does not take.
               ; The round's own weights, a ratio in the order [recorder drawer].
               ; Divide AFTER multiplying and floor to PREC: decimal division here
               ; is unbounded, and an unfloored value must never reach a transfer.
               ; The drawer takes what is left, so the dust of the floor and an
               ; unpayable recorder's share land there rather than stranding.
               (wsum (+ (at 0 bsplit) (at 1 bsplit)))
               (rec-bounty (if (or (= recorder "") (= "m:" (take 2 recorder)))
                               0.0
                               (floor (/ (* bounty-pool (dec (at 0 bsplit))) (dec wsum)) PREC)))
               (draw-bounty (- bounty-pool rec-bounty))
               (to-revenue (- fee bounty-pool))
               (fund (+ (- sales fee) seed-in))
               (k (if (< n (length tiers)) n (length tiers)))
               (ranks (draw-ranks dseed rk n k))
               (amounts (tier-amounts fund tiers k))
               (accounts (map (lambda (r:integer)
                                (at 'account (read tickets (ticket-key rk r))))
                              ranks))
               ; Every outflow of this transaction — winners, both crank shares
               ; and the fee — aggregated per DISTINCT account. Pact 5's managed
               ; install identity is (sender, receiver) and EXCLUDES the amount,
               ; so two installs to one account collide however different the
               ; amounts are. The recorder is very often also the drawer and may
               ; also be a winner, so aggregating all of them together is the
               ; only shape that survives every aliasing case. Without this a
               ; round whose winner also recorded its block would abort here
               ; FOREVER, with the escape already closed by the recording.
               (outflows (filter (lambda (o:object) (> (at 'amount o) 0.0))
                           ; `+` is BINARY in Pact 5, exactly like `or` and `and`.
                           (+ (map (lambda (i:integer)
                                     { "account": (at i accounts)
                                     , "amount":  (at i amounts) })
                                   (enumerate 0 (- k 1)))
                              [ { "account": recorder, "amount": rec-bounty }
                              , { "account": payee,    "amount": draw-bounty }
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
          (if (> rec-bounty 0.0)
              (let ((e (emit-event (BOUNTY-PAID id seq "record" recorder rec-bounty))))
                "record share paid")
              "no record share")
          (if (> draw-bounty 0.0)
              (let ((e (emit-event (BOUNTY-PAID id seq "draw" payee draw-bounty))))
                "draw share paid")
              "no draw share")
          (emit-event (FEE-PAID id seq fee bounty-pool))
          (update rounds rk
            { "state": "drawn", "draw-seed": dseed, "deciding-block": d
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
          (emit-event (DRAWN id seq dseed d n ranks amounts accounts))
          (format "{} round {}: seed {} ranks {} pay {}" [id seq dseed ranks amounts])))))

  ; This is the fairness claim made checkable by a stranger: the site publishes
  ; the candidate heights the moment the draw is opened, and this the instant a
  ; candidate is recorded. It is unavailable before that — until then the outcome
  ; genuinely is not determined, and saying otherwise would be a lie.
  (defun preview:object (id:string seq:integer)
    @doc "READ-ONLY: exactly what `draw` will do, computable by anyone from the \
    \moment the deciding block is recorded and before the draw transaction is \
    \sent. If a settled round ever disagrees with what this returned, the module \
    \is broken."
    (let ((rk (round-key id seq)))
      (with-read rounds rk
        { "state" := st, "decide-height" := dh, "tickets" := n, "tiers" := tiers
        , "sales" := sales, "rake" := rake, "seed-in" := seed-in }
        (enforce (!= dh 0) "the draw has not been opened yet — nothing is decided")
        (let ((d0 (decided-height dh)))
          (enforce (!= d0 -1) "no deciding block is recorded for this round"))
        (let* ((d (decided-height dh))
               (bhash (hash-of d))
               (dseed (round-seed rk bhash))
               (k (if (< n (length tiers)) n (length tiers)))
               (ranks (draw-ranks dseed rk n k))
               (fee (floor (* rake sales) PREC))
               (fund (+ (- sales fee) seed-in)))
          { "state": st, "decide-height": dh, "deciding-block": d, "block-hash": bhash
          , "draw-seed": dseed, "ranks": ranks
          , "amounts": (tier-amounts fund tiers k)
          , "accounts": (map (lambda (r:integer)
                               (at 'account (read tickets (ticket-key rk r))))
                             ranks) }))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; ESCAPE ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ; TWO WAYS IN.
  ; 1. Nobody opened the draw within OPEN-DRAW-GRACE-SECONDS of the draw instant.
  ; 2. No candidate in its DECIDE-WINDOW was recorded. That is permanent once the
  ;    last candidate's one recording block has passed, and the round then escapes
  ;    at once.
  ; It is closed FOREVER once a candidate is recorded, so nobody can wait out an
  ; outcome they dislike. Every round has at least one ticket, so the refund is
  ; always a real division: stake plus an exact per-ticket share of the bonus.
  (defun escape:string (id:string seq:integer)
    @doc "Last resort, permissionless: a round escapes when it can never be \
    \drawn — its draw was never opened, or no candidate block was recorded. It \
    \books every buyer their own stake plus their exact share of the bonus, \
    \selects no winner and takes no fee."
    (let ((rk (round-key id seq)))
      (with-read rounds rk
        { "state" := st, "decide-height" := dh, "draws-at" := da
        , "sales" := sales, "tickets" := n, "seed-in" := seed-in }
        (enforce (= st "selling") "this round is settled")
        ; a frozen module states its own preconditions: a round exists only from
        ; its first ticket, so this cannot fail, and the division below is safe.
        (enforce (> n 0) "this round has no tickets")
        ; With no draw opened there are no candidates, so nothing can be
        ; recorded; `decided-height` is never asked about height 0.
        (let* ((opened (!= dh 0))
               (recorded (if opened (!= (decided-height dh) -1) false)))
          (enforce (not recorded)
            "this round can be drawn — draw it, do not escape it")
          ; The draw was never opened: the round waits a grace past its draw
          ; instant, during which anyone may still open it, then escapes.
          (enforce (or opened (> (diff-time (now-time) da) OPEN-DRAW-GRACE-SECONDS))
            "the draw has not been opened — anyone may open it once its draw instant passes, and this round can only escape a day after that")
          ; No candidate recorded: the round waits only while one still CAN be.
          ; The last candidate, dh + DECIDE-WINDOW - 1, is recordable only in block
          ; dh + DECIDE-WINDOW, so after that nothing can change and the round
          ; escapes at once.
          (enforce (or (not opened) (> (now) (+ dh DECIDE-WINDOW)))
            "the deciding window is still open — a candidate block can still be recorded")
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
            (emit-event (ESCAPED id seq dh booked))
            (format "{} round {} escaped: {}"
              [id seq (if opened "block was never recorded" "the draw was never opened")]))))))

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
    @doc "A round: frozen terms, sales, its deciding block and the draw result."
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
