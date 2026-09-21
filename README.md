# 5dive-ui

The `ui` plugin for [5dive](https://github.com/5dive-ai/5dive): a read-only web view of one
box — its org chart, its queue, its open gates, and the signed trigger deliveries that opened
rows. One plugin, one repo.

```
5dive plugin add 5dive-ai/5dive-ui

5dive ui                 # serve on http://127.0.0.1:8735
5dive ui --data          # the JSON the views render
5dive ui --html          # the page itself
```

Needs a 5dive that carries the `board` verb (`5dive board --contract-version` answers). On an
older box, install refuses nothing and the verb says so on the first run: `sudo 5dive self-update`.

## Why this is its own repository

Changing a screen used to mean cloning 121k lines of runtime. It does not any more. **Core owns
the board document; this repository owns the presentation** — the page, the routes, the layout,
the interaction, all of it in one file you can read in an afternoon.

That boundary is a published contract rather than a convention. The first version of this plugin
carried core's five SQL queries across with the rest of the code: it opened core's private sqlite
store and named `tasks`, `agents_org`, `event_triggers` and about thirty columns, two of them
derived expressions that existed nowhere but inside the query strings. That coupling was a
*string* — nothing in either repository could see it break, so a core migration renaming a column
would have broken these views silently on every box that upgraded one side and not the other.

Now the runtime publishes the document instead:

```
$ 5dive board --contract-version
1
$ 5dive board --json | jq -c .data.contract
{"name":"5dive.board","version":1}
```

`ui --data` is that document, passed through byte for byte. This plugin does not open a database,
does not need `sqlite3`, and does not know what a column is. The version integer moves only on a
**break** — a field removed, renamed or retyped — never on a growth, so this build pins the
versions it understands and refuses an unknown one **by name and before it binds a socket**, on
the terminal of the person who typed the command rather than as a blank page in a tab.

The contract, and the two alternatives that were refused, are written down in core's
[docs/board-contract.md](https://github.com/5dive-ai/5dive/blob/main/docs/board-contract.md).

## What is here

| path | what it is |
|---|---|
| `ui/bin/ui` | the verb. One file: the board call, the page, and the server that holds the socket |
| `ui/.claude-plugin/plugin.json` | the plugin manifest (contract 1, `verb` capability) |
| `.claude-plugin/marketplace.json` | the one-entry marketplace at the repo root |
| `docs/contribute.md` | **start here if you want to build a screen** — the scoped issues and where each number comes from |
| `tests/ui_plugin_unit.sh` | the harness: the passthrough, the negotiation, the refusals, the served page |
| `tests/ui_mutants.sh` | the control: each mutant breaks one behaviour and names the arm that must kill it |

## Contributing

[docs/contribute.md](docs/contribute.md) is the honest map of what is missing, with five scoped
issues and the data source named for each one. Two of them are good first issues.

```
bash tests/ui_plugin_unit.sh
bash tests/ui_mutants.sh
```

The suite needs `bash`, `jq`, `python3` and `curl` — no 5dive and no box, because it drives
`ui/bin/ui` against a stub runtime it writes itself. Its two parity arms compare this plugin's
output with the real `5dive board --json` and skip themselves where core is not installed, because
that comparison is a box arm, not a CI arm.

MIT.
