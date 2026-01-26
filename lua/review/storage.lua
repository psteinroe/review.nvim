-- Comment persistence for review.nvim
-- Saves comments to disk so they survive Neovim restarts
local M = {}

local data_dir = vim.fn.stdpath("data") .. "/review"

---Get the git root directory
---@return string?
local function get_git_root()
  local result = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true }):wait()
  if result.code == 0 and result.stdout then
    return vim.trim(result.stdout)
  end
  return nil
end

---Get the current git branch
---@return string?
local function get_git_branch()
  local result = vim.system({ "git", "rev-parse", "--abbrev-ref", "HEAD" }, { text = true }):wait()
  if result.code == 0 and result.stdout then
    return vim.trim(result.stdout)
  end
  return nil
end

---Hash a string to create a short identifier
---@param str string
---@return string
local function hash(str)
  local h = 0
  for i = 1, #str do
    h = ((h * 31) + string.byte(str, i)) % 2147483647
  end
  return string.format("%x", h)
end

---Sanitize a string for use in filenames
---@param str string
---@return string
local function sanitize_filename(str)
  return str:gsub("[^%w%-_]", "_")
end

---Get the storage path for current repo/branch
---@return string?
function M.get_storage_path()
  local git_root = get_git_root()
  local branch = get_git_branch()

  if not git_root or not branch then
    return nil
  end

  local safe_branch = sanitize_filename(branch)
  local project_hash = hash(git_root)

  -- Ensure directory exists
  pcall(vim.fn.mkdir, data_dir, "p")

  return string.format("%s/%s-%s.json", data_dir, project_hash, safe_branch)
end

---Get storage path for a specific PR
---@param pr_number number PR number
---@return string?
function M.get_pr_storage_path(pr_number)
  local git_root = get_git_root()

  if not git_root then
    return nil
  end

  local project_hash = hash(git_root)

  -- Ensure directory exists
  pcall(vim.fn.mkdir, data_dir, "p")

  return string.format("%s/%s-pr-%d.json", data_dir, project_hash, pr_number)
end

---@class Review.StorageData
---@field comments Review.Comment[] Stored comments
---@field metadata? {saved_at: string, version: number}

---Save comments to disk
---@param comments Review.Comment[] Comments to save
---@param path? string Override storage path
---@return boolean success
function M.save(comments, path)
  path = path or M.get_storage_path()
  if not path then
    return false
  end

  -- Only save local comments (not GitHub comments)
  local local_comments = vim.tbl_filter(function(c)
    return c.kind == "local"
  end, comments)

  -- Don't save if no local comments
  if #local_comments == 0 then
    -- Remove existing file if it exists
    pcall(os.remove, path)
    return true
  end

  ---@type Review.StorageData
  local data = {
    comments = local_comments,
    metadata = {
      saved_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
      version = 1,
    },
  }

  local ok, encoded = pcall(vim.json.encode, data)
  if not ok then
    vim.notify("Failed to encode comments for storage", vim.log.levels.ERROR)
    return false
  end

  local file = io.open(path, "w")
  if not file then
    vim.notify("Failed to open storage file for writing", vim.log.levels.ERROR)
    return false
  end

  file:write(encoded)
  file:close()

  return true
end

---Load comments from disk
---@param path? string Override storage path
---@return Review.Comment[]
function M.load(path)
  path = path or M.get_storage_path()
  if not path then
    return {}
  end

  local file = io.open(path, "r")
  if not file then
    return {}
  end

  local content = file:read("*a")
  file:close()

  if not content or content == "" then
    return {}
  end

  local ok, data = pcall(vim.json.decode, content)
  if not ok or not data then
    return {}
  end

  -- Handle both old format (array) and new format (object with comments)
  if vim.islist(data) then
    return data
  elseif data.comments then
    return data.comments
  end

  return {}
end

---Save comments for a PR
---@param pr_number number PR number
---@param comments Review.Comment[] Comments to save
---@return boolean success
function M.save_pr(pr_number, comments)
  local path = M.get_pr_storage_path(pr_number)
  return M.save(comments, path)
end

---Load comments for a PR
---@param pr_number number PR number
---@return Review.Comment[]
function M.load_pr(pr_number)
  local path = M.get_pr_storage_path(pr_number)
  return M.load(path)
end

---Clear stored comments for current branch
---@return boolean success
function M.clear()
  local path = M.get_storage_path()
  if path then
    pcall(os.remove, path)
    return true
  end
  return false
end

---Clear stored comments for a PR
---@param pr_number number PR number
---@return boolean success
function M.clear_pr(pr_number)
  local path = M.get_pr_storage_path(pr_number)
  if path then
    pcall(os.remove, path)
    return true
  end
  return false
end

---Check if there are stored comments for current branch
---@return boolean
function M.has_stored_comments()
  local path = M.get_storage_path()
  if not path then
    return false
  end

  local file = io.open(path, "r")
  if not file then
    return false
  end

  file:close()
  return true
end

---Check if there are stored comments for a PR
---@param pr_number number PR number
---@return boolean
function M.has_pr_stored_comments(pr_number)
  local path = M.get_pr_storage_path(pr_number)
  if not path then
    return false
  end

  local file = io.open(path, "r")
  if not file then
    return false
  end

  file:close()
  return true
end

---List all stored review files
---@return {path: string, branch?: string, pr?: number}[]
function M.list_stored()
  local stored = {}

  -- Check if data directory exists
  if vim.fn.isdirectory(data_dir) ~= 1 then
    return stored
  end

  local files = vim.fn.glob(data_dir .. "/*.json", false, true)
  for _, file in ipairs(files) do
    local filename = vim.fn.fnamemodify(file, ":t:r")
    local pr = filename:match("%-pr%-(%d+)$")

    if pr then
      table.insert(stored, {
        path = file,
        pr = tonumber(pr),
      })
    else
      local branch = filename:match("^[^-]+-(.+)$")
      table.insert(stored, {
        path = file,
        branch = branch,
      })
    end
  end

  return stored
end

---Get storage directory path
---@return string
function M.get_data_dir()
  return data_dir
end

return M
