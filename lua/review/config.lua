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
---@field comment_ai_processing string Sign for comments being processed by AI

---@class Review.KeymapsConfig
---@field enabled boolean Whether to set up default keymaps

---@class Review.GithubConfig
---@field enabled boolean Whether GitHub integration is enabled

---@class Review.AIConfig
---@field provider "auto" | "opencode" | "claude" | "codex" | "custom" AI provider
---@field command? string Custom command with $PROMPT placeholder
---@field auto_reload boolean Auto-reload buffers when files change
---@field on_complete? fun() Callback when AI finishes

---@class Review.VirtualTextConfig
---@field enabled boolean Whether virtual text is enabled
---@field max_length number Maximum length of preview text
---@field position "eol" | "overlay" | "right_align" Position of virtual text

---@class Review.PickerConfig
---@field backend "auto" | "native" | "telescope" | "fzf-lua" Picker backend
---@field detailed boolean Whether to show detailed PR info in picker

---@class Review.StorageConfig
---@field enabled boolean Whether to persist comments to disk
---@field auto_load boolean Whether to auto-load stored comments on review open
---@field auto_save boolean Whether to auto-save comments on change

---@class Review.Config
---@field ui Review.UIConfig UI settings
---@field signs Review.SignsConfig Sign characters
---@field keymaps Review.KeymapsConfig Keymap settings
---@field github Review.GithubConfig GitHub settings
---@field ai Review.AIConfig AI integration settings
---@field virtual_text Review.VirtualTextConfig Virtual text settings
---@field picker Review.PickerConfig Picker settings
---@field storage Review.StorageConfig Storage settings

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
    comment_ai_processing = "●",
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
    -- Provider: "auto" (detect), "opencode", "claude", "codex", "custom"
    provider = "auto",

    -- Custom command with $PROMPT placeholder (for "custom" provider)
    -- Example: "my-ai-tool --prompt $PROMPT"
    command = nil,

    -- Auto-reload buffers when files change
    auto_reload = true,

    -- Callback when AI finishes (optional)
    on_complete = nil,
  },

  -- Virtual text settings
  virtual_text = {
    enabled = true,
    max_length = 40,
    position = "eol",
  },

  -- Picker settings
  picker = {
    -- Picker backend: "auto" (detect), "native" (vim.ui.select), "telescope", "fzf-lua"
    backend = "auto",
    -- Show detailed PR info in picker
    detailed = true,
  },

  -- Storage settings
  storage = {
    -- Persist comments to disk
    enabled = true,
    -- Auto-load stored comments when opening a review
    auto_load = true,
    -- Auto-save comments when they change
    auto_save = true,
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
