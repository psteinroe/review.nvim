local M = {}

---@class Review.UIConfig
---@field tree_width number Width of file tree panel
---@field panel_width number Width of PR panel
---@field panel_height number Height of PR panel

---@class Review.SignsConfig
---@field comment_github string Sign for GitHub comments
---@field comment_local string Sign for local comments
---@field comment_issue string Sign for issue comments
---@field comment_suggestion string Sign for suggestion comments
---@field comment_praise string Sign for praise comments
---@field comment_resolved string Sign for resolved comments

---@class Review.KeymapsConfig
---@field enabled boolean Whether to set up default keymaps

---@class Review.GithubConfig
---@field enabled boolean Whether GitHub integration is enabled

---@class Review.AITerminalConfig
---@field height number Terminal split height
---@field position "bottom" | "right" Terminal position

---@class Review.AIConfig
---@field provider "auto" | "opencode" | "claude" | "codex" | "aider" | "avante" | "clipboard" | "custom"
---@field preference string[] Provider preference order for auto-detection
---@field instructions? string Custom instructions (replaces default)
---@field custom_handler? fun(prompt: string, opts: table) Custom handler for "custom" provider
---@field terminal Review.AITerminalConfig Terminal settings

---@class Review.VirtualTextConfig
---@field enabled boolean Whether virtual text is enabled
---@field max_length number Maximum length of preview text
---@field position "eol" | "overlay" | "right_align" Position of virtual text

---@class Review.Config
---@field ui Review.UIConfig UI settings
---@field signs Review.SignsConfig Sign characters
---@field keymaps Review.KeymapsConfig Keymap settings
---@field github Review.GithubConfig GitHub settings
---@field ai Review.AIConfig AI integration settings
---@field virtual_text Review.VirtualTextConfig Virtual text settings

---@type Review.Config
M.defaults = {
  -- UI settings
  ui = {
    tree_width = 30,
    panel_width = 80,
    panel_height = 40,
  },

  -- Signs
  signs = {
    comment_github = "G",
    comment_local = "L",
    comment_issue = "!",
    comment_suggestion = "*",
    comment_praise = "+",
    comment_resolved = "R",
  },

  -- Keymaps (can be overridden)
  keymaps = {
    enabled = true,
  },

  -- GitHub settings
  github = {
    enabled = true,
  },

  -- AI settings
  ai = {
    -- Provider selection: "auto", "opencode", "claude", "codex", "aider", "avante", "clipboard", "custom"
    provider = "auto",

    -- Provider preference order for auto-detection
    preference = {
      "opencode",
      "avante",
      "claude",
      "codex",
      "aider",
      "clipboard",
    },

    -- Custom instructions (replaces default)
    instructions = nil,

    -- Custom handler function for "custom" provider
    custom_handler = nil,

    -- Terminal settings
    terminal = {
      height = 15,
      position = "bottom",
    },
  },

  -- Virtual text settings
  virtual_text = {
    enabled = true,
    max_length = 40,
    position = "eol",
  },
}

---@type Review.Config
M.config = {}

---Setup config
---@param opts? Review.Config
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

---Get config value by dot-separated path
---@param key string Dot-separated key (e.g., "ui.tree_width")
---@return any
function M.get(key)
  local keys = vim.split(key, ".", { plain = true })
  local value = M.config
  for _, k in ipairs(keys) do
    if type(value) ~= "table" then
      return nil
    end
    value = value[k]
    if value == nil then
      return nil
    end
  end
  return value
end

---Check if config has been initialized
---@return boolean
function M.is_setup()
  return next(M.config) ~= nil
end

return M
