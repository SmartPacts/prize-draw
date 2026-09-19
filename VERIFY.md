# Verify this yourself

Five checks, in increasing order of what they prove. None of them needs a key, an account, or our
permission, and none of them sends a transaction.

If any of this disagrees with what you read elsewhere in this repository — **trust the chain, not
this repository.**

---

## 1. The chain is running this code

This is the one that matters, and for this contract it is unusually direct: **the deployed code is
the file in `pact/modules/`, verbatim.** There is no stripped "deploy variant" to reconcile.

Two commands. Read both scripts first — they are short, and they only make a read-only `/local`
request. Pass any node URL you trust as an argument; the default is a public community node.

```bash
python3 .github/scripts/fetch-onchain.py > /tmp/onchain.pact
python3 .github/scripts/compare-onchain.py /tmp/onchain.pact
```

Expected output, measured 2026-09-18:

```
VERBATIM: the 69761 characters the chain runs appear exactly, in order, in
          pact/modules/prize-draw.pact, from character 7241.
          Outside them: 7241 characters of header comments and 235 of create-table footer,
          both outside the (module …) form.
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

The runner also fails if any `expect-failure` in the tree was written with too few arguments to
say *why* it expected the failure, and if the frozen-module fixture is anything other than this
module with its governance body replaced.

## 4. The descriptions match the contract

[`docs/PRIZE-DRAW-SPEC.md`](docs/PRIZE-DRAW-SPEC.md) is the engineering statement: every property
it lists names the tests that fail if it is violated, and every function it cites is cited by name
so you can find it in the module.

`docs/PRIZE-DRAW-WHAT-IT-DOES.md` is **generated**, not written by hand: every mark, caller, key
count and quoted limit in it is read out of the contract source and the test results. If it says a
promise is proven by a test, a named test exists and passed.

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
| `n_48867b242317a0216a67f8c7ca26696b5878e0e3.prize-draw-admin` | `keys-2` — any 2 of the 3 | upgrade or freeze the module (and, while it is not frozen, reach any pool) |
| `n_48867b242317a0216a67f8c7ca26696b5878e0e3.prize-draw-operator` | `keys-any` — any 1 of the 3 | create games, set their terms, schedule rounds, add a bonus, retire a game |

```
2d1b2aae29e95a4a7e7a3eb22aa2b6dae8f5a0d269603e5a92275d21304e31aa
3ce46b93e74d8466ea0681f14ba0fcb6c83cbb3a8c815a0359cdf9c931cde3b2
729b3842bc5b33b45a1a559f76e407eeba470ac1a2a9664238c4a24db8970538
```

Under the deployed code, neither keyset can choose a winner, change a round that is already
selling, or pay a prize the draw did not award. The one exception is the admin keyset's power to
publish a new version of the module: until the module is frozen, a new version could do any of
those things. Freezing ends that power permanently; it has not happened.

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

---

## What none of this proves

- **Not that the contract is correct.** It proves the code you can read is the code that runs, and
  that its own tests pass. Tests encode what their author believed.
- **Not that the tests are strong.** A green suite is a floor, not a ceiling. Read them.
- **Not that the operators are trustworthy.** It proves what the *code* can and cannot do. While
  the module remains upgradeable, its 2-of-3 admin keyset can replace it — that is stated in the
  README rather than hidden, and freezing is what ends it.
- **Not anything about a chain you did not query.** If you use our node URL and we lie to you, you
  have verified our lie. Use a node you trust, or run one.
