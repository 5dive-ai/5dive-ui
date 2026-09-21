# Changes

## 0.1.0 — 2026-09-21

First publication of the `ui` plugin into its own repository (DIVE-4618, step 1 of the migration:
publish, remove nothing).

- `ui/bin/ui` carries core's `src/cmd_ui.sh` across, with a prelude re-establishing the six core
  symbols a plugin executable cannot inherit (`fail`, `warn`, `step`, the `E_*` codes, the state
  paths, the reader) and three marked divergences.
- The reader refuses any statement that is not a single `SELECT`: a plugin never writes core's
  store, and the arm that proves it compares the database byte for byte across a full render.
- `tests/ui_plugin_unit.sh`: 43 arms, hermetic (its own fixture board, no 5dive needed), plus two
  parity arms against the core verb that run only where core is installed.
- `tests/ui_mutants.sh`: six mutants, each named to the arm that must kill it.

Not yet installable — core still claims the `ui` verb. See the repository README.
