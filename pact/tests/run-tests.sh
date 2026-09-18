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
( cd ../.. && ./.github/scripts/pact-static-check.sh ) || BAD=$((BAD+1))

echo
# ONE CALL PER FILE, and the count is checked: a gate that inspected zero files must FAIL, never
# pass quietly. A two-argument `expect-failure` gets a result but asserts nothing about WHY it
# failed, so a suite full of them can be green while proving very little.
echo "== expect-failure arity (a two-argument expect-failure asserts nothing about WHY)"
(
  cd ../..
  nf=$(find pact -name '*.pact' -o -name '*.repl' | wc -l)
  ar=$(find pact -name '*.pact' -o -name '*.repl' | sort | while read -r f; do python3 .github/scripts/pact-arity-check.py "$f" 2>&1; done)
  na=$(echo "$ar" | grep -c 'forms,')
  bad3=$(echo "$ar" | grep -E 'forms,' | grep -vc ' 0 with 3+ operands')
  echo "   files on disk: $nf   reported on: $na   with a 3+ operand form: $bad3"
  [ "$na" -eq "$nf" ] || { echo "   BAD: the checker reported on $na of $nf files"; exit 1; }
  [ "$bad3" -eq 0 ] || { echo "$ar" | grep -E 'forms,' | grep -v ' 0 with 3+ operands' | sed 's/^/   /'; exit 1; }
) || BAD=$((BAD+1))

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
         prize-draw-frozen-testing.repl; do
  "$PACT" -t "$f" > "/tmp/$f.out" 2>&1
  rc=$?
  n=$(grep -c 'Expect' "/tmp/$f.out" 2>/dev/null || echo 0)
  if [ $rc -eq 0 ]; then printf '   ok   %-40s exit=0  %s assertions printed\n' "$f" "$n"
  else printf '   FAIL %-40s exit=%s  (see /tmp/%s.out)\n' "$f" "$rc" "$f"; BAD=$((BAD+1)); fi
done

echo
if [ "$BAD" -eq 0 ]; then echo "SUITE RESULT: PASS"; else echo "SUITE RESULT: FAIL ($BAD)"; fi
exit $((BAD > 0))
