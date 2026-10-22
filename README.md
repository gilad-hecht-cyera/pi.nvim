# pi.nvim

A Neovim/LazyVim sidebar frontend for the [Pi coding agent](https://pi.dev).

This is a fork/migration of [`sudo-tee/opencode.nvim`](https://github.com/sudo-tee/opencode.nvim): the sidebar UI, input/output panes, markdown rendering, context workflows, and keymap shape are preserved while the backend is replaced with Pi RPC (`pi --mode rpc`).

> [!WARNING]
> **AI-generated project.** The conversion of opencode.nvim to Pi, and all further development of this fork, is entirely AI generated and maintained. Code, tests, and docs (including this README) are written by AI coding agents, with a human only steering and reviewing. Expect rough edges, and review the code before relying on it. Credit for the original plugin design goes to the opencode.nvim authors.

## Status

Work in progress. Core Pi chat, model and thinking-level switching, Pi sessions (select, rename, fork), and multi-session sidebar tabs work. The Lua namespace is `pi`, so this can be installed alongside `opencode.nvim`.

### Requirements:

- Neovim with the dependencies listed below
- The [`pi`](https://pi.dev) CLI on your `$PATH` (or set `pi_executable`)
- Node.js 24+ only for running the extension tests

Run `:checkhealth pi` to verify the setup.

## Installation

```lua
return {
  dir = "~/path/to/pi.nvim",
  name = "pi.nvim",
  lazy = false,
  config = function()
    require("pi").setup({
      ui = { position = "right" },
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
}
```

## Usage

Open the sidebar:

```vim
:Pi
```

Open Pi as the only Neovim UI in the current working directory:

```bash
bin/pi-in-neovim
```

Install or symlink `bin/pi-in-neovim` (or its short alias `bin/pin`) somewhere on your `$PATH` if you want to run it as `pi-in-neovim`.
This runs `nvim +"Pi pin"`, opens Pi in the current window, and closes other windows in the current tab (for example file explorer/main panes).

### Default keymap prefix is `<leader>p`, mirroring the original opencode.nvim layout with a Pi prefix:

- `<leader>pg` toggle Pi sidebar
- `<leader>pi` open input
- `<leader>pI` open input in a new session
- `<leader>po` open output
- `<leader>pt` toggle focus
- `<leader>pq` close the Pi windows
- `<leader>ps` select session
- `<leader>pT` session timeline (undo to / fork from a message)
- `<leader>ph` select from prompt history
- `<leader>pR` rename session
- `<leader>pp` select provider/model
- `<leader>pV` select thinking level
- `<leader>py` add visual selection to context, `<leader>pY` insert it inline
- `<leader>pz` toggle zoom, `<leader>px` swap sidebar position
- `<leader>ptr` / `<leader>ptt` toggle reasoning / tool output
- `<leader>p/` quick chat
- `<leader>pn` new tab, `<leader>pf` fork session into a new tab, `<leader>pw` close tab
- `<leader>p>` / `<leader>p<` next / previous tab

Set `keymap_prefix` to move all of these, or `default_global_keymaps = false` to disable the editor mappings.

Each sidebar tab runs its own Pi process, so background tabs keep working. Open tabs are restored per
directory. Tab options: `ui.tabs.persist`, `ui.tabs.notify`, and `ui.tabs.fork_target` (`'ask'`, `'tab'`, or `'current'`).

### Moving around

- `]]` / `[[` next / previous tab (also `]t` / `[t`, in both Pi windows)
- `]m` / `[m` next / previous message
- `]u` / `[u` next / previous user message
- `gf` open the file reference under the cursor
- `g<Space>` pick a file matching the reference under the cursor
- `gr` browse all file references in the conversation
- `<CR>` open whatever target is under the cursor

Except for tab switching, these work in the output window (filetype `pi_output`).

### Pasteboard images 

Pasteboard images can be pasted directly in the input window with `p`, `P`, `<C-r>+`, or `<M-v>`. The image is saved to a temporary file, attached to the prompt, and previewed in a small floating window when `snacks.nvim` image support is available. Text paste keeps its normal behavior.

WezTerm handles `Cmd-v` before Neovim sees it. To route `Cmd-v` through pi.nvim while preserving normal paste outside Neovim, add this key to your WezTerm configuration:

```lua
{
  key = "v",
  mods = "CMD",
  action = wezterm.action_callback(function(window, pane)
    local process = pane:get_foreground_process_name() or ""
    local action = process:match("nvim$")
        and wezterm.action.SendKey({ key = "v", mods = "ALT" })
      or wezterm.action.PasteFrom("Clipboard")
    window:perform_action(action, pane)
  end),
}
```

After sending, place the cursor on an `@pasted_image_…` mention in either Pi pane and press `<leader>pv` to toggle its preview. The temporary image must still exist in the current Neovim session.

The preview can be sized or disabled:

```lua
require("pi").setup({
  ui = {
    input = {
      image_preview = {
        enabled = true,
        width = 30,
        height = 10,
        border = "rounded",
      },
    },
  },
})
```

### Useful slash commands in the input window:

- `/sessions` select between sessions (`/resume` remains an alias)
- `/new` start a new session
- `/model` and `/thinking` pick the model and thinking level
- `/fork` fork from a previous user message
- `/compact` compact the current session
- `/reload` restart Pi RPC to reload Pi resources (extensions, settings)
- `/rename <name>` rename the current session
- `/rename` or `/autoname` ask Pi to suggest and apply a concise session name
- `/help` list all commands, including those forwarded to Pi (`/login`, `/export`, `/share`, ...)

New unnamed sessions are automatically given a concise display name after their first `agent_settled` event. Existing
and manually assigned names are never overwritten automatically.

Session naming uses the selected model's resolved authentication, including AWS profiles and the credential chain
for Amazon Bedrock; an API key is not required for those auth methods. After updating the bundled extension, run
`/reload` in the Pi input window to restart Pi RPC, then retry `/rename` in a session with conversation history.

## Pi backend

The plugin spawns Pi RPC with its bundled session-naming extension:

```bash
pi --mode rpc --extension <pi.nvim>/extensions/auto-session-name.ts
```

RPC is JSONL over stdin/stdout. No opencode HTTP server, REST API, or SSE stream is used by the Pi namespace.

Useful config options:

```lua
require("pi").setup({
  pi_executable = "pi",
  pi_args = {}, -- e.g. { "--no-session" } for ephemeral testing
  keymap_prefix = "<leader>p",
  model_picker = {
    -- Restrict the model picker to these "provider/model" ids; nil shows all models.
    include = { "anthropic/claude-sonnet-4-5", "openai/gpt-5" },
  },
  ui = {
    position = "right",
    output = { filetype = "pi_output" },
  },
})
```

## Queued messages

Prompts submitted while the agent is still responding appear in a compact
`Queued` panel above the input. Each prompt is removed from the panel as soon
as its user message enters the conversation stream.

## Thinking output

Model reasoning is rendered as a distinct italic block above the answer. Toggle it with `<leader>ptr`, or
hide it by default with `ui.output.tools.show_reasoning_output = false`.

## Markdown table rendering

Markdown tables are reflowed so each cell wraps inside its own column instead
of producing one very long line that soft-wraps into an unreadable blob.
Column widths are fitted to the output window using display width (so emoji
and CJK text keep the borders aligned), and the widest columns give up space
first.

By default (`style = "box"`) each table is drawn as plain text with box
characters inside a ```` ```box ```` code block, so no markdown renderer
re-parses it:

```
┌─────────┬──────────────────────┬───────────────────────┐
│         │ Logs                 │ Metrics               │
╞═════════╪══════════════════════╪═══════════════════════╡
│ Shape   │ Append-only stream   │ Cumulative state,     │
│         │                      │ rendered on demand    │
└─────────┴──────────────────────┴───────────────────────┘
```

Box tables are plain text: markdown markers and backslash escapes are dropped,
and `<br>` starts a new line inside the cell. Inline formatting is restored as
highlights instead:

- `**bold**` / `__bold__` → `PiTableBold` (linked to `@markup.strong`)
- `*italic*` / `_italic_` → `PiTableItalic` (linked to `@markup.italic`)
- `` `code` `` → `PiTableCode` (linked to `@markup.raw.markdown_inline`)
- `~~struck~~` → `PiTableStrikethrough` (linked to `@markup.strikethrough`)

Emphasis follows the CommonMark delimiter rules, so `snake_case`, `**kwargs`
and `a * b` stay literal, and markers inside code spans are kept as written.
Header cells use the `PiTableHeader` highlight (linked to `Title`) and the
first column uses `PiTableFirstColumn` (linked to `@label`); override any of
these with `vim.api.nvim_set_hl`.

With `style = "markdown"` the output stays a GFM table. Header rows are then
truncated with `…` so the table stays valid GFM, long unbreakable tokens are
split at `_ - . / , : )` boundaries where possible, and inline code spans are
re-fenced on each line so backticks stay balanced.

```lua
require("pi").setup({
  ui = {
    output = {
      rendering = {
        tables = {
          style = "box", -- 'box' | 'markdown'
          reflow = true, -- set false to keep the raw table text
          min_column_width = 8, -- narrowest a column may shrink to
          max_width = nil, -- fixed width in cells; output window width when nil
          row_separator = "auto", -- 'auto' | 'always' | 'never'
        },
      },
    },
  },
})
```

`row_separator` draws a rule between body rows, which makes multi-line rows much
easier to scan:

- `auto` (default) — only when at least one body row wraps
- `always` — between every body row
- `never` — no rules

## Development

Run tests (Node.js 24+ is required for the TypeScript extension tests):

```bash
./run_tests.sh
```

Run a single test file:

```bash
./run_tests.sh -t tests/unit/model_picker_spec.lua
```

Design notes live in `docs/design/` (for example `docs/design/tabs.md`), and the original migration plan is in `IMPLEMENTATION_PLAN.md`.

## License

Apache 2.0, inherited from opencode.nvim. See `LICENSE`.
