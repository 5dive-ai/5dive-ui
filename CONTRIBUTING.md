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
bash -n ui/bin/ui               # no build step, no install, no dependencies to fetch
ui/bin/ui --data                # the JSON every view renders
ui/bin/ui --port=9000           # the page itself, at http://127.0.0.1:9000
```

**You do not need a 5dive box to build a view.** With no task store to read, `ui/bin/ui --data`
answers `"store": "absent"` and the page renders the empty board by name, so every view is
reachable from a clone. With a box, the same command prints exactly what `5dive ui --data`
prints, from the same store.

Never installed 5dive? [Quickstart](https://github.com/5dive-ai/5dive#quickstart) is a one-liner
and a few minutes.

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

Two of the five are labelled [good first issue](https://github.com/5dive-ai/5dive-ui/labels/good%20first%20issue),
because two of them are. A page where everything is tagged beginner-friendly is a page where
nothing was measured.

### Where the code is

All of it is [`ui/bin/ui`](ui/bin/ui), one file, in this repository:

- `_ui_state_json()` builds the view state from the local SQLite store and serves it at
  `GET /api/state`.
- `_ui_html()` emits the page — inline CSS and JS, no build step, no CDN, because the
  single-file executable is the only artifact we ship.

**Work here, not in core.** `ui/bin/ui` is core's `src/cmd_ui.sh` carried across, and core still
ships its own copy while it holds the `ui` verb name (see [README.md](README.md) for why the
install line is refused until it releases it). A pull request against core's copy is orphaned the
day that copy goes; one against this file is not.

The three deliberate divergences from the carried code are marked `PLUGIN DIVERGENCE` at their
sites and listed in [`ui/README.md`](ui/README.md). If you touch one, say so in the PR — they are
the seam this repo is responsible for.

### Running the tests

```bash
bash tests/ui_plugin_unit.sh    # 43 arms over the data seam, the divergences and the refusals
bash tests/ui_mutants.sh        # 6 mutants, each named to the arm that must kill it
```

They need `bash`, `sqlite3`, `jq`, `python3` and `curl` — no 5dive, no box. Two arms (T71/T72)
compare this plugin's output with the core verb's byte for byte and skip themselves when `5dive`
is not on `PATH`; that comparison is a box arm, not a CI arm. `.github/workflows/ui-tests.yml`
runs both files on every pull request.

A view that changes what `/api/state` carries owes an arm in `tests/ui_plugin_unit.sh`; a view
that only changes the page owes `bash -n ui/bin/ui` clean and a screenshot in the PR.

[The core CONTRIBUTING](https://github.com/5dive-ai/5dive/blob/main/CONTRIBUTING.md) covers the
runtime itself — dev setup, the bundle rule, the CLI's tests.
[What the runtime exposes](https://5dive.ai/docs/5dive-cli) is the CLI reference.

### Two lines this UI does not cross

1. **Read-only by construction.** The server answers `GET` and `HEAD` on exactly three paths and
   returns 405 for everything else, so no amount of client-side code can make it write. Anything
   that mutates state already has a CLI verb; this UI's job is to make the org layer *visible*.
2. **One host.** Every query reads the local store. There is no cross-box roll-up here, on
   purpose.

Both are argued at the top of `ui/bin/ui`. A change that needs either one relaxed is worth
opening an issue about before you build it — not a no, but a conversation.

### Come argue with us

[Discord](https://discord.gg/aU2UQC9Myy). Bring the disagreement; the design notes in
[core's `docs/`](https://github.com/5dive-ai/5dive/tree/main/docs) are where most of ours are
already written down.
