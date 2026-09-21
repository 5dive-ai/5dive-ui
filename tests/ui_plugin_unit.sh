#!/usr/bin/env bash
# DIVE-4618/DIVE-4783 — `ui` as a standalone plugin: the arms that say whether
# this repo still owns only what it is supposed to own.
#
# WHAT CHANGED, AND WHY THE SUITE CHANGED WITH IT. The first published version of
# bin/ui carried core's five SQL queries across, so this file graded them: a
# fixture sqlite board written out by hand, and ~20 arms over handoff_state,
# gate_live, the flows derivation and the stats. Every one of those arms graded
# CORE'S SEMANTICS from a repo that does not own them, which is the same defect
# the port itself had — it just wore a test's clothes. DIVE-4779 gave core a
# versioned read contract (`5dive board`), DIVE-4783 made the plugin read it, and
# those arms went to `tests/board_contract_unit.sh` in core, where the producer
# lives. What is left here is everything this repo actually owns:
#
#   passthrough      -> T1x. `--data` is core's document, BYTE for byte. Not
#                       re-keyed, not re-ordered, not re-wrapped. This one arm
#                       replaces every derived-view arm the suite used to carry,
#                       because if the bytes are core's then the semantics are.
#   the negotiation  -> T2x. The thing the seam was bought for: an incompatible
#                       board is refused BY NAME and BEFORE the socket, a core
#                       too old to serve one says so, and the check reads no
#                       store. This is the only place this repo has an opinion
#                       about the document at all.
#   no store, at all -> T3x. The coupling is gone at RUNTIME, not just in the
#                       diff: with `sqlite3` poisoned on PATH, a full render
#                       still succeeds and the poison is never tripped.
#   divergence 1+3   -> T4x. The served page polls THIS executable, and what it
#                       serves is what `--data` prints.
#   the refusals     -> T6x. No sign-in means the loopback bind is the only
#                       control there is, so its refusal is a graded arm.
#   parity           -> T7x. Same output as core's `board`, when core is here to
#                       ask. Skipped in CI by design — CI has no box.
#
# The fixture is a STUB `5dive` rather than a real one, for the same reason the
# fixture board used to be hand-written: this suite must run on a runner with no
# 5dive installed, and a stub is what lets an arm serve a version 2 board, or a
# core that has never heard of `board`, on demand.
set -uo pipefail
printf 'grading tree: %s @ %s\n' "$PWD" "$(git rev-parse --short HEAD 2>/dev/null || echo unknown)" >&2
cd "$(dirname "$0")/.."
ROOT="$PWD"
UI="${UI_BIN:-$ROOT/ui/bin/ui}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ui-plugin-unit.XXXXXX")"
trap 'rc=$?; rm -rf "$TMP"; echo "HARNESS-RC=$rc"' EXIT
PASS=0; FAIL=0

t() { # name expected actual
  local name="$1" want="$2" got="$3"
  if [[ "$want" == "$got" ]]; then PASS=$((PASS+1)); printf 'ok   %s\n' "$name"
  else FAIL=$((FAIL+1)); printf 'FAIL %s\n       want: %s\n       got : %s\n' "$name" "$want" "$got"; fi
}
tcontains() { # name needle haystack
  local name="$1" needle="$2" hay="$3"
  if [[ "$hay" == *"$needle"* ]]; then PASS=$((PASS+1)); printf 'ok   %s\n' "$name"
  else FAIL=$((FAIL+1)); printf 'FAIL %s\n       missing: %s\n       in     : %s\n' "$name" "$needle" "${hay:0:300}"; fi
}

free_port() { python3 - <<'PY'
import socket
s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()
PY
}

# ---------------------------------------------------------------------------
# The fixture: a stub `5dive` that serves whatever board the arm needs, and
# RECORDS its own argv. The call log is not decoration — T26 is the arm that
# says the negotiation reads no store, and the only way to see that from outside
# the process is to see which sub-command it asked for.
# ---------------------------------------------------------------------------
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/5dive" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
# STUB_NO_BOARD models a core older than the read contract: the verb does not
# exist, so EVERY form of it fails the exec — which is the answer the contract
# says a too-old box gives, in the same place a wrong version would.
[[ -z "${STUB_NO_BOARD:-}" && "${1:-}" == "board" ]] \
  || { echo "error: unknown command: ${1:-}" >&2; exit 2; }
case "${2:-}" in
  --contract-version)
    [[ -n "${STUB_VERSION:-}" ]] || { echo "error: unknown command: board" >&2; exit 2; }
    printf '%s\n' "$STUB_VERSION" ;;
  --json|"")
    [[ -r "${STUB_DOC:-}" ]] || { echo "error: no document" >&2; exit 1; }
    cat "$STUB_DOC" ;;
  *) exit 2 ;;
esac
STUB
chmod +x "$BIN/5dive"

# The documents. Shaped exactly as core's `_board_state_json` emits them — the
# key set is version 1's, and the `contract` block is what this plugin reads.
mkboard() { # <file> <store> <version> [name]
  jq -n --arg store "$2" --argjson cv "$3" --arg cn "${4:-5dive.board}" \
    '{ok: true, data: {contract: {name: $cn, version: $cv}, scope: "single-host",
      store: $store, host: "fixture", generated_at: "2026-09-21 12:00:00Z",
      org: [{name: "main", reports_to: null, role: "lead", title: "Lead"},
            {name: "dev",  reports_to: "main", role: "builder", title: "Builder"}],
      queue: [{ident: "DIVE-1", title: "a row", status: "todo", priority: "high",
               assignee: "dev", created_by: "main", handoff_state: "delivered"}],
      gates: [{ident: "DIVE-2", title: "a gate", need_type: "decision", tier: 2}],
      flows: [{from: "main", to: "dev", ident: "DIVE-1", kind: "delegation", human: false}],
      triggers: [], deliveries: [],
      stats: {agents: 2, open: 1, gates: 1, delegated: 1, agent_to_agent: 1,
              human_touch: 0, awaiting_verify: 1, in_review: 0,
              triggers: 0, trigger_deliveries: 0}}}' > "$1"
}
mkboard "$TMP/ready.json"  ready  1
mkboard "$TMP/absent.json" absent 1
mkboard "$TMP/v2.json"     ready  2
mkboard "$TMP/alien.json"  ready  1 "someone.elses.board"

STUB_LOG="$TMP/calls.log"; : > "$STUB_LOG"
# Every invocation goes through here: the plugin resolves the CLI from
# FIVE_UI_CLI, which is also what a box with a relocated install would set.
ui() { # [env overrides come from the caller's exported STUB_* vars]
  env FIVE_UI_CLI="$BIN/5dive" STUB_LOG="$STUB_LOG" \
      STUB_VERSION="${STUB_VERSION:-1}" STUB_DOC="${STUB_DOC:-$TMP/ready.json}" \
      STUB_NO_BOARD="${STUB_NO_BOARD:-}" "$UI" "$@"
}

# `--once` serves EXACTLY ONE request, so a readiness PROBE spends the request
# the arm is about, and the arm then reads 000 from a server that has already
# exited. Wait on the server SAYING it is listening instead of asking it.
serve_once() { # logfile port
  local log="$1" port="$2" i
  ( ui --once --port="$port" >"$log" 2>&1 & )
  for i in $(seq 1 80); do grep -q "listening on" "$log" 2>/dev/null && return 0; sleep 0.25; done
  return 1
}

echo "== T1x the document is CORE'S, and it arrives untouched"
DATA="$(ui --data 2>"$TMP/t1.err")"; RC=$?
t 'T11 --data exits 0 against a board this build understands' 0 "$RC"
# THE ARM THIS SUITE IS BUILT ON. Anything less than byte-identity — same keys,
# same order, same whitespace — means this repo is transforming core's document,
# and a transformation is a second producer with nobody grading it. It is also
# what makes `5dive ui --data`, `/api/state` and `5dive board --json` provably
# the same answer instead of three that agree today.
t 'T12 --data is the producer document BYTE FOR BYTE (one producer, and it is not here)' \
  "$(cat "$TMP/ready.json")" "$DATA"
t 'T13 the store label is passed through, not re-derived' ready "$(jq -r .data.store <<<"$DATA")"
# A fresh box that has never run `task init` is core's answer now, not this
# file's: the plugin used to carry its own named-empty-board reply, and two
# copies of "what an empty board looks like" is exactly the drift the contract
# removed.
ABSENT="$(STUB_DOC="$TMP/absent.json" ui --data)"
t 'T14 a store-absent board renders too, and is ALSO passed through untouched' \
  "$(cat "$TMP/absent.json")" "$ABSENT"

echo "== T2x the negotiation — what the read contract was bought for"
set +e
OUT="$(STUB_DOC="$TMP/v2.json" STUB_VERSION=2 ui --data 2>&1 >/dev/null)"; RC=$?
set -e
t 'T21 a board version this build does not understand is REFUSED, not rendered' 3 "$RC"
tcontains 'T22 ...and the refusal names the version the box serves' '2' "$OUT"
tcontains 'T23 ...and the version(s) this build understands (both numbers, or it is not actionable)' '1' "$OUT"
set +e
OUT="$(STUB_NO_BOARD=1 ui --data 2>&1 >/dev/null)"; RC=$?
set -e
t 'T24 a core too old to carry `board` is refused as NOT INSTALLED, not as a crash' 7 "$RC"
tcontains 'T25 ...and it says what to do about it' 'self-update' "$OUT"
set +e
OUT="$(env FIVE_UI_CLI="$TMP/no-such-cli" STUB_LOG="$STUB_LOG" "$UI" --data 2>&1 >/dev/null)"; RC=$?
set -e
t 'T26 no 5dive on PATH at all is its own refusal' 7 "$RC"
tcontains 'T27 ...naming the override a relocated install would use' 'FIVE_UI_CLI' "$OUT"
set +e
OUT="$(STUB_DOC="$TMP/alien.json" ui --data 2>&1 >/dev/null)"; RC=$?
set -e
t 'T28 a document that is not a board is refused by NAME, not rendered because the version matched' 3 "$RC"
tcontains 'T29 ...naming what it got' 'someone.elses.board' "$OUT"
# THE PROPERTY THE REFUSED published-view OPTION COULD NOT HAVE: compatibility is
# settled by an exec that reads no store, so it answers on a box whose board is
# absent, unreadable or mid-migration. Seen from outside the process as: the
# first thing asked is `--contract-version`, never the document.
: > "$STUB_LOG"
STUB_DOC="$TMP/absent.json" ui --data >/dev/null 2>&1
PORT="$(free_port)"; : > "$STUB_LOG"
serve_once "$TMP/neg.log" "$PORT" >/dev/null 2>&1
NEGFIRST="$(head -1 "$STUB_LOG")"
curl -s -o /dev/null "http://127.0.0.1:$PORT/healthz"   # spend the --once request so the server exits
t 'T2a the server negotiates with --contract-version BEFORE it binds a socket' \
  'board --contract-version' "$NEGFIRST"
# `timeout` is load-bearing, not caution. The failure this arm grades is "the
# server binds anyway", and a bound `--once` server blocks forever waiting for a
# request nobody sends — so without a clock the RED case hangs the suite instead
# of failing it, and the mutant that proves this arm works (M6) would never
# report. 124 is not 3, which is the answer the arm wants.
set +e
timeout 15 env FIVE_UI_CLI="$BIN/5dive" STUB_LOG="$STUB_LOG" STUB_VERSION=2 \
  STUB_DOC="$TMP/v2.json" "$UI" --once --port="$(free_port)" >"$TMP/bind2.out" 2>&1; RC=$?
set -e
t 'T2b ...so an incompatible box fails on a terminal, not as a broken page in a tab' 3 "$RC"

echo "== T3x the store coupling is gone at RUNTIME, not just in the diff"
# A grep for `sqlite3` would pass on a tree that still shells out through a
# variable. Poison the binary instead: first on PATH, trips a sentinel, exits 1.
POISON="$TMP/poison"; mkdir -p "$POISON"
printf '#!/bin/sh\ntouch "%s/tripped"\nexit 1\n' "$TMP" > "$POISON/sqlite3"; chmod +x "$POISON/sqlite3"
RC=0
env PATH="$POISON:$PATH" FIVE_UI_CLI="$BIN/5dive" STUB_LOG="$STUB_LOG" STUB_VERSION=1 \
    STUB_DOC="$TMP/ready.json" "$UI" --data >/dev/null 2>&1 || RC=$?
env PATH="$POISON:$PATH" FIVE_UI_CLI="$BIN/5dive" STUB_LOG="$STUB_LOG" STUB_VERSION=1 \
    STUB_DOC="$TMP/ready.json" "$UI" --html >/dev/null 2>&1 || RC=$?
t 'T31 a full render succeeds with sqlite3 poisoned' 0 "$RC"
t 'T32 ...and the poison was never tripped: this plugin opens no database' \
  'no' "$([[ -e "$TMP/tripped" ]] && echo yes || echo no)"

echo "== T4x divergences 1+3: the page polls THIS executable"
PORT="$(free_port)"
serve_once "$TMP/serve.log" "$PORT" || echo "server did not come up" >&2
SERVED="$(curl -s "http://127.0.0.1:$PORT/api/state")"
t 'T41 the served state is the plugin own data, not a 404 from a missing CLI' true "$(jq -r .ok <<<"$SERVED")"
t 'T42 ...and it is the SAME board --data prints' \
  "$(jq -Sc 'del(.data.generated_at)' <<<"$DATA")" "$(jq -Sc 'del(.data.generated_at)' <<<"$SERVED")"
PORT="$(free_port)"
serve_once "$TMP/serve2.log" "$PORT" || echo "server did not come up" >&2
t 'T43 the page itself serves 200' 200 "$(curl -s -o "$TMP/page.html" -w '%{http_code}' "http://127.0.0.1:$PORT/")"
PORT="$(free_port)"
serve_once "$TMP/serve3.log" "$PORT" || echo "server did not come up" >&2
t 'T44 a write method is refused by the server, not by the page' 405 \
  "$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/api/state")"
HTML="$(ui --html)"
tcontains 'T45 --html carries the queue view'   'gates' "$HTML"
t 'T46 the page fetches nothing off this host' 0 \
  "$(grep -coE '(src|href)="https?://' <<<"$HTML" || true)"
# --html is pure presentation: it must render with no box to ask at all, because
# that is the surface a contributor iterates on.
RC=0; env FIVE_UI_CLI="$TMP/no-such-cli" STUB_LOG="$STUB_LOG" "$UI" --html >/dev/null 2>&1 || RC=$?
t 'T47 --html needs no board at all (the page is this repo own, end to end)' 0 "$RC"

echo "== T6x the refusals (no sign-in, so the bind is the only control)"
set +e
ui --host=10.0.0.1 --once --port="$(free_port)" >"$TMP/bind.out" 2>&1; RC=$?
set -e
t 'T61 a non-loopback bind is refused' 3 "$RC"
tcontains 'T62 ...and the refusal names the way out' 'FIVE_UI_ALLOW_REMOTE' "$(cat "$TMP/bind.out")"
for bad in 0 99999 abc; do
  set +e; ui --port="$bad" --once >/dev/null 2>&1; RC=$?; set -e
  t "T63 --port=$bad is refused" 3 "$RC"
done
set +e; ui --nope >/dev/null 2>&1; RC=$?; set -e
t 'T64 an unknown flag is a usage error' 2 "$RC"
set +e; ui --help >/dev/null 2>&1; RC=$?; set -e
t 'T65 --help exits 0' 0 "$RC"

echo "== T7x parity with the real producer (skipped where core is not installed)"
if command -v 5dive >/dev/null 2>&1 && 5dive board --contract-version >/dev/null 2>&1; then
  t 'T71 --data on a REAL box is `5dive board --json`, byte for byte' \
    "$(5dive board --json | jq -Sc 'del(.data.generated_at)')" \
    "$(FIVE_UI_CLI=5dive "$UI" --data | jq -Sc 'del(.data.generated_at)')"
  t 'T72 ...and the version this build pins is one the box actually serves' 0 \
    "$(FIVE_UI_CLI=5dive "$UI" --data >/dev/null 2>&1; echo $?)"
else
  printf 'skip T71/T72 (no 5dive carrying `board` on PATH: parity is a box arm, not a CI arm)\n'
fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
