-- Mock for review.integrations.git module
-- Allows testing without actual git repos
local M = {}

---@class MockGit.State
---@field current_branch string
---@field current_commit string
---@field is_git_repo boolean
---@field is_clean boolean
---@field root_dir string?
---@field remote_url string?
---@field default_branch string?
---@field files table<string, string> File path -> content mapping
---@field diff_output string
---@field changed_files string[]
---@field changed_files_status {path: string, status: string, old_path?: string}[]
---@field diff_stats {additions: number, deletions: number, files_changed: number}
---@field diff_stats_per_file table<string, {additions: number, deletions: number}>
---@field refs table<string, boolean> Which refs exist
---@field merge_bases table<string, string> "ref1..ref2" -> merge base

---@type MockGit.State
local state = {
  current_branch = "main",
  current_commit = "abc123def456abc123def456abc123def456abc1",
  is_git_repo = true,
  is_clean = true,
  root_dir = "/mock/repo",
  remote_url = "git@github.com:owner/repo.git",
  default_branch = "main",
  files = {},
  diff_output = "",
  changed_files = {},
  changed_files_status = {},
  diff_stats = { additions = 0, deletions = 0, files_changed = 0 },
  diff_stats_per_file = {},
  refs = { HEAD = true, main = true },
  merge_bases = {},
}

-- Store original module for restore
local original_git = nil

---Reset mock state to defaults
function M.reset()
  state = {
    current_branch = "main",
    current_commit = "abc123def456abc123def456abc123def456abc1",
    is_git_repo = true,
    is_clean = true,
    root_dir = "/mock/repo",
    remote_url = "git@github.com:owner/repo.git",
    default_branch = "main",
    files = {},
    diff_output = "",
    changed_files = {},
    changed_files_status = {},
    diff_stats = { additions = 0, deletions = 0, files_changed = 0 },
    diff_stats_per_file = {},
    refs = { HEAD = true, main = true },
    merge_bases = {},
  }
end

---Configure mock state
---@param opts table Partial state to merge (use vim.NIL to set nil values)
function M.setup(opts)
  if not opts then
    return
  end
  for k, v in pairs(opts) do
    -- Support setting values to nil using explicit nil in table
    state[k] = v
  end
  -- Handle explicit nil values by checking for keys that should be nil
  -- Since pairs() skips nil, we need a different approach
  -- Allow passing vim.NIL to represent nil
  for k, v in pairs(opts) do
    if v == vim.NIL then
      state[k] = nil
    end
  end
end

---Get current mock state (for assertions)
---@return MockGit.State
function M.get_state()
  return vim.deepcopy(state)
end

-- Mock implementations matching git.lua interface

---@class Review.GitResult
---@field stdout string
---@field stderr string
---@field code number

---Mock run - returns preconfigured results based on args
---@param args string[]
---@param opts? {cwd?: string, timeout?: number}
---@return Review.GitResult
function M.run(args, opts)
  -- Default success response
  local result = { stdout = "", stderr = "", code = 0 }

  local cmd = args[1]

  if cmd == "version" then
    result.stdout = "git version 2.40.0"
  elseif cmd == "branch" and args[2] == "--show-current" then
    result.stdout = state.current_branch .. "\n"
  elseif cmd == "rev-parse" then
    if args[2] == "--show-toplevel" then
      if state.root_dir then
        result.stdout = state.root_dir .. "\n"
      else
        result.code = 128
        result.stderr = "fatal: not a git repository"
      end
    elseif args[2] == "--is-inside-work-tree" then
      if state.is_git_repo then
        result.stdout = "true\n"
      else
        result.code = 128
        result.stderr = "fatal: not a git repository"
      end
    elseif args[2] == "--verify" then
      local ref = args[4] or args[3]
      if state.refs[ref] then
        result.stdout = state.current_commit .. "\n"
      else
        result.code = 128
        result.stderr = "fatal: Needed a single revision"
      end
    elseif args[2] == "--short" then
      result.stdout = state.current_commit:sub(1, 7) .. "\n"
    elseif args[2] == "HEAD" then
      result.stdout = state.current_commit .. "\n"
    end
  elseif cmd == "status" and args[2] == "--porcelain" then
    if state.is_clean then
      result.stdout = ""
    else
      result.stdout = "M file.lua\n"
    end
  elseif cmd == "remote" and args[2] == "get-url" then
    if state.remote_url then
      result.stdout = state.remote_url .. "\n"
    else
      result.code = 2
      result.stderr = "fatal: No such remote 'origin'"
    end
  elseif cmd == "diff" then
    if vim.tbl_contains(args, "--name-only") then
      result.stdout = table.concat(state.changed_files, "\n")
      if #state.changed_files > 0 then
        result.stdout = result.stdout .. "\n"
      end
    elseif vim.tbl_contains(args, "--name-status") then
      local lines = {}
      for _, f in ipairs(state.changed_files_status) do
        local status_char = ({
          added = "A",
          modified = "M",
          deleted = "D",
          renamed = "R100",
          copied = "C",
        })[f.status] or "M"
        if f.old_path then
          table.insert(lines, status_char .. "\t" .. f.old_path .. "\t" .. f.path)
        else
          table.insert(lines, status_char .. "\t" .. f.path)
        end
      end
      result.stdout = table.concat(lines, "\n")
      if #lines > 0 then
        result.stdout = result.stdout .. "\n"
      end
    elseif vim.tbl_contains(args, "--shortstat") then
      if state.diff_stats.files_changed > 0 then
        result.stdout = string.format(
          " %d files changed, %d insertions(+), %d deletions(-)\n",
          state.diff_stats.files_changed,
          state.diff_stats.additions,
          state.diff_stats.deletions
        )
      else
        result.stdout = ""
      end
    elseif vim.tbl_contains(args, "--numstat") then
      local lines = {}
      for path, stats in pairs(state.diff_stats_per_file) do
        table.insert(lines, string.format("%d\t%d\t%s", stats.additions, stats.deletions, path))
      end
      result.stdout = table.concat(lines, "\n")
      if #lines > 0 then
        result.stdout = result.stdout .. "\n"
      end
    else
      result.stdout = state.diff_output
    end
  elseif cmd == "show" then
    local ref_path = args[2]
    if ref_path then
      local _, _, path = ref_path:find("^[^:]+:(.+)$")
      if path and state.files[path] then
        result.stdout = state.files[path]
      else
        result.code = 128
        result.stderr = "fatal: path not found"
      end
    end
  elseif cmd == "symbolic-ref" then
    if state.default_branch then
      result.stdout = "origin/" .. state.default_branch .. "\n"
    else
      result.code = 128
      result.stderr = "fatal: ref not found"
    end
  elseif cmd == "merge-base" then
    local key = args[2] .. ".." .. args[3]
    if state.merge_bases[key] then
      result.stdout = state.merge_bases[key] .. "\n"
    else
      result.stdout = state.current_commit .. "\n"
    end
  elseif cmd == "fetch" then
    result.stdout = ""
  elseif cmd == "checkout" then
    local ref = args[2]
    if state.refs[ref] then
      state.current_branch = ref
      result.stdout = ""
    else
      result.code = 1
      result.stderr = "error: pathspec '" .. ref .. "' did not match any file(s) known to git"
    end
  else
    -- Unknown command - return success with empty output
    result.stdout = ""
  end

  return result
end

---Mock run_async - calls callback with mock result
---@param args string[]
---@param opts? {cwd?: string, timeout?: number}
---@param callback fun(result: Review.GitResult)
function M.run_async(args, opts, callback)
  vim.schedule(function()
    callback(M.run(args, opts))
  end)
end

---Mock diff
---@param base? string
---@param head? string
---@param file? string
---@return string
function M.diff(base, head, file)
  return state.diff_output
end

---Mock changed_files
---@param base? string
---@param head? string
---@return string[]
function M.changed_files(base, head)
  return vim.deepcopy(state.changed_files)
end

---Mock changed_files_with_status
---@param base? string
---@param head? string
---@return {path: string, status: string, old_path?: string}[]
function M.changed_files_with_status(base, head)
  return vim.deepcopy(state.changed_files_status)
end

---Mock parse_status
---@param status string
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

---Mock diff_stats
---@param base? string
---@param head? string
---@return {additions: number, deletions: number, files_changed: number}
function M.diff_stats(base, head)
  return vim.deepcopy(state.diff_stats)
end

---Mock diff_stats_per_file
---@param base? string
---@param head? string
---@return table<string, {additions: number, deletions: number}>
function M.diff_stats_per_file(base, head)
  return vim.deepcopy(state.diff_stats_per_file)
end

---Mock current_branch
---@return string
function M.current_branch()
  return state.current_branch
end

---Mock current_commit
---@param short? boolean
---@return string
function M.current_commit(short)
  if short then
    return state.current_commit:sub(1, 7)
  end
  return state.current_commit
end

---Mock remote_url
---@param remote? string
---@return string?
function M.remote_url(remote)
  return state.remote_url
end

---Mock parse_repo
---@param url? string
---@return {owner: string, repo: string}?
function M.parse_repo(url)
  url = url or state.remote_url
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

---Mock show_file
---@param ref string
---@param path string
---@return string?
function M.show_file(ref, path)
  return state.files[path]
end

---Mock ref_exists
---@param ref string
---@return boolean
function M.ref_exists(ref)
  return state.refs[ref] == true
end

---Mock merge_base
---@param ref1 string
---@param ref2 string
---@return string?
function M.merge_base(ref1, ref2)
  local key = ref1 .. ".." .. ref2
  return state.merge_bases[key] or state.current_commit
end

---Mock is_clean
---@return boolean
function M.is_clean()
  return state.is_clean
end

---Mock root_dir
---@return string?
function M.root_dir()
  return state.root_dir
end

---Mock is_git_repo
---@return boolean
function M.is_git_repo()
  return state.is_git_repo
end

---Mock default_branch
---@return string?
function M.default_branch()
  return state.default_branch
end

---Mock fetch
---@param remote? string
---@param opts? {prune?: boolean}
---@return boolean
function M.fetch(remote, opts)
  return true
end

---Mock checkout
---@param ref string
---@return boolean success
---@return string? error
function M.checkout(ref)
  if state.refs[ref] then
    state.current_branch = ref
    return true, nil
  end
  return false, "error: pathspec '" .. ref .. "' did not match"
end

-- Module injection helpers

---Install mock into package.loaded, storing original
function M.install()
  original_git = package.loaded["review.integrations.git"]
  package.loaded["review.integrations.git"] = M
end

---Restore original git module
function M.restore()
  if original_git then
    package.loaded["review.integrations.git"] = original_git
    original_git = nil
  else
    package.loaded["review.integrations.git"] = nil
  end
  M.reset()
end

return M
