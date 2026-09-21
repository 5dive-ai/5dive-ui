# Changes

## 0.2.0 — 2026-09-21

**Installable.** Core released the `ui` verb (DIVE-4783), so `5dive plugin add 5dive-ai/5dive-ui`
now succeeds and `5dive ui` on a box that has not installed it prints the install line instead of
`unknown command`.

**The plugin stopped reading core's database.** 0.1.0 carried core's five SQL queries across; it
opened the task store and named `tasks`, `agents_org`, `event_triggers`, `event_deliveries` and
about thirty columns, two of them derived expressions that existed nowhere but inside the query
strings. That coupling was a string, invisible to every test in both repositories, and a core
migration renaming a column would have broken these views silently on any box that upgraded one
side and not the other.

`_ui_state_json()` is now one `5dive board --json` call, and the document is passed through **byte
for byte** — not re-keyed, not re-ordered, not re-wrapped — so `ui --data`, `/api/state` and
`5dive board --json` are provably the same answer on the same state instead of three that happen
to agree. `sqlite3` is no longer a dependency, and the store-absent board is core's answer too:
this file no longer carries its own copy of what an empty board looks like.

**The version is negotiated before the socket.** `5dive board --contract-version` is one exec that
reads no store, so it answers on a box whose board is absent, unreadable or mid-migration.
`FIVE_UI_BOARD_VERSIONS` is what this build understands; anything else is refused by name, naming
both numbers, and a core too old to carry `board` at all is named as that rather than arriving as
a broken page. `FIVE_UI_CLI` overrides the CLI path for a relocated install or a test.

**The harness moved with the code.** The ~20 arms over `handoff_state`, `gate_live`, the flows
derivation and the stats graded core's semantics from a repository that does not own them — they
now live in core's `tests/board_contract_unit.sh`, next to the producer. What is left here grades
what this repository owns: the passthrough, the negotiation, the refusals, the served page, and a
runtime arm that poisons `sqlite3` on `PATH` to show the store coupling is gone in the binary and
not just in the diff. 31 arms, 7 mutants.

**The contributor page is corrected, not re-carried.** DIVE-4784 landed it here as
`CONTRIBUTING.md` while this change was in flight; that version described the SQL store read and
told contributors a clone answers `--data`, both of which this release falsifies. The page now
names the board call, `--html` as the no-box loop, and drops `sqlite3` from the prerequisites.

## 0.1.0 — 2026-09-21

First publication of the `ui` plugin into its own repository (DIVE-4618, step 1 of the migration:
publish, remove nothing).

- `ui/bin/ui` carries core's `src/cmd_ui.sh` across, with a prelude re-establishing the core
  symbols a plugin executable cannot inherit and three marked divergences.
- `tests/ui_plugin_unit.sh`: 43 arms, hermetic (its own fixture board, no 5dive needed), plus two
  parity arms against the core verb that run only where core is installed.
- `tests/ui_mutants.sh`: six mutants, each named to the arm that must kill it.

Not installable — core still claimed the `ui` verb. See 0.2.0.
