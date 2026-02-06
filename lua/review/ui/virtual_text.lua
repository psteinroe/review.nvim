-- Virtual text (inline comment previews) for review.nvim
local M = {}

local state = require("review.core.state")
local utils = require("review.utils")

-- Namespace for virtual text extmarks
local ns_id = vim.api.nvim_create_namespace("review_virtual_text")

---@class Review.VirtualTextConfig
---@field enabled boolean Whether virtual text is enabled
---@field max_length number Maximum length of preview text
---@field position "eol" | "overlay" | "right_align" Position of virtual text

---Get default config for virtual text
---@return Review.VirtualTextConfig
local function get_config()
  local config = require("review.config")
  local cfg = config.config.virtual_text or {}
  return {
    enabled = cfg.enabled ~= false, -- Default to true
    max_length = cfg.max_length or 40,
    position = cfg.position or "eol",
  }
end

---Get the namespace ID
---@return number
function M.get_namespace()
  return ns_id
end

---Get status info for a comment
---@param comment Review.Comment
---@return string sign, string highlight, string status_label
function M.get_status_info(comment)
  -- AI processing takes priority
  if comment.status == "ai_processing" then
    return "●", "ReviewVirtualAI", "processing"
  end
  if comment.status == "ai_complete" then
    return "○", "ReviewVirtualSubmitted", "complete"
  end

  -- Resolved threads
  if comment.resolved then
    return "◆", "ReviewVirtualResolved", "resolved"
  end

  -- Local comments
  if comment.kind == "local" then
    if comment.status == "submitted" then
      return "○", "ReviewVirtualSubmitted", ""
    else
      return "●", "ReviewVirtualPending", "pending"
    end
  end

  -- GitHub comments from others
  return "◇", "ReviewVirtualGithub", ""
end

---Truncate text for display
---@param text string Text to truncate
---@param max_len number Maximum length
---@return string
function M.truncate(text, max_len)
  if not text then
    return ""
  end
  -- Replace newlines with spaces
  text = text:gsub("\n", " ")
  -- Collapse multiple spaces
  text = text:gsub("%s+", " ")
  -- Trim leading/trailing whitespace
  text = text:match("^%s*(.-)%s*$") or ""

  if #text > max_len then
    return text:sub(1, max_len - 3) .. "..."
  end
  return text
end

---Format virtual text for a comment
---@param comment Review.Comment
---@param max_len? number Maximum text length
---@return string formatted_text
---@return string highlight_group
function M.format_virtual_text(comment, max_len)
  local cfg = get_config()
  max_len = max_len or cfg.max_length

  local sign, hl, status_label = M.get_status_info(comment)
  local preview = M.truncate(comment.body, max_len)

  -- Build the virtual text string
  local parts = { sign }

  -- Add status label if present
  if status_label ~= "" then
    table.insert(parts, "[" .. status_label .. "]")
  end

  -- Add author
  local author = comment.author or "you"
  if author == "you" then
    table.insert(parts, "you:")
  else
    table.insert(parts, "@" .. author .. ":")
  end

  -- Add preview text
  if preview ~= "" then
    table.insert(parts, preview)
  end

  return table.concat(parts, " "), hl
end

---Add virtual text for a single comment
---@param buf number Buffer handle
---@param comment Review.Comment
---@return number? extmark_id The extmark ID, or nil if failed
function M.add_virtual_text(buf, comment)
  if type(comment.line) ~= "number" then
    return nil
  end

  if not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end

  local cfg = get_config()
  if not cfg.enabled then
    return nil
  end

  -- Get the line count to validate the line number
  local line_count = vim.api.nvim_buf_line_count(buf)
  local line_num = type(comment.line) == "number" and comment.line or nil
  if not line_num or line_num < 1 or line_num > line_count then
    return nil
  end

  local text, hl = M.format_virtual_text(comment, cfg.max_length)

  local extmark_id = vim.api.nvim_buf_set_extmark(buf, ns_id, line_num - 1, 0, {
    virt_text = { { " " .. text, hl } },
    virt_text_pos = cfg.position,
    hl_mode = "combine",
  })

  return extmark_id
end

---Remove virtual text by extmark ID
---@param buf number Buffer handle
---@param extmark_id number Extmark ID
function M.remove_virtual_text(buf, extmark_id)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  pcall(vim.api.nvim_buf_del_extmark, buf, ns_id, extmark_id)
end

---Clear all virtual text in a buffer
---@param buf number Buffer handle
function M.clear_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
end

---Clear all virtual text in all buffers
function M.clear_all()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      M.clear_buffer(buf)
    end
  end
end

---Refresh virtual text in a specific buffer for a file
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

  -- Clear existing virtual text in this buffer
  M.clear_buffer(buf)

  local cfg = get_config()
  if not cfg.enabled then
    return
  end

  -- Get comments for this file
  local comments = state.get_comments_for_file(file)

  -- Group comments by line (show only the first comment per line as virtual text)
  local comments_by_line = {}
  for _, comment in ipairs(comments) do
    if type(comment.line) == "number" then
      if not comments_by_line[comment.line] then
        comments_by_line[comment.line] = comment
      end
    end
  end

  -- Add virtual text for each line with comments
  for _, comment in pairs(comments_by_line) do
    M.add_virtual_text(buf, comment)
  end
end

---Refresh virtual text in the diff buffer(s)
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

---Get all extmarks in a buffer
---@param buf number Buffer handle
---@return table[] List of extmark info {id, row, col, details}
function M.get_extmarks(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return {}
  end
  return vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, { details = true })
end

---Get extmark at a specific line in a buffer
---@param buf number Buffer handle
---@param line number Line number (1-indexed)
---@return table? Extmark info or nil
function M.get_extmark_at_line(buf, line)
  if not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end

  local extmarks = vim.api.nvim_buf_get_extmarks(
    buf,
    ns_id,
    { line - 1, 0 },
    { line - 1, -1 },
    { details = true }
  )

  if #extmarks > 0 then
    return extmarks[1]
  end
  return nil
end

---Count virtual text extmarks in a buffer
---@param buf number Buffer handle
---@return number
function M.count_extmarks(buf)
  return #M.get_extmarks(buf)
end

---Check if virtual text is enabled
---@return boolean
function M.is_enabled()
  return get_config().enabled
end

---Enable virtual text
function M.enable()
  local config = require("review.config")
  config.config.virtual_text = config.config.virtual_text or {}
  config.config.virtual_text.enabled = true
  M.refresh()
end

---Disable virtual text
function M.disable()
  local config = require("review.config")
  config.config.virtual_text = config.config.virtual_text or {}
  config.config.virtual_text.enabled = false
  M.clear_all()
end

---Toggle virtual text
function M.toggle()
  if M.is_enabled() then
    M.disable()
  else
    M.enable()
  end
end

---Get all lines with virtual text in a buffer
---@param buf number Buffer handle
---@return number[] List of line numbers (1-indexed) with virtual text
function M.get_virtual_text_lines(buf)
  local extmarks = M.get_extmarks(buf)
  local lines = {}
  local seen = {}
  for _, extmark in ipairs(extmarks) do
    local line = extmark[2] + 1 -- Convert 0-indexed to 1-indexed
    if not seen[line] then
      table.insert(lines, line)
      seen[line] = true
    end
  end
  table.sort(lines)
  return lines
end

---Update virtual text for a single comment (after edit)
---@param buf number Buffer handle
---@param comment Review.Comment
function M.update_comment(buf, comment)
  local line_num = type(comment.line) == "number" and comment.line or nil
  if not line_num then
    return
  end

  -- Remove existing virtual text at this line
  local existing = M.get_extmark_at_line(buf, line_num)
  if existing then
    M.remove_virtual_text(buf, existing[1])
  end

  -- Add new virtual text
  M.add_virtual_text(buf, comment)
end

return M
