# review.nvim

A Neovim plugin for efficient code reviews with GitHub integration and AI feedback loops.

## Features

- **Local diff review** - Review AI-generated or manual code changes
- **GitHub PR review** - Full comment integration with GitHub PRs
- **AI feedback loop** - Send reviews to AI providers for iteration
- **Editable diffs** - Fix issues directly while reviewing
- **Unified comments** - Local and GitHub comments in one view
- **Keyboard-driven** - Everything accessible via keymaps

## Requirements

- Neovim 0.10+
- `gh` CLI (optional, for GitHub integration)

## Installation

### lazy.nvim

```lua
{
  "psteinroe/review.nvim",
  config = function()
    require("review").setup()
  end,
}
```

### packer.nvim

```lua
use {
  "psteinroe/review.nvim",
  config = function()
    require("review").setup()
  end,
}
```

## Configuration

```lua
require("review").setup({
  -- UI settings
  ui = {
    tree_width = 30,      -- Width of file tree panel
    panel_width = 80,     -- Width of PR panel
    panel_height = 40,    -- Height of PR panel
  },

  -- Signs shown in gutter
  signs = {
    comment_github = "G",
    comment_local = "L",
    comment_issue = "!",
    comment_suggestion = "*",
    comment_praise = "+",
    comment_resolved = "R",
  },

  -- Keymaps (set enabled = false to define your own)
  keymaps = {
    enabled = true,
  },

  -- GitHub settings
  github = {
    enabled = true,
  },

  -- AI provider settings
  ai = {
    provider = "auto",    -- "auto", "opencode", "claude", "codex", "aider", "avante", "clipboard", "custom"
    preference = {        -- Auto-detection preference order
      "opencode",
      "avante",
      "claude",
      "codex",
      "aider",
      "clipboard",
    },
    instructions = nil,   -- Custom instructions (replaces default)
    custom_handler = nil, -- Custom handler for "custom" provider
    terminal = {
      height = 15,
      position = "bottom",
    },
  },

  -- Virtual text (inline comment preview)
  virtual_text = {
    enabled = true,
    max_length = 40,
    position = "eol",
  },
})
```

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `:Review` | Open local diff against HEAD |
| `:Review {base}` | Open local diff against branch/commit |
| `:Review pr` | Open PR picker |
| `:Review pr {number}` | Open specific PR |
| `:Review close` | Close review session |
| `:Review panel` | Toggle PR panel |
| `:Review refresh` | Refresh current review |
| `:Review status` | Show review status |
| `:ReviewAI` | Send to configured AI provider |
| `:ReviewAI {provider}` | Send to specific provider |
| `:ReviewAI pick` | Show provider picker |
| `:ReviewAI clipboard` | Copy to clipboard |
| `:ReviewComment` | Add note comment at cursor |
| `:ReviewComment {type}` | Add comment (note/issue/suggestion/praise) |

### Keymaps

All keymaps are active when a review session is open.

#### File Navigation

| Keymap | Action |
|--------|--------|
| `<C-j>` | Next file in tree |
| `<C-k>` | Previous file in tree |

#### Comment Navigation

| Keymap | Action |
|--------|--------|
| `]c` | Next comment |
| `[c` | Previous comment |
| `]u` | Next unresolved comment |
| `[u` | Previous unresolved comment |
| `]m` | Next pending comment |
| `[m` | Previous pending comment |

#### Hunk Navigation

| Keymap | Action |
|--------|--------|
| `<Tab>` | Next hunk (across files) |
| `<S-Tab>` | Previous hunk (across files) |

#### Views

| Keymap | Action |
|--------|--------|
| `<leader>rp` | Toggle PR panel |
| `<leader>rf` | Focus file tree |
| `<leader>rd` | Focus diff view |

#### Comment Actions

| Keymap | Action |
|--------|--------|
| `<leader>cc` | Add note comment |
| `<leader>ci` | Add issue comment |
| `<leader>cs` | Add suggestion comment |
| `<leader>cp` | Add praise comment |
| `<leader>ce` | Edit comment at cursor |
| `<leader>cd` | Delete comment at cursor |
| `K` | Show comment popup |
| `r` | Reply to comment |
| `R` | Toggle resolve status |

#### PR Actions

| Keymap | Action |
|--------|--------|
| `<leader>rC` | Add conversation comment |
| `<leader>rs` | Send to AI |
| `<leader>rS` | Pick AI provider |
| `<leader>ry` | Copy to clipboard |
| `<leader>rg` | Submit to GitHub |
| `<leader>ra` | Approve PR |
| `<leader>rx` | Request changes |

#### Pickers

| Keymap | Action |
|--------|--------|
| `<leader>rr` | Pick from review requests |
| `<leader>rl` | Pick from open PRs |

### File Tree Symbols

Each file in the tree is displayed as: `{reviewed} {status} {path} {comments}`

**Reviewed status (first column):**
| Symbol | Meaning |
|--------|---------|
| `✓` | File reviewed (staged in local mode, viewed in PR mode) |
| `·` | File pending review |

**Git status (second column):**
| Symbol | Meaning |
|--------|---------|
| `A` | Added (new file) |
| `M` | Modified |
| `D` | Deleted |
| `R` | Renamed |

**Comment count (right-aligned):**
| Format | Meaning |
|--------|---------|
| `3` | 3 comments on this file |
| `3*` | 3 comments, includes pending (unsent) comments |

### File Tree Keymaps

When focused on the file tree:

| Keymap | Action |
|--------|--------|
| `<CR>` / `o` / `l` | Open file |
| `j` / `<Down>` | Next file |
| `k` / `<Up>` | Previous file |
| `<Space>` / `x` / `s` | Toggle reviewed (stages file in local mode) |
| `<Tab>` | Next hunk (across files) |
| `<S-Tab>` | Previous hunk (across files) |
| `R` | Refresh files from git |
| `q` | Close review |
| Mouse click | Open file |

### Comment Input Keymaps

When typing a comment in the floating input window:

| Keymap | Action |
|--------|--------|
| `<C-s>` | Save comment (insert or normal mode) |
| `<CR>` | Save comment (normal mode only) |
| `<C-c>` | Cancel comment |

### Diff View Keymaps

When focused on the diff view:

| Keymap | Action |
|--------|--------|
| `<Tab>` | Next hunk (across files) |
| `<S-Tab>` | Previous hunk (across files) |
| `q` | Close review |

## Workflow Examples

### Local AI-Generated Diff Review

1. AI generates code changes
2. Run `:Review` to see diff
3. Add comments with `<leader>cc`
4. Send to AI with `<leader>rs`
5. AI fixes issues
6. Repeat until satisfied

### GitHub PR Review

1. Run `:Review pr` or `:Review pr 123`
2. Plugin fetches PR details, diff, and comments
3. See existing comments inline in diff
4. Add new comments (pending locally)
5. Reply to existing threads with `r`
6. Submit review with `<leader>rg`

## API

```lua
local review = require("review")

-- Open reviews
review.open()           -- Local diff against HEAD
review.open("main")     -- Local diff against main
review.open_pr(123)     -- Open PR #123
review.pick_pr()        -- Open PR picker

-- Session control
review.close()          -- Close review
review.toggle_panel()   -- Toggle PR panel
review.refresh()        -- Refresh current review
review.status()         -- Show review status

-- Comments
review.add_comment("note")        -- Add note
review.add_comment("issue")       -- Add issue
review.add_comment("suggestion")  -- Add suggestion
review.add_comment("praise")      -- Add praise

-- AI integration
review.send_to_ai()           -- Send to configured provider
review.send_to_ai("claude")   -- Send to specific provider
review.send_to_clipboard()    -- Copy to clipboard

-- State inspection
review.is_active()    -- Check if session active
review.get_state()    -- Get current state
review.get_config()   -- Get configuration
review.is_setup()     -- Check if plugin is set up
```

## License

MIT
