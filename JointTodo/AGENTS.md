# JointTodo local-agent playbook

JointTodo is a local-first macOS application. The GUI and `jointodo` CLI use the
same JSON library. Use the CLI for agent changes; do not edit the JSON by hand.

## Connectivity boundary

This version supports only agents running locally with shell/filesystem access
to the Mac. It has no web API, cloud sync, MCP server, browser bridge, or remote
authentication. A web-only LLM cannot operate JointTodo.

Do not claim remote or web connectivity, and do not upload the task library.

## Safe operating procedure

Before changing anything:

```sh
jointodo path
jointodo show --json
```

Then:

1. Confirm the active data path is the intended library.
2. Resolve the target project, list, and item from JSON.
3. Prefer UUIDs over names. Names are accepted only when unique.
4. Make the smallest requested mutation.
5. Re-run `jointodo show --json` and verify the final state.
6. Report exactly what changed.

Use a disposable library for tests:

```sh
jointodo --data-file /tmp/jointodo-agent-test.json show --json
```

Never test destructive or completion-changing commands against the user's live
library. Never rewrite IDs, parent links, positions, timestamps, schemaVersion,
or revision manually.

## Command reference

```text
jointodo path
jointodo show [--json]

jointodo project-add <name>
jointodo project-rename <project-ref> <new-name>
jointodo project-delete <project-ref> [project-ref ...]
jointodo project-move <project-ref> <position>

jointodo list-add <project-ref> <title>
jointodo list-rename <list-ref> <new-title>
jointodo list-delete <list-ref> [list-ref ...]
jointodo list-move <list-ref> <position>
jointodo list-complete <list-ref>
jointodo list-uncomplete <list-ref>
jointodo list-timestamp <list-ref> <date|datetime|timezone>

jointodo item-add <list-ref> <title> [--parent <item-ref>]
jointodo item-rename <list-ref> <item-ref> <new-title>
jointodo item-delete <list-ref> <item-ref> [item-ref ...]
jointodo item-move <list-ref> <item-ref> <position> [--parent <item-ref|root>]
jointodo item-complete <list-ref> <item-ref>
jointodo item-uncomplete <list-ref> <item-ref>
```

`<ref>` means an exact case-insensitive name or a UUID. A duplicate name is an
error; retry with the UUID returned by `show --json`.

All commands accept an explicit data file:

```sh
jointodo --data-file /absolute/path/to/library.json <command>
```

`JOINTODO_DATA_FILE` is also supported, but `--data-file` is clearer for an
agent and takes precedence.

Move positions are one-based. An item stays under its current parent unless
`--parent` is provided. Use `--parent root` to promote it to the top level.
Cycle-producing moves fail without changing the library.

## Example agent session

```sh
jointodo show --json
jointodo list-add E8A02BB8-C01F-44E4-AB36-EABC24E7EF02 "Paint office"
jointodo item-add 8CE767AE-6FD4-444E-99BE-14B0D7990DC6 "Choose color"
jointodo item-complete 8CE767AE-6FD4-444E-99BE-14B0D7990DC6 2D02855E-62FB-4102-917A-00E70B94BA28
jointodo show --json
```

The UUIDs above are illustrative. Always read the current library and use its
actual IDs.

## Completion rules

- Completing an item completes all descendants.
- Completing all children completes their parent.
- Uncompleting a child uncompletes its ancestors.
- Completing a list completes every item in it.
- A list is complete when all root items are complete.

The GUI polls for revision changes and normally reflects CLI edits within about
two seconds. Its Reload button forces an immediate refresh.
