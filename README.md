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

The output filetype is `pi_output`.

Useful slash commands in the input window:

- `/sessions` select between sessions (`/resume` remains an alias)
- `/rename <name>` rename the current session
- `/rename` or `/autoname` ask Pi to suggest and apply a concise session name
- `/session` show current session info

## Pi backend

The plugin spawns:

```bash
pi --mode rpc
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

## Markdown table rendering

Wide markdown tables are reflowed so each cell wraps inside its own column
instead of producing one very long line that soft-wraps into an unreadable
blob. Column widths are fitted to the output window using display width (so
emoji and CJK text keep the borders aligned); the widest columns give up space
first, and header rows are truncated with `…` so the table stays valid GFM.

Long unbreakable tokens are split at `_ - . / , : )` boundaries where possible,
and inline code spans are re-fenced on each line so backticks stay balanced.

```lua
require("pi").setup({
  ui = {
    output = {
      rendering = {
        tables = {
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

Run tests:

```bash
./run_tests.sh
```

The plugin uses the `lua/pi` namespace and does not provide an `opencode` Lua module, so it can be installed alongside `opencode.nvim`.

## License

MIT. See `LICENSE`.
