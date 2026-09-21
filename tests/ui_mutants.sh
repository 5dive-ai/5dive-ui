#!/usr/bin/env bash
# DIVE-4618 — the control for tests/ui_plugin_unit.sh.
#
# A port's suite is the easiest place in the world to write arms that cannot
# fail: the code under test already worked, so every assertion is green the
# moment it is typed and nothing says whether it is LOOKING at anything. So each
# mutant below breaks ONE named behaviour in a copy of bin/ui and names the arm
# that must go red for it. A mutant that leaves the suite green is a missing
# arm, and it is reported here as a failure of this file.
#
# The fifth mutant is the one this row exists for: it reverts PLUGIN DIVERGENCE
# 3 back to core's own line. Core's form is correct IN CORE and wrong here, and
# nothing but an arm can tell the difference.
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

run_mutant 'M1 the DIVE-1610 null-key strip is dropped' 'T2d' \
  's|^  printf .%s. "\$out" . jq -c .if type=="array".*$|  printf "%s" "$out"|'

run_mutant 'M2 the loopback check accepts any host' 'T61' \
  's|\^(127(\\\.\[0-9\]{1,3}){3}\|::1\|localhost)\$|.*|'

run_mutant 'M3 the guard stops testing whether the database is READABLE' 'T33' \
  's|! -d "\$TASKS_DIR" .. ! -r "\$TASKS_DB"|! -d "$TASKS_DIR"|'

run_mutant 'M4 the ready board is labelled something else' 'T13' \
  's|store: "ready",|store: "live",|'

run_mutant 'M5 PLUGIN DIVERGENCE 3 is reverted to core own poll argv' 'T41' \
  's|\[BUNDLE, "--data"\],|[BUNDLE, "ui", "--data"],|'

run_mutant 'M6 delivered and reviewing are swapped' 'T21' \
  "s|THEN 'reviewing' ELSE 'delivered' END|THEN 'delivered' ELSE 'reviewing' END|"

printf '\n%s mutants killed, %s not\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
