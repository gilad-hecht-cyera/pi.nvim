# Sidebar Tabs

Status: planned

## Goal

Allow several Pi sessions to be open in the pi.nvim sidebar at once, with background sessions continuing to run.

### Use cases

1. **Side question**: ask something quick without losing place in a long-running task.
2. **Parallel planning**: plan the next step while the current task is still running.

## Constraints

- One `pi --mode rpc` process holds exactly one live session. `new_session`, `switch_session`, `fork`, and `clone` replace the active session of that process (see pi `docs/rpc.md`, `docs/sdk.md`).
- No installed or known Pi extension offers multiple live sessions inside one process. Pi's own `subagent` example spawns a separate `pi` process per agent.
- pi.nvim currently assumes a single runtime:
  - `PiProcess.get()` / `rpc_client.get()` are module singletons.
  - `pi.state.store` is one global store (`active_session`, `messages`, `windows`, `cost`, ...), read by ~65 modules.
- `quick_chat.lua` shares the same process, so it does not solve the side-question case.

## Decision

**One tab = one Pi RPC process.** This mirrors opening `pi` in another shell tab in the same folder.

```text
Tab {
  id, label, status,
  process, rpc_client, event_manager,
  store,
  input_buf, output_buf,
}
```

### Tab creation

| Action | Result |
|---|---|
| `:Pi tab new` | Empty tab with a fresh session |
| `:Pi tab fork` | New tab forked from the current session |
| Fork from an earlier message | New tab forked at that entry |

### Forking

A fork must never run inside the source process, since that would replace the running session. Instead, the new tab's process does it:

| Fork kind | New tab process |
|---|---|
| At current position | `pi --mode rpc --fork <session>` |
| From earlier message | `--fork <session>`, then RPC `fork {entryId}` |

Existing fork entry points to route through this:

- `/fork` and `:Pi fork` (`commands/handlers/session.lua`)
- session picker `<C-f>` (`ui/session_picker.lua`)
- timeline picker `<C-f>` (`ui/timeline_picker.lua`)
- `[F]ork` output action (`ui/render_state.lua`)

### Config

```lua
ui = {
  tabs = {
    fork_target = 'ask', -- 'ask' | 'tab' | 'current'
  },
}
```

- `ask` (default): prompt with "New tab" / "Replace current".
- `tab`: always fork into a new tab.
- `current`: keep the pre-tabs behavior (fork replaces the current session).

## Architecture

- **Runtime registry**: replace the process/RPC/event-manager singletons with a registry keyed by tab id. `.get()` returns the active tab's instance so existing call sites keep working.
- **Per-tab state slice**: the store stays global. `state/tab_scope.lua` lists the keys a tab owns (session, messages, stats, model, queued messages, input draft, ...). Switching swaps that slice in one batch, so subscribed UI (topbar, footer, context bar) updates without changes. Window handles, focus, cwd, mode, and the event manager stay shared.
- **Pi is the source of truth**: a background tab's conversation lives in its Pi process. Switching re-renders the session from `get_messages` of the new active process, then replays the in-progress assistant message, which `get_messages` does not include yet (`RpcClient.stream_events`). A tab switched into mid-run is re-rendered once more when it settles, so tool results and status end up exact.
- **Background tabs**: only the active tab feeds the event adapter and renderer; background events are not rendered.
- **Tab bar**: rendered in the output window `winbar`, next to the existing session title from `ui/topbar.lua`. Clickable via `%N@Func@label%X`. Shows per-tab status: running, idle, or waiting for permission/question.
- **Notifications**: a background tab notifies when it finishes or needs input.
- **Closing a tab**: if the tab is running, send `abort`, then stop its process. Idle tabs just stop their process. The session file is kept and can be reopened later.
- **Persistence**: save the open tabs (session ids, labels, order, active tab) per cwd under `stdpath('data')`. On restart, restore the tab list, but spawn a tab's process lazily when it is first activated, so N tabs do not cost N process startups.
- **Boundaries**: tab lifecycle actions live in `services/` (per `services/AGENTS.md`); UI lives in `ui/tabbar.lua`.

## Risks

- **Concurrent edits**: two agents writing the same working tree can conflict. Fine for planning; for parallel implementation, a later option is a per-tab `jj workspace`.
- **Same session in two tabs**: two processes writing one session file would corrupt it. Refuse to open a session already owned by another tab.
- **Fork intermediate session**: forking from an earlier message leaves a full-copy session from `--fork`. Delete it right after the entry fork succeeds, since nothing references it.

## Spike results

Run against pi 1.3.0 with throwaway RPC processes.

| Check | Result |
|---|---|
| RPC startup to first `get_state` | ~0.35s |
| Two processes, same cwd | Independent sessions |
| `--fork` while source is streaming | Works, source unaffected |
| Prompt a mid-stream fork | Works |
| Entry ids after `--fork` | Preserved |
| RPC `fork {entryId}` in the forked process | Works |
| `switch_session` to another tab's session | Writes to that file |

Findings:

- A mid-stream fork copies only what has been persisted. It can end on an assistant tool call with no result; prompting it still worked.
- Pi writes a new session file lazily, on the first persisted entry. `get_state.sessionFile` may point to a file that does not exist yet.
- Loading a session runs extension hooks that append entries (e.g. `plannotator` custom entries). So a second process must never open a session owned by another tab, even read-only. `--fork` is the only safe way to branch from a live session.
- After an entry fork, the new session's header has `parentSession` pointing to the intermediate copy. Deleting the intermediate leaves that link dangling. Verified in step 5: pi.nvim never reads `parentSession`; Pi loads the session, and `get_messages` / `get_tree` work. Pi's `/resume` tree shows a session with a missing parent as a root, so the fork no longer appears nested under the original.
- `PiProcess:start()` registered its `VimLeavePre` cleanup in a shared augroup with `clear = true`, so with several processes only the last one would be stopped on exit. Fixed in step 2: the registry owns a single `VimLeavePre` that stops every tab.
- **Startup cost**: each tab spawns a `pi` process.

## Plan

Each step is a separate jj change.

1. ~~**Spike**~~ (done, see Spike results):
   - two RPC processes in the same cwd
   - `--fork` on a session that is still streaming
   - entry IDs are preserved across `--fork`
   - measure process startup time
2. ~~Per-tab runtime registry~~ (done): `lua/pi/tab_runtimes.lua` owns a process and RPC client per tab. `PiProcess.get()` / `RpcClient.get()` return the active tab's. Events from background tabs are not rendered; responses and `streaming` tracking still work.
3. ~~Per-tab state on switch~~ (done): `services/tabs.lua` (`switch`, `new`, `close`), `state/tab_scope.lua`, per-tab output view and input draft, mid-stream replay.
4. ~~Tab commands and the tab bar~~ (done): `:Pi tab new|fork|next|prev|close|goto`, keymaps, clickable strip in the output winbar (`ui/tabbar.lua`), and switching to the owning tab when a session is already open elsewhere.
5. ~~Route fork entry points through `fork_target`~~ (done): `[F]ork`, the timeline picker, `:Pi fork`, `/fork`, and the session picker `<C-f>` ask "New tab" / "Replace current session". Forks into a tab are named `FORK <n> <title>` like in-place forks, and an entry fork prefills the input with the forked prompt. Undo/revert still forks in place.
6. Background status and notifications.
7. Persist and restore tabs per cwd.
