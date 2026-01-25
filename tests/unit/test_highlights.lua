-- Tests for review.ui.highlights module
local T = MiniTest.new_set()

local highlights = require("review.ui.highlights")

-- Helper to check if highlight exists
local function hl_exists(name)
  local hl = vim.api.nvim_get_hl(0, { name = name })
  return next(hl) ~= nil
end

-- Cleanup before each test
T["setup()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      highlights.clear()
    end,
  },
})

T["setup()"]["creates all default highlight groups"] = function()
  highlights.setup()

  for name, _ in pairs(highlights.defaults) do
    MiniTest.expect.equality(hl_exists(name), true, "Missing highlight: " .. name)
  end
end

T["setup()"]["sets is_setup flag"] = function()
  MiniTest.expect.equality(highlights.is_setup(), false)
  highlights.setup()
  MiniTest.expect.equality(highlights.is_setup(), true)
end

T["setup()"]["applies sign highlights with links"] = function()
  highlights.setup()

  local hl = vim.api.nvim_get_hl(0, { name = "ReviewSignGithub" })
  MiniTest.expect.equality(hl.link, "DiagnosticInfo")
end

T["setup()"]["applies virtual text highlights"] = function()
  highlights.setup()

  local hl = vim.api.nvim_get_hl(0, { name = "ReviewVirtualLocal" })
  MiniTest.expect.equality(hl.italic, true)
end

T["setup()"]["applies tree highlights"] = function()
  highlights.setup()

  local hl = vim.api.nvim_get_hl(0, { name = "ReviewTreeDir" })
  MiniTest.expect.equality(hl.link, "Directory")
end

T["setup()"]["applies panel highlights"] = function()
  highlights.setup()

  local hl = vim.api.nvim_get_hl(0, { name = "ReviewPanelHeader" })
  MiniTest.expect.equality(hl.bold, true)
end

T["setup()"]["applies review state highlights"] = function()
  highlights.setup()

  local hl = vim.api.nvim_get_hl(0, { name = "ReviewStateApproved" })
  MiniTest.expect.equality(hl.bold, true)
end

T["setup()"]["accepts user overrides"] = function()
  highlights.setup({
    ReviewSignGithub = { fg = "#ff0000", bold = true },
  })

  local hl = vim.api.nvim_get_hl(0, { name = "ReviewSignGithub" })
  MiniTest.expect.equality(hl.bold, true)
  -- Link should be removed when overriding
  MiniTest.expect.equality(hl.link, nil)
end

T["setup()"]["merges overrides with defaults"] = function()
  highlights.setup({
    ReviewPanelHeader = { fg = "#ff0000" },
  })

  -- Override should be applied
  local hl = vim.api.nvim_get_hl(0, { name = "ReviewPanelHeader" })
  -- New property applied
  MiniTest.expect.equality(type(hl.fg), "number")

  -- Non-overridden should still exist
  local hl2 = vim.api.nvim_get_hl(0, { name = "ReviewSignLocal" })
  MiniTest.expect.equality(hl2.link, "DiagnosticHint")
end

T["defaults"] = MiniTest.new_set()

T["defaults"]["has sign highlights"] = function()
  MiniTest.expect.no_equality(highlights.defaults.ReviewSignGithub, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewSignLocal, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewSignIssue, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewSignSuggestion, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewSignPraise, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewSignResolved, nil)
end

T["defaults"]["has virtual text highlights"] = function()
  MiniTest.expect.no_equality(highlights.defaults.ReviewVirtualGithub, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewVirtualLocal, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewVirtualResolved, nil)
end

T["defaults"]["has tree highlights"] = function()
  MiniTest.expect.no_equality(highlights.defaults.ReviewTreeFile, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewTreeDir, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewTreeSelected, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewTreeModified, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewTreeAdded, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewTreeDeleted, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewTreeRenamed, nil)
end

T["defaults"]["has panel highlights"] = function()
  MiniTest.expect.no_equality(highlights.defaults.ReviewPanelHeader, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewPanelSection, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewPanelComment, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewPanelAuthor, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewPanelTime, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewPanelResolved, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewPanelUnresolved, nil)
end

T["defaults"]["has comment type highlights"] = function()
  MiniTest.expect.no_equality(highlights.defaults.ReviewCommentNote, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewCommentIssue, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewCommentSuggestion, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewCommentPraise, nil)
end

T["defaults"]["has review state highlights"] = function()
  MiniTest.expect.no_equality(highlights.defaults.ReviewStateApproved, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewStateChangesRequested, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewStateCommented, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewStatePending, nil)
end

T["defaults"]["has diff highlights"] = function()
  MiniTest.expect.no_equality(highlights.defaults.ReviewDiffAdd, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewDiffDelete, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewDiffChange, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewDiffContext, nil)
end

T["defaults"]["has float highlights"] = function()
  MiniTest.expect.no_equality(highlights.defaults.ReviewFloatBorder, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewFloatTitle, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewFloatNormal, nil)
end

T["defaults"]["has key hint highlights"] = function()
  MiniTest.expect.no_equality(highlights.defaults.ReviewKeyHint, nil)
  MiniTest.expect.no_equality(highlights.defaults.ReviewKeyHintBracket, nil)
end

T["get()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      highlights.clear()
      highlights.setup()
    end,
  },
})

T["get()"]["returns highlight definition for valid name"] = function()
  local hl = highlights.get("ReviewSignGithub")
  MiniTest.expect.no_equality(hl, nil)
  MiniTest.expect.equality(type(hl), "table")
end

T["get()"]["returns nil for unknown highlight"] = function()
  local hl = highlights.get("NonExistentHighlight")
  MiniTest.expect.equality(hl, nil)
end

T["get_names()"] = MiniTest.new_set()

T["get_names()"]["returns all highlight names"] = function()
  local names = highlights.get_names()
  MiniTest.expect.equality(type(names), "table")
  MiniTest.expect.equality(#names > 0, true)
end

T["get_names()"]["returns sorted names"] = function()
  local names = highlights.get_names()
  local sorted = vim.deepcopy(names)
  table.sort(sorted)
  MiniTest.expect.equality(vim.deep_equal(names, sorted), true)
end

T["get_names()"]["includes all default highlights"] = function()
  local names = highlights.get_names()
  local name_set = {}
  for _, name in ipairs(names) do
    name_set[name] = true
  end

  for name, _ in pairs(highlights.defaults) do
    MiniTest.expect.equality(name_set[name], true, "Missing name: " .. name)
  end
end

T["clear()"] = MiniTest.new_set()

T["clear()"]["clears all highlights"] = function()
  highlights.setup()
  MiniTest.expect.equality(highlights.is_setup(), true)

  highlights.clear()
  MiniTest.expect.equality(highlights.is_setup(), false)
end

T["clear()"]["removes highlight definitions"] = function()
  highlights.setup()

  -- Verify highlight exists
  local before = vim.api.nvim_get_hl(0, { name = "ReviewSignGithub" })
  MiniTest.expect.equality(next(before) ~= nil, true)

  highlights.clear()

  -- Highlight should be empty after clear
  local after = vim.api.nvim_get_hl(0, { name = "ReviewSignGithub" })
  MiniTest.expect.equality(next(after) == nil, true)
end

T["reset()"] = MiniTest.new_set()

T["reset()"]["restores defaults after overrides"] = function()
  highlights.setup({
    ReviewSignGithub = { fg = "#ff0000" },
  })

  -- Verify override was applied
  local overridden = vim.api.nvim_get_hl(0, { name = "ReviewSignGithub" })
  MiniTest.expect.equality(overridden.link, nil)

  highlights.reset()

  -- Verify default is restored
  local reset = vim.api.nvim_get_hl(0, { name = "ReviewSignGithub" })
  MiniTest.expect.equality(reset.link, "DiagnosticInfo")
end

T["is_setup()"] = MiniTest.new_set()

T["is_setup()"]["returns false initially"] = function()
  highlights.clear()
  MiniTest.expect.equality(highlights.is_setup(), false)
end

T["is_setup()"]["returns true after setup"] = function()
  highlights.clear()
  highlights.setup()
  MiniTest.expect.equality(highlights.is_setup(), true)
end

T["is_setup()"]["returns false after clear"] = function()
  highlights.setup()
  highlights.clear()
  MiniTest.expect.equality(highlights.is_setup(), false)
end

return T
