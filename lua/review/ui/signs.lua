-- Gutter signs for review.nvim
local M = {}

local state = require("review.core.state")
local config = require("review.config")

-- Sign group name
local SIGN_GROUP = "review_signs"

-- Namespace for extmark-based signs (Neovim 0.10+)
local ns_id = vim.api.nvim_create_namespace("review_signs")

---@type boolean
local is_setup = false

---@class Review.SignDef
---@field text string Sign text
---@field texthl string Text highlight group
---@field numhl? string Line number highlight group
---@field linehl? string Line highlight group

---Get sign definitions from config
---@return table<string, Review.SignDef>
local function get_sign_definitions()
  local cfg = config.config.signs or config.defaults.signs
  return {
    -- Status-based signs
    comment_pending = { text = cfg.comment_pending or "●", texthl = "ReviewSignPending" },
    comment_submitted = { text = cfg.comment_submitted or "○", texthl = "ReviewSignSubmitted" },
    comment_github = { text = cfg.comment_github or "◇", texthl = "ReviewSignGithub" },
    comment_resolved = { text = cfg.comment_resolved or "◆", texthl = "ReviewSignResolved" },
    -- AI status
    comment_ai_processing = { text = cfg.comment_ai_processing or "●", texthl = "ReviewSignAI" },
    comment_ai_complete = { text = "✓", texthl = "ReviewSignSubmitted" },
  }
end

---Setup sign definitions
function M.setup()
  if is_setup then
    return
  end

  local signs = get_sign_definitions()
  for name, def in pairs(signs) do
    vim.fn.sign_define("Review_" .. name, def)
  end

  is_setup = true
end

---Check if signs are set up
---@return boolean
function M.is_setup()
  return is_setup
end

---Clear setup state (useful for testing)
function M.clear()
  -- Undefine all signs (use pcall to avoid errors for undefined signs)
  local signs = get_sign_definitions()
  for name, _ in pairs(signs) do
    pcall(vim.fn.sign_undefine, "Review_" .. name)
  end
  is_setup = false
end

---Reset signs to defaults
function M.reset()
  M.clear()
  M.setup()
end

---Get the sign name for a comment
---@param comment Review.Comment
---@return string
function M.get_sign_name(comment)
  -- AI processing/complete takes priority
  if comment.status == "ai_processing" then
    return "Review_comment_ai_processing"
  elseif comment.status == "ai_complete" then
    return "Review_comment_ai_complete"
  end

  -- Resolved threads
  if comment.resolved then
    return "Review_comment_resolved"
  end

  -- Local comments
  if comment.kind == "local" then
    if comment.status == "submitted" then
      return "Review_comment_submitted"
    else
      return "Review_comment_pending"
    end
  end

  -- GitHub comments from others
  return "Review_comment_github"
end

---Get sign definition by name
---@param name string Sign name (without "Review_" prefix)
---@return Review.SignDef?
function M.get_sign_def(name)
  local signs = get_sign_definitions()
  return signs[name]
end

---Get all sign names
---@return string[]
function M.get_sign_names()
  local names = {}
  for name, _ in pairs(get_sign_definitions()) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

---Place a sign for a comment in a buffer
---@param buf number Buffer handle
---@param comment Review.Comment
---@return number? sign_id The placed sign ID, or nil if no line
function M.place_sign(buf, comment)
  if not comment.line then
    return nil
  end

  if not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end

  -- Ensure line is a valid number
  local lnum = tonumber(comment.line)
  if not lnum or lnum < 1 then
    return nil
  end

  -- Check line is within buffer range
  local line_count = vim.api.nvim_buf_line_count(buf)
  if lnum > line_count then
    return nil
  end

  local sign_name = M.get_sign_name(comment)

  local ok, sign_id = pcall(vim.fn.sign_place, 0, SIGN_GROUP, sign_name, buf, {
    lnum = lnum,
    priority = 10,
  })

  if ok then
    return sign_id
  end
  return nil
end

---Remove a sign by ID from a buffer
---@param buf number Buffer handle
---@param sign_id number Sign ID
function M.remove_sign(buf, sign_id)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.fn.sign_unplace(SIGN_GROUP, { buffer = buf, id = sign_id })
end

---Clear all signs in a buffer
---@param buf number Buffer handle
function M.clear_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.fn.sign_unplace(SIGN_GROUP, { buffer = buf })
end

---Clear all signs in all buffers
function M.clear_all()
  vim.fn.sign_unplace(SIGN_GROUP)
end

---Refresh signs in a specific buffer for a file
---@param buf number Buffer handle
---@param file? string File path (defaults to state.current_file)
function M.refresh_buffer(buf, file)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  file = file or state.state.current_file
  if not file then
    return
  end

  -- Clear existing signs in this buffer
  M.clear_buffer(buf)

  -- Get comments for this file
  local comments = state.get_comments_for_file(file)

  -- Place signs for each comment
  for _, comment in ipairs(comments) do
    M.place_sign(buf, comment)
  end
end

---Refresh signs in the diff buffer(s)
function M.refresh()
  local file = state.state.current_file
  if not file then
    return
  end

  -- Try to get the diff buffer from layout
  local diff_buf = state.state.layout.diff_buf
  if diff_buf and vim.api.nvim_buf_is_valid(diff_buf) then
    M.refresh_buffer(diff_buf, file)
  end

  -- Also refresh current buffer if different
  local current_buf = vim.api.nvim_get_current_buf()
  if current_buf ~= diff_buf and vim.api.nvim_buf_is_valid(current_buf) then
    M.refresh_buffer(current_buf, file)
  end
end

---Get all placed signs in a buffer
---@param buf number Buffer handle
---@return table[] List of sign info tables
function M.get_signs(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return {}
  end
  return vim.fn.sign_getplaced(buf, { group = SIGN_GROUP })[1].signs or {}
end

---Get sign at a specific line in a buffer
---@param buf number Buffer handle
---@param line number Line number (1-indexed)
---@return table? Sign info or nil
function M.get_sign_at_line(buf, line)
  local signs = M.get_signs(buf)
  for _, sign in ipairs(signs) do
    if sign.lnum == line then
      return sign
    end
  end
  return nil
end

---Get all lines with signs in a buffer
---@param buf number Buffer handle
---@return number[] List of line numbers with signs
function M.get_signed_lines(buf)
  local signs = M.get_signs(buf)
  local lines = {}
  local seen = {}
  for _, sign in ipairs(signs) do
    if not seen[sign.lnum] then
      table.insert(lines, sign.lnum)
      seen[sign.lnum] = true
    end
  end
  table.sort(lines)
  return lines
end

---Count signs in a buffer
---@param buf number Buffer handle
---@return number
function M.count_signs(buf)
  return #M.get_signs(buf)
end

---Navigate to next sign in buffer
---@param buf number Buffer handle
---@param current_line number Current line number
---@param wrap? boolean Whether to wrap around (default true)
---@return number? Line number of next sign, or nil if none
function M.next_sign(buf, current_line, wrap)
  if wrap == nil then
    wrap = true
  end

  local lines = M.get_signed_lines(buf)
  if #lines == 0 then
    return nil
  end

  -- Find next line after current
  for _, line in ipairs(lines) do
    if line > current_line then
      return line
    end
  end

  -- Wrap around to first sign
  if wrap then
    return lines[1]
  end

  return nil
end

---Navigate to previous sign in buffer
---@param buf number Buffer handle
---@param current_line number Current line number
---@param wrap? boolean Whether to wrap around (default true)
---@return number? Line number of previous sign, or nil if none
function M.prev_sign(buf, current_line, wrap)
  if wrap == nil then
    wrap = true
  end

  local lines = M.get_signed_lines(buf)
  if #lines == 0 then
    return nil
  end

  -- Find previous line before current (search in reverse)
  for i = #lines, 1, -1 do
    if lines[i] < current_line then
      return lines[i]
    end
  end

  -- Wrap around to last sign
  if wrap then
    return lines[#lines]
  end

  return nil
end

return M
