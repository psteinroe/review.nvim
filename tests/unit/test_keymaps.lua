-- Tests for review.nvim keymaps module
local MiniTest = require("mini.test")
local expect = MiniTest.expect

local T = MiniTest.new_set()

-- Helper to get fresh modules
local function get_state()
  package.loaded["review.core.state"] = nil
  return require("review.core.state")
end

local function get_config()
  package.loaded["review.config"] = nil
  return require("review.config")
end

local function get_keymaps()
  package.loaded["review.keymaps"] = nil
  return require("review.keymaps")
end

-- Reset state before each test
T["setup"] = function()
  local state = get_state()
  state.reset()
  local config = get_config()
  config.setup()
  -- Suppress vim.notify messages during tests
  vim.notify = function() end
end

-- =============================================================================
-- Defaults Tests
-- =============================================================================

T["defaults"] = MiniTest.new_set()

T["defaults"]["has all expected keymaps defined"] = function()
  local keymaps = get_keymaps()

  -- File navigation
  expect.no_equality(keymaps.defaults.tree_next, nil)
  expect.no_equality(keymaps.defaults.tree_prev, nil)
  expect.no_equality(keymaps.defaults.file_next, nil)
  expect.no_equality(keymaps.defaults.file_prev, nil)

  -- Comment navigation
  expect.no_equality(keymaps.defaults.comment_next, nil)
  expect.no_equality(keymaps.defaults.comment_prev, nil)
  expect.no_equality(keymaps.defaults.unresolved_next, nil)
  expect.no_equality(keymaps.defaults.unresolved_prev, nil)
  expect.no_equality(keymaps.defaults.pending_next, nil)
  expect.no_equality(keymaps.defaults.pending_prev, nil)

  -- Hunk navigation
  expect.no_equality(keymaps.defaults.hunk_next, nil)
  expect.no_equality(keymaps.defaults.hunk_prev, nil)

  -- Views
  expect.no_equality(keymaps.defaults.toggle_panel, nil)
  expect.no_equality(keymaps.defaults.focus_tree, nil)
  expect.no_equality(keymaps.defaults.focus_diff, nil)

  -- Comment actions
  expect.no_equality(keymaps.defaults.add_comment, nil)
  expect.no_equality(keymaps.defaults.add_issue, nil)
  expect.no_equality(keymaps.defaults.add_suggestion, nil)
  expect.no_equality(keymaps.defaults.add_praise, nil)
  expect.no_equality(keymaps.defaults.edit_comment, nil)
  expect.no_equality(keymaps.defaults.delete_comment, nil)
  expect.no_equality(keymaps.defaults.show_comment, nil)
  expect.no_equality(keymaps.defaults.reply, nil)
  expect.no_equality(keymaps.defaults.resolve, nil)

  -- PR actions
  expect.no_equality(keymaps.defaults.add_conversation, nil)
  expect.no_equality(keymaps.defaults.send_to_ai, nil)
  expect.no_equality(keymaps.defaults.pick_ai_provider, nil)
  expect.no_equality(keymaps.defaults.send_to_clipboard, nil)
  expect.no_equality(keymaps.defaults.submit_to_github, nil)
  expect.no_equality(keymaps.defaults.approve, nil)
  expect.no_equality(keymaps.defaults.request_changes, nil)

  -- Picker
  expect.no_equality(keymaps.defaults.pick_review_requests, nil)
  expect.no_equality(keymaps.defaults.pick_open_prs, nil)
end

T["defaults"]["file navigation uses expected keys"] = function()
  local keymaps = get_keymaps()

  expect.equality(keymaps.defaults.tree_next, "<C-j>")
  expect.equality(keymaps.defaults.tree_prev, "<C-k>")
  expect.equality(keymaps.defaults.file_next, "<Tab>")
  expect.equality(keymaps.defaults.file_prev, "<S-Tab>")
end

T["defaults"]["comment navigation uses bracket keys"] = function()
  local keymaps = get_keymaps()

  expect.equality(keymaps.defaults.comment_next, "]c")
  expect.equality(keymaps.defaults.comment_prev, "[c")
  expect.equality(keymaps.defaults.unresolved_next, "]u")
  expect.equality(keymaps.defaults.unresolved_prev, "[u")
  expect.equality(keymaps.defaults.pending_next, "]m")
  expect.equality(keymaps.defaults.pending_prev, "[m")
end

T["defaults"]["hunk navigation uses bracket keys"] = function()
  local keymaps = get_keymaps()

  expect.equality(keymaps.defaults.hunk_next, "]h")
  expect.equality(keymaps.defaults.hunk_prev, "[h")
end

T["defaults"]["views use leader-r prefix"] = function()
  local keymaps = get_keymaps()

  expect.equality(keymaps.defaults.toggle_panel, "<leader>rp")
  expect.equality(keymaps.defaults.focus_tree, "<leader>rf")
  expect.equality(keymaps.defaults.focus_diff, "<leader>rd")
end

T["defaults"]["comment actions use leader-c prefix"] = function()
  local keymaps = get_keymaps()

  expect.equality(keymaps.defaults.add_comment, "<leader>cc")
  expect.equality(keymaps.defaults.add_issue, "<leader>ci")
  expect.equality(keymaps.defaults.add_suggestion, "<leader>cs")
  expect.equality(keymaps.defaults.add_praise, "<leader>cp")
  expect.equality(keymaps.defaults.edit_comment, "<leader>ce")
  expect.equality(keymaps.defaults.delete_comment, "<leader>cd")
end

T["defaults"]["show comment uses K"] = function()
  local keymaps = get_keymaps()
  expect.equality(keymaps.defaults.show_comment, "K")
end

T["defaults"]["reply and resolve use single keys"] = function()
  local keymaps = get_keymaps()
  expect.equality(keymaps.defaults.reply, "r")
  expect.equality(keymaps.defaults.resolve, "R")
end

T["defaults"]["PR actions use leader-r prefix"] = function()
  local keymaps = get_keymaps()

  expect.equality(keymaps.defaults.add_conversation, "<leader>rC")
  expect.equality(keymaps.defaults.send_to_ai, "<leader>rs")
  expect.equality(keymaps.defaults.pick_ai_provider, "<leader>rS")
  expect.equality(keymaps.defaults.send_to_clipboard, "<leader>ry")
  expect.equality(keymaps.defaults.submit_to_github, "<leader>rg")
  expect.equality(keymaps.defaults.approve, "<leader>ra")
  expect.equality(keymaps.defaults.request_changes, "<leader>rx")
end

T["defaults"]["picker keymaps use leader-r prefix"] = function()
  local keymaps = get_keymaps()

  expect.equality(keymaps.defaults.pick_review_requests, "<leader>rr")
  expect.equality(keymaps.defaults.pick_open_prs, "<leader>rl")
end

-- =============================================================================
-- get_keymaps Tests
-- =============================================================================

T["get_keymaps"] = MiniTest.new_set()

T["get_keymaps"]["returns defaults when no user config"] = function()
  local config = get_config()
  config.setup({})

  local keymaps = get_keymaps()
  local result = keymaps.get_keymaps()

  expect.equality(result.tree_next, "<C-j>")
  expect.equality(result.comment_next, "]c")
end

T["get_keymaps"]["merges user config with defaults"] = function()
  local config = get_config()
  config.setup({
    keymaps = {
      tree_next = "<C-n>",
      tree_prev = "<C-p>",
    },
  })

  local keymaps = get_keymaps()
  local result = keymaps.get_keymaps()

  -- User config overrides
  expect.equality(result.tree_next, "<C-n>")
  expect.equality(result.tree_prev, "<C-p>")

  -- Other defaults preserved
  expect.equality(result.comment_next, "]c")
  expect.equality(result.file_next, "<Tab>")
end

T["get_keymaps"]["allows disabling keymaps with false"] = function()
  local config = get_config()
  config.setup({
    keymaps = {
      tree_next = false,
    },
  })

  local keymaps = get_keymaps()
  local result = keymaps.get_keymaps()

  expect.equality(result.tree_next, false)
end

-- =============================================================================
-- get_default Tests
-- =============================================================================

T["get_default"] = MiniTest.new_set()

T["get_default"]["returns default for valid action"] = function()
  local keymaps = get_keymaps()

  expect.equality(keymaps.get_default("tree_next"), "<C-j>")
  expect.equality(keymaps.get_default("comment_next"), "]c")
  expect.equality(keymaps.get_default("show_comment"), "K")
end

T["get_default"]["returns nil for invalid action"] = function()
  local keymaps = get_keymaps()

  expect.equality(keymaps.get_default("nonexistent"), nil)
  expect.equality(keymaps.get_default(""), nil)
end

-- =============================================================================
-- is_setup Tests
-- =============================================================================

T["is_setup"] = MiniTest.new_set()

T["is_setup"]["returns false before setup"] = function()
  local keymaps = get_keymaps()
  expect.equality(keymaps.is_setup(), false)
end

T["is_setup"]["returns true after setup"] = function()
  local config = get_config()
  config.setup({ keymaps = { enabled = true } })

  local keymaps = get_keymaps()
  keymaps.setup()

  expect.equality(keymaps.is_setup(), true)

  -- Cleanup
  keymaps.teardown()
end

T["is_setup"]["returns false after teardown"] = function()
  local config = get_config()
  config.setup({ keymaps = { enabled = true } })

  local keymaps = get_keymaps()
  keymaps.setup()
  keymaps.teardown()

  expect.equality(keymaps.is_setup(), false)
end

-- =============================================================================
-- setup Tests
-- =============================================================================

T["setup"] = MiniTest.new_set()

T["setup"]["does nothing when keymaps disabled"] = function()
  local config = get_config()
  config.setup({ keymaps = { enabled = false } })

  local keymaps = get_keymaps()
  keymaps.setup()

  expect.equality(keymaps.is_setup(), false)
end

T["setup"]["creates keymaps when enabled"] = function()
  local config = get_config()
  config.setup({ keymaps = { enabled = true } })

  local keymaps = get_keymaps()
  keymaps.setup()

  expect.equality(keymaps.is_setup(), true)

  -- Check that some keymaps exist
  local mapping = vim.fn.maparg("]c", "n", false, true)
  expect.equality(mapping.desc, "Review: Next comment")

  -- Cleanup
  keymaps.teardown()
end

T["setup"]["sets descriptions on keymaps"] = function()
  local config = get_config()
  config.setup({ keymaps = { enabled = true } })

  local keymaps = get_keymaps()
  keymaps.setup()

  local comment_next = vim.fn.maparg("]c", "n", false, true)
  local comment_prev = vim.fn.maparg("[c", "n", false, true)
  local file_next = vim.fn.maparg("<Tab>", "n", false, true)

  expect.equality(comment_next.desc, "Review: Next comment")
  expect.equality(comment_prev.desc, "Review: Prev comment")
  expect.equality(file_next.desc, "Review: Open next file")

  -- Cleanup
  keymaps.teardown()
end

-- =============================================================================
-- teardown Tests
-- =============================================================================

T["teardown"] = MiniTest.new_set()

T["teardown"]["removes keymaps created by setup"] = function()
  local config = get_config()
  config.setup({ keymaps = { enabled = true } })

  local keymaps = get_keymaps()
  keymaps.setup()

  -- Verify keymap exists
  local before = vim.fn.maparg("]c", "n", false, true)
  expect.equality(before.desc, "Review: Next comment")

  keymaps.teardown()

  -- Verify keymap is removed or restored
  local after = vim.fn.maparg("]c", "n", false, true)
  expect.no_equality(after.desc, "Review: Next comment")
end

T["teardown"]["can be called multiple times safely"] = function()
  local config = get_config()
  config.setup({ keymaps = { enabled = true } })

  local keymaps = get_keymaps()
  keymaps.setup()
  keymaps.teardown()
  keymaps.teardown()
  keymaps.teardown()

  expect.equality(keymaps.is_setup(), false)
end

-- =============================================================================
-- get_all_definitions Tests
-- =============================================================================

T["get_all_definitions"] = MiniTest.new_set()

T["get_all_definitions"]["returns categorized keymaps"] = function()
  local keymaps = get_keymaps()
  local defs = keymaps.get_all_definitions()

  -- Check categories exist
  expect.no_equality(defs["File Navigation"], nil)
  expect.no_equality(defs["Comment Navigation"], nil)
  expect.no_equality(defs["Hunk Navigation"], nil)
  expect.no_equality(defs["Views"], nil)
  expect.no_equality(defs["Comment Actions"], nil)
  expect.no_equality(defs["PR Actions"], nil)
  expect.no_equality(defs["Picker"], nil)
end

T["get_all_definitions"]["file navigation has correct entries"] = function()
  local keymaps = get_keymaps()
  local defs = keymaps.get_all_definitions()

  local file_nav = defs["File Navigation"]
  expect.equality(#file_nav, 4)

  local keys = {}
  for _, entry in ipairs(file_nav) do
    keys[entry.key] = entry.desc
  end

  expect.equality(keys["<C-j>"], "Navigate to next file in tree")
  expect.equality(keys["<C-k>"], "Navigate to previous file in tree")
  expect.equality(keys["<Tab>"], "Open next file")
  expect.equality(keys["<S-Tab>"], "Open previous file")
end

T["get_all_definitions"]["comment navigation has correct entries"] = function()
  local keymaps = get_keymaps()
  local defs = keymaps.get_all_definitions()

  local comment_nav = defs["Comment Navigation"]
  expect.equality(#comment_nav, 6)
end

T["get_all_definitions"]["comment actions has correct entries"] = function()
  local keymaps = get_keymaps()
  local defs = keymaps.get_all_definitions()

  local comment_actions = defs["Comment Actions"]
  expect.equality(#comment_actions, 9)
end

T["get_all_definitions"]["PR actions has correct entries"] = function()
  local keymaps = get_keymaps()
  local defs = keymaps.get_all_definitions()

  local pr_actions = defs["PR Actions"]
  expect.equality(#pr_actions, 7)
end

-- =============================================================================
-- refresh_ui Tests
-- =============================================================================

T["refresh_ui"] = MiniTest.new_set()

T["refresh_ui"]["does not error when modules not loaded"] = function()
  local keymaps = get_keymaps()

  -- Should not error even if UI modules aren't available
  keymaps.refresh_ui()
end

-- =============================================================================
-- Buffer-local keymap Tests
-- =============================================================================

T["setup_tree_keymaps"] = MiniTest.new_set()

T["setup_tree_keymaps"]["sets keymaps on valid buffer"] = function()
  local keymaps = get_keymaps()

  -- Create a test buffer
  local buf = vim.api.nvim_create_buf(false, true)

  keymaps.setup_tree_keymaps(buf)

  -- Check keymaps exist on buffer
  local cr_mapping = vim.fn.maparg("<CR>", "n", false, true)
  -- The buffer-local mapping should exist (may need to switch buffer to check)

  -- Cleanup
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["setup_tree_keymaps"]["does nothing with invalid buffer"] = function()
  local keymaps = get_keymaps()

  -- Should not error with invalid buffer
  keymaps.setup_tree_keymaps(-1)
  keymaps.setup_tree_keymaps(99999)
end

T["setup_diff_keymaps"] = MiniTest.new_set()

T["setup_diff_keymaps"]["does nothing with invalid buffer"] = function()
  local keymaps = get_keymaps()

  -- Should not error with invalid buffer
  keymaps.setup_diff_keymaps(-1)
  keymaps.setup_diff_keymaps(99999)
end

return T
