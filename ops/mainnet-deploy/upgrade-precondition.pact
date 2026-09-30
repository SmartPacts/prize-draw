;; upgrade-precondition.pact — the first form of the drand upgrade transaction (ADR-C20).
;; build-upgrade.ts prepends this, verbatim, to the module source, so the check holds AT THE
;; MOMENT THE UPGRADE LANDS, not only when it was built. If it aborts, the whole transaction
;; aborts and the old module stays exactly as it was.
;;
;; WHY: a round the old code opened carries no drand round. With decide-height 0 (draw never
;; opened) it could neither draw nor escape after the upgrade; with a block height (draw opened)
;; the new code reads a ~2025 drand round, whose beacon is public and whose 90 days are long
;; over, so it could be escaped at once by a buyer who can see they lost.
;; (pact/tests/prize-draw-upgrade-testing.repl HAZARD-1..5.)
;;
;; So every raffle must hold nothing pending (no round has sold a ticket and waits for its draw;
;; a round exists only from a ticket, price >= 0.1 — which also covers any bonus bound to a live
;; round) and must be unable to open a round before the upgrade lands (retired, or no schedule).
;; A check over zero raffles FAILS. Each refusal is pinned: HAZARD-5 in the upgrade suite and the
;; two upgrade-precondition-*-must-fail.repl inverted controls.
(let* ((ids (n_48867b242317a0216a67f8c7ca26696b5878e0e3.prize-draw.list-raffles))
       (epoch (time "1970-01-01T00:00:00Z")))
  (enforce (> (length ids) 0) "upgrade precondition: no raffle was read")
  (map (lambda (id:string)
         (let ((g (n_48867b242317a0216a67f8c7ca26696b5878e0e3.prize-draw.get-raffle id)))
           (enforce (= (at 'pending g) 0.0)
             (format "upgrade precondition: {} has a round waiting for its draw" [id]))
           (enforce (or (not (at 'active g)) (= (at 'next-opens-at g) epoch))
             (format "upgrade precondition: {} could open a round before the upgrade lands" [id]))))
       ids))
