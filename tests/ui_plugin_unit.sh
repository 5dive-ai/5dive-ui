#!/usr/bin/env bash
# DIVE-4618 — `ui` published as a standalone plugin: the arms that say whether
# the carried code still behaves like the core verb it was carried from.
#
# WHAT THIS SUITE IS ARRANGED AROUND. bin/ui is core's src/cmd_ui.sh plus a
# prelude and three marked divergences, so the defects worth grading are not
# "does it print something" — they are the specific ways a PORT rots:
#
#   the data seam    -> T1x/T2x: the plugin reads core's task store by SQL. Every
#                       query is graded against a fixture board whose schema is
#                       written out HERE, so the day core renames a column this
#                       suite is the thing that says which query died.
#   divergence 2     -> T3x: a store this process cannot read is a NAMED empty
#                       board, and the plugin never creates or migrates one.
#   divergence 1+3   -> T4x: the served page polls THIS executable, and what it
#                       serves is what `--data` prints.
#   read-only        -> T5x: the store is byte-identical after a full render.
#   the refusals     -> T6x: no sign-in means the loopback bind is the only
#                       control there is, so its refusal is a graded arm.
#   parity           -> T7x: same output as the core verb, when core is here to
#                       ask. Skipped in CI by design — CI has no box.
#
# The fixture board is deliberately hand-written rather than produced by
# `5dive task init`: this suite must run on a runner with no 5dive installed,
# and writing the schema out is what makes the coupling visible instead of
# inherited.
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
# The fixture board. Only the columns the plugin's five queries actually name —
# a wider schema would hide the coupling this suite exists to pin.
# ---------------------------------------------------------------------------
BOARD="$TMP/board"; mkdir -p "$BOARD"
sqlite3 "$BOARD/tasks.db" <<'SQL'
CREATE TABLE agents_org (name TEXT PRIMARY KEY, reports_to TEXT, role TEXT, title TEXT);
CREATE TABLE tasks (
  id INTEGER PRIMARY KEY, ident TEXT, title TEXT, status TEXT, priority TEXT,
  assignee TEXT, created_by TEXT, verifier TEXT, maker_agent TEXT, project_key TEXT,
  created_at TEXT, handoff_ack_at TEXT, need_type TEXT, need_answered_at TEXT,
  tier INTEGER, ask TEXT, recommend TEXT, need_options TEXT, kind TEXT);
CREATE TABLE event_triggers (
  id INTEGER PRIMARY KEY, name TEXT, source TEXT, event_pattern TEXT, source_scope TEXT,
  filter_json TEXT, target TEXT, enabled INTEGER, max_pending INTEGER, on_overflow TEXT,
  max_payload_bytes INTEGER);
CREATE TABLE event_deliveries (
  id INTEGER PRIMARY KEY, trigger_id INTEGER, event_type TEXT, received_at TEXT,
  signature_status TEXT, outcome TEXT, task_id INTEGER, error TEXT, replay_count INTEGER);

INSERT INTO agents_org VALUES ('main', NULL, 'lead', 'Lead');
INSERT INTO agents_org VALUES ('dev', 'main', 'builder', 'Builder');
INSERT INTO agents_org VALUES ('quinn', 'main', 'verifier', 'Grader');

-- open, delegated agent->agent
INSERT INTO tasks (id,ident,title,status,priority,assignee,created_by,project_key,created_at)
  VALUES (1,'DIVE-1','agent to agent','todo','high','dev','main','dive','2026-09-01 00:00:00');
-- open, delegated by a human (not a name in agents_org) -> human:true edge
INSERT INTO tasks (id,ident,title,status,priority,assignee,created_by,project_key,created_at)
  VALUES (2,'DIVE-2','human filed','in_progress','medium','dev','lodar','dive','2026-09-02 00:00:00');
-- maker->verifier, delivered (assignee swapped to verifier, no ack yet)
INSERT INTO tasks (id,ident,title,status,priority,assignee,created_by,verifier,maker_agent,project_key,created_at)
  VALUES (3,'DIVE-3','delivered','todo','high','quinn','main','quinn','dev','dive','2026-09-03 00:00:00');
-- maker->verifier, acked -> reviewing
INSERT INTO tasks (id,ident,title,status,priority,assignee,created_by,verifier,maker_agent,project_key,created_at,handoff_ack_at)
  VALUES (4,'DIVE-4','reviewing','todo','high','quinn','main','quinn','dev','dive','2026-09-04 00:00:00','2026-09-05 00:00:00');
-- live gate
INSERT INTO tasks (id,ident,title,status,priority,assignee,created_by,project_key,created_at,need_type,tier,ask,recommend)
  VALUES (5,'DIVE-5','gated','todo','urgent','main','dev','dive','2026-09-05 00:00:00','decision',2,'ship it?','yes');
-- answered gate: NOT live
INSERT INTO tasks (id,ident,title,status,priority,assignee,created_by,project_key,created_at,need_type,need_answered_at)
  VALUES (6,'DIVE-6','answered','todo','low','main','dev','dive','2026-09-06 00:00:00','approval','2026-09-07 00:00:00');
-- closed and recurring rows are off the queue
INSERT INTO tasks (id,ident,title,status,priority,assignee,created_by,project_key,created_at)
  VALUES (7,'DIVE-7','closed','done','low','dev','main','dive','2026-09-07 00:00:00');
INSERT INTO tasks (id,ident,title,status,priority,assignee,created_by,project_key,created_at,kind)
  VALUES (8,'DIVE-8','beat','todo','low','dev','main','dive','2026-09-08 00:00:00','recurring');

INSERT INTO event_triggers VALUES (1,'gh-issues','github','issues.labeled','5dive-ai/5dive','{}','dev',1,10,'drop',65536);
INSERT INTO event_deliveries VALUES (1,1,'issues.labeled','2026-09-09 00:00:00','verified','accepted',1,NULL,0);
INSERT INTO event_deliveries VALUES (2,1,'issues.labeled','2026-09-09 01:00:00','invalid','invalid_signature',NULL,'bad sig',0);
SQL

board() { env TASKS_DIR="$BOARD" TASKS_DB="$BOARD/tasks.db" "$UI" "$@"; }

# `--once` serves EXACTLY ONE request, so a readiness PROBE spends the request
# the arm is about, and the arm then reads 000 from a server that has already
# exited. Wait on the server SAYING it is listening instead of asking it.
serve_once() { # logfile port
  local log="$1" port="$2" i
  ( board --once --port="$port" >"$log" 2>&1 & )
  for i in $(seq 1 80); do grep -q "listening on" "$log" 2>/dev/null && return 0; sleep 0.25; done
  return 1
}

echo "== T1x the board reads"
DATA="$(board --data 2>"$TMP/t1.err")"; RC=$?
t 'T11 --data exits 0 on a readable board' 0 "$RC"
t 'T12 the envelope is ok'            true   "$(jq -r .ok <<<"$DATA")"
t 'T13 the store is named ready'      ready  "$(jq -r .data.store <<<"$DATA")"
t 'T14 the org chart is the whole org' 3     "$(jq -r '.data.org|length' <<<"$DATA")"
t 'T15 the queue excludes done and recurring rows' 6 "$(jq -r '.data.queue|length' <<<"$DATA")"
t 'T16 the queue is priority-ordered, urgent first' DIVE-5 "$(jq -r '.data.queue[0].ident' <<<"$DATA")"
t 'T17 only the UNANSWERED gate is a gate' 1 "$(jq -r '.data.gates|length' <<<"$DATA")"
t 'T18 ...and it is the one with no answer' DIVE-5 "$(jq -r '.data.gates[0].ident' <<<"$DATA")"
t 'T19 gate_live is the inbox predicate, not need_type IS NOT NULL' 1 \
  "$(jq -r '[.data.queue[]|select(.gate_live==1)]|length' <<<"$DATA")"

echo "== T2x the derived views (the part a column rename kills silently)"
t 'T21 handoff_state: delivered before the ack'  delivered "$(jq -r '.data.queue[]|select(.ident=="DIVE-3").handoff_state' <<<"$DATA")"
t 'T22 handoff_state: reviewing after the ack'   reviewing "$(jq -r '.data.queue[]|select(.ident=="DIVE-4").handoff_state' <<<"$DATA")"
t 'T23 a verify edge is drawn from the MAKER, not the current assignee' dev \
  "$(jq -r '[.data.flows[]|select(.kind=="verify" and .ident=="DIVE-3")][0].from' <<<"$DATA")"
t 'T24 an edge between two org names is not a human edge' false \
  "$(jq -r '[.data.flows[]|select(.ident=="DIVE-1")][0].human' <<<"$DATA")"
t 'T25 an edge touching a name that is not in the org IS a human edge' true \
  "$(jq -r '[.data.flows[]|select(.ident=="DIVE-2")][0].human' <<<"$DATA")"
t 'T26 human_touch counts edges off the board, not rows' 1 "$(jq -r '.data.stats.human_touch' <<<"$DATA")"
t 'T27 agent_to_agent counts the rest of the edges (8 - 1)' 7 "$(jq -r '.data.stats.agent_to_agent' <<<"$DATA")"
t 'T28 awaiting_verify counts delivered rows'            1 "$(jq -r '.data.stats.awaiting_verify' <<<"$DATA")"
t 'T29 in_review counts acked rows'                      1 "$(jq -r '.data.stats.in_review' <<<"$DATA")"
t 'T2a triggers roll their deliveries up'                2 "$(jq -r '.data.triggers[0].deliveries' <<<"$DATA")"
t 'T2b ...and count the failed ones separately'          1 "$(jq -r '.data.triggers[0].failed' <<<"$DATA")"
t 'T2c a delivery names the row it opened'          DIVE-1 "$(jq -r '[.data.deliveries[]|select(.id==1)][0].task' <<<"$DATA")"
t 'T2d null columns are dropped, as core drops them (DIVE-1610)' 0 \
  "$(jq -r '[.data.queue[]|select(has("verifier"))]|length - 2' <<<"$DATA")"

echo "== T3x divergence 2: a store this process cannot read"
OUT="$(env TASKS_DIR="$TMP/nope" TASKS_DB="$TMP/nope/tasks.db" "$UI" --data 2>/dev/null)"; RC=$?
t 'T31 a missing store directory is a NAMED empty board' absent "$(jq -r .data.store <<<"$OUT")"
t 'T32 ...and it still exits 0'                               0 "$RC"
mkdir -p "$TMP/empty"
OUT="$(env TASKS_DIR="$TMP/empty" TASKS_DB="$TMP/empty/tasks.db" "$UI" --data 2>/dev/null)"
t 'T33 a directory with no database reads absent too (core would have CREATED it)' absent "$(jq -r .data.store <<<"$OUT")"
t 'T34 ...and the plugin created nothing' 0 "$(find "$TMP/empty" -type f | wc -l)"
UNREADABLE="$TMP/locked"; mkdir -p "$UNREADABLE"; : > "$UNREADABLE/tasks.db"; chmod 000 "$UNREADABLE/tasks.db"
if [[ -r "$UNREADABLE/tasks.db" ]]; then
  printf 'skip T35 (running as root: chmod 000 is still readable)\n'
else
  OUT="$(env TASKS_DIR="$UNREADABLE" TASKS_DB="$UNREADABLE/tasks.db" "$UI" --data 2>/dev/null)"
  t 'T35 an unreadable database is absent, not a crash' absent "$(jq -r .data.store <<<"$OUT")"
fi
chmod 644 "$UNREADABLE/tasks.db"

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
HTML="$(board --html)"
tcontains 'T45 --html carries the queue view'   'gates' "$HTML"
t 'T46 the page fetches nothing off this host' 0 \
  "$(grep -coE '(src|href)="https?://' <<<"$HTML" || true)"

echo "== T5x read-only: a full render must not touch the store"
BEFORE="$(sha256sum "$BOARD/tasks.db" | cut -d' ' -f1) $(ls -A "$BOARD" | sort | tr '\n' ' ')"
board --data >/dev/null; board --html >/dev/null
AFTER="$(sha256sum "$BOARD/tasks.db" | cut -d' ' -f1) $(ls -A "$BOARD" | sort | tr '\n' ' ')"
t 'T51 the database and its sidecars are byte-identical after a render' "$BEFORE" "$AFTER"

echo "== T6x the refusals (no sign-in, so the bind is the only control)"
set +e
board --host=10.0.0.1 --once --port="$(free_port)" >"$TMP/bind.out" 2>&1; RC=$?
set -e
t 'T61 a non-loopback bind is refused' 3 "$RC"
tcontains 'T62 ...and the refusal names the way out' 'FIVE_UI_ALLOW_REMOTE' "$(cat "$TMP/bind.out")"
for bad in 0 99999 abc; do
  set +e; board --port="$bad" --once >/dev/null 2>&1; RC=$?; set -e
  t "T63 --port=$bad is refused" 3 "$RC"
done
set +e; board --nope >/dev/null 2>&1; RC=$?; set -e
t 'T64 an unknown flag is a usage error' 2 "$RC"
set +e; board --help >/dev/null 2>&1; RC=$?; set -e
t 'T65 --help exits 0' 0 "$RC"

echo "== T7x parity with the core verb (skipped where core is not installed)"
if command -v 5dive >/dev/null 2>&1 && 5dive ui --html >/dev/null 2>&1; then
  t 'T71 --html is byte-identical to the core verb' \
    "$(5dive ui --html | sha256sum | cut -d' ' -f1)" "$("$UI" --html | sha256sum | cut -d' ' -f1)"
  t 'T72 --data agrees with the core verb on the LIVE board' \
    "$(5dive ui --data | jq -Sc 'del(.data.generated_at)')" \
    "$("$UI" --data | jq -Sc 'del(.data.generated_at)')"
else
  printf 'skip T71/T72 (no 5dive on PATH: parity is a box arm, not a CI arm)\n'
fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
