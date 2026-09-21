# ui

Four views over ONE host: the org chart, the open queue, the live gates, and the trigger
deliveries that opened rows. Read-only by construction — the server answers `GET`/`HEAD` on
exactly three paths and returns 405 for everything else, so no amount of client-side code can
make it write.

```
5dive ui                       # serve on http://127.0.0.1:8735 (Ctrl-C to stop)
5dive ui --port=9000
5dive ui --data                # the JSON the views render (no server)
5dive ui --html                # the page itself (no server)
5dive ui --once                # serve exactly one request, then exit (tests/probes)
  --host=<addr>                # loopback only unless FIVE_UI_ALLOW_REMOTE=1
```

**There is no sign-in and there will not be one**, which makes the loopback bind the only thing
between an unauthenticated view of your board and the network. `--host` therefore accepts loopback
addresses only; binding anywhere else needs `FIVE_UI_ALLOW_REMOTE=1` set deliberately and says so,
loudly, at startup.

Deliberately absent, because this is the free single-host view: anything fleet-wide, the
marketplace, hosted council.

## Where the data comes from

Everything on every screen is one document, emitted by the runtime:

```
5dive board --json              # exactly what `ui --data` prints
5dive board --contract-version  # the integer this build pins
```

**Core owns the document, this plugin owns the presentation.** `--data` passes core's bytes
through untouched, so `ui --data`, `/api/state` and `5dive board --json` cannot drift apart: there
is one producer and it is not in this repository. This file opens no database and does not need
`sqlite3`.

`FIVE_UI_BOARD_VERSIONS` is the list of contract versions this build can render. The integer moves
only on a **break** (a field removed, renamed or retyped) and never on a growth, so an unknown
version is not "newer", it is incompatible — it is refused by name, naming both numbers, and
refused **before the socket is bound**, because a named error on a terminal is diagnosable and a
blank page in a browser tab is not. A core too old to answer `board --contract-version` fails that
same exec, in the same place, and is told to `self-update`.

`FIVE_UI_CLI` points at the 5dive binary; it defaults to `5dive` on `PATH`.

## The two divergences from the core verb

`bin/ui`'s presentation half came from core's `src/cmd_ui.sh`. Two lines of it had to change, and
each is marked `PLUGIN DIVERGENCE` at its site:

1. **The page polls this executable**, not the CLI bundle — core asked `five_self_bundle` for the
   binary that answers `5dive ui --data`; here that binary is `bin/ui` itself.
2. **The served page's poll argv** drops the `ui` word for the same reason as (1).

(The third divergence 0.1.0 carried — a widened guard around core's task store — is gone with the
store reads themselves.)

`tests/ui_plugin_unit.sh` is what says whether all of this is still true, and
`tests/ui_mutants.sh` is what says whether those arms are looking at anything.
