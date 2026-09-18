# Reporting a security issue

**Email: security@smartpacts.io** — or open a GitHub security advisory on this repository
(Security → Report a vulnerability), which stays private until we publish it.

There is **no bug bounty**. We would rather say that plainly than imply one.

## What we commit to

- An acknowledgement within **72 hours**, from a person.
- An assessment, with our reasoning, within **10 days** — including when we conclude it is not a
  problem, and why.
- Credit where you want it, and none where you do not.

## What is at stake

The contract is **live on Kadena mainnet01, chain 2**, and holds real KDA in raffle pools while a
round is selling. It is **not frozen**: its 2-of-3 admin keyset can still upgrade it, which means a
problem found today can be fixed — and also means you should judge the operators, not only the
code. Freezing removes that power permanently, and has not happened.

Please do not test against mainnet. Everything here runs locally — `cd pact/tests && ./run-tests.sh`
— and the suite already carries fixtures for the failure paths.

## Scope

In scope: the contract in `pact/modules/`, the claims this repository makes about it, and the
recipe in [VERIFY.md](VERIFY.md). **If you can make that recipe report a pass on code the chain is
not running, tell us urgently** — that is the claim everything else rests on.

Out of scope: the Kadena node software, the `coin` contract, and everything under `pact/vendor/`,
which is not ours. Please report those upstream.
