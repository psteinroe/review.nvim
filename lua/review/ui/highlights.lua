local M = {}

---@class Review.HighlightDef
---@field fg? string Foreground color
---@field bg? string Background color
---@field sp? string Special color (for underlines)
---@field bold? boolean Bold text
---@field italic? boolean Italic text
---@field underline? boolean Underline
---@field undercurl? boolean Undercurl
---@field underdouble? boolean Double underline
---@field underdotted? boolean Dotted underline
---@field underdashed? boolean Dashed underline
---@field strikethrough? boolean Strikethrough
---@field reverse? boolean Reverse colors
---@field standout? boolean Standout
---@field nocombine? boolean Don't combine with other highlights
---@field link? string Link to another highlight group
---@field default? boolean Only set if not already defined

---@type table<string, Review.HighlightDef>
M.defaults = {
  -- Signs (gutter icons)
  ReviewSignGithub = { link = "DiagnosticInfo" },
  ReviewSignLocal = { link = "DiagnosticHint" },
  ReviewSignIssue = { link = "DiagnosticWarn" },
  ReviewSignSuggestion = { link = "DiagnosticOk" },
  ReviewSignPraise = { link = "DiagnosticOk" },
  ReviewSignResolved = { link = "Comment" },

  -- Virtual text (inline comment previews)
  ReviewVirtualGithub = { link = "Comment" },
  ReviewVirtualLocal = { fg = "#89b4fa", italic = true },
  ReviewVirtualResolved = { fg = "#6c7086", strikethrough = true },

  -- File tree
  ReviewTreeFile = { link = "Normal" },
  ReviewTreeDir = { link = "Directory" },
  ReviewTreeSelected = { link = "CursorLine" },
  ReviewTreeModified = { fg = "#f9e2af" },
  ReviewTreeAdded = { fg = "#a6e3a1" },
  ReviewTreeDeleted = { fg = "#f38ba8" },
  ReviewTreeRenamed = { fg = "#89b4fa" },

  -- Panel
  ReviewPanelHeader = { bold = true },
  ReviewPanelSection = { fg = "#89b4fa", bold = true },
  ReviewPanelComment = { link = "Normal" },
  ReviewPanelAuthor = { fg = "#cba6f7" },
  ReviewPanelTime = { link = "Comment" },
  ReviewPanelResolved = { fg = "#a6e3a1" },
  ReviewPanelUnresolved = { fg = "#f9e2af" },

  -- Comment types in panel/floats
  ReviewCommentNote = { link = "Comment" },
  ReviewCommentIssue = { fg = "#f9e2af" },
  ReviewCommentSuggestion = { fg = "#a6e3a1" },
  ReviewCommentPraise = { fg = "#a6e3a1", italic = true },

  -- Review states
  ReviewStateApproved = { fg = "#a6e3a1", bold = true },
  ReviewStateChangesRequested = { fg = "#f38ba8", bold = true },
  ReviewStateCommented = { fg = "#89b4fa", bold = true },
  ReviewStatePending = { fg = "#f9e2af", italic = true },

  -- Diff highlights (for custom rendering, complements built-in diff)
  ReviewDiffAdd = { link = "DiffAdd" },
  ReviewDiffDelete = { link = "DiffDelete" },
  ReviewDiffChange = { link = "DiffChange" },
  ReviewDiffContext = { link = "Normal" },

  -- Float/popup
  ReviewFloatBorder = { link = "FloatBorder" },
  ReviewFloatTitle = { bold = true },
  ReviewFloatNormal = { link = "NormalFloat" },

  -- Keyhint in floats
  ReviewKeyHint = { fg = "#89b4fa" },
  ReviewKeyHintBracket = { link = "Comment" },
}

---@type boolean
local is_setup = false

---Setup highlight groups
---@param overrides? table<string, Review.HighlightDef> User overrides for highlight groups
function M.setup(overrides)
  overrides = overrides or {}

  -- Apply all highlight groups
  for name, default_def in pairs(M.defaults) do
    local def
    if overrides[name] then
      -- User override replaces default entirely (don't merge, as link + fg/bg is confusing)
      def = overrides[name]
    else
      -- Check if highlight already exists (user-defined in colorscheme)
      -- If so, don't override it
      local existing = vim.api.nvim_get_hl(0, { name = name })
      if next(existing) ~= nil then
        def = nil -- Skip this highlight
      else
        def = vim.tbl_extend("force", {}, default_def)
      end
    end
    if def then
      vim.api.nvim_set_hl(0, name, def)
    end
  end

  is_setup = true
end

---Check if highlights have been set up
---@return boolean
function M.is_setup()
  return is_setup
end

---Get a highlight definition
---@param name string Highlight group name
---@return Review.HighlightDef?
function M.get(name)
  if M.defaults[name] then
    return vim.api.nvim_get_hl(0, { name = name })
  end
  return nil
end

---Get all highlight group names
---@return string[]
function M.get_names()
  local names = {}
  for name, _ in pairs(M.defaults) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

---Reset highlights to defaults
function M.reset()
  M.clear()
  M.setup({})
end

---Clear all review highlights (useful for cleanup)
function M.clear()
  for name, _ in pairs(M.defaults) do
    -- Use highlight clear command instead of nvim_set_hl(0, name, {})
    -- The latter creates an "empty" highlight that still exists,
    -- which prevents default = true from working on subsequent setup()
    vim.cmd("highlight clear " .. name)
  end
  is_setup = false
end

return M
