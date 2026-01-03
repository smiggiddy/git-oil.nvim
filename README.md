# git-oil.nvim

Git status integration for [oil.nvim](https://github.com/stevearc/oil.nvim). Shows git status indicators in your oil file browser with colored filenames and status symbols.

Based on [oil-git.nvim](https://github.com/benomahony/oil-git.nvim) by Ben O'Mahony, with performance improvements including caching and debouncing.

![screenshot](screenshot.png)

## Features

- Colored filenames based on git status
- Status symbols displayed as virtual text
- **Staged vs unstaged distinction** - different colors/symbols for staged, unstaged, and partially staged files
- **Directory status** - directories show status of their most important child file
- **Merge conflict indicators** - clearly see files with conflicts
- **Async git status** - non-blocking on Neovim 0.10+ (falls back to sync on older versions)
- Cached git status (avoids repeated `git status` calls)
- Debounced updates for rapid events
- Auto-refresh when returning from terminal (lazygit, etc.)
- Respects your colorscheme (only sets highlights if not already defined)
- **Enable/disable toggle** - turn the plugin on/off at runtime
- **Buffer-local keymaps** - `gr` to refresh, `gd` to toggle (customizable)

## Status Indicators

| Symbol | Highlight | Meaning |
|--------|-----------|---------|
| `+` | Green | Added (staged) |
| `●` | Green | Staged modification |
| `○` | Yellow | Unstaged modification |
| `±` | Orange | Partially staged (both staged and unstaged changes) |
| `→` | Purple | Renamed |
| `✗` | Red | Deleted (unstaged) |
| `●` | Green | Deleted (staged) |
| `?` | Blue | Untracked |
| `!` | Red (bold) | Merge conflict |

## Installation

### lazy.nvim

```lua
{
  "smiggiddy/git-oil.nvim",
  dependencies = { "stevearc/oil.nvim" },
  opts = {},
}
```

### packer.nvim

```lua
use {
  "smiggiddy/git-oil.nvim",
  requires = { "stevearc/oil.nvim" },
  config = function()
    require("git-oil").setup()
  end,
}
```

## Configuration

```lua
require("git-oil").setup({
  -- Enable/disable the plugin (default: true)
  enabled = true,

  -- Show git status on directories (default: true)
  -- Directories will show the status of their "most important" child
  show_directory_status = true,

  -- Cache timeout in milliseconds (default: 2000)
  cache_timeout = 2000,

  -- Debounce delay in milliseconds (default: 200)
  debounce_delay = 200,

  -- Keymaps (only active in oil buffers)
  -- Set to false to disable a keymap
  keymaps = {
    refresh = "gr", -- Refresh git status
    toggle = "gd",  -- Toggle plugin on/off
  },

  -- Customize status symbols
  symbols = {
    added = "+",
    modified = "~",
    renamed = "→",
    deleted = "✗",
    untracked = "?",
    conflict = "!",
    staged = "●",
    unstaged = "○",
    partially_staged = "±",
  },

  -- Override default highlight colors
  highlights = {
    OilGitAdded = { fg = "#a6e3a1" },
    OilGitModified = { fg = "#f9e2af" },
    OilGitRenamed = { fg = "#cba6f7" },
    OilGitDeleted = { fg = "#f38ba8" },
    OilGitUntracked = { fg = "#89b4fa" },
    OilGitConflict = { fg = "#f38ba8", bold = true },
    OilGitStagedModified = { fg = "#a6e3a1" },
    OilGitUnstagedModified = { fg = "#f9e2af" },
    OilGitPartiallyStaged = { fg = "#fab387" },
    OilGitStagedDeleted = { fg = "#a6e3a1" },
    OilGitUnstagedDeleted = { fg = "#f38ba8" },
  },
})
```

## Usage

The plugin works automatically once installed. Open any directory with oil.nvim and git-tracked files will show their status.

### Keymaps

These keymaps are available in oil buffers by default:

| Key | Action |
|-----|--------|
| `gr` | Refresh git status |
| `gd` | Toggle plugin on/off |

To customize or disable keymaps:

```lua
require("git-oil").setup({
  keymaps = {
    refresh = "<leader>gr", -- Custom key
    toggle = false,         -- Disable this keymap
  },
})
```

### API

```lua
-- Manual refresh (also invalidates cache)
require("git-oil").refresh()

-- Enable/disable the plugin at runtime
require("git-oil").enable()
require("git-oil").disable()
require("git-oil").toggle()

-- Check if plugin is enabled
if require("git-oil").enabled then
  -- ...
end
```

## Directory Status

When `show_directory_status` is enabled (default), directories will show the status of their most important child file. The priority order is:

1. Conflict (highest)
2. Partially staged
3. Modified
4. Added
5. Renamed/Deleted
6. Untracked (lowest)

For example, if a directory contains both an untracked file and a modified file, the directory will show the modified indicator.

## Async Support

On Neovim 0.10+, git status is fetched asynchronously using `vim.system()`, which prevents UI freezes in large repositories. On older Neovim versions, it falls back to synchronous `vim.fn.system()`.

## Improvements over oil-git.nvim

- **Caching**: Git status is cached per repository with configurable TTL
- **Debouncing**: Rapid events (typing, focus changes) are debounced to prevent UI thrashing
- **Performance**: Removed `--ignored` flag from git status (major perf improvement in large repos)
- **Cache invalidation**: Automatically invalidates cache on terminal close and git-related events
- **Async**: Non-blocking git status on Neovim 0.10+
- **Staged/unstaged distinction**: See at a glance what's staged vs unstaged
- **Directory status**: Navigate faster by seeing which directories have changes
- **Conflict indicators**: Easily spot merge conflicts

## License

MIT - see [LICENSE](LICENSE)
