-- Layout management for review.nvim
-- Handles window/split management for review sessions

local M = {}

local state = require("review.core.state")
local config = require("review.config")
local utils = require("review.utils")

---Open review layout in new tabpage
---@param opts? {width?: number}
function M.open(opts)
  opts = opts or {}
  local tree_width = opts.width or config.get("ui.tree_width") or 30

  -- Create new tabpage
  vim.cmd("tabnew")
  state.state.layout.tabpage = vim.api.nvim_get_current_tabpage()

  -- Create left panel (file tree)
  vim.cmd("vsplit")
  vim.cmd("wincmd H")
  vim.cmd("vertical resize " .. tree_width)
  state.state.layout.file_tree_win = vim.api.nvim_get_current_win()
  state.state.layout.file_tree_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(state.state.layout.file_tree_win, state.state.layout.file_tree_buf)

  -- Set file tree buffer options
  local buf = state.state.layout.file_tree_buf
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "review_tree"
  -- Use unique buffer name with buffer ID to avoid conflicts
  pcall(vim.api.nvim_buf_set_name, buf, string.format("[Review Files %d]", buf))

  -- Set file tree window options
  local win = state.state.layout.file_tree_win
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].winfixwidth = true
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true

  -- Move to right panel (diff view)
  vim.cmd("wincmd l")
  state.state.layout.diff_win = vim.api.nvim_get_current_win()
  state.state.layout.diff_buf = vim.api.nvim_get_current_buf()

  state.state.active = true

  -- Setup autocmds for cleanup
  M.setup_autocmds()
end

---Close review layout (internal, no confirmation)
function M.close_internal()
  local layout = state.state.layout

  -- Close panel if open
  if layout.panel_win and vim.api.nvim_win_is_valid(layout.panel_win) then
    vim.api.nvim_win_close(layout.panel_win, true)
  end

  -- Close tabpage if exists
  if layout.tabpage and vim.api.nvim_tabpage_is_valid(layout.tabpage) then
    -- Switch to a different tabpage first if possible
    local tabs = vim.api.nvim_list_tabpages()
    if #tabs > 1 then
      local current_tab = vim.api.nvim_get_current_tabpage()
      if current_tab == layout.tabpage then
        -- Find another tab to switch to
        for _, tab in ipairs(tabs) do
          if tab ~= layout.tabpage then
            vim.api.nvim_set_current_tabpage(tab)
            break
          end
        end
      end
      -- Close the review tabpage
      local tab_nr = vim.api.nvim_tabpage_get_number(layout.tabpage)
      vim.cmd("tabclose " .. tab_nr)
    else
      -- Only one tab, close all windows
      if layout.file_tree_win and vim.api.nvim_win_is_valid(layout.file_tree_win) then
        vim.api.nvim_win_close(layout.file_tree_win, true)
      end
      if layout.diff_win and vim.api.nvim_win_is_valid(layout.diff_win) then
        -- Don't close the last window, just clear it
        vim.cmd("enew")
      end
    end
  end

  state.reset()
end

---Close review layout with confirmation if there are pending comments
---@param opts? {force?: boolean} Options - force=true skips confirmation
function M.close(opts)
  opts = opts or {}

  -- Check for pending comments
  local pending = state.get_pending_comments()
  if #pending > 0 and not opts.force then
    local msg = string.format(
      "You have %d unsaved comment%s. Close anyway?",
      #pending,
      #pending > 1 and "s" or ""
    )
    vim.ui.select({ "Yes, discard comments", "No, keep reviewing" }, {
      prompt = msg,
    }, function(choice)
      if choice and choice:match("^Yes") then
        M.close_internal()
      end
    end)
  else
    M.close_internal()
  end
end

---Focus file tree window
function M.focus_tree()
  local win = state.state.layout.file_tree_win
  if utils.is_valid_win(win) then
    vim.api.nvim_set_current_win(win)
  end
end

---Focus diff view window
function M.focus_diff()
  local win = state.state.layout.diff_win
  if utils.is_valid_win(win) then
    vim.api.nvim_set_current_win(win)
  end
end

---Check if file tree window is focused
---@return boolean
function M.is_tree_focused()
  local win = state.state.layout.file_tree_win
  if not utils.is_valid_win(win) then
    return false
  end
  return vim.api.nvim_get_current_win() == win
end

---Check if diff window is focused
---@return boolean
function M.is_diff_focused()
  local win = state.state.layout.diff_win
  if not utils.is_valid_win(win) then
    return false
  end
  return vim.api.nvim_get_current_win() == win
end

---Get file tree buffer
---@return number? buffer handle or nil
function M.get_tree_buf()
  local buf = state.state.layout.file_tree_buf
  if utils.is_valid_buf(buf) then
    return buf
  end
  return nil
end

---Get diff buffer
---@return number? buffer handle or nil
function M.get_diff_buf()
  local buf = state.state.layout.diff_buf
  if utils.is_valid_buf(buf) then
    return buf
  end
  return nil
end

---Get file tree window
---@return number? window handle or nil
function M.get_tree_win()
  local win = state.state.layout.file_tree_win
  if utils.is_valid_win(win) then
    return win
  end
  return nil
end

---Get diff window
---@return number? window handle or nil
function M.get_diff_win()
  local win = state.state.layout.diff_win
  if utils.is_valid_win(win) then
    return win
  end
  return nil
end

---Set diff buffer (when opening a file)
---@param buf number Buffer handle
function M.set_diff_buf(buf)
  local win = state.state.layout.diff_win
  if utils.is_valid_win(win) and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_win_set_buf(win, buf)
    state.state.layout.diff_buf = buf
  end
end

---Resize file tree
---@param width number New width
function M.resize_tree(width)
  local win = state.state.layout.file_tree_win
  if utils.is_valid_win(win) then
    vim.api.nvim_win_set_width(win, width)
  end
end

---Get current tree width
---@return number? width or nil if window invalid
function M.get_tree_width()
  local win = state.state.layout.file_tree_win
  if utils.is_valid_win(win) then
    return vim.api.nvim_win_get_width(win)
  end
  return nil
end

---Check if layout is valid (all windows exist)
---@return boolean
function M.is_valid()
  local layout = state.state.layout
  if not layout.tabpage or not vim.api.nvim_tabpage_is_valid(layout.tabpage) then
    return false
  end
  if not utils.is_valid_win(layout.file_tree_win) then
    return false
  end
  if not utils.is_valid_win(layout.diff_win) then
    return false
  end
  return true
end

---Ensure we're in the review tabpage
---@return boolean success
function M.ensure_tabpage()
  local tabpage = state.state.layout.tabpage
  if not tabpage or not vim.api.nvim_tabpage_is_valid(tabpage) then
    return false
  end
  if vim.api.nvim_get_current_tabpage() ~= tabpage then
    vim.api.nvim_set_current_tabpage(tabpage)
  end
  return true
end

---Setup autocmds for layout cleanup
function M.setup_autocmds()
  local group = vim.api.nvim_create_augroup("ReviewLayout", { clear = true })

  -- Clean up when tabpage is closed
  vim.api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = function()
      local layout = state.state.layout
      if layout.tabpage and not vim.api.nvim_tabpage_is_valid(layout.tabpage) then
        state.reset()
      end
    end,
  })

  -- Clean up when file tree buffer is wiped
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = state.state.layout.file_tree_buf,
    callback = function()
      -- If file tree is wiped, close the whole review
      if state.is_active() then
        M.close()
      end
    end,
  })

  -- Intercept :q/:quit in review tabpage to close entire review
  vim.api.nvim_create_autocmd("QuitPre", {
    group = group,
    callback = function()
      if not state.is_active() then
        return
      end

      local layout = state.state.layout
      if not layout.tabpage or not vim.api.nvim_tabpage_is_valid(layout.tabpage) then
        return
      end

      -- Check if we're in the review tabpage
      if vim.api.nvim_get_current_tabpage() == layout.tabpage then
        local pending = state.get_pending_comments()
        if #pending > 0 then
          -- Warn user about unsaved comments
          vim.notify(
            string.format("Discarding %d unsaved comment(s). Use 'q' keymap for confirmation dialog.", #pending),
            vim.log.levels.WARN
          )
        end
        -- Close the review layout
        vim.schedule(function()
          M.close_internal()
        end)
      end
    end,
  })
end

---Cleanup autocmds
function M.cleanup_autocmds()
  pcall(vim.api.nvim_del_augroup_by_name, "ReviewLayout")
end

return M
