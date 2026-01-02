# git-oil.nvim

Git status integration for [oil.nvim](https://github.com/stevearc/oil.nvim). Shows git status indicators in your oil file browser with colored filenames and status symbols.

Based on [oil-git.nvim](https://github.com/benomahony/oil-git.nvim) by Ben O'Mahony, with performance improvements including caching and debouncing.

## Features

- Colored filenames based on git status
- Status symbols displayed as virtual text
- Cached git status (avoids repeated `git status` calls)
- Debounced updates for rapid events
- Auto-refresh when returning from terminal (lazygit, etc.)
- Respects your colorscheme (only sets highlights if not already defined)

## Status Indicators

| Symbol | Color | Meaning |
|--------|-------|---------|
| `+` | Green | Added (staged) |
| `~` | Yellow | Modified |
| `→` | Purple | Renamed |
| `✗` | Red | Deleted |
| `?` | Blue | Untracked |

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
  -- Cache timeout in milliseconds (default: 2000)
  cache_timeout = 2000,

  -- Debounce delay in milliseconds (default: 200)
  debounce_delay = 200,

  -- Customize status symbols
  symbols = {
    added = "+",
    modified = "~",
    renamed = "→",
    deleted = "✗",
    untracked = "?",
  },

  -- Override default highlight colors
  highlights = {
    OilGitAdded = { fg = "#a6e3a1" },
    OilGitModified = { fg = "#f9e2af" },
    OilGitRenamed = { fg = "#cba6f7" },
    OilGitDeleted = { fg = "#f38ba8" },
    OilGitUntracked = { fg = "#89b4fa" },
  },
})
```

## Usage

The plugin works automatically once installed. Open any directory with oil.nvim and git-tracked files will show their status.

### Manual Refresh

If you need to manually refresh the git status:

```lua
require("git-oil").refresh()
```

## Improvements over oil-git.nvim

- **Caching**: Git status is cached per repository with configurable TTL
- **Debouncing**: Rapid events (typing, focus changes) are debounced to prevent UI thrashing
- **Performance**: Removed `--ignored` flag from git status (major perf improvement in large repos)
- **Cache invalidation**: Automatically invalidates cache on terminal close and git-related events

## License

MIT - see [LICENSE](LICENSE)
