# JointTodo

JointTodo is a local-first macOS to-do application designed to be edited by
both a person and a local LLM/coding agent. It provides a native three-column
GUI, a machine-friendly CLI, nested tasks, projects, completion propagation,
and configurable timestamps.

## Current scope: local agents only

JointTodo 0.4 is intentionally local-only. It has no cloud service, hosted API,
browser extension, account system, sync server, MCP server, or public URL.

A local agent such as Codex or another locally running LLM tool can use
JointTodo when it has permission to execute the `jointodo` CLI or access the
Mac's filesystem. A web-only application cannot reach the library on your Mac.
Putting this source code on GitHub does not expose or synchronize your task
data.

Supporting web-based assistants later would require a separately designed
bridge or authenticated service. That functionality does not exist in this
version.

## Features

- Projects, lists, tasks, and nested subtasks
- Collapsible subtask groups at every nesting level
- Drag-and-drop ordering for projects, lists, tasks, and nested tasks
- Task promotion and nesting by dropping above, below, or inside another task
- Native macOS GUI with inline renaming and multi-select project deletion
- Click-and-drag project range selection
- Automatic parent/list completion when all children are complete
- Completing a parent completes every descendant
- Created and completed timestamps with adjustable display granularity
- Shared local JSON library for the GUI and CLI
- Automatic GUI reload after local-agent changes
- Stable UUIDs and JSON output for reliable agent operation

## Requirements

- macOS 14 or newer
- Xcode Command Line Tools or Xcode with a compatible Swift toolchain

Install the command-line tools if needed:

```sh
xcode-select --install
```

## Installation

Clone the repository, then run:

```sh
./scripts/build-app.sh
./scripts/install-app.sh
./scripts/install-cli.sh
```

This installs:

- The GUI at `~/Applications/JointTodo.app`
- The CLI at `~/.local/bin/jointodo`

If `~/.local/bin` is not already on your shell path, add this to `~/.zshrc`:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

You can also run directly from the repository without installing:

```sh
swift run JointTodo
swift run jointodo show
```

## GUI basics

The left column contains projects, the middle column contains lists in the
selected project, and the right column contains the selected list's tasks.

- Double-click empty space in the Projects or Lists column to add an entry.
- Double-click a name to rename it; Return saves and Escape cancels.
- Use the input above the task area to add a task.
- Use the plus button beside a task to add a subtask.
- Use the chevron beside a task to collapse or expand its subtasks.
- Drag the handle beside any project, list, or task to reorder it.
- Drop a task above or below another task to place it at that task's level; drop
  it in the center to make it a subtask.
- Click a completion circle to change status.
- Command-click, Shift-click, or click-drag to select multiple projects.
- Press Delete to remove selected projects or the selected list.
- Click empty project-column space to clear project selection.

## Data and privacy

The default library is:

```text
~/Documents/JointTodo/jointodo.json
```

The library stays on the Mac unless you deliberately copy or sync it. Task data
is excluded by this repository's `.gitignore`.

Use a different library for testing or automation with either:

```sh
JOINTODO_DATA_FILE=/path/to/library.json jointodo show
jointodo --data-file /path/to/library.json show
```

The CLI's `--data-file` option takes precedence over the environment variable.

## CLI quick start

Discover the active library and inspect it before making changes:

```sh
jointodo path
jointodo show
jointodo show --json
```

Create a hierarchy:

```sh
jointodo project-add "Home Projects"
jointodo list-add "Home Projects" "Door replacement"
jointodo item-add "Door replacement" "Remove old door"
jointodo item-add "Door replacement" "Buy new door"
jointodo item-add "Door replacement" "Clean frame" --parent "Remove old door"
```

Change completion:

```sh
jointodo item-complete "Door replacement" "Remove old door"
jointodo item-uncomplete "Door replacement" "Remove old door"
jointodo list-complete "Door replacement"
jointodo list-uncomplete "Door replacement"
```

Rename or delete entries:

```sh
jointodo project-rename "Home Projects" "House"
jointodo project-move "House" 1
jointodo list-rename "Door replacement" "Replace front door"
jointodo list-move "Replace front door" 1
jointodo item-rename "Replace front door" "Buy new door" "Order new door"
jointodo item-move "Replace front door" "Order new door" 1
jointodo item-move "Replace front door" "Order new door" 2 --parent "Remove old door"
jointodo item-move "Replace front door" "Order new door" 1 --parent root
jointodo item-delete "Replace front door" "Order new door"
jointodo list-delete "Replace front door"
jointodo project-delete "House"
```

Set timestamp display granularity:

```sh
jointodo list-timestamp "Door replacement" date
jointodo list-timestamp "Door replacement" datetime
jointodo list-timestamp "Door replacement" timezone
```

Run `jointodo` with no arguments for the complete command reference.

### Reliable agent workflow

Local agents should use this sequence:

1. Run `jointodo path` to confirm the target library.
2. Run `jointodo show --json` and retain the relevant UUIDs.
3. Use UUIDs for mutations when a name is duplicated or could be renamed.
4. Perform the smallest required mutation.
5. Run `jointodo show --json` again and verify the requested end state.

Mutation commands print tab-separated records in the form:

```text
action<TAB>entity<TAB>uuid<TAB>name-or-detail
```

The CLI exits nonzero for missing or ambiguous references and writes errors to
standard error. It saves atomically and maintains completion propagation,
timestamps, positions, and the library revision. Prefer it over editing the JSON
file directly.

Move positions are one-based. `project-move` reorders projects, `list-move`
reorders within the list's current project, and `item-move` reorders within the
item's current parent unless `--parent` is supplied. Use `--parent root` to
promote a subtask to the top level. Moves that would create a parent/descendant
cycle are rejected.

See [AGENTS.md](AGENTS.md) for a concise playbook intended for coding agents.

## Completion behavior

- Completing a task completes all of its descendants.
- Completing every child completes its parent.
- Uncompleting a child uncompletes its ancestors.
- Completing or uncompleting a list applies to all tasks in that list.
- A list becomes complete when all root tasks are complete.

## Development

Build both products:

```sh
swift build --disable-sandbox
```

Run tests:

```sh
swift test --disable-sandbox
```

Build an ad-hoc-signed app bundle:

```sh
./scripts/build-app.sh
```

Generated builds, local task libraries, Xcode user state, and test data are
ignored by Git.
