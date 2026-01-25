-- Tests for review.integrations.git module
local T = MiniTest.new_set()

local git = require("review.integrations.git")

-- Helper to create a temporary git repo
local function create_test_repo()
  local tmp_dir = vim.fn.tempname()
  vim.fn.mkdir(tmp_dir, "p")

  -- Initialize git repo
  vim.fn.system({ "git", "init", tmp_dir })
  vim.fn.system({ "git", "-C", tmp_dir, "config", "user.email", "test@test.com" })
  vim.fn.system({ "git", "-C", tmp_dir, "config", "user.name", "Test User" })

  -- Create initial commit
  local file = tmp_dir .. "/test.lua"
  vim.fn.writefile({ "local M = {}", "return M" }, file)
  vim.fn.system({ "git", "-C", tmp_dir, "add", "." })
  vim.fn.system({ "git", "-C", tmp_dir, "commit", "-m", "Initial commit" })

  return tmp_dir
end

local function cleanup_repo(dir)
  vim.fn.delete(dir, "rf")
end

T["run()"] = MiniTest.new_set()

T["run()"]["executes git command and returns result"] = function()
  local result = git.run({ "version" })
  MiniTest.expect.equality(result.code, 0)
  MiniTest.expect.equality(result.stdout:match("git version") ~= nil, true)
end

T["run()"]["returns error code for invalid command"] = function()
  local result = git.run({ "invalid-command-xyz" })
  MiniTest.expect.no_equality(result.code, 0)
end

T["run()"]["accepts cwd option"] = function()
  local tmp_dir = create_test_repo()
  local result = git.run({ "status" }, { cwd = tmp_dir })
  MiniTest.expect.equality(result.code, 0)
  cleanup_repo(tmp_dir)
end

T["parse_status()"] = MiniTest.new_set()

T["parse_status()"]["parses A as added"] = function()
  MiniTest.expect.equality(git.parse_status("A"), "added")
end

T["parse_status()"]["parses M as modified"] = function()
  MiniTest.expect.equality(git.parse_status("M"), "modified")
end

T["parse_status()"]["parses D as deleted"] = function()
  MiniTest.expect.equality(git.parse_status("D"), "deleted")
end

T["parse_status()"]["parses R as renamed"] = function()
  MiniTest.expect.equality(git.parse_status("R"), "renamed")
end

T["parse_status()"]["parses C as copied"] = function()
  MiniTest.expect.equality(git.parse_status("C"), "copied")
end

T["parse_status()"]["defaults to modified for unknown"] = function()
  MiniTest.expect.equality(git.parse_status("X"), "modified")
end

T["parse_repo()"] = MiniTest.new_set()

T["parse_repo()"]["parses SSH URL with .git"] = function()
  local result = git.parse_repo("git@github.com:owner/repo.git")
  MiniTest.expect.equality(result.owner, "owner")
  MiniTest.expect.equality(result.repo, "repo")
end

T["parse_repo()"]["parses SSH URL without .git"] = function()
  local result = git.parse_repo("git@github.com:owner/repo")
  MiniTest.expect.equality(result.owner, "owner")
  MiniTest.expect.equality(result.repo, "repo")
end

T["parse_repo()"]["parses HTTPS URL with .git"] = function()
  local result = git.parse_repo("https://github.com/owner/repo.git")
  MiniTest.expect.equality(result.owner, "owner")
  MiniTest.expect.equality(result.repo, "repo")
end

T["parse_repo()"]["parses HTTPS URL without .git"] = function()
  local result = git.parse_repo("https://github.com/owner/repo")
  MiniTest.expect.equality(result.owner, "owner")
  MiniTest.expect.equality(result.repo, "repo")
end

T["parse_repo()"]["returns nil for invalid URL"] = function()
  local result = git.parse_repo("not-a-url")
  MiniTest.expect.equality(result, nil)
end

T["parse_repo()"]["falls back to remote when nil input"] = function()
  -- When nil is passed, it tries to use M.remote_url()
  -- In a git repo, this returns the repo info; outside, it returns nil
  local result = git.parse_repo(nil)
  -- Result depends on whether we're in a git repo with origin
  -- Just verify it returns a table or nil (not an error)
  MiniTest.expect.equality(result == nil or type(result) == "table", true)
end

T["parse_repo()"]["handles repos with hyphens and underscores"] = function()
  local result = git.parse_repo("git@github.com:my-org/my_repo-name.git")
  MiniTest.expect.equality(result.owner, "my-org")
  MiniTest.expect.equality(result.repo, "my_repo-name")
end

T["current_branch()"] = MiniTest.new_set()

T["current_branch()"]["returns branch name in git repo"] = function()
  local tmp_dir = create_test_repo()
  -- Save current dir and change to test repo
  local orig_dir = vim.fn.getcwd()
  vim.cmd("cd " .. tmp_dir)

  local branch = git.current_branch()
  -- Could be 'main' or 'master' depending on git config
  MiniTest.expect.equality(branch ~= "", true)

  vim.cmd("cd " .. orig_dir)
  cleanup_repo(tmp_dir)
end

T["current_commit()"] = MiniTest.new_set()

T["current_commit()"]["returns full SHA"] = function()
  local tmp_dir = create_test_repo()
  local orig_dir = vim.fn.getcwd()
  vim.cmd("cd " .. tmp_dir)

  local sha = git.current_commit()
  MiniTest.expect.equality(#sha, 40)

  vim.cmd("cd " .. orig_dir)
  cleanup_repo(tmp_dir)
end

T["current_commit()"]["returns short SHA when requested"] = function()
  local tmp_dir = create_test_repo()
  local orig_dir = vim.fn.getcwd()
  vim.cmd("cd " .. tmp_dir)

  local sha = git.current_commit(true)
  MiniTest.expect.equality(#sha >= 7 and #sha <= 40, true)

  vim.cmd("cd " .. orig_dir)
  cleanup_repo(tmp_dir)
end

T["is_git_repo()"] = MiniTest.new_set()

T["is_git_repo()"]["returns true in git repo"] = function()
  local tmp_dir = create_test_repo()
  local orig_dir = vim.fn.getcwd()
  vim.cmd("cd " .. tmp_dir)

  MiniTest.expect.equality(git.is_git_repo(), true)

  vim.cmd("cd " .. orig_dir)
  cleanup_repo(tmp_dir)
end

T["is_git_repo()"]["returns false outside git repo"] = function()
  local tmp_dir = vim.fn.tempname()
  vim.fn.mkdir(tmp_dir, "p")
  local orig_dir = vim.fn.getcwd()
  vim.cmd("cd " .. tmp_dir)

  MiniTest.expect.equality(git.is_git_repo(), false)

  vim.cmd("cd " .. orig_dir)
  vim.fn.delete(tmp_dir, "rf")
end

T["root_dir()"] = MiniTest.new_set()

T["root_dir()"]["returns repo root"] = function()
  local tmp_dir = create_test_repo()
  local orig_dir = vim.fn.getcwd()
  vim.cmd("cd " .. tmp_dir)

  local root = git.root_dir()
  -- Resolve any symlinks for comparison
  local expected = vim.fn.resolve(tmp_dir)
  local actual = vim.fn.resolve(root)
  MiniTest.expect.equality(actual, expected)

  vim.cmd("cd " .. orig_dir)
  cleanup_repo(tmp_dir)
end

T["root_dir()"]["returns nil outside git repo"] = function()
  local tmp_dir = vim.fn.tempname()
  vim.fn.mkdir(tmp_dir, "p")
  local orig_dir = vim.fn.getcwd()
  vim.cmd("cd " .. tmp_dir)

  MiniTest.expect.equality(git.root_dir(), nil)

  vim.cmd("cd " .. orig_dir)
  vim.fn.delete(tmp_dir, "rf")
end

T["ref_exists()"] = MiniTest.new_set()

T["ref_exists()"]["returns true for HEAD"] = function()
  local tmp_dir = create_test_repo()
  local orig_dir = vim.fn.getcwd()
  vim.cmd("cd " .. tmp_dir)

  MiniTest.expect.equality(git.ref_exists("HEAD"), true)

  vim.cmd("cd " .. orig_dir)
  cleanup_repo(tmp_dir)
end

T["ref_exists()"]["returns false for nonexistent ref"] = function()
  local tmp_dir = create_test_repo()
  local orig_dir = vim.fn.getcwd()
  vim.cmd("cd " .. tmp_dir)

  MiniTest.expect.equality(git.ref_exists("nonexistent-branch-xyz"), false)

  vim.cmd("cd " .. orig_dir)
  cleanup_repo(tmp_dir)
end

T["is_clean()"] = MiniTest.new_set()

T["is_clean()"]["returns true for clean repo"] = function()
  local tmp_dir = create_test_repo()
  local orig_dir = vim.fn.getcwd()
  vim.cmd("cd " .. tmp_dir)

  MiniTest.expect.equality(git.is_clean(), true)

  vim.cmd("cd " .. orig_dir)
  cleanup_repo(tmp_dir)
end

T["is_clean()"]["returns false for dirty repo"] = function()
  local tmp_dir = create_test_repo()
  local orig_dir = vim.fn.getcwd()
  vim.cmd("cd " .. tmp_dir)

  -- Create untracked file
  vim.fn.writefile({ "new content" }, tmp_dir .. "/new_file.txt")

  MiniTest.expect.equality(git.is_clean(), false)

  vim.cmd("cd " .. orig_dir)
  cleanup_repo(tmp_dir)
end

T["diff()"] = MiniTest.new_set()

T["diff()"]["returns empty string when no changes"] = function()
  local tmp_dir = create_test_repo()
  local orig_dir = vim.fn.getcwd()
  vim.cmd("cd " .. tmp_dir)

  local diff = git.diff()
  MiniTest.expect.equality(diff, "")

  vim.cmd("cd " .. orig_dir)
  cleanup_repo(tmp_dir)
end

T["diff()"]["returns diff when files changed"] = function()
  local tmp_dir = create_test_repo()
  local orig_dir = vim.fn.getcwd()
  vim.cmd("cd " .. tmp_dir)

  -- Modify file
  vim.fn.writefile({ "local M = {}", "M.x = 1", "return M" }, tmp_dir .. "/test.lua")

  local diff = git.diff()
  MiniTest.expect.equality(diff:match("diff %-%-git") ~= nil, true)
  MiniTest.expect.equality(diff:match("%+M%.x = 1") ~= nil, true)

  vim.cmd("cd " .. orig_dir)
  cleanup_repo(tmp_dir)
end

T["diff()"]["accepts base ref"] = function()
  local tmp_dir = create_test_repo()
  local orig_dir = vim.fn.getcwd()
  vim.cmd("cd " .. tmp_dir)

  -- Create a second commit
  vim.fn.writefile({ "local M = {}", "M.x = 1", "return M" }, tmp_dir .. "/test.lua")
  vim.fn.system({ "git", "-C", tmp_dir, "add", "." })
  vim.fn.system({ "git", "-C", tmp_dir, "commit", "-m", "Second commit" })

  local diff = git.diff("HEAD~1")
  MiniTest.expect.equality(diff:match("diff %-%-git") ~= nil, true)

  vim.cmd("cd " .. orig_dir)
  cleanup_repo(tmp_dir)
end

T["changed_files()"] = MiniTest.new_set()

T["changed_files()"]["returns empty list when no changes"] = function()
  local tmp_dir = create_test_repo()
  local orig_dir = vim.fn.getcwd()
  vim.cmd("cd " .. tmp_dir)

  local files = git.changed_files()
  MiniTest.expect.equality(#files, 0)

  vim.cmd("cd " .. orig_dir)
  cleanup_repo(tmp_dir)
end

T["changed_files()"]["returns list of changed files"] = function()
  local tmp_dir = create_test_repo()
  local orig_dir = vim.fn.getcwd()
  vim.cmd("cd " .. tmp_dir)

  -- Modify file
  vim.fn.writefile({ "local M = {}", "M.x = 1", "return M" }, tmp_dir .. "/test.lua")

  local files = git.changed_files()
  MiniTest.expect.equality(#files, 1)
  MiniTest.expect.equality(files[1], "test.lua")

  vim.cmd("cd " .. orig_dir)
  cleanup_repo(tmp_dir)
end

T["changed_files_with_status()"] = MiniTest.new_set()

T["changed_files_with_status()"]["returns files with status"] = function()
  local tmp_dir = create_test_repo()
  local orig_dir = vim.fn.getcwd()
  vim.cmd("cd " .. tmp_dir)

  -- Create a second commit with changes
  vim.fn.writefile({ "local M = {}", "M.x = 1", "return M" }, tmp_dir .. "/test.lua")
  vim.fn.writefile({ "new file" }, tmp_dir .. "/new.lua")
  vim.fn.system({ "git", "-C", tmp_dir, "add", "." })
  vim.fn.system({ "git", "-C", tmp_dir, "commit", "-m", "Second commit" })

  -- Now diff against HEAD~1
  local files = git.changed_files_with_status("HEAD~1")

  -- Find files
  local test_file = nil
  local new_file = nil
  for _, f in ipairs(files) do
    if f.path == "test.lua" then
      test_file = f
    elseif f.path == "new.lua" then
      new_file = f
    end
  end

  MiniTest.expect.no_equality(test_file, nil)
  MiniTest.expect.no_equality(new_file, nil)
  MiniTest.expect.equality(test_file.status, "modified")
  MiniTest.expect.equality(new_file.status, "added")

  vim.cmd("cd " .. orig_dir)
  cleanup_repo(tmp_dir)
end

T["diff_stats()"] = MiniTest.new_set()

T["diff_stats()"]["returns zero stats for no changes"] = function()
  local tmp_dir = create_test_repo()
  local orig_dir = vim.fn.getcwd()
  vim.cmd("cd " .. tmp_dir)

  local stats = git.diff_stats()
  MiniTest.expect.equality(stats.additions, 0)
  MiniTest.expect.equality(stats.deletions, 0)
  MiniTest.expect.equality(stats.files_changed, 0)

  vim.cmd("cd " .. orig_dir)
  cleanup_repo(tmp_dir)
end

T["diff_stats()"]["returns correct stats for changes"] = function()
  local tmp_dir = create_test_repo()
  local orig_dir = vim.fn.getcwd()
  vim.cmd("cd " .. tmp_dir)

  -- Modify file (add 2 lines)
  vim.fn.writefile({ "local M = {}", "M.x = 1", "M.y = 2", "return M" }, tmp_dir .. "/test.lua")

  local stats = git.diff_stats()
  MiniTest.expect.equality(stats.files_changed, 1)
  MiniTest.expect.equality(stats.additions >= 2, true)

  vim.cmd("cd " .. orig_dir)
  cleanup_repo(tmp_dir)
end

T["diff_stats_per_file()"] = MiniTest.new_set()

T["diff_stats_per_file()"]["returns per-file stats"] = function()
  local tmp_dir = create_test_repo()
  local orig_dir = vim.fn.getcwd()
  vim.cmd("cd " .. tmp_dir)

  -- Modify file
  vim.fn.writefile({ "local M = {}", "M.x = 1", "return M" }, tmp_dir .. "/test.lua")

  local stats = git.diff_stats_per_file()
  MiniTest.expect.no_equality(stats["test.lua"], nil)
  MiniTest.expect.equality(stats["test.lua"].additions >= 1, true)

  vim.cmd("cd " .. orig_dir)
  cleanup_repo(tmp_dir)
end

T["show_file()"] = MiniTest.new_set()

T["show_file()"]["returns file content at ref"] = function()
  local tmp_dir = create_test_repo()
  local orig_dir = vim.fn.getcwd()
  vim.cmd("cd " .. tmp_dir)

  local content = git.show_file("HEAD", "test.lua")
  MiniTest.expect.equality(content:match("local M = {}") ~= nil, true)

  vim.cmd("cd " .. orig_dir)
  cleanup_repo(tmp_dir)
end

T["show_file()"]["returns nil for nonexistent file"] = function()
  local tmp_dir = create_test_repo()
  local orig_dir = vim.fn.getcwd()
  vim.cmd("cd " .. tmp_dir)

  local content = git.show_file("HEAD", "nonexistent.lua")
  MiniTest.expect.equality(content, nil)

  vim.cmd("cd " .. orig_dir)
  cleanup_repo(tmp_dir)
end

T["merge_base()"] = MiniTest.new_set()

T["merge_base()"]["returns merge base commit"] = function()
  local tmp_dir = create_test_repo()
  local orig_dir = vim.fn.getcwd()
  vim.cmd("cd " .. tmp_dir)

  -- Get current branch name
  local branch = git.current_branch()
  local base = git.merge_base(branch, "HEAD")
  MiniTest.expect.no_equality(base, nil)
  MiniTest.expect.equality(#base, 40)

  vim.cmd("cd " .. orig_dir)
  cleanup_repo(tmp_dir)
end

T["checkout()"] = MiniTest.new_set()

T["checkout()"]["checks out a ref"] = function()
  local tmp_dir = create_test_repo()
  local orig_dir = vim.fn.getcwd()
  vim.cmd("cd " .. tmp_dir)

  -- Create a new branch
  vim.fn.system({ "git", "-C", tmp_dir, "branch", "test-branch" })

  local success, err = git.checkout("test-branch")
  MiniTest.expect.equality(success, true)
  MiniTest.expect.equality(err, nil)
  MiniTest.expect.equality(git.current_branch(), "test-branch")

  vim.cmd("cd " .. orig_dir)
  cleanup_repo(tmp_dir)
end

T["checkout()"]["returns error for invalid ref"] = function()
  local tmp_dir = create_test_repo()
  local orig_dir = vim.fn.getcwd()
  vim.cmd("cd " .. tmp_dir)

  local success, err = git.checkout("nonexistent-branch-xyz")
  MiniTest.expect.equality(success, false)
  MiniTest.expect.no_equality(err, nil)

  vim.cmd("cd " .. orig_dir)
  cleanup_repo(tmp_dir)
end

return T
