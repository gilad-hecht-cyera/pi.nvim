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
- `<leader>pp` select provider/model
- `<leader>pV` select thinking level
- `<leader>p/` quick chat

The output filetype is `pi_output`.

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

## Development

Run tests:

```bash
./run_tests.sh
```

The plugin uses the `lua/pi` namespace and does not provide an `opencode` Lua module, so it can be installed alongside `opencode.nvim`.

## License

MIT. See `LICENSE`.
