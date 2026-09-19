# Contributing

**Issues and questions are very welcome.** If you find something wrong in the tests or in a claim
this repository makes, please open an issue — including "your README says X and the code does Y",
which is the most useful kind. **A flaw someone could exploit on mainnet is different:** report it
privately, as [SECURITY.md](SECURITY.md) describes, never in a public issue.

**Pull requests against the contract are not.** What runs on mainnet is the file in `pact/modules/`,
byte for byte, and changing it here would break the one property this repository exists to let you
check. Tell us what is wrong and we will fix it through the process that produced the deployment.

Corrections to the documentation, a test you think is missing, or a case where our verification
recipe does not work on your machine — those are worth a pull request, and thank you.

For anything you would rather not post in public, see [SECURITY.md](SECURITY.md).
