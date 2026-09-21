# 5dive-ui

The `ui` plugin for [5dive](https://github.com/5dive-ai/5dive): a read-only web view of one
box — its org chart, its queue, its open gates, and the signed trigger deliveries that opened
rows. One plugin, one repo.

```
5dive ui                 # serve on http://127.0.0.1:8735
5dive ui --data          # the JSON the views render
5dive ui --html          # the page itself
```

## This repository is not installable yet, and that is on purpose

`5dive plugin add 5dive-ai/5dive-ui` is **refused today**, with:

```
error: ui declares the verb 'ui', which is already a 5dive command — a plugin verb is only
       ever reached AFTER the builtin table, so this one could never run.
```

That refusal is correct. `ui` is still a builtin in the core CLI (`src/main.sh`'s dispatch table
and `FIVEDIVE_BUILTIN_VERBS` in `src/cmd_plugin.sh`), and the same name cannot be claimed twice.
The migration order is *readers first, delete last*: this tree is published while core still owns
the verb, so the code can be reviewed and graded before anything is removed from anyone's box. The
install line starts working when core releases the name and routes the un-migrated case through its
moved-verb fallthrough (DIVE-4618).

**Until then, keep using `5dive ui` from the core CLI.** Nothing has been removed and no box needs
to do anything.

## What is here

| path | what it is |
|---|---|
| `ui/bin/ui` | the verb. Core's `src/cmd_ui.sh` carried across, plus a prelude and three marked divergences |
| `ui/.claude-plugin/plugin.json` | the plugin manifest (contract 1, `verb` capability) |
| `.claude-plugin/marketplace.json` | the one-entry marketplace at the repo root |
| `tests/ui_plugin_unit.sh` | the harness: 43 arms over the data seam, the divergences and the refusals |
| `tests/ui_mutants.sh` | the control: six mutants, each named to the arm that must kill it |

## Running the tests

```
bash tests/ui_plugin_unit.sh    # 43 passed, 0 failed
bash tests/ui_mutants.sh        # 6 mutants killed, 0 not
```

The harness needs `bash`, `sqlite3`, `jq`, `python3` and `curl` — no 5dive, no box. Two of its arms
(T71/T72) compare this plugin's output with the core verb's byte for byte and are skipped when
`5dive` is not on `PATH`, because that comparison is a box arm, not a CI arm.

## The seam this does not close

The carried code reads the box's task store **by SQL**, naming core's tables and columns. Those are
core's private schema, not a published contract, so once boxes install this plugin a core migration
that renames a column breaks the views silently on any box that upgraded one side and not the other.
Publishing this tree does not create that risk — nothing is removed and nobody is told to install it
— but advertising the install does. The read contract is owed before that step.

## Want to build a view?

The control plane is early and four read-only views is a start, not a finish.
[CONTRIBUTING.md](CONTRIBUTING.md) is the honest map of what is missing, with the data source
named for each screen, plus five scoped issues — two of them
[good first issue](https://github.com/5dive-ai/5dive-ui/labels/good%20first%20issue). You do not
need a 5dive box: `ui/bin/ui --data` answers from a clone.

MIT licensed, like the CLI.
