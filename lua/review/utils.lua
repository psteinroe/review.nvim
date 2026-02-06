local M = {}

---Debounce a function call
---@param fn function Function to debounce
---@param ms number Milliseconds to wait
---@return function Debounced function
function M.debounce(fn, ms)
  local timer = nil
  return function(...)
    local args = { ... }
    if timer then
      timer:stop()
    end
    timer = vim.defer_fn(function()
      fn(unpack(args))
    end, ms)
  end
end

---Get relative time string from ISO timestamp
---@param iso_time string|nil ISO 8601 timestamp
---@return string Relative time (e.g., "2 hours ago", "yesterday")
function M.relative_time(iso_time)
  -- Handle nil, empty, or non-string values (e.g., vim.NIL from JSON)
  if not iso_time or type(iso_time) ~= "string" or iso_time == "" then
    return "unknown"
  end

  -- Parse ISO timestamp: 2024-01-15T10:30:00Z
  local year, month, day, hour, min, sec = iso_time:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not year then
    return iso_time
  end

  local timestamp = os.time({
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = tonumber(hour),
    min = tonumber(min),
    sec = tonumber(sec),
  })

  local diff = os.time() - timestamp
  if diff < 0 then
    return "in the future"
  elseif diff < 60 then
    return "just now"
  elseif diff < 3600 then
    local mins = math.floor(diff / 60)
    return mins == 1 and "1 minute ago" or mins .. " minutes ago"
  elseif diff < 86400 then
    local hours = math.floor(diff / 3600)
    return hours == 1 and "1 hour ago" or hours .. " hours ago"
  elseif diff < 172800 then
    return "yesterday"
  elseif diff < 604800 then
    local days = math.floor(diff / 86400)
    return days .. " days ago"
  elseif diff < 2592000 then
    local weeks = math.floor(diff / 604800)
    return weeks == 1 and "1 week ago" or weeks .. " weeks ago"
  else
    local months = math.floor(diff / 2592000)
    return months == 1 and "1 month ago" or months .. " months ago"
  end
end

---Truncate string with ellipsis
---@param str string String to truncate
---@param max_len number Maximum length
---@return string Truncated string
function M.truncate(str, max_len)
  -- Handle nil, vim.NIL (userdata), and non-string values
  if not str or type(str) ~= "string" then
    return ""
  end
  str = str:gsub("\n", " ") -- Replace newlines with spaces
  if #str > max_len then
    return str:sub(1, max_len - 3) .. "..."
  end
  return str
end

---Normalize file path (remove leading ./ etc)
---@param path string File path
---@return string Normalized path
function M.normalize_path(path)
  -- First collapse multiple slashes, then remove leading ./
  path = path:gsub("//+", "/") -- Collapse multiple slashes
  path = path:gsub("^%./", "") -- Remove leading ./
  return path
end

---Check if a buffer is valid and loaded
---@param buf number Buffer handle
---@return boolean
function M.is_valid_buf(buf)
  if not buf then
    return false
  end
  return vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf)
end

---Check if a window is valid
---@param win number Window handle
---@return boolean
function M.is_valid_win(win)
  if not win then
    return false
  end
  return vim.api.nvim_win_is_valid(win)
end

---Safe require with fallback
---@param module string Module name
---@return any? module Module or nil
---@return string? error Error message if failed
function M.safe_require(module)
  local ok, result = pcall(require, module)
  if ok then
    return result, nil
  else
    return nil, result
  end
end

---Create a unique ID
---@param prefix? string Optional prefix
---@return string
function M.generate_id(prefix)
  prefix = prefix or "id"
  return string.format("%s_%d_%d", prefix, os.time(), math.random(10000, 99999))
end

return M
