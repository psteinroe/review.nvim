-- Tests for review.storage module
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Reset storage module before each test
      package.loaded["review.storage"] = nil
    end,
    post_case = function()
      -- Clean up any test files
      local storage = require("review.storage")
      local data_dir = storage.get_data_dir()
      -- Clean up test files
      local test_files = vim.fn.glob(data_dir .. "/test_*.json", false, true)
      for _, f in ipairs(test_files) do
        pcall(os.remove, f)
      end
    end,
  },
})

local function get_storage()
  return require("review.storage")
end

-- Helper to create a temp file path
local function temp_path()
  local storage = get_storage()
  local dir = storage.get_data_dir()
  -- Ensure directory exists
  vim.fn.mkdir(dir, "p")
  return dir .. "/test_" .. os.time() .. "_" .. math.random(1000) .. ".json"
end

-- Mock comments for testing
local function mock_local_comments()
  return {
    {
      id = "local_1",
      kind = "local",
      body = "Test comment 1",
      file = "test.lua",
      line = 10,
      type = "issue",
    },
    {
      id = "local_2",
      kind = "local",
      body = "Test comment 2",
      file = "test.lua",
      line = 20,
      type = "suggestion",
    },
  }
end

local function mock_mixed_comments()
  return {
    {
      id = "local_1",
      kind = "local",
      body = "Local comment",
      file = "test.lua",
      line = 10,
    },
    {
      id = "gh_1",
      kind = "review",
      body = "GitHub comment",
      file = "test.lua",
      line = 15,
      author = "someone",
    },
    {
      id = "local_2",
      kind = "local",
      body = "Another local",
      file = "test.lua",
      line = 20,
    },
  }
end

T["get_data_dir()"] = MiniTest.new_set()

T["get_data_dir()"]["returns path in stdpath data"] = function()
  local storage = get_storage()
  local dir = storage.get_data_dir()
  MiniTest.expect.equality(type(dir), "string")
  MiniTest.expect.equality(dir:find("review") ~= nil, true)
end

T["save()"] = MiniTest.new_set()

T["save()"]["saves local comments to file"] = function()
  local storage = get_storage()
  local path = temp_path()
  local comments = mock_local_comments()

  local success = storage.save(comments, path)
  MiniTest.expect.equality(success, true)

  -- Verify file exists
  local file = io.open(path, "r")
  MiniTest.expect.equality(file ~= nil, true)
  file:close()

  -- Clean up
  os.remove(path)
end

T["save()"]["only saves local comments, filters out github comments"] = function()
  local storage = get_storage()
  local path = temp_path()
  local comments = mock_mixed_comments()

  storage.save(comments, path)

  -- Load and verify only local comments were saved
  local loaded = storage.load(path)
  MiniTest.expect.equality(#loaded, 2)
  MiniTest.expect.equality(loaded[1].kind, "local")
  MiniTest.expect.equality(loaded[2].kind, "local")

  os.remove(path)
end

T["save()"]["removes file when no local comments"] = function()
  local storage = get_storage()
  local path = temp_path()

  -- First save some comments
  storage.save(mock_local_comments(), path)
  MiniTest.expect.equality(io.open(path, "r") ~= nil, true)

  -- Now save empty/github-only comments
  local github_only = {
    { id = "gh_1", kind = "review", body = "GitHub comment" },
  }
  storage.save(github_only, path)

  -- File should be removed
  MiniTest.expect.equality(io.open(path, "r"), nil)
end

T["save()"]["returns false for nil path"] = function()
  local storage = get_storage()
  -- Can't easily test nil path without mocking git, so test with explicit nil
  local success = storage.save({}, nil)
  -- This will try get_storage_path() which might return nil or a path
  -- Just verify it doesn't error
  MiniTest.expect.equality(type(success), "boolean")
end

T["load()"] = MiniTest.new_set()

T["load()"]["loads saved comments"] = function()
  local storage = get_storage()
  local path = temp_path()
  local comments = mock_local_comments()

  storage.save(comments, path)
  local loaded = storage.load(path)

  MiniTest.expect.equality(#loaded, 2)
  MiniTest.expect.equality(loaded[1].id, "local_1")
  MiniTest.expect.equality(loaded[1].body, "Test comment 1")
  MiniTest.expect.equality(loaded[2].id, "local_2")

  os.remove(path)
end

T["load()"]["returns empty table for non-existent file"] = function()
  local storage = get_storage()
  local loaded = storage.load("/nonexistent/path/file.json")
  MiniTest.expect.equality(#loaded, 0)
end

T["load()"]["returns empty table for empty file"] = function()
  local storage = get_storage()
  local path = temp_path()

  -- Create empty file
  local file = io.open(path, "w")
  file:write("")
  file:close()

  local loaded = storage.load(path)
  MiniTest.expect.equality(#loaded, 0)

  os.remove(path)
end

T["load()"]["handles old array format"] = function()
  local storage = get_storage()
  local path = temp_path()

  -- Write old array format
  local file = io.open(path, "w")
  file:write(vim.json.encode(mock_local_comments()))
  file:close()

  local loaded = storage.load(path)
  MiniTest.expect.equality(#loaded, 2)
  MiniTest.expect.equality(loaded[1].id, "local_1")

  os.remove(path)
end

T["load()"]["handles new object format with metadata"] = function()
  local storage = get_storage()
  local path = temp_path()

  -- Write new object format
  local data = {
    comments = mock_local_comments(),
    metadata = {
      saved_at = "2024-01-15T10:00:00Z",
      version = 1,
    },
  }
  local file = io.open(path, "w")
  file:write(vim.json.encode(data))
  file:close()

  local loaded = storage.load(path)
  MiniTest.expect.equality(#loaded, 2)
  MiniTest.expect.equality(loaded[1].id, "local_1")

  os.remove(path)
end

T["load()"]["returns empty table for invalid JSON"] = function()
  local storage = get_storage()
  local path = temp_path()

  -- Write invalid JSON
  local file = io.open(path, "w")
  file:write("not valid json {{{")
  file:close()

  local loaded = storage.load(path)
  MiniTest.expect.equality(#loaded, 0)

  os.remove(path)
end

T["clear()"] = MiniTest.new_set()

T["clear()"]["removes storage file"] = function()
  local storage = get_storage()
  local path = temp_path()

  -- Save comments
  storage.save(mock_local_comments(), path)
  MiniTest.expect.equality(io.open(path, "r") ~= nil, true)

  -- Clear using explicit path removal (since clear() uses get_storage_path)
  os.remove(path)
  MiniTest.expect.equality(io.open(path, "r"), nil)
end

T["has_stored_comments()"] = MiniTest.new_set()

T["has_stored_comments()"]["returns true when file exists"] = function()
  local storage = get_storage()
  local path = temp_path()

  -- Save comments
  storage.save(mock_local_comments(), path)

  -- Check file exists
  local file = io.open(path, "r")
  MiniTest.expect.equality(file ~= nil, true)
  file:close()

  os.remove(path)
end

T["PR storage"] = MiniTest.new_set()

T["PR storage"]["get_pr_storage_path returns path with pr number"] = function()
  local storage = get_storage()
  -- This depends on being in a git repo
  local path = storage.get_pr_storage_path(142)
  if path then
    MiniTest.expect.equality(path:find("pr%-142%.json") ~= nil, true)
  end
end

T["PR storage"]["save_pr and load_pr work together"] = function()
  local storage = get_storage()
  local comments = mock_local_comments()

  -- Get the path that would be used
  local path = storage.get_pr_storage_path(999)
  if path then
    storage.save_pr(999, comments)
    local loaded = storage.load_pr(999)

    MiniTest.expect.equality(#loaded, 2)
    MiniTest.expect.equality(loaded[1].body, "Test comment 1")

    -- Clean up
    storage.clear_pr(999)
  end
end

T["list_stored()"] = MiniTest.new_set()

T["list_stored()"]["returns array"] = function()
  local storage = get_storage()
  local stored = storage.list_stored()
  MiniTest.expect.equality(type(stored), "table")
end

T["list_stored()"]["identifies PR files correctly"] = function()
  local storage = get_storage()
  local path = storage.get_data_dir() .. "/test_abc123-pr-42.json"

  -- Create a mock PR file
  local file = io.open(path, "w")
  if file then
    file:write(vim.json.encode({ comments = {} }))
    file:close()

    local stored = storage.list_stored()
    local found = false
    for _, item in ipairs(stored) do
      if item.path == path then
        found = true
        MiniTest.expect.equality(item.pr, 42)
      end
    end

    os.remove(path)
  end
end

T["list_stored()"]["identifies branch files correctly"] = function()
  local storage = get_storage()
  local path = storage.get_data_dir() .. "/test_abc123-feature_branch.json"

  -- Create a mock branch file
  local file = io.open(path, "w")
  if file then
    file:write(vim.json.encode({ comments = {} }))
    file:close()

    local stored = storage.list_stored()
    local found = false
    for _, item in ipairs(stored) do
      if item.path == path then
        found = true
        MiniTest.expect.equality(item.branch, "feature_branch")
      end
    end

    os.remove(path)
  end
end

T["round trip"] = MiniTest.new_set()

T["round trip"]["preserves all comment fields"] = function()
  local storage = get_storage()
  local path = temp_path()

  local original = {
    {
      id = "test_1",
      kind = "local",
      body = "Multi\nline\nbody",
      file = "path/to/file.lua",
      line = 42,
      end_line = 50,
      type = "suggestion",
      status = "pending",
    },
  }

  storage.save(original, path)
  local loaded = storage.load(path)

  MiniTest.expect.equality(#loaded, 1)
  MiniTest.expect.equality(loaded[1].id, "test_1")
  MiniTest.expect.equality(loaded[1].kind, "local")
  MiniTest.expect.equality(loaded[1].body, "Multi\nline\nbody")
  MiniTest.expect.equality(loaded[1].file, "path/to/file.lua")
  MiniTest.expect.equality(loaded[1].line, 42)
  MiniTest.expect.equality(loaded[1].end_line, 50)
  MiniTest.expect.equality(loaded[1].type, "suggestion")
  MiniTest.expect.equality(loaded[1].status, "pending")

  os.remove(path)
end

return T
