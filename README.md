# pi.nvim

A Neovim/LazyVim sidebar frontend for the [Pi coding agent](https://pi.dev).

This is a fork/migration of `sudo-tee/opencode.nvim`: the sidebar UI, input/output panes, markdown rendering, context workflows, and keymap shape are being preserved while the backend is replaced with Pi RPC (`pi --mode rpc`).

## Status

Work in progress. Core Pi chat works, model switching is wired, Pi sessions are partially supported, and the Lua namespace is now `pi` so this can be installed separately from `opencode.nvim`.

## Installation

```lua
return {
  dir = "/Users/gilad.hecht/workspace/personal/pi.nvim",
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

Install or symlink `bin/pi-in-neovim` somewhere on your `$PATH` if you want to run it as `pi-in-neovim`.
This runs `nvim +"Pi pin"`, opens Pi in the current window, and closes other windows in the current tab (for example file explorer/main panes).

Default keymap prefix is `<leader>p`, mirroring the original opencode.nvim layout with a Pi prefix:

- `<leader>pg` toggle Pi sidebar
- `<leader>pi` open input
- `<leader>pI` open input in a new session
- `<leader>po` open output
- `<leader>pt` toggle focus
- `<leader>ps` select session
- `<leader>pR` rename session
- `<leader>pp` select provider/model
- `<leader>pV` select thinking level
- `<leader>p/` quick chat

### Tabs

The sidebar can hold several Pi sessions at once. Each tab runs its own `pi --mode rpc` process, so a background tab keeps working while you use another one, like opening `pi` in a second shell tab.

- `:Pi tab new` / `<leader>pn` opens an empty tab with a fresh session
- `:Pi tab fork` / `<leader>pf` opens a new tab with a fork of the current session at its current position; the original tab keeps running
- `:Pi tab next` / `:Pi tab prev`, `]t` / `[t` in the Pi windows, or `<leader>p>` / `<leader>p<`
- `:Pi tab goto <n>` jumps to a tab by number
- `:Pi tab close` / `<leader>pw` closes the active tab, aborting it first if it is running

Open tabs are remembered per working directory and reopened the first time you open the sidebar after a restart (`ui.tabs.persist = false` turns this off). Restored background tabs only start their Pi process when you first switch to them.

Fork actions (`[F]ork` on a message, the timeline and session pickers' `<C-f>`, `:Pi fork`, `/fork`) ask whether to fork into a new tab or replace the current session. Set `ui.tabs.fork_target` to `'tab'` or `'current'` to skip the question.

With more than one tab, the output window's top bar shows a clickable tab strip; `●` marks a running tab, `?` a tab waiting for your input (for example an extension confirmation), and `✓` a tab that finished while you were elsewhere. You get a notification when a background tab finishes or needs input (`ui.tabs.notify = false` turns these off); its pending question is shown when you switch to it. Selecting a session that is already open in another tab switches to that tab instead of opening it twice.

In the Pi output window:

- `gf` opens an exact file reference under the cursor
- `g<Space>` opens the file picker filtered by the reference under the cursor, then jumps to its line and column
- `gr` browses all file references from the conversation
- `<CR>` opens any rendered navigation target under the cursor

The output filetype is `pi_output`.

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

Useful slash commands in the input window:

- `/sessions` select between sessions (`/resume` remains an alias)
- `/rename <name>` rename the current session
- `/rename` or `/autoname` ask Pi to suggest and apply a concise session name

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

The plugin uses the `lua/pi` namespace and does not provide an `opencode` Lua module, so it can be installed alongside `opencode.nvim`.

## License

MIT. See `LICENSE`.
