-- Floating window helpers for review.nvim
local M = {}

local utils = require("review.utils")

-- Namespace for float-related extmarks (tracking popup positions)
local ns_id = vim.api.nvim_create_namespace("review_float")

---@class Review.FloatConfig
---@field border string|table Border style
---@field max_width number Maximum width for floating windows
---@field max_height number Maximum height for floating windows
---@field min_width number Minimum width for floating windows
---@field min_height number Minimum height for floating windows

---Get default config for floats
---@return Review.FloatConfig
local function get_config()
  local config = require("review.config")
  local cfg = config.config.float or {}
  return {
    border = cfg.border or "rounded",
    max_width = cfg.max_width or 80,
    max_height = cfg.max_height or 40,
    min_width = cfg.min_width or 20,
    min_height = cfg.min_height or 3,
  }
end

---Get the namespace ID
---@return number
function M.get_namespace()
  return ns_id
end

---Calculate width for floating window based on content
---@param lines string[] Lines to display
---@param max_width? number Maximum width (defaults to config)
---@param min_width? number Minimum width (defaults to config)
---@return number
function M.calculate_width(lines, max_width, min_width)
  local cfg = get_config()
  max_width = max_width or cfg.max_width
  min_width = min_width or cfg.min_width

  local max_line_width = 0
  for _, line in ipairs(lines) do
    -- Account for display width (handles multi-byte characters)
    local width = vim.fn.strdisplaywidth(line)
    if width > max_line_width then
      max_line_width = width
    end
  end

  -- Add padding
  local width = max_line_width + 2
  return math.max(min_width, math.min(width, max_width))
end

---Calculate height for floating window based on content
---@param lines string[] Lines to display
---@param max_height? number Maximum height (defaults to config)
---@param min_height? number Minimum height (defaults to config)
---@return number
function M.calculate_height(lines, max_height, min_height)
  local cfg = get_config()
  max_height = max_height or cfg.max_height
  min_height = min_height or cfg.min_height

  local height = #lines
  return math.max(min_height, math.min(height, max_height))
end

---Calculate window position relative to cursor
---@param width number Window width
---@param height number Window height
---@param opts? {relative?: string, anchor?: string}
---@return {row: number, col: number}
function M.calculate_position(width, height, opts)
  opts = opts or {}

  local cursor = vim.api.nvim_win_get_cursor(0)
  local win_height = vim.api.nvim_win_get_height(0)
  local win_width = vim.api.nvim_win_get_width(0)

  local row = 1 -- Default: below cursor
  local col = 0

  -- Check if there's room below the cursor
  local cursor_row = cursor[1]
  local lines_below = win_height - cursor_row

  if lines_below < height + 2 and cursor_row > height + 2 then
    -- Show above cursor if not enough room below
    row = -height - 1
  end

  -- Prevent going off the right edge
  local cursor_col = cursor[2]
  if cursor_col + width > win_width then
    col = win_width - width - cursor_col
  end

  return { row = row, col = col }
end

---Create a floating window with content
---@param lines string[] Lines to display
---@param opts? {enter?: boolean, focus?: boolean, relative?: string, row?: number, col?: number, width?: number, height?: number, border?: string|table, title?: string, title_pos?: string, filetype?: string, modifiable?: boolean, wrap?: boolean, cursorline?: boolean}
---@return number? win_id Window ID or nil on failure
---@return number? buf_id Buffer ID or nil on failure
function M.create(lines, opts)
  opts = opts or {}
  local cfg = get_config()

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  if not vim.api.nvim_buf_is_valid(buf) then
    return nil, nil
  end

  -- Set buffer content
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Calculate dimensions
  local width = opts.width or M.calculate_width(lines)
  local height = opts.height or M.calculate_height(lines)

  -- Calculate position if not provided
  local row = opts.row
  local col = opts.col
  if row == nil or col == nil then
    local pos = M.calculate_position(width, height)
    row = row or pos.row
    col = col or pos.col
  end

  -- Build window config
  local win_config = {
    relative = opts.relative or "cursor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = opts.border or cfg.border,
  }

  -- Add optional title
  if opts.title then
    win_config.title = " " .. opts.title .. " "
    win_config.title_pos = opts.title_pos or "center"
  end

  -- Create window
  local enter = opts.enter ~= false and opts.focus ~= false
  local win = vim.api.nvim_open_win(buf, enter, win_config)
  if not vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_buf_delete(buf, { force = true })
    return nil, nil
  end

  -- Set buffer options
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  if opts.filetype then
    vim.bo[buf].filetype = opts.filetype
  end
  if opts.modifiable == false then
    vim.bo[buf].modifiable = false
  end

  -- Set window options
  if opts.wrap ~= nil then
    vim.wo[win].wrap = opts.wrap
  else
    vim.wo[win].wrap = true
  end
  if opts.cursorline then
    vim.wo[win].cursorline = true
  end

  return win, buf
end

---Close a floating window if it exists and is valid
---@param win number Window ID
function M.close(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

---Check if a window is a floating window
---@param win number Window ID
---@return boolean
function M.is_float(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return false
  end
  local config = vim.api.nvim_win_get_config(win)
  return config.relative ~= ""
end

---Get icon for a comment based on its type
---@param comment Review.Comment
---@return string
function M.get_comment_icon(comment)
  -- Delegate to virtual_text module for consistency
  local virtual_text = require("review.ui.virtual_text")
  return virtual_text.get_icon(comment)
end

---Format a comment for display in a floating window
---@param comment Review.Comment
---@return string[]
function M.format_comment(comment)
  local lines = {}

  -- Header
  local icon = M.get_comment_icon(comment)
  local author = comment.author or "you"
  local time = utils.relative_time(comment.created_at)
  table.insert(lines, string.format("%s @%s • %s", icon, author, time))
  table.insert(lines, string.rep("─", 40))

  -- Body
  if comment.body and comment.body ~= "" then
    for line in comment.body:gmatch("[^\n]+") do
      table.insert(lines, line)
    end
  else
    table.insert(lines, "(no content)")
  end

  -- Replies
  if comment.replies and #comment.replies > 0 then
    table.insert(lines, "")
    for _, reply in ipairs(comment.replies) do
      local reply_author = reply.author or "anonymous"
      local reply_body = (reply.body or ""):gsub("\n", " ")
      table.insert(lines, string.format("  └─ @%s: %s", reply_author, reply_body))
    end
  end

  -- Actions hint
  table.insert(lines, "")
  if comment.kind == "local" then
    table.insert(lines, "[e]dit [d]elete")
  else
    table.insert(lines, "[r]eply [R]esolve")
  end

  return lines
end

---Show a comment in a floating window
---@param comment Review.Comment
---@param opts? {close_on_cursor_move?: boolean, keymaps?: boolean}
---@return number? win_id Window ID or nil
---@return number? buf_id Buffer ID or nil
function M.show_comment(comment, opts)
  opts = opts or {}
  local close_on_cursor_move = opts.close_on_cursor_move ~= false

  local lines = M.format_comment(comment)
  local win, buf = M.create(lines, {
    filetype = "markdown",
    modifiable = false,
    enter = false,
  })

  if not win then
    return nil, nil
  end

  -- Setup auto-close on cursor move
  if close_on_cursor_move then
    local augroup = vim.api.nvim_create_augroup("ReviewFloatAutoClose", { clear = true })
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave" }, {
      group = augroup,
      once = true,
      callback = function()
        M.close(win)
        vim.api.nvim_del_augroup_by_id(augroup)
      end,
    })
  end

  return win, buf
end

---Prompt for single-line input using vim.ui.input
---@param prompt string Prompt text
---@param opts? {default?: string}
---@param callback fun(input: string?) Callback with result (nil if cancelled)
function M.input(prompt, opts, callback)
  opts = opts or {}
  vim.ui.input({
    prompt = prompt,
    default = opts.default,
  }, callback)
end

---Prompt for multi-line input in a floating window
---@param opts {prompt: string, default?: string, filetype?: string}
---@param callback fun(lines: string[]?) Callback with result (nil if cancelled)
function M.multiline_input(opts, callback)
  -- Create scratch buffer for input
  local lines = {}
  if opts.default then
    lines = vim.split(opts.default, "\n")
  else
    lines = { "" }
  end

  local cfg = get_config()
  local width = math.min(60, cfg.max_width)
  local height = math.min(10, cfg.max_height)

  -- Center the window in the editor
  local editor_height = vim.o.lines
  local editor_width = vim.o.columns
  local row = math.floor((editor_height - height) / 2)
  local col = math.floor((editor_width - width) / 2)

  local win, buf = M.create(lines, {
    title = opts.prompt,
    title_pos = "center",
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    filetype = opts.filetype or "markdown",
    modifiable = true,
    enter = true,
    wrap = true,
  })

  if not win or not buf then
    callback(nil)
    return
  end

  -- Track whether callback was called
  local callback_called = false

  -- Helper to call callback only once
  local function safe_callback(result)
    if not callback_called then
      callback_called = true
      callback(result)
    end
  end

  -- Cancel keymap
  vim.keymap.set({ "n", "i" }, "<C-c>", function()
    M.close(win)
    safe_callback(nil)
  end, { buffer = buf, nowait = true })

  -- Save keymap (Ctrl+S)
  vim.keymap.set({ "n", "i" }, "<C-s>", function()
    local result = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    M.close(win)
    safe_callback(result)
  end, { buffer = buf, nowait = true })

  -- Alternative save with <CR> in normal mode (optional, can be disabled)
  vim.keymap.set("n", "<CR>", function()
    local result = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    M.close(win)
    safe_callback(result)
  end, { buffer = buf, nowait = true })

  -- Handle buffer close (e.g., :q)
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      safe_callback(nil)
    end,
  })

  -- Start in insert mode
  vim.cmd("startinsert")
end

---Show a confirmation dialog
---@param prompt string Prompt text
---@param callback fun(confirmed: boolean) Callback with result
function M.confirm(prompt, callback)
  local lines = {
    prompt,
    "",
    "[y]es  [n]o  [Esc]cancel",
  }

  local win, buf = M.create(lines, {
    modifiable = false,
    enter = true,
    cursorline = false,
  })

  if not win or not buf then
    callback(false)
    return
  end

  local function close_and_callback(result)
    M.close(win)
    callback(result)
  end

  -- Yes
  vim.keymap.set("n", "y", function()
    close_and_callback(true)
  end, { buffer = buf, nowait = true })

  vim.keymap.set("n", "Y", function()
    close_and_callback(true)
  end, { buffer = buf, nowait = true })

  -- No
  vim.keymap.set("n", "n", function()
    close_and_callback(false)
  end, { buffer = buf, nowait = true })

  vim.keymap.set("n", "N", function()
    close_and_callback(false)
  end, { buffer = buf, nowait = true })

  -- Escape/cancel
  vim.keymap.set("n", "<Esc>", function()
    close_and_callback(false)
  end, { buffer = buf, nowait = true })

  vim.keymap.set("n", "q", function()
    close_and_callback(false)
  end, { buffer = buf, nowait = true })
end

---Show a notification in a floating window (auto-closes after timeout)
---@param message string|string[] Message to display
---@param opts? {timeout?: number, level?: "info"|"warn"|"error", title?: string}
---@return number? win_id Window ID or nil
function M.notify(message, opts)
  opts = opts or {}
  local timeout = opts.timeout or 3000

  local lines
  if type(message) == "string" then
    lines = vim.split(message, "\n")
  else
    lines = message
  end

  -- Add icon based on level
  local level = opts.level or "info"
  local icon_map = {
    info = "ℹ️",
    warn = "⚠️",
    error = "❌",
  }
  local icon = icon_map[level] or "ℹ️"

  -- Prepend icon to first line
  if #lines > 0 then
    lines[1] = icon .. " " .. lines[1]
  end

  local win, _ = M.create(lines, {
    title = opts.title,
    enter = false,
    modifiable = false,
    relative = "editor",
    row = 1,
    col = vim.o.columns - M.calculate_width(lines) - 2,
  })

  if win then
    -- Auto-close after timeout
    vim.defer_fn(function()
      M.close(win)
    end, timeout)
  end

  return win
end

---Show a menu with selectable items
---@param items string[] Items to select from
---@param opts? {prompt?: string, callback: fun(choice: string?, idx: number?)}
function M.menu(items, opts)
  opts = opts or {}

  if #items == 0 then
    if opts.callback then
      opts.callback(nil, nil)
    end
    return
  end

  -- Use vim.ui.select for native feel
  vim.ui.select(items, {
    prompt = opts.prompt or "Select:",
    format_item = function(item)
      return item
    end,
  }, function(choice, idx)
    if opts.callback then
      opts.callback(choice, idx)
    end
  end)
end

---Update content in an existing floating window
---@param win number Window ID
---@param lines string[] New lines to display
---@return boolean success
function M.update_content(win, lines)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return false
  end

  local buf = vim.api.nvim_win_get_buf(win)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  -- Temporarily make buffer modifiable
  local was_modifiable = vim.bo[buf].modifiable
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = was_modifiable

  return true
end

---Resize a floating window
---@param win number Window ID
---@param width number New width
---@param height number New height
---@return boolean success
function M.resize(win, width, height)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return false
  end

  vim.api.nvim_win_set_width(win, width)
  vim.api.nvim_win_set_height(win, height)
  return true
end

return M
