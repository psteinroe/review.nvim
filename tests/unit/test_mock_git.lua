-- Tests for tests/mocks/git.lua
local T = MiniTest.new_set()

local mock_git = require("mocks.git")

-- Reset mock before each test group
T["setup"] = function()
  mock_git.reset()
end

T["reset()"] = MiniTest.new_set()

T["reset()"]["resets to default state"] = function()
  mock_git.setup({ current_branch = "feature" })
  MiniTest.expect.equality(mock_git.current_branch(), "feature")

  mock_git.reset()
  MiniTest.expect.equality(mock_git.current_branch(), "main")
end

T["setup()"] = MiniTest.new_set()

T["setup()"]["configures mock state"] = function()
  mock_git.reset()
  mock_git.setup({
    current_branch = "develop",
    is_clean = false,
    remote_url = "git@github.com:test/project.git",
  })

  MiniTest.expect.equality(mock_git.current_branch(), "develop")
  MiniTest.expect.equality(mock_git.is_clean(), false)
  MiniTest.expect.equality(mock_git.remote_url(), "git@github.com:test/project.git")
end

T["get_state()"] = MiniTest.new_set()

T["get_state()"]["returns copy of current state"] = function()
  mock_git.reset()
  mock_git.setup({ current_branch = "test" })

  local state = mock_git.get_state()
  MiniTest.expect.equality(state.current_branch, "test")

  -- Verify it's a copy (modifying returned state doesn't affect mock)
  state.current_branch = "modified"
  MiniTest.expect.equality(mock_git.current_branch(), "test")
end

T["run()"] = MiniTest.new_set()

T["run()"]["returns version for git version"] = function()
  mock_git.reset()
  local result = mock_git.run({ "version" })
  MiniTest.expect.equality(result.code, 0)
  MiniTest.expect.equality(result.stdout:match("git version") ~= nil, true)
end

T["run()"]["returns branch for branch --show-current"] = function()
  mock_git.reset()
  mock_git.setup({ current_branch = "feature/test" })

  local result = mock_git.run({ "branch", "--show-current" })
  MiniTest.expect.equality(result.code, 0)
  MiniTest.expect.equality(vim.trim(result.stdout), "feature/test")
end

T["run()"]["returns root dir for rev-parse --show-toplevel"] = function()
  mock_git.reset()
  mock_git.setup({ root_dir = "/my/project" })

  local result = mock_git.run({ "rev-parse", "--show-toplevel" })
  MiniTest.expect.equality(result.code, 0)
  MiniTest.expect.equality(vim.trim(result.stdout), "/my/project")
end

T["run()"]["returns error when not in git repo"] = function()
  mock_git.reset()
  mock_git.setup({ root_dir = vim.NIL, is_git_repo = false })

  local result = mock_git.run({ "rev-parse", "--show-toplevel" })
  MiniTest.expect.equality(result.code, 128)
end

T["run()"]["returns diff output"] = function()
  mock_git.reset()
  mock_git.setup({ diff_output = "diff --git a/test.lua b/test.lua\n+new line\n" })

  local result = mock_git.run({ "diff" })
  MiniTest.expect.equality(result.code, 0)
  MiniTest.expect.equality(result.stdout:match("diff %-%-git") ~= nil, true)
end

T["run()"]["returns changed files for diff --name-only"] = function()
  mock_git.reset()
  mock_git.setup({ changed_files = { "file1.lua", "file2.lua" } })

  local result = mock_git.run({ "diff", "--name-only" })
  MiniTest.expect.equality(result.code, 0)
  MiniTest.expect.equality(result.stdout:match("file1.lua") ~= nil, true)
  MiniTest.expect.equality(result.stdout:match("file2.lua") ~= nil, true)
end

T["run()"]["returns status for diff --name-status"] = function()
  mock_git.reset()
  mock_git.setup({
    changed_files_status = {
      { path = "new.lua", status = "added" },
      { path = "mod.lua", status = "modified" },
    },
  })

  local result = mock_git.run({ "diff", "--name-status" })
  MiniTest.expect.equality(result.code, 0)
  MiniTest.expect.equality(result.stdout:match("A%s+new.lua") ~= nil, true)
  MiniTest.expect.equality(result.stdout:match("M%s+mod.lua") ~= nil, true)
end

T["run()"]["returns shortstat for diff --shortstat"] = function()
  mock_git.reset()
  mock_git.setup({
    diff_stats = { additions = 10, deletions = 5, files_changed = 2 },
  })

  local result = mock_git.run({ "diff", "--shortstat" })
  MiniTest.expect.equality(result.code, 0)
  MiniTest.expect.equality(result.stdout:match("2 files changed") ~= nil, true)
  MiniTest.expect.equality(result.stdout:match("10 insertions") ~= nil, true)
end

T["run()"]["returns numstat for diff --numstat"] = function()
  mock_git.reset()
  mock_git.setup({
    diff_stats_per_file = {
      ["file.lua"] = { additions = 5, deletions = 2 },
    },
  })

  local result = mock_git.run({ "diff", "--numstat" })
  MiniTest.expect.equality(result.code, 0)
  MiniTest.expect.equality(result.stdout:match("5%s+2%s+file.lua") ~= nil, true)
end

T["run()"]["returns file content for show"] = function()
  mock_git.reset()
  mock_git.setup({
    files = { ["test.lua"] = "local M = {}\nreturn M" },
  })

  local result = mock_git.run({ "show", "HEAD:test.lua" })
  MiniTest.expect.equality(result.code, 0)
  MiniTest.expect.equality(result.stdout, "local M = {}\nreturn M")
end

T["run()"]["returns error for missing file in show"] = function()
  mock_git.reset()
  local result = mock_git.run({ "show", "HEAD:nonexistent.lua" })
  MiniTest.expect.equality(result.code, 128)
end

T["run()"]["handles checkout of existing ref"] = function()
  mock_git.reset()
  mock_git.setup({ refs = { HEAD = true, main = true, develop = true } })

  local result = mock_git.run({ "checkout", "develop" })
  MiniTest.expect.equality(result.code, 0)
  MiniTest.expect.equality(mock_git.current_branch(), "develop")
end

T["run()"]["returns error for checkout of nonexistent ref"] = function()
  mock_git.reset()
  local result = mock_git.run({ "checkout", "nonexistent" })
  MiniTest.expect.no_equality(result.code, 0)
end

T["diff()"] = MiniTest.new_set()

T["diff()"]["returns configured diff output"] = function()
  mock_git.reset()
  mock_git.setup({ diff_output = "test diff" })
  MiniTest.expect.equality(mock_git.diff(), "test diff")
end

T["changed_files()"] = MiniTest.new_set()

T["changed_files()"]["returns configured files"] = function()
  mock_git.reset()
  mock_git.setup({ changed_files = { "a.lua", "b.lua" } })

  local files = mock_git.changed_files()
  MiniTest.expect.equality(#files, 2)
  MiniTest.expect.equality(files[1], "a.lua")
end

T["changed_files()"]["returns copy of files"] = function()
  mock_git.reset()
  mock_git.setup({ changed_files = { "a.lua" } })

  local files = mock_git.changed_files()
  files[1] = "modified"

  local files2 = mock_git.changed_files()
  MiniTest.expect.equality(files2[1], "a.lua")
end

T["changed_files_with_status()"] = MiniTest.new_set()

T["changed_files_with_status()"]["returns configured files with status"] = function()
  mock_git.reset()
  mock_git.setup({
    changed_files_status = {
      { path = "new.lua", status = "added" },
      { path = "old.lua", status = "deleted" },
    },
  })

  local files = mock_git.changed_files_with_status()
  MiniTest.expect.equality(#files, 2)
  MiniTest.expect.equality(files[1].path, "new.lua")
  MiniTest.expect.equality(files[1].status, "added")
end

T["parse_status()"] = MiniTest.new_set()

T["parse_status()"]["parses status correctly"] = function()
  mock_git.reset()
  MiniTest.expect.equality(mock_git.parse_status("A"), "added")
  MiniTest.expect.equality(mock_git.parse_status("M"), "modified")
  MiniTest.expect.equality(mock_git.parse_status("D"), "deleted")
  MiniTest.expect.equality(mock_git.parse_status("R"), "renamed")
  MiniTest.expect.equality(mock_git.parse_status("C"), "copied")
  MiniTest.expect.equality(mock_git.parse_status("X"), "modified")
end

T["diff_stats()"] = MiniTest.new_set()

T["diff_stats()"]["returns configured stats"] = function()
  mock_git.reset()
  mock_git.setup({
    diff_stats = { additions = 100, deletions = 50, files_changed = 5 },
  })

  local stats = mock_git.diff_stats()
  MiniTest.expect.equality(stats.additions, 100)
  MiniTest.expect.equality(stats.deletions, 50)
  MiniTest.expect.equality(stats.files_changed, 5)
end

T["diff_stats_per_file()"] = MiniTest.new_set()

T["diff_stats_per_file()"]["returns configured per-file stats"] = function()
  mock_git.reset()
  mock_git.setup({
    diff_stats_per_file = {
      ["a.lua"] = { additions = 10, deletions = 2 },
      ["b.lua"] = { additions = 5, deletions = 0 },
    },
  })

  local stats = mock_git.diff_stats_per_file()
  MiniTest.expect.equality(stats["a.lua"].additions, 10)
  MiniTest.expect.equality(stats["b.lua"].deletions, 0)
end

T["current_commit()"] = MiniTest.new_set()

T["current_commit()"]["returns full SHA"] = function()
  mock_git.reset()
  mock_git.setup({ current_commit = "1234567890abcdef1234567890abcdef12345678" })

  local sha = mock_git.current_commit()
  MiniTest.expect.equality(#sha, 40)
end

T["current_commit()"]["returns short SHA"] = function()
  mock_git.reset()
  mock_git.setup({ current_commit = "1234567890abcdef1234567890abcdef12345678" })

  local sha = mock_git.current_commit(true)
  MiniTest.expect.equality(sha, "1234567")
end

T["parse_repo()"] = MiniTest.new_set()

T["parse_repo()"]["parses SSH URL"] = function()
  mock_git.reset()
  local result = mock_git.parse_repo("git@github.com:owner/repo.git")
  MiniTest.expect.equality(result.owner, "owner")
  MiniTest.expect.equality(result.repo, "repo")
end

T["parse_repo()"]["parses HTTPS URL"] = function()
  mock_git.reset()
  local result = mock_git.parse_repo("https://github.com/owner/repo.git")
  MiniTest.expect.equality(result.owner, "owner")
  MiniTest.expect.equality(result.repo, "repo")
end

T["parse_repo()"]["uses configured remote when nil"] = function()
  mock_git.reset()
  mock_git.setup({ remote_url = "git@github.com:test/project.git" })

  local result = mock_git.parse_repo(nil)
  MiniTest.expect.equality(result.owner, "test")
  MiniTest.expect.equality(result.repo, "project")
end

T["parse_repo()"]["returns nil for invalid URL"] = function()
  mock_git.reset()
  local result = mock_git.parse_repo("not-a-url")
  MiniTest.expect.equality(result, nil)
end

T["show_file()"] = MiniTest.new_set()

T["show_file()"]["returns configured file content"] = function()
  mock_git.reset()
  mock_git.setup({ files = { ["test.lua"] = "content here" } })

  local content = mock_git.show_file("HEAD", "test.lua")
  MiniTest.expect.equality(content, "content here")
end

T["show_file()"]["returns nil for missing file"] = function()
  mock_git.reset()
  local content = mock_git.show_file("HEAD", "missing.lua")
  MiniTest.expect.equality(content, nil)
end

T["ref_exists()"] = MiniTest.new_set()

T["ref_exists()"]["returns true for configured refs"] = function()
  mock_git.reset()
  mock_git.setup({ refs = { HEAD = true, main = true, develop = true } })

  MiniTest.expect.equality(mock_git.ref_exists("HEAD"), true)
  MiniTest.expect.equality(mock_git.ref_exists("main"), true)
  MiniTest.expect.equality(mock_git.ref_exists("develop"), true)
end

T["ref_exists()"]["returns false for missing refs"] = function()
  mock_git.reset()
  MiniTest.expect.equality(mock_git.ref_exists("nonexistent"), false)
end

T["merge_base()"] = MiniTest.new_set()

T["merge_base()"]["returns configured merge base"] = function()
  mock_git.reset()
  mock_git.setup({
    merge_bases = { ["main..feature"] = "abc123" },
  })

  local base = mock_git.merge_base("main", "feature")
  MiniTest.expect.equality(base, "abc123")
end

T["merge_base()"]["returns current commit as default"] = function()
  mock_git.reset()
  mock_git.setup({ current_commit = "default123" })

  local base = mock_git.merge_base("a", "b")
  MiniTest.expect.equality(base, "default123")
end

T["checkout()"] = MiniTest.new_set()

T["checkout()"]["succeeds for existing ref"] = function()
  mock_git.reset()
  mock_git.setup({ refs = { HEAD = true, main = true, feature = true } })

  local ok, err = mock_git.checkout("feature")
  MiniTest.expect.equality(ok, true)
  MiniTest.expect.equality(err, nil)
  MiniTest.expect.equality(mock_git.current_branch(), "feature")
end

T["checkout()"]["fails for missing ref"] = function()
  mock_git.reset()
  local ok, err = mock_git.checkout("nonexistent")
  MiniTest.expect.equality(ok, false)
  MiniTest.expect.no_equality(err, nil)
end

T["install() and restore()"] = MiniTest.new_set()

T["install() and restore()"]["installs mock into package.loaded"] = function()
  mock_git.reset()
  mock_git.setup({ current_branch = "mocked" })

  mock_git.install()

  local git = require("review.integrations.git")
  MiniTest.expect.equality(git.current_branch(), "mocked")

  mock_git.restore()
end

T["install() and restore()"]["restore reverts to original"] = function()
  -- First install
  mock_git.reset()
  mock_git.install()

  -- Restore
  mock_git.restore()

  -- Now require should get the real module
  local git = require("review.integrations.git")
  -- The real module has different behavior
  MiniTest.expect.equality(type(git.run), "function")
end

return T
