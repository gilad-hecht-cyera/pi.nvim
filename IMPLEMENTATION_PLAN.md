# pi.nvim Implementation Plan

Goal: fork `sudo-tee/opencode.nvim` into a Pi-native Neovim/LazyVim sidebar plugin. Preserve the useful sidebar UX, input/output panes, markdown rendering, keymaps, visual-selection workflows, and diff/review ideas, while replacing the opencode HTTP/SSE backend with Pi's RPC protocol.

Pi integration target:

```bash
pi --mode rpc
```

Pi RPC is LF-delimited JSONL over stdin/stdout. Do **not** use opencode's `serve` model, REST endpoints, or SSE event stream in the final implementation.

## High-level Architecture

Current upstream shape:

```text
opencode.nvim UI
  -> opencode HTTP API
  -> opencode serve
```

Target shape:

```text
pi.nvim UI
  -> Lua Pi RPC client
  -> pi --mode rpc subprocess
```

Initial strategy: keep most UI and renderer code intact, but replace the backend layer. Where the existing renderer expects opencode-shaped messages, add an adapter that converts Pi messages/events into a compatible internal message/part model. Later, once the fork is stable, gradually make the renderer Pi-native.

## Important Pi RPC Commands

Minimum useful commands:

- `prompt`: send a user prompt.
- `steer`: queue steering while Pi is running.
- `follow_up`: queue a follow-up after Pi settles.
- `abort`: abort current operation.
- `get_state`: current model/session/streaming state.
- `get_messages`: current conversation messages.
- `get_entries`: append-only session tree entries.
- `get_tree`: full session tree.
- `new_session`: create a fresh session.
- `switch_session`: load another session file.
- `fork`: fork from an entry.
- `clone`: clone current branch.
- `compact`: manual compaction.
- `get_commands`: skills, prompt templates, extension commands.
- `get_available_models`: model picker data.
- `set_model`: model switching.
- `cycle_model`: quick model cycle.
- `set_thinking_level` / `cycle_thinking_level`.
- `get_session_stats`: footer/status data.

Important streamed event types:

- `agent_start`
- `agent_end`
- `agent_settled`
- `turn_start`
- `turn_end`
- `message_start`
- `message_update`
- `message_end`
- `tool_execution_start`
- `tool_execution_update`
- `tool_execution_end`
- `queue_update`
- `compaction_start`
- `compaction_end`
- `auto_retry_start`
- `auto_retry_end`
- `extension_error`
- `extension_ui_request`

## Core Files to Replace or Heavily Adapt

From the forked opencode.nvim codebase, these are the backend-heavy areas:

- `lua/opencode/server_job.lua`
- `lua/opencode/opencode_server.lua`
- `lua/opencode/api_client.lua`
- `lua/opencode/event_manager.lua`
- `lua/opencode/services/messaging.lua`
- `lua/opencode/services/session_runtime.lua`
- `lua/opencode/services/agent_model.lua`

The UI and renderer code can be preserved initially:

- `lua/opencode/ui/output_window.lua`
- `lua/opencode/ui/input_window.lua`
- `lua/opencode/ui/output.lua`
- `lua/opencode/ui/renderer.lua`
- `lua/opencode/ui/renderer/*`
- picker/completion/context modules where useful

## Proposed New Modules

Eventually rename the module namespace from `opencode` to `pi`. Early in the migration, it is okay to keep `opencode` names to reduce churn.

Suggested final structure:

```text
lua/pi/
  init.lua
  config.lua
  pi_process.lua
  rpc_client.lua
  event_adapter.lua
  services/
    messaging.lua
    session_runtime.lua
    model.lua
  ui/
    ...existing adapted UI...
```

### `pi_process.lua`

Responsibilities:

- Spawn `pi --mode rpc` with `vim.system` or `vim.fn.jobstart`.
- Use project cwd as subprocess cwd.
- Read stdout as strict LF-delimited JSONL.
- Strip optional trailing `\r` from each line.
- Decode each JSON object with `vim.json.decode`.
- Send JSON commands to stdin with a trailing `\n`.
- Track process state and PID.
- Stop process on `VimLeavePre`.
- Surface stderr and process exits as user-visible errors.

Important: Pi's docs explicitly warn to split only on `\n`; do not use a generic line reader that splits on Unicode separators.

### `rpc_client.lua`

Responsibilities:

- Provide high-level methods over `pi_process`.
- Add request IDs to commands that expect responses.
- Match `type = "response"` events by `id`.
- Return promises/futures compatible with the existing plugin style.
- Expose command methods like:
  - `prompt(message, opts)`
  - `abort()`
  - `get_state()`
  - `get_messages()`
  - `new_session()`
  - `switch_session(path)`
  - `get_available_models()`
  - `set_model(provider, model_id)`

### `event_adapter.lua`

Responsibilities:

- Convert Pi RPC events into the plugin's internal render model.
- Initially adapt Pi into opencode-like `message.info` + `message.parts` objects so existing renderer code can remain mostly unchanged.
- Later, this can be removed if the renderer becomes Pi-native.

Suggested initial mappings:

- Pi user message -> internal message with `info.role = "user"` and one `text` part.
- Pi assistant text -> assistant message with `text` part.
- Pi thinking -> assistant `reasoning`/`thinking` part.
- Pi tool call -> `tool` part.
- Pi tool result/update -> tool output part or update on the existing tool part.
- Pi `agent_settled` -> session idle/done event.
- Pi `compaction_*` -> synthetic status part or notification.
- Pi `auto_retry_*` -> synthetic status part or notification.
- Pi `extension_ui_request` -> Neovim prompt/select/input UI, then send `extension_ui_response`.

## Migration Phases

### Phase 0: Fork hygiene

- Fork `sudo-tee/opencode.nvim` into `pi.nvim`.
- Preserve upstream license.
- Add this implementation plan.
- Decide whether to keep module name `opencode` temporarily or immediately rename to `pi`.
- Add a development LazyVim plugin entry pointing to the local fork:

```lua
{
  dir = "/Users/gilad.hecht/workspace/personal/pi.nvim",
  name = "pi.nvim",
  config = function()
    require("pi").setup({
      ui = { position = "right" },
    })
  end,
}
```

If module rename is deferred, use `require("opencode")` until the rename lands.

### Phase 1: Minimal Pi RPC chat

Goal: open sidebar, type prompt, stream assistant text.

Tasks:

- Add `pi_process.lua` to spawn `pi --mode rpc`.
- Add JSONL parser and command sender.
- Add `rpc_client.lua` with `prompt`, `abort`, `get_state`, `get_messages`.
- Replace message send path in `services/messaging.lua` to call Pi RPC `prompt`.
- Handle `message_update` text deltas and append them to the output pane.
- Handle `agent_settled` to mark the run complete.
- Keep session picker/model picker disabled if needed.

Acceptance criteria:

- `:Pi` or configured keymap opens the sidebar.
- Submitting a prompt sends `{"type":"prompt","message":"..."}` to Pi.
- Streaming assistant text appears in the output pane.
- `<C-c>` or existing cancel key sends `{"type":"abort"}`.

### Phase 2: Internal message adapter

Goal: use existing renderer more fully.

Tasks:

- Implement `event_adapter.lua`.
- Assign stable internal IDs for Pi messages/content blocks when Pi events do not include the exact IDs the renderer expects.
- Convert full `get_messages` output into internal message/part arrays.
- On startup/session switch, call `get_messages` and render the full session.
- Adapt `message_start`, `message_update`, `message_end`, `tool_execution_*` into internal update events.

Acceptance criteria:

- Existing output renderer shows user messages, assistant messages, markdown, tool calls, and tool results coherently.
- Re-opening the sidebar can reconstruct current session from `get_messages`.

### Phase 3: Pi session support

Goal: use Pi sessions instead of opencode sessions.

Tasks:

- Replace session runtime APIs with Pi RPC equivalents.
- Implement `new_session`.
- Implement `get_state`-based current session metadata.
- Implement `get_entries` and/or `get_tree` for timeline/tree UI.
- Implement `switch_session` by path.
- Implement `fork` and `clone` flows.
- Decide how to list available Pi sessions. Pi RPC does not appear to expose a global session list directly; likely use filesystem discovery under `~/.pi/agent/sessions` or invoke `pi` session CLI behavior only if exposed later.

Acceptance criteria:

- New session works.
- Current session name/file/id can appear in footer/header.
- Existing session/timeline UI either works with Pi sessions or is clearly disabled until implemented.

### Phase 4: Tool, thinking, queue, compaction rendering

Goal: expose Pi-native runtime features.

Tasks:

- Render thinking deltas with a fold/toggle similar to opencode reasoning output.
- Render tool execution start/update/end.
- Show running/settled status.
- Show queued steering/follow-up messages from `queue_update`.
- Render compaction start/end.
- Render auto-retry status.
- Refresh edited buffers on tool results that modify files; conservatively run `:checktime` after `tool_execution_end` for write/edit/bash, or detect file changes later.

Acceptance criteria:

- User can understand what Pi is doing from the sidebar.
- Tool output can be folded/toggled.
- File edits are noticed by Neovim.

### Phase 5: Models and slash commands

Goal: make model/command workflows Pi-native.

Tasks:

- Model picker from `get_available_models`.
- Switch model with `set_model`.
- Cycle model with `cycle_model`.
- Thinking level picker/cycle with `set_thinking_level` / `cycle_thinking_level`.
- Slash commands picker from `get_commands`.
- Prompt templates and skills can be invoked by sending `/command` text through Pi `prompt`.

Acceptance criteria:

- Existing model keymaps map to Pi models.
- Existing slash-command UI lists Pi commands instead of opencode commands.

### Phase 6: Extension UI request support

Goal: support Pi extensions that ask the user questions.

Tasks:

- Handle `extension_ui_request` events.
- For `select`, show picker and respond with `extension_ui_response`.
- For `confirm`, use `vim.ui.select` or custom confirmation UI.
- For `input`, use `vim.ui.input`.
- For `editor`, open temporary buffer or floating editor.
- For fire-and-forget methods (`notify`, `setStatus`, `setWidget`, `setTitle`, `set_editor_text`), map to Neovim notifications/status/input buffer updates.

Acceptance criteria:

- A Pi extension using `ctx.ui.select()` works from inside Neovim.

### Phase 7: Rename and polish

Tasks:

- Rename Lua module namespace `opencode` -> `pi`.
- Rename commands and augroups from `Opencode*` -> `Pi*`.
- Rename filetype `opencode_output` -> `pi_output`.
- Update docs and README.
- Update default keymap prefix, probably from `<leader>o` to one of:
  - `<leader>p` for Pi
  - `<leader>a` for AI/agent
  - keep `<leader>o` for compatibility
- Update LazyVim config example.

## LazyVim Plugin Config Target

Final desired config:

```lua
return {
  {
    "gilad/pi.nvim",
    config = function()
      require("pi").setup({
        ui = {
          position = "right",
        },
      })
    end,
    dependencies = {
      "nvim-lua/plenary.nvim",
      {
        "MeanderingProgrammer/render-markdown.nvim",
        opts = {
          anti_conceal = { enabled = false },
          file_types = { "markdown", "pi_output" },
        },
        ft = { "markdown", "pi_output" },
      },
      "saghen/blink.cmp",
      "folke/snacks.nvim",
    },
  },
}
```

## Notes and Risks

- Pi RPC is process-based JSONL, not HTTP. Avoid preserving opencode's HTTP abstraction unless needed as a temporary compatibility shim.
- Pi does not have opencode's permission system by default. Permission UI should either be removed, repurposed for Pi extension UI, or implemented later as a Pi extension.
- Pi session format is JSONL tree-based. This differs from opencode's session/message model.
- Existing diff/revert flows may depend on opencode snapshots. For Pi, start with Neovim/Git diff support and later consider checkpoint integration.
- Avoid a huge rename in the first commit if it blocks backend progress. A staged rename is safer.

## Immediate Next Steps

1. Inspect the fork in `/Users/gilad.hecht/workspace/personal/pi.nvim`.
2. Check whether module namespace is still `opencode`.
3. Add a minimal `pi_process.lua` and test spawning `pi --mode rpc --no-session`.
4. Implement JSONL stdout parsing and command sending.
5. Wire one keymap/action to send a hardcoded prompt and print streamed deltas into an output buffer.
6. Replace the normal input submit path with Pi `prompt`.
7. Iterate toward the existing sidebar renderer once basic streaming works.
