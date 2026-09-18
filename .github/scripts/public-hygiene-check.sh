#!/usr/bin/env bash
# public-hygiene-check.sh — the scrub that made this repository publishable, enforced on every
# push instead of once. A one-time removal decays: the next paragraph copied in from somewhere
# internal brings an identifier back and nobody notices.
#
# WHAT IT DOES NOT DO: it does not remove reasoning. Saying WHAT a guard prevents, and why, is the
# point of publishing. What it bans is internal bookkeeping an outside reader cannot resolve —
# decision-record numbers, review-round numbering, private paths, assistant trace.
#
# 🔴 THE ONE EXCEPTION, AND WHY. pact/modules/prize-draw.pact is DEPLOYED VERBATIM: the code on
# chain is this file, and VERIFY.md's whole claim is that they are identical. Scrubbing a comment
# out of it would break that claim while hiding nothing — the comments are already public on the
# chain, readable by anyone with `describe-module`. The frozen-module fixture is that same file
# with one substitution, and must stay so. Both are excluded from the decision-record pattern BY
# EXACT PATH, never by a wildcard that could quietly cover a new file.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

SELF=".github/scripts/public-hygiene-check.sh"
DEPLOYED_VERBATIM=("pact/modules/prize-draw.pact" "pact/tests/fixtures/prize-draw-frozen.pact")

mapfile -t FILES < <(git ls-files)
if [ "${#FILES[@]}" -lt 10 ]; then
  echo "hygiene: REFUSING — only ${#FILES[@]} tracked files. A scan that inspects nothing is not a pass."
  exit 2
fi

bad=0
check() {                       # check <label> <pattern> [exempt...]
  local label="$1" pat="$2"; shift 2
  local exempt=("$SELF" "$@") f hit
  for f in "${FILES[@]}"; do
    local skip=0
    for e in "${exempt[@]}"; do [ "$f" = "$e" ] && skip=1; done
    [ "$skip" = 1 ] && continue
    [ -f "$f" ] || continue
    if hit=$(grep -nE "$pat" "$f" 2>/dev/null | head -3); then
      [ -n "$hit" ] && { echo "hygiene: $label in $f"; echo "$hit" | sed 's/^/    /'; bad=$((bad+1)); }
    fi
  done
}

check "decision-record reference" 'ADR-[0-9]{3}|ADR-C[0-9]+|docs/adr' "${DEPLOYED_VERBATIM[@]}"
check "internal epic id"          'CW32-[0-9]+'
check "review-round numbering"    'cold audit|audit #[0-9]+|delta audit|red[- ]team engagement'
check "private path"              '/home/[A-Za-z0-9_-]+|~/claude|/mnt/c/Users'
check "personal email"            'afloresh|@gmail\.com'
check "assistant trace"           'Claude|Anthropic|Co-Authored-By|claude-code|Generated with'
check "internal memory/config"    'CLAUDE\.md|STATUS\.md|MANAGER-NEXT|smart-pacts-shares|prize-draw-private'
check "device or custody id"      "m/44'?/626|Nano S|device hash|\\bpurple\\b|\\bpink\\b"

# WRAP-TOLERANT SECOND PASS. A scrubbed phrase can survive by breaking across a line: MEASURED
# elsewhere in this estate, "cold audit #22" shipped publicly because "cold audit" ended one line
# and "#22" began the next. The pattern was right; the line was wrong.
for f in "${FILES[@]}"; do
  [ "$f" = "$SELF" ] && continue
  [ -f "$f" ] || continue
  case " ${DEPLOYED_VERBATIM[*]} " in *" $f "*) continue;; esac
  if paste -d' ' <(sed 's/^[ \t>*-]*//' "$f") <(sed '1d;s/^[ \t>*-]*//' "$f") 2>/dev/null \
      | grep -qE 'ADR-C?[0-9]|CW32-[0-9]|cold audit|Co-Authored'; then
    echo "hygiene: a banned phrase appears ACROSS TWO LINES in $f"; bad=$((bad+1))
  fi
done

echo "hygiene: ${#FILES[@]} tracked files scanned"
[ "$bad" -eq 0 ] && { echo "hygiene: clean"; exit 0; }
echo "hygiene: $bad finding(s)"; exit 1
