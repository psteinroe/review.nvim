---@class Review.GitResult
---@field stdout string
---@field stderr string
---@field code number

local M = {}

---Run git command synchronously
---@param args string[] Git arguments
---@param opts? {cwd?: string, timeout?: number}
---@return Review.GitResult
function M.run(args, opts)
  opts = opts or {}
  local cmd = vim.list_extend({ "git" }, args)
  local result = vim.system(cmd, {
    text = true,
    cwd = opts.cwd,
    timeout = opts.timeout,
  }):wait()
  return {
    stdout = result.stdout or "",
    stderr = result.stderr or "",
    code = result.code or -1,
  }
end

---Run git command asynchronously
---@param args string[] Git arguments
---@param opts? {cwd?: string, timeout?: number}
---@param callback fun(result: Review.GitResult)
function M.run_async(args, opts, callback)
  opts = opts or {}
  local cmd = vim.list_extend({ "git" }, args)
  vim.system(cmd, {
    text = true,
    cwd = opts.cwd,
    timeout = opts.timeout,
  }, function(result)
    vim.schedule(function()
      callback({
        stdout = result.stdout or "",
        stderr = result.stderr or "",
        code = result.code or -1,
      })
    end)
  end)
end

---Get diff between refs
---@param base? string Base ref (branch/commit)
---@param head? string Head ref (defaults to working tree)
---@param file? string Optional specific file
---@return string diff output
function M.diff(base, head, file)
  local args = { "diff" }
  if base then
    table.insert(args, base)
  end
  if head then
    table.insert(args, head)
  end
  if file then
    table.insert(args, "--")
    table.insert(args, file)
  end
  -- Use git root directory to ensure we're in the right place
  local root = M.root_dir()
  local result = M.run(args, { cwd = root })
  return result.stdout
end

---Get list of changed files between refs
---@param base? string Base ref
---@param head? string Head ref
---@return string[] List of file paths
function M.changed_files(base, head)
  local args = { "diff", "--name-only" }
  if base then
    table.insert(args, base)
  end
  if head then
    table.insert(args, head)
  end
  local root = M.root_dir()
  local result = M.run(args, { cwd = root })
  return vim.split(result.stdout, "\n", { trimempty = true })
end

---Get list of untracked files
---@return string[] List of untracked file paths
function M.get_untracked_files()
  local root = M.root_dir()
  local result = M.run({ "ls-files", "--others", "--exclude-standard" }, { cwd = root })
  if result.code ~= 0 then
    return {}
  end
  return vim.split(result.stdout, "\n", { trimempty = true })
end

---Get diff with file status (added, modified, deleted, renamed)
---@param base? string Base ref
---@param head? string Head ref
---@param opts? {include_untracked?: boolean}
---@return {path: string, status: string, old_path?: string}[]
function M.changed_files_with_status(base, head, opts)
  opts = opts or {}
  local args = { "diff", "--name-status" }
  if base then
    table.insert(args, base)
  end
  if head then
    table.insert(args, head)
  end
  local result = M.run(args)
  local files = {}
  local seen = {}

  for line in result.stdout:gmatch("[^\n]+") do
    local status, path, old_path = line:match("^([AMDRC])%d*%s+(.+)$")
    if not status then
      -- Handle renames: R100\toldpath\tnewpath
      status, old_path, path = line:match("^(R)%d*%s+(.+)%s+(.+)$")
    end

    if status and path then
      local file = {
        path = path,
        status = M.parse_status(status),
      }
      if old_path and status == "R" then
        file.old_path = old_path
      end
      table.insert(files, file)
      seen[path] = true
    end
  end

  -- Include untracked files as "added"
  if opts.include_untracked then
    local untracked = M.get_untracked_files()
    for _, path in ipairs(untracked) do
      if not seen[path] then
        table.insert(files, {
          path = path,
          status = "added",
        })
      end
    end
  end

  return files
end

---Parse single-letter git status to human-readable
---@param status string Single letter status (A, M, D, R, C)
---@return "added"|"modified"|"deleted"|"renamed"|"copied"
function M.parse_status(status)
  local map = {
    A = "added",
    M = "modified",
    D = "deleted",
    R = "renamed",
    C = "copied",
  }
  return map[status] or "modified"
end

---Get diff stats (additions/deletions)
---@param base? string Base ref
---@param head? string Head ref
---@return {additions: number, deletions: number, files_changed: number}
function M.diff_stats(base, head)
  local args = { "diff", "--shortstat" }
  if base then
    table.insert(args, base)
  end
  if head then
    table.insert(args, head)
  end
  local result = M.run(args)

  local stats = { additions = 0, deletions = 0, files_changed = 0 }

  -- Parse: " 3 files changed, 10 insertions(+), 5 deletions(-)"
  local files = result.stdout:match("(%d+) files? changed")
  local insertions = result.stdout:match("(%d+) insertions?")
  local deletions = result.stdout:match("(%d+) deletions?")

  stats.files_changed = tonumber(files) or 0
  stats.additions = tonumber(insertions) or 0
  stats.deletions = tonumber(deletions) or 0

  return stats
end

---Get per-file diff stats
---@param base? string Base ref
---@param head? string Head ref
---@return {[string]: {additions: number, deletions: number}}
function M.diff_stats_per_file(base, head)
  local args = { "diff", "--numstat" }
  if base then
    table.insert(args, base)
  end
  if head then
    table.insert(args, head)
  end
  local result = M.run(args)

  local stats = {}
  -- Parse: "10\t5\tpath/to/file"
  for line in result.stdout:gmatch("[^\n]+") do
    local add, del, path = line:match("^(%d+)%s+(%d+)%s+(.+)$")
    if add and del and path then
      stats[path] = {
        additions = tonumber(add) or 0,
        deletions = tonumber(del) or 0,
      }
    end
  end

  return stats
end

---Get current branch name
---@return string Branch name (empty if detached HEAD)
function M.current_branch()
  local result = M.run({ "branch", "--show-current" })
  return vim.trim(result.stdout)
end

---Get current commit SHA
---@param short? boolean Return short SHA (default: false)
---@return string Commit SHA
function M.current_commit(short)
  local args = { "rev-parse" }
  if short then
    table.insert(args, "--short")
  end
  table.insert(args, "HEAD")
  local result = M.run(args)
  return vim.trim(result.stdout)
end

---Get remote URL for a remote
---@param remote? string Remote name (default: "origin")
---@return string? URL or nil if not found
function M.remote_url(remote)
  remote = remote or "origin"
  local result = M.run({ "remote", "get-url", remote })
  if result.code == 0 then
    return vim.trim(result.stdout)
  end
  return nil
end

---Parse owner/repo from GitHub remote URL
---@param url? string URL to parse (defaults to origin remote)
---@return {owner: string, repo: string}? Parsed repo info or nil
function M.parse_repo(url)
  url = url or M.remote_url()
  if not url then
    return nil
  end

  -- Handle SSH format: git@github.com:owner/repo.git
  local owner, repo = url:match("git@github%.com:([^/]+)/([^/%.]+)")
  if owner and repo then
    return { owner = owner, repo = repo }
  end

  -- Handle HTTPS format: https://github.com/owner/repo.git
  owner, repo = url:match("github%.com/([^/]+)/([^/%.]+)")
  if owner and repo then
    return { owner = owner, repo = repo }
  end

  return nil
end

---Get file content at a specific ref
---@param ref string Git ref (branch, commit, tag)
---@param path string File path
---@return string? content File content or nil if not found
function M.show_file(ref, path)
  local result = M.run({ "show", ref .. ":" .. path })
  if result.code == 0 then
    return result.stdout
  end
  return nil
end

---Check if a ref exists
---@param ref string Git ref to check
---@return boolean
function M.ref_exists(ref)
  local result = M.run({ "rev-parse", "--verify", "--quiet", ref })
  return result.code == 0
end

---Get the merge base between two refs
---@param ref1 string First ref
---@param ref2 string Second ref
---@return string? Merge base commit or nil
function M.merge_base(ref1, ref2)
  local result = M.run({ "merge-base", ref1, ref2 })
  if result.code == 0 then
    return vim.trim(result.stdout)
  end
  return nil
end

---Check if working tree is clean
---@return boolean
function M.is_clean()
  local result = M.run({ "status", "--porcelain" })
  return result.code == 0 and vim.trim(result.stdout) == ""
end

---Get the root directory of the git repository
---@param path? string Optional path to start searching from (defaults to current buffer or cwd)
---@return string? Root path or nil if not in a git repo
function M.root_dir(path)
  -- Try to get path from current buffer if not provided
  if not path then
    local bufname = vim.api.nvim_buf_get_name(0)
    if bufname and bufname ~= "" then
      -- Handle special buffer types (oil.nvim, fugitive, etc.)
      -- oil:///path/to/dir -> /path/to/dir
      -- fugitive:///path/.git//... -> /path
      if bufname:match("^%w+://") then
        -- Extract path from URL-like buffer names
        local extracted = bufname:match("^%w+://(.+)$")
        if extracted then
          -- Remove any trailing git-specific paths for fugitive
          extracted = extracted:gsub("%.git//.*$", "")
          path = extracted
        end
      else
        path = vim.fn.fnamemodify(bufname, ":h")
      end
    end
  end

  -- Fallback to cwd if path is still nil or invalid
  -- Note: vim.fn.isdirectory returns 0 or 1, and in Lua 0 is truthy
  if not path or path == "" or vim.fn.isdirectory(path) ~= 1 then
    path = vim.fn.getcwd()
  end

  -- Run git rev-parse from the detected path
  local result = M.run({ "rev-parse", "--show-toplevel" }, { cwd = path })
  if result.code == 0 then
    return vim.trim(result.stdout)
  end
  return nil
end

---Check if current directory is inside a git repository
---@param path? string Optional path to check
---@return boolean
function M.is_git_repo(path)
  -- Try to get path from current buffer if not provided
  if not path then
    local bufname = vim.api.nvim_buf_get_name(0)
    if bufname and bufname ~= "" then
      -- Handle special buffer types (oil.nvim, fugitive, etc.)
      if bufname:match("^%w+://") then
        local extracted = bufname:match("^%w+://(.+)$")
        if extracted then
          extracted = extracted:gsub("%.git//.*$", "")
          path = extracted
        end
      else
        path = vim.fn.fnamemodify(bufname, ":h")
      end
    end
  end

  -- Fallback to cwd if path is still nil or invalid
  -- Note: vim.fn.isdirectory returns 0 or 1, and in Lua 0 is truthy
  if not path or path == "" or vim.fn.isdirectory(path) ~= 1 then
    path = vim.fn.getcwd()
  end

  local result = M.run({ "rev-parse", "--is-inside-work-tree" }, { cwd = path })
  return result.code == 0 and vim.trim(result.stdout) == "true"
end

---Get default branch name
---@return string? Default branch name or nil
function M.default_branch()
  -- Try to get from remote HEAD
  local result = M.run({ "symbolic-ref", "refs/remotes/origin/HEAD", "--short" })
  if result.code == 0 then
    local branch = vim.trim(result.stdout)
    -- Remove "origin/" prefix
    return branch:gsub("^origin/", "")
  end

  -- Fallback: check common names
  for _, name in ipairs({ "main", "master" }) do
    if M.ref_exists("refs/heads/" .. name) then
      return name
    end
  end

  return nil
end

---Fetch from remote
---@param remote? string Remote name (default: "origin")
---@param opts? {prune?: boolean}
---@return boolean success
function M.fetch(remote, opts)
  remote = remote or "origin"
  opts = opts or {}
  local args = { "fetch", remote }
  if opts.prune then
    table.insert(args, "--prune")
  end
  local result = M.run(args)
  return result.code == 0
end

---Checkout a ref
---@param ref string Ref to checkout
---@return boolean success
---@return string? error Error message if failed
function M.checkout(ref)
  local result = M.run({ "checkout", ref })
  if result.code == 0 then
    return true, nil
  end
  return false, vim.trim(result.stderr)
end

---Get list of staged files
---@return string[] List of staged file paths
function M.get_staged_files()
  local root = M.root_dir()
  local result = M.run({ "diff", "--cached", "--name-only" }, { cwd = root })
  if result.code ~= 0 then
    return {}
  end
  return vim.split(result.stdout, "\n", { trimempty = true })
end

---Check if a file is staged
---@param path string File path (relative to git root)
---@return boolean
function M.is_staged(path)
  local staged = M.get_staged_files()
  for _, file in ipairs(staged) do
    if file == path then
      return true
    end
  end
  return false
end

---Stage a file
---@param path string File path (relative to git root)
---@return boolean success
---@return string? error Error message if failed
function M.stage_file(path)
  local root = M.root_dir()
  local result = M.run({ "add", "--", path }, { cwd = root })
  if result.code == 0 then
    return true, nil
  end
  return false, vim.trim(result.stderr)
end

---Unstage a file
---@param path string File path (relative to git root)
---@return boolean success
---@return string? error Error message if failed
function M.unstage_file(path)
  local root = M.root_dir()
  local result = M.run({ "reset", "HEAD", "--", path }, { cwd = root })
  if result.code == 0 then
    return true, nil
  end
  return false, vim.trim(result.stderr)
end

return M
