#!/usr/bin/env python3
# Is the code on chain the file in this repository?
#
#   python3 .github/scripts/fetch-onchain.py > /tmp/onchain.pact
#   python3 .github/scripts/compare-onchain.py /tmp/onchain.pact
#
# FAILS CLOSED. An empty or truncated fetch must never read as a pass: `"" in anything` is True,
# and a check that inspected nothing reporting PASS is worse than no check at all. So the size is
# asserted first, against the smallest thing this module could plausibly be.
import sys, pathlib

MIN_CHARS = 60000          # the module is ~69.8k; anything far below this is a failed fetch

onchain = pathlib.Path(sys.argv[1]).read_text()
source  = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "pact/modules/prize-draw.pact").read_text()

if len(onchain) < MIN_CHARS:
    sys.exit(f"REFUSING to compare: the fetched code is {len(onchain)} characters, under the "
             f"{MIN_CHARS} floor. The fetch failed; this is not a mismatch, it is nothing to compare.")
if onchain not in source:
    # Say WHERE it first diverges, so a real difference is actionable rather than a bare False.
    head = onchain[:200]
    at = source.find(head)
    sys.exit("MISMATCH: the deployed code is NOT a verbatim slice of this file.\n"
             + (f"  its first 200 characters were not found in the file at all\n" if at < 0 else
                f"  it starts at character {at} of the file, then diverges\n")
             + "  TRUST THE CHAIN, NOT THIS REPOSITORY.")
i = source.index(onchain)
print(f"VERBATIM: the {len(onchain)} characters the chain runs appear exactly, in order, in")
print(f"          pact/modules/prize-draw.pact, from character {i}.")
print(f"          Outside them: {i} characters of header comments and "
      f"{len(source) - i - len(onchain)} of create-table footer, both outside the (module …) form.")
