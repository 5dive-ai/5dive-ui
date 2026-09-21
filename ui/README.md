# ui

Three views over ONE host: the org chart, the open queue, the live gates, and the trigger
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

## The three divergences from the core verb

`bin/ui` is core's `src/cmd_ui.sh` carried across verbatim apart from these, each marked
`PLUGIN DIVERGENCE` at its site:

1. **The page polls this executable**, not the CLI bundle — core asked `five_self_bundle` for the
   binary that answers `5dive ui --data`; here that binary is `bin/ui` itself.
2. **A store this process cannot read is a named empty board.** Core called `tasks_db_init`, which
   creates the store when it is missing and the caller is root. A plugin must never create core's
   state or run its migrations, so the guard widens to cover an unreadable database instead.
3. **The served page's poll argv** drops the `ui` word for the same reason as (1).

Everything else — every query, the flow derivation, the whole page — is core's code, and
`tests/ui_plugin_unit.sh` is what says whether that is still true.
