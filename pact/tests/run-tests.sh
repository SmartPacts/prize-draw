#!/usr/bin/env bash
# run-tests.sh — everything this repository claims about the contract, run in one command.
#
#   cd pact/tests && ./run-tests.sh
#
# This is the same command CI runs, with no reduced subset: a CI that runs less than you do
# teaches you to trust a green tick that means less than you think.
#
# SCORED BY EXIT CODE, NEVER BY GREPPING THE TRANSCRIPT. A later hard error in a Pact REPL
# suppresses earlier FAILURE lines, so a mutation that breaks an early assertion can leave a
# transcript with no FAILURE in it at all. Only the exit code is trustworthy.
set -uo pipefail
cd "$(dirname "$0")" || exit 2
PACT="${PACT:-pact}"
BAD=0

echo "== engine"
"$PACT" --version || { echo "no pact on PATH — set PACT=/path/to/pact"; exit 2; }

echo
echo "== static gate (every .pact and .repl, loaded through the engine and pattern-scanned)"
# Two files fail a BARE load by design and are dispositioned here BY EXACT PATH, never silenced:
# fixtures/beacons.repl (the genuine-beacon table; its helper names the module, so it loads only
# after the module — prize-draw-test-init.repl does that) and ops/mainnet-deploy/upgrade-precondition.pact
# (the first form of the upgrade transaction; it reads the LIVE module, so it loads only inside the
# upgrade suite, which proves it both ways). Any other VIOLATION is real. A static check that
# crashed or checked nothing must not read as clean: the summary line and a file count are required.
( cd ../.. && ./.github/scripts/pact-static-check.sh ) > /tmp/static.out 2>&1
src=$?
sfiles=$(sed -n 's/^VIOLATIONs: [0-9]*   WARNs: [0-9]*   files: \([0-9]*\)$/\1/p' /tmp/static.out)
DISP='pact/tests/fixtures/beacons.repl|ops/mainnet-deploy/upgrade-precondition.pact'
und=$(grep '^VIOLATION: ' /tmp/static.out | grep -vE "$DISP")
grep -E '^(VIOLATION|WARN):' /tmp/static.out | cut -c1-160 | sed 's/^/   /'
if [ -z "$sfiles" ] || [ "$sfiles" -eq 0 ] || { [ "$src" != 0 ] && [ "$src" != 1 ]; }; then
  echo "   BAD: the static check did not run cleanly (exit $src, files '${sfiles:-none}')"; BAD=$((BAD+1))
elif [ -n "$und" ]; then
  echo "   BAD: VIOLATION(s) outside the two dispositioned files:"; echo "$und" | sed 's/^/   /'; BAD=$((BAD+1))
else
  echo "   ok: $sfiles files checked, $(grep -c '^VIOLATION: ' /tmp/static.out) VIOLATION(s), all in the dispositioned files"
fi

echo
# ONE CALL PER FILE, and the count is checked: a gate that inspected zero files must FAIL, never
# pass quietly. In Pact 5 `or`, `and` and `+` take exactly TWO operands: a three-operand form loads,
# passes the static gate, and only throws when that line runs.
echo "== binary forms (or / and / + take exactly two operands in Pact 5)"
(
  cd ../..
  nf=$(find pact ops -name '*.pact' -o -name '*.repl' | wc -l)
  ar=$(find pact ops -name '*.pact' -o -name '*.repl' | sort | while read -r f; do python3 .github/scripts/pact-arity-check.py "$f" 2>&1; done)
  na=$(echo "$ar" | grep -c 'forms,')
  bad3=$(echo "$ar" | grep -E 'forms,' | grep -vc ' 0 with 3+ operands')
  echo "   files on disk: $nf   reported on: $na   with a 3+ operand form: $bad3"
  [ "$na" -eq "$nf" ] || { echo "   BAD: the checker reported on $na of $nf files"; exit 1; }
  [ "$bad3" -eq 0 ] || { echo "$ar" | grep -E 'forms,' | grep -v ' 0 with 3+ operands' | sed 's/^/   /'; exit 1; }
) || BAD=$((BAD+1))

# A two-argument `expect-failure` matches ANY failure, so it asserts nothing about WHY the call
# failed — an arity error or a typo would pass it. The checker self-tests before scanning and
# fails if it can parse no file, so it cannot certify an empty scan as clean.
echo "== expect-failure arity (a two-argument expect-failure asserts nothing about WHY)"
( cd ../.. && python3 .github/scripts/expect-failure-arity.py pact/tests/*.repl ) || BAD=$((BAD+1))

# The frozen-module suite deploys a copy of this module whose GOVERNANCE can never pass again.
# That copy must be THIS module with only that one substitution, or the suite proves the freeze
# behaviour of some other contract.
echo "== the frozen fixture is this module with governance replaced, and nothing else"
FROZE='(enforce false "prize-draw is frozen: governance can never pass again")'
if diff -q <(sed "s/(enforce-guard (keyset-ref-guard ADMIN-KS))/$FROZE/" ../modules/prize-draw.pact) \
           fixtures/prize-draw-frozen.pact > /dev/null; then
  echo "   identical apart from the GOVERNANCE body"
else
  echo "   BAD: the frozen fixture is not this module with governance replaced"; BAD=$((BAD+1))
fi

echo
echo "== suites"
for f in prize-draw-unit-testing.repl prize-draw-vision-testing.repl \
         prize-draw-worstcase-testing.repl prize-draw-revenue-testing.repl \
         prize-draw-frozen-testing.repl prize-draw-upgrade-testing.repl \
         prize-draw-upgrade2-testing.repl; do
  "$PACT" -t "$f" > "/tmp/$f.out" 2>&1
  rc=$?
  n=$(grep -c 'Expect' "/tmp/$f.out" 2>/dev/null || echo 0)
  if [ $rc -eq 0 ]; then printf '   ok   %-40s exit=0  %s assertions printed\n' "$f" "$n"
  else printf '   FAIL %-40s exit=%s  (see /tmp/%s.out)\n' "$f" "$rc" "$f"; BAD=$((BAD+1)); fi
done

echo
if [ "$BAD" -eq 0 ]; then echo "SUITE RESULT: PASS"; else echo "SUITE RESULT: FAIL ($BAD)"; fi
exit $((BAD > 0))
