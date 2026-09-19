# Reporting a security issue

**Open a GitHub security advisory on this repository** — Security → Report a vulnerability. It is
private until we publish it, it reaches us immediately, and it needs no account of ours to be
working. That is the route we can promise today, so it is the one we publish.

**No GitHub account?** Write to **contact@smartpacts.io** saying only that you have a security
report — not the details — and we will set up a private channel with you from there.

There is **no bug bounty**. We would rather say that plainly than imply one.

## What we commit to

- An acknowledgement within **72 hours**, from a person.
- An assessment, with our reasoning, within **10 days** — including when we conclude it is not a
  problem, and why.
- Credit where you want it, and none where you do not.

## What is at stake

The contract is **live on Kadena mainnet01, chain 2**, and holds real KDA in game pools: ticket
money of rounds not yet drawn, bonuses waiting for or bound to a round, and refunds not yet sent.
It is **not frozen**: its 2-of-3 admin keyset can still upgrade it and, as module admin, move pool
money and rewrite any stored record directly. That means a problem found today can be fixed — and
also means you should judge the operators, not only the code. Freezing removes that power
permanently, and has not happened.

Please do not test against mainnet. Everything here runs locally — `cd pact/tests && ./run-tests.sh`
— and the suite already carries fixtures for the failure paths.

## Scope

In scope: the contract in `pact/modules/`, the claims this repository makes about it, and the
recipe in [VERIFY.md](VERIFY.md). **If you can make that recipe report a pass on code the chain is
not running, tell us urgently** — that is the claim everything else rests on.

Out of scope: the Kadena node software, the `coin` contract and the fungible interfaces (the
copies under `pact/vendor/fixtures/` are Kadena's) — please report those upstream. The block record
(`pact/vendor/block-history.pact`) is ours but has its own repository: report it at
[SmartPacts/block-history](https://github.com/SmartPacts/block-history).
