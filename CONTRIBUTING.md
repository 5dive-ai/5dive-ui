# Build the open control plane for an agent company

5dive runs a company of agents: teammates with roles, a shared task queue, approvals, an audit
trail, on a Linux box you own. The runtime is open. The control plane on top of it is early,
and that is the honest reason this page exists.

`5dive ui` today is four read-only views — the org chart, the queue, the gates waiting on a
human, and the signed event triggers. That is a real start and it is not much. The roster, the
live view of what every agent is doing right now, the record of what was approved and by whom,
the same views on a phone: the runtime already emits what those screens need. Somebody has to
build the screens.

**Today**, the whole thing, running on the box this page was written from:

![The org chart view of `5dive ui`, showing the agent tree and how many live handoffs had no human in the path](docs/ui-today.png)

**Wanted:** the views below, and the ones you think of that we did not.

Showing what exists is deliberate. Nobody contributes to a screenshot that already looks
finished.

## Why this is worth your evening

If you are reverse-engineering a closed product to get this, you are doing the hardest possible
version of the work, on a codebase whose licence does not let you keep it, for a runtime you
cannot change.

Here, the runtime is the part that is already open. You are not reconstructing behaviour from
the outside. You can read exactly what the thing does, change it, and see your change run.

## What you get to own

- A real surface, not a toy. People run their companies on this.
- Scoped issues, each with the data source named, so the first hour is building rather than
  archaeology.
- The runtime underneath stays yours: tasks, agents, permissions, audit and execution are
  inspectable and forkable. A frontend you can fork is worth much less than a runtime you can.

## Start here

Run it first. Everything below makes more sense once the page is open in front of you:

```bash
git clone https://github.com/5dive-ai/5dive-ui.git && cd 5dive-ui
./ui/bin/ui --html > page.html    # the page, with no box needed at all
./ui/bin/ui --data                # the JSON every view renders, from the box you are on
./ui/bin/ui --port=9000           # serve it
```

**This whole repository is the UI.** One file is the verb (`ui/bin/ui`), one is the harness. You
do not need the 5dive runtime checked out to change a screen — `--html` renders with no box to
ask at all, which is the loop most frontend work lives in.

Never installed 5dive? [Quickstart](https://github.com/5dive-ai/5dive#quickstart) is a one-liner
and a few minutes; then `5dive plugin add 5dive-ai/5dive-ui` and `5dive ui`.

### The scoped issues

| | Issue | Size |
|---|---|---|
| Roster | [Every agent on the box, and whether it is working right now](https://github.com/5dive-ai/5dive-ui/issues/2) | M |
| Live view | [Poll `/api/state` and surface the runs in flight](https://github.com/5dive-ai/5dive-ui/issues/3) | M |
| Queue | [Group the board by status instead of one flat table](https://github.com/5dive-ai/5dive-ui/issues/4) | **S — good first issue** |
| Gates | [Show the answered gates, not just the open ones](https://github.com/5dive-ai/5dive-ui/issues/5) | M |
| Mobile | [There is no width breakpoint — make the four views work on a phone](https://github.com/5dive-ai/5dive-ui/issues/6) | **S — good first issue** |

Every one of them names **what you see, where the data comes from, what done looks like, and
roughly how big it is.** If an issue ever sends you into archaeology to find out where a number
comes from, that is a bug in the issue — say so in the thread and we will fix it.

Two of the five are labelled good first issue, because two of them are. A page where everything
is tagged beginner-friendly is a page where nothing was measured.

### Where the code is

All of it is [`ui/bin/ui`](ui/bin/ui), one file:

- `_ui_state_json()` asks the runtime for this host's board — one `5dive board --json` call — and
  passes the document through untouched. It is served at `GET /api/state`.
- `_ui_html()` emits the page — inline CSS and JS, no build step, no CDN, because one file is the
  only artifact this plugin ships.

### Where the DATA comes from, and the one boundary that matters

**Core owns the document. This repository owns the presentation.** Every number on every screen
comes out of one versioned JSON document that the runtime emits:

```bash
5dive board --json              # exactly what --data prints
5dive board --contract-version  # the integer this UI pins
```

Its keys are `contract`, `scope`, `store`, `host`, `generated_at`, `org[]`, `queue[]`, `gates[]`,
`flows[]`, `triggers[]`, `deliveries[]` and `stats{}`, and they are written down in core's
[board contract](https://github.com/5dive-ai/5dive/blob/main/docs/board-contract.md). Layout,
routes, styling, interaction and anything else you can see are 100% yours to change here. A new
*field* — a new fact about the board — is a one-line additive PR to core, reviewed by the people
who own that data, because this plugin cannot invent one.

The version integer moves only on a **break**; new fields are additive and leave it alone. This
build pins what it understands in `FIVE_UI_BOARD_VERSIONS` and refuses anything else by name,
before it binds a socket.

### Two lines this UI does not cross

1. **Read-only by construction.** The server answers `GET` and `HEAD` on exactly three paths and
   returns 405 for everything else, so no amount of client-side code can make it write. Anything
   that mutates state already has a CLI verb; this UI's job is to make the org layer *visible*.
2. **One host.** The board document describes the box you are on. There is no cross-box roll-up
   here, on purpose.

Both are argued at the top of `ui/bin/ui`. A change that needs either one relaxed is worth
opening an issue about before you build it — not a no, but a conversation.

### Running the tests

```bash
bash tests/ui_plugin_unit.sh    # the arms
bash tests/ui_mutants.sh        # the control: each mutant names the arm that must kill it
```

Needs `bash`, `jq`, `python3` and `curl`. No 5dive and no box: the suite drives `ui/bin/ui`
against a stub runtime it writes itself.

### Come argue with us

[Discord](https://discord.gg/aU2UQC9Myy).
