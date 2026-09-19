# Verify this yourself

Four checks and one warning, in increasing order of what they prove. None of them needs a key, an account, or our
permission, and none of them sends a transaction.

If any of this disagrees with what you read elsewhere in this repository — **trust the chain, not
this repository.**

---

## 1. The chain is running this code

This is the one that matters, and for this contract it is unusually direct: **the module stored on
chain is the `(module …)` form of the file in `pact/modules/`, verbatim, comments and all.** There
is no stripped "deploy variant" to reconcile. What this check does not cover: the lines before and
after that form — the header, the `namespace` line, a load-time admin check and the table-creation
footer — ran once, in the deploy transaction, together with the two `define-keyset` calls that
created the keysets, and none of that is stored. The deploy transaction itself (block 7240922, §5)
carries that code, and anyone can read it from the block's payload.

Two commands. Read both scripts first — they are short, and they only make a read-only `/local`
request. Pass any node URL you trust as an argument; the default is a public community node.

```bash
python3 .github/scripts/fetch-onchain.py > /tmp/onchain.pact
python3 .github/scripts/compare-onchain.py /tmp/onchain.pact
```

Expected output, measured 2026-09-19:

```
VERBATIM: the 69761 characters the chain runs appear exactly, in order, in
          pact/modules/prize-draw.pact, from character 7241.
          Outside them: 7241 characters before the (module …) form (header comments, the
          namespace line and a load-time admin check) and 235 after it (the
          create-table footer). Those ran once in the deploy transaction; they are not stored.
```

**Why it is two scripts and not a `curl`.** A Pact command carries its own hash, the node checks
that hash against the exact command *bytes*, and re-serialising the JSON changes those bytes — so
the request has to be built and hashed in one place. `fetch-onchain.py` does that (blake2b-256,
base64url, unpadded) and nothing else.

**The comparison fails closed.** `"" in anything` is True, so a truncated or failed fetch could
otherwise read as a pass; `compare-onchain.py` refuses to compare anything under 60,000 characters
and says so. You can check that yourself: run it against an empty file and it must refuse, and
change one character of the fetched file and it must report a mismatch. Both were verified when
this was written.

## 2. 🔴 Do NOT verify by comparing module hashes

A Pact 5 module hash covers the module's **dependencies' hashes**, not only its own code. The test
suite here loads a vendored snapshot of `coin`; mainnet runs a different `coin`. So a hash computed
locally will **never** equal the hash mainnet reports, and a mismatch tells you nothing about the
code.

We learned this the expensive way — on deploy day, against a value we had carried in our own
documents for weeks. The hash on chain is
`r1ecwafNL89gBUcstQ5GY4edqGOXq3HMWied_rOOhaI`; compare it with what `describe-module` reports if you
like, but the check in §1 is the one that means something.

To read it from the chain, change `'code` to `'hash` in `fetch-onchain.py`.

## 3. The tests pass on your machine, not just ours

Install [Pact 5.4ce](https://github.com/kda-community/pact-5), then:

```bash
cd pact/tests && ./run-tests.sh
```

Every suite is scored by **exit code**. This matters more than it sounds: a later hard error in a
Pact REPL suppresses earlier `FAILURE` lines, so a broken assertion can leave a transcript that
looks clean. Grepping for `FAILURE` is not a test result; an exit code is.

The runner also fails if `or`, `and` or `+` is ever given more than two operands, if any
`expect-failure` in the suites was written with too few arguments to say *why* it expected the
failure (that checker tests itself on a known sample first, so it cannot pass by scanning nothing),
and if the frozen-module fixture is anything other than this module with its governance body
replaced.

## 4. The descriptions match the contract

[`docs/PRIZE-DRAW-SPEC.md`](docs/PRIZE-DRAW-SPEC.md) is the engineering statement: every property
it lists names the tests that fail if it is violated, and every function it cites is cited by name
so you can find it in the module.

`docs/PRIZE-DRAW-WHAT-IT-DOES.md` is **generated**, not written by hand, by a script in our
private repository that reads the contract source, the test results and a manifest of which test
backs which promise. That generator is not published, so from here its ✅ marks are our claim, not
something you can re-run — and seven of them name tests in internal attack suites that are not
published either. `docs/PRIZE-DRAW-SPEC.md` is the checkable version: every property names the
public test that fails if it is violated, except two that only an internal suite covers, which its
§11 names.

Read it against the module and tell us if you find a sentence the code does not support.

## 5. What was deployed, and who holds the keys

Every line of this record is on chain. The calls are read-only and free, from any node on
mainnet01 chain 2 (for example with `/local` or Chainweaver).

| what | block | request key | gas |
|---|---:|---|---:|
| deploy the module | 7240922 | `5Bc0-gs7RFx-HBuIIVXVAZZ_05OWsNe1XhixZm8Dd1s` | 60,992 |
| `initialize` — names where fees go, once | 7240942 | `TP8zVpAtVFRwtbz0kvz_j2TafiL_JIVAKaXOeAX71H4` | 225 |

Both were signed by **two of the three admin keys**, as the admin keyset requires, plus a separate
key that only pays gas.

**The keys.** Two keysets govern the module, over the same three public keys:

| keyset | rule | may |
|---|---|---|
| `n_48867b242317a0216a67f8c7ca26696b5878e0e3.prize-draw-admin` | `keys-2` — any 2 of the 3 | upgrade or freeze the module; **until it is frozen, hold module admin** — move money out of any pool and rewrite any record the contract keeps, in one transaction, with no new code; redefine this keyset |
| `n_48867b242317a0216a67f8c7ca26696b5878e0e3.prize-draw-operator` | `keys-any` — any 1 of the 3 | create games, set their terms, schedule rounds, add a bonus, retire a game; **redefine this keyset** — any one key can replace the other two, and because keysets live outside the module a freeze does not end this |

```
2d1b2aae29e95a4a7e7a3eb22aa2b6dae8f5a0d269603e5a92275d21304e31aa
3ce46b93e74d8466ea0681f14ba0fcb6c83cbb3a8c815a0359cdf9c931cde3b2
729b3842bc5b33b45a1a559f76e407eeba470ac1a2a9664238c4a24db8970538
```

The contract's own functions let neither keyset choose a winner, change a round that is already
selling, or pay a prize the draw did not award. **The admin keyset can do all three anyway, until
the module is frozen**, and not only by publishing a new version: any 2 of the 3 keys hold *module
admin*, so one transaction can move money out of a pool or rewrite any stored record — a selling
round's terms, who owns a ticket, where fees go — with no new code. Such a transaction leaves the
module hash and the §1 check unchanged; it is visible only as a transaction signed by two of the
keys above. Freezing ends it permanently; it has not happened.

Check it yourself:

```lisp
(describe-keyset "n_48867b242317a0216a67f8c7ca26696b5878e0e3.prize-draw-admin")
(describe-keyset "n_48867b242317a0216a67f8c7ca26696b5878e0e3.prize-draw-operator")
(n_48867b242317a0216a67f8c7ca26696b5878e0e3.prize-draw.get-revenue)       ; where fees go
(at 'hash (describe-module "free.block-history"))                       ; the block record it pins
```

`get-revenue` returns SPT's funding account,
`m:n_48867b242317a0216a67f8c7ca26696b5878e0e3.SPT:SPT-funding`. The block record's hash must be
`P3J_LK-Wivmuyw7SB7TzPmfj6t-GCtG3YnfHNAaU2UU` — the hash this module names when it imports it, so it
refuses to load against any other code under that name.

The games created on it, each with its own transactions, are in [`games/`](games/).

[`verification/artifact-baseline.json`](verification/artifact-baseline.json) records the same
identity in machine-readable form, as written on deploy day. We do not edit a published record, so
two of its notes are corrected here instead: **no check in this repository reads that file**, though
its first note says gates do; and its review note (0 critical, 0 high, 0 medium) was written before
we measured module admin on mainnet — it says nothing about that power.

---

## What none of this proves

- **Not that the contract is correct.** It proves the code you can read is the code that runs, and
  that its own tests pass. Tests encode what their author believed.
- **Not that the tests are strong.** A green suite is a floor, not a ceiling. Read them.
- **Not that the operators are trustworthy.** It proves what the *code* can and cannot do. While
  the module is not frozen, its 2-of-3 admin keyset can replace it or override it directly, and
  §1 cannot see a direct override — it changes records, not code. That is stated in the README
  rather than hidden, and freezing is what ends it.
- **Not anything about a chain you did not query.** If you use our node URL and we lie to you, you
  have verified our lie. Use a node you trust, or run one.
