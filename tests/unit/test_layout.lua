-- Tests for review.ui.layout module
local T = MiniTest.new_set()

local layout = require("review.ui.layout")
local state = require("review.core.state")
local config = require("review.config")

-- Helper to clean up after tests
local function cleanup()
  pcall(function()
    layout.cleanup_autocmds()
  end)
  pcall(function()
    -- Close file tree buffer if it exists
    local buf = state.state.layout.file_tree_buf
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end)
  pcall(function()
    -- Close all windows/tabs created by layout
    if state.state.layout.tabpage and vim.api.nvim_tabpage_is_valid(state.state.layout.tabpage) then
      local tabs = vim.api.nvim_list_tabpages()
      if #tabs > 1 then
        local tab_nr = vim.api.nvim_tabpage_get_number(state.state.layout.tabpage)
        vim.cmd("tabclose! " .. tab_nr)
      end
    end
  end)
  state.reset()
end

T["open()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["open()"]["creates new tabpage"] = function()
  local initial_tabs = #vim.api.nvim_list_tabpages()
  layout.open()
  local final_tabs = #vim.api.nvim_list_tabpages()
  MiniTest.expect.equality(final_tabs, initial_tabs + 1)
end

T["open()"]["stores tabpage in layout state"] = function()
  layout.open()
  MiniTest.expect.no_equality(state.state.layout.tabpage, nil)
  MiniTest.expect.equality(vim.api.nvim_tabpage_is_valid(state.state.layout.tabpage), true)
end

T["open()"]["creates file tree window"] = function()
  layout.open()
  MiniTest.expect.no_equality(state.state.layout.file_tree_win, nil)
  MiniTest.expect.equality(vim.api.nvim_win_is_valid(state.state.layout.file_tree_win), true)
end

T["open()"]["creates file tree buffer"] = function()
  layout.open()
  MiniTest.expect.no_equality(state.state.layout.file_tree_buf, nil)
  MiniTest.expect.equality(vim.api.nvim_buf_is_valid(state.state.layout.file_tree_buf), true)
end

T["open()"]["creates diff window"] = function()
  layout.open()
  MiniTest.expect.no_equality(state.state.layout.diff_win, nil)
  MiniTest.expect.equality(vim.api.nvim_win_is_valid(state.state.layout.diff_win), true)
end

T["open()"]["sets active state to true"] = function()
  MiniTest.expect.equality(state.is_active(), false)
  layout.open()
  MiniTest.expect.equality(state.is_active(), true)
end

T["open()"]["sets file tree buffer options correctly"] = function()
  layout.open()
  local buf = state.state.layout.file_tree_buf
  MiniTest.expect.equality(vim.bo[buf].buftype, "nofile")
  MiniTest.expect.equality(vim.bo[buf].filetype, "review_tree")
  MiniTest.expect.equality(vim.bo[buf].swapfile, false)
end

T["open()"]["sets file tree window options correctly"] = function()
  layout.open()
  local win = state.state.layout.file_tree_win
  MiniTest.expect.equality(vim.wo[win].number, false)
  MiniTest.expect.equality(vim.wo[win].relativenumber, false)
  MiniTest.expect.equality(vim.wo[win].signcolumn, "no")
  MiniTest.expect.equality(vim.wo[win].winfixwidth, true)
end

T["open()"]["uses configured tree width"] = function()
  config.setup({ ui = { tree_width = 40 } })
  layout.open()
  local width = vim.api.nvim_win_get_width(state.state.layout.file_tree_win)
  MiniTest.expect.equality(width, 40)
end

T["open()"]["uses custom width from opts"] = function()
  layout.open({ width = 35 })
  local width = vim.api.nvim_win_get_width(state.state.layout.file_tree_win)
  MiniTest.expect.equality(width, 35)
end

T["open()"]["opts width overrides config"] = function()
  config.setup({ ui = { tree_width = 40 } })
  layout.open({ width = 25 })
  local width = vim.api.nvim_win_get_width(state.state.layout.file_tree_win)
  MiniTest.expect.equality(width, 25)
end

T["close()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
      layout.open()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["close()"]["resets state"] = function()
  MiniTest.expect.equality(state.is_active(), true)
  layout.close()
  MiniTest.expect.equality(state.is_active(), false)
end

T["close()"]["clears layout references"] = function()
  layout.close()
  MiniTest.expect.equality(state.state.layout.tabpage, nil)
  MiniTest.expect.equality(state.state.layout.file_tree_win, nil)
  MiniTest.expect.equality(state.state.layout.diff_win, nil)
end

T["focus_tree()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
      layout.open()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["focus_tree()"]["focuses file tree window"] = function()
  layout.focus_diff() -- Start elsewhere
  layout.focus_tree()
  MiniTest.expect.equality(vim.api.nvim_get_current_win(), state.state.layout.file_tree_win)
end

T["focus_tree()"]["handles invalid window gracefully"] = function()
  vim.api.nvim_win_close(state.state.layout.file_tree_win, true)
  -- Should not error
  layout.focus_tree()
end

T["focus_diff()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
      layout.open()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["focus_diff()"]["focuses diff window"] = function()
  layout.focus_tree() -- Start elsewhere
  layout.focus_diff()
  MiniTest.expect.equality(vim.api.nvim_get_current_win(), state.state.layout.diff_win)
end

T["focus_diff()"]["handles invalid window gracefully"] = function()
  vim.api.nvim_win_close(state.state.layout.diff_win, true)
  -- Should not error
  layout.focus_diff()
end

T["is_tree_focused()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
      layout.open()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["is_tree_focused()"]["returns true when tree is focused"] = function()
  layout.focus_tree()
  MiniTest.expect.equality(layout.is_tree_focused(), true)
end

T["is_tree_focused()"]["returns false when diff is focused"] = function()
  layout.focus_diff()
  MiniTest.expect.equality(layout.is_tree_focused(), false)
end

T["is_diff_focused()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
      layout.open()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["is_diff_focused()"]["returns true when diff is focused"] = function()
  layout.focus_diff()
  MiniTest.expect.equality(layout.is_diff_focused(), true)
end

T["is_diff_focused()"]["returns false when tree is focused"] = function()
  layout.focus_tree()
  MiniTest.expect.equality(layout.is_diff_focused(), false)
end

T["get_tree_buf()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
      layout.open()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["get_tree_buf()"]["returns valid buffer"] = function()
  local buf = layout.get_tree_buf()
  MiniTest.expect.no_equality(buf, nil)
  MiniTest.expect.equality(vim.api.nvim_buf_is_valid(buf), true)
end

T["get_tree_buf()"]["returns nil when buffer is invalid"] = function()
  vim.api.nvim_buf_delete(state.state.layout.file_tree_buf, { force = true })
  local buf = layout.get_tree_buf()
  MiniTest.expect.equality(buf, nil)
end

T["get_diff_buf()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
      layout.open()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["get_diff_buf()"]["returns valid buffer"] = function()
  local buf = layout.get_diff_buf()
  MiniTest.expect.no_equality(buf, nil)
  MiniTest.expect.equality(vim.api.nvim_buf_is_valid(buf), true)
end

T["get_tree_win()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
      layout.open()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["get_tree_win()"]["returns valid window"] = function()
  local win = layout.get_tree_win()
  MiniTest.expect.no_equality(win, nil)
  MiniTest.expect.equality(vim.api.nvim_win_is_valid(win), true)
end

T["get_tree_win()"]["returns nil when window is invalid"] = function()
  vim.api.nvim_win_close(state.state.layout.file_tree_win, true)
  local win = layout.get_tree_win()
  MiniTest.expect.equality(win, nil)
end

T["get_diff_win()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
      layout.open()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["get_diff_win()"]["returns valid window"] = function()
  local win = layout.get_diff_win()
  MiniTest.expect.no_equality(win, nil)
  MiniTest.expect.equality(vim.api.nvim_win_is_valid(win), true)
end

T["set_diff_buf()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
      layout.open()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["set_diff_buf()"]["sets new buffer in diff window"] = function()
  local new_buf = vim.api.nvim_create_buf(false, true)
  layout.set_diff_buf(new_buf)
  MiniTest.expect.equality(state.state.layout.diff_buf, new_buf)
  MiniTest.expect.equality(vim.api.nvim_win_get_buf(state.state.layout.diff_win), new_buf)
end

T["resize_tree()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
      layout.open()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["resize_tree()"]["changes tree width"] = function()
  layout.resize_tree(50)
  local width = vim.api.nvim_win_get_width(state.state.layout.file_tree_win)
  MiniTest.expect.equality(width, 50)
end

T["get_tree_width()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
      layout.open()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["get_tree_width()"]["returns current width"] = function()
  layout.resize_tree(45)
  MiniTest.expect.equality(layout.get_tree_width(), 45)
end

T["get_tree_width()"]["returns nil when window invalid"] = function()
  vim.api.nvim_win_close(state.state.layout.file_tree_win, true)
  MiniTest.expect.equality(layout.get_tree_width(), nil)
end

T["is_valid()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["is_valid()"]["returns true when layout is complete"] = function()
  layout.open()
  MiniTest.expect.equality(layout.is_valid(), true)
end

T["is_valid()"]["returns false when tabpage invalid"] = function()
  layout.open()
  -- Simulate invalid tabpage
  state.state.layout.tabpage = 99999
  MiniTest.expect.equality(layout.is_valid(), false)
end

T["is_valid()"]["returns false when tree window invalid"] = function()
  layout.open()
  vim.api.nvim_win_close(state.state.layout.file_tree_win, true)
  MiniTest.expect.equality(layout.is_valid(), false)
end

T["is_valid()"]["returns false when diff window invalid"] = function()
  layout.open()
  vim.api.nvim_win_close(state.state.layout.diff_win, true)
  MiniTest.expect.equality(layout.is_valid(), false)
end

T["is_valid()"]["returns false before open"] = function()
  MiniTest.expect.equality(layout.is_valid(), false)
end

T["ensure_tabpage()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
      layout.open()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["ensure_tabpage()"]["switches to review tabpage"] = function()
  local review_tab = state.state.layout.tabpage
  vim.cmd("tabnew") -- Create another tab
  MiniTest.expect.no_equality(vim.api.nvim_get_current_tabpage(), review_tab)

  local success = layout.ensure_tabpage()
  MiniTest.expect.equality(success, true)
  MiniTest.expect.equality(vim.api.nvim_get_current_tabpage(), review_tab)

  -- Clean up extra tab
  vim.cmd("tabclose")
end

T["ensure_tabpage()"]["returns true when already in review tabpage"] = function()
  MiniTest.expect.equality(layout.ensure_tabpage(), true)
end

T["ensure_tabpage()"]["returns false when tabpage invalid"] = function()
  state.state.layout.tabpage = nil
  MiniTest.expect.equality(layout.ensure_tabpage(), false)
end

return T
