#!/usr/bin/env bash
# DIVE-4618/DIVE-4783 — the control for tests/ui_plugin_unit.sh.
#
# A port's suite is the easiest place in the world to write arms that cannot
# fail: the code under test already worked, so every assertion is green the
# moment it is typed and nothing says whether it is LOOKING at anything. So each
# mutant below breaks ONE named behaviour in a copy of ui/bin/ui and names the
# arm that must go red for it. A mutant that leaves the suite green is a missing
# arm, and it is reported here as a failure of this file.
#
# THE FIRST FOUR ARE THIS REPO'S WHOLE JOB. The plugin owns exactly two things
# now — it passes core's document through untouched, and it refuses a document
# it cannot render, before the browser. M1 reverts the passthrough into a
# transformation; M3 and M4 revert each half of the refusal into an acceptance;
# M7 reverts the "your core is too old" answer into a generic failure. Nothing
# below grades a column name, a query or a derived view, because none of those
# live here any more: they are core's, and core's board_contract harness grades
# them (DIVE-4783).
#
# M5 is still the port mutant this repo started with: it reverts PLUGIN
# DIVERGENCE 3 back to core's own line. Core's form is correct IN CORE and wrong
# here, and nothing but an arm can tell the difference.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ui-mutants.XXXXXX")"
trap 'rc=$?; rm -rf "$TMP"; echo "HARNESS-RC=$rc"' EXIT
PASS=0; FAIL=0

# name | expected-red-arm | sed program
run_mutant() {
  local name="$1" arm="$2" prog="$3"
  local bin="$TMP/ui.$RANDOM"
  cp "$ROOT/ui/bin/ui" "$bin"
  sed -i "$prog" "$bin"
  chmod +x "$bin"
  if cmp -s "$bin" "$ROOT/ui/bin/ui"; then
    FAIL=$((FAIL+1)); printf 'FAIL %s — the mutation did not apply (the text it anchors on moved)\n' "$name"; return
  fi
  local out rc
  out="$(UI_BIN="$bin" bash "$ROOT/tests/ui_plugin_unit.sh" 2>&1)"; rc=$?
  if (( rc == 0 )); then
    FAIL=$((FAIL+1)); printf 'FAIL %s — the suite stayed GREEN on a broken tree\n' "$name"; return
  fi
  if ! grep -q "FAIL $arm" <<<"$out"; then
    FAIL=$((FAIL+1))
    printf 'FAIL %s — the suite went red, but not on %s. It red on:\n%s\n' \
      "$name" "$arm" "$(grep '^FAIL' <<<"$out" | sed 's/^/       /')"
    return
  fi
  PASS=$((PASS+1))
  printf 'ok   %s — killed by %s (%s arms red)\n' "$name" "$arm" "$(grep -c '^FAIL' <<<"$out")"
}

# M1 — the passthrough becomes a transformation. jq -c re-emits the same FACTS
# in different bytes, which is exactly the shape that would pass a "the numbers
# match" arm and still make this repo a second producer.
run_mutant 'M1 the document is re-emitted instead of passed through' 'T12' \
  's@^  printf .%s\\n. "\$doc"$@  printf "%s\\n" "$doc" | jq -c .@'

run_mutant 'M2 the loopback check accepts any host' 'T61' \
  's|\^(127(\\\.\[0-9\]{1,3}){3}\|::1\|localhost)\$|.*|'

# M3 — the version pin stops pinning. The document still parses and every key is
# present, so nothing downstream notices: a version-2 board renders with fields
# that mean something else. This is the failure the contract exists to prevent.
run_mutant 'M3 an unknown contract version is rendered anyway' 'T21' \
  's|^  \[\[ " \$FIVE_UI_BOARD_VERSIONS " == \*" \$ver "\* \]\] .*$|  :|'

# M4 — the other half of the same refusal: the version matched, so the name is
# never checked and any JSON with a `contract.version` of 1 is treated as a board.
run_mutant 'M4 a document that is not a board is accepted because its version matched' 'T28' \
  's@\[\[ "\$name" == "\$FIVE_UI_BOARD_CONTRACT" \]\]@[[ -n "$name" ]]@'

run_mutant 'M5 PLUGIN DIVERGENCE 2 is reverted to core own poll argv' 'T41' \
  's|\[BUNDLE, "--data"\],|[BUNDLE, "ui", "--data"],|'

# M6 — negotiation moves back behind the socket. The server binds, the browser
# opens, and the box's incompatibility arrives as a broken page instead of a
# named error on the terminal of the person who typed the command.
run_mutant 'M6 the server binds without negotiating first' 'T2b' \
  '/^  _ui_board_preflight >\/dev\/null$/d'

# M7 — "your core predates the read contract" collapses into a generic failure.
# The exit code and the sentence are the whole remedy: a box that cannot serve a
# board needs `self-update`, not a bug report about a blank page.
run_mutant 'M7 a core too old to serve a board gets a generic error' 'T24' \
  '/^    _ui_board_preflight >\/dev\/null   # names the real cause/d'

printf '\n%s mutants killed, %s not\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
