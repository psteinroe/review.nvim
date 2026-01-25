-- Tests for review.utils module
local T = MiniTest.new_set()

local utils = require("review.utils")

T["truncate()"] = MiniTest.new_set()

T["truncate()"]["returns empty string for nil input"] = function()
  MiniTest.expect.equality(utils.truncate(nil, 10), "")
end

T["truncate()"]["returns string unchanged when shorter than max"] = function()
  MiniTest.expect.equality(utils.truncate("hello", 10), "hello")
end

T["truncate()"]["truncates with ellipsis when longer than max"] = function()
  MiniTest.expect.equality(utils.truncate("hello world", 8), "hello...")
end

T["truncate()"]["replaces newlines with spaces"] = function()
  MiniTest.expect.equality(utils.truncate("hello\nworld", 20), "hello world")
end

T["truncate()"]["handles exact length"] = function()
  MiniTest.expect.equality(utils.truncate("hello", 5), "hello")
end

T["normalize_path()"] = MiniTest.new_set()

T["normalize_path()"]["removes leading ./"] = function()
  MiniTest.expect.equality(utils.normalize_path("./src/file.lua"), "src/file.lua")
end

T["normalize_path()"]["collapses multiple slashes"] = function()
  MiniTest.expect.equality(utils.normalize_path("src//file.lua"), "src/file.lua")
end

T["normalize_path()"]["handles already normalized paths"] = function()
  MiniTest.expect.equality(utils.normalize_path("src/file.lua"), "src/file.lua")
end

T["normalize_path()"]["handles multiple issues"] = function()
  MiniTest.expect.equality(utils.normalize_path(".//src///file.lua"), "src/file.lua")
end

T["generate_id()"] = MiniTest.new_set()

T["generate_id()"]["uses default prefix"] = function()
  local id = utils.generate_id()
  MiniTest.expect.equality(id:match("^id_") ~= nil, true)
end

T["generate_id()"]["uses custom prefix"] = function()
  local id = utils.generate_id("comment")
  MiniTest.expect.equality(id:match("^comment_") ~= nil, true)
end

T["generate_id()"]["generates unique IDs"] = function()
  local id1 = utils.generate_id()
  local id2 = utils.generate_id()
  MiniTest.expect.no_equality(id1, id2)
end

T["relative_time()"] = MiniTest.new_set()

T["relative_time()"]["returns 'unknown' for nil"] = function()
  MiniTest.expect.equality(utils.relative_time(nil), "unknown")
end

T["relative_time()"]["returns 'unknown' for empty string"] = function()
  MiniTest.expect.equality(utils.relative_time(""), "unknown")
end

T["relative_time()"]["returns original string for invalid format"] = function()
  MiniTest.expect.equality(utils.relative_time("not-a-date"), "not-a-date")
end

T["relative_time()"]["handles 'just now' (< 60 seconds)"] = function()
  -- Create a timestamp for "now" using local time (matching what relative_time uses internally)
  local now = os.date("%Y-%m-%dT%H:%M:%SZ")
  MiniTest.expect.equality(utils.relative_time(now), "just now")
end

T["safe_require()"] = MiniTest.new_set()

T["safe_require()"]["returns module when it exists"] = function()
  local mod, err = utils.safe_require("review.utils")
  MiniTest.expect.no_equality(mod, nil)
  MiniTest.expect.equality(err, nil)
end

T["safe_require()"]["returns nil and error for missing module"] = function()
  local mod, err = utils.safe_require("nonexistent.module.xyz")
  MiniTest.expect.equality(mod, nil)
  MiniTest.expect.no_equality(err, nil)
end

T["is_valid_buf()"] = MiniTest.new_set()

T["is_valid_buf()"]["returns false for nil"] = function()
  MiniTest.expect.equality(utils.is_valid_buf(nil), false)
end

T["is_valid_buf()"]["returns true for valid loaded buffer"] = function()
  local buf = vim.api.nvim_create_buf(true, false)
  MiniTest.expect.equality(utils.is_valid_buf(buf), true)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["is_valid_buf()"]["returns false for deleted buffer"] = function()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_delete(buf, { force = true })
  MiniTest.expect.equality(utils.is_valid_buf(buf), false)
end

T["is_valid_win()"] = MiniTest.new_set()

T["is_valid_win()"]["returns false for nil"] = function()
  MiniTest.expect.equality(utils.is_valid_win(nil), false)
end

T["is_valid_win()"]["returns true for current window"] = function()
  local win = vim.api.nvim_get_current_win()
  MiniTest.expect.equality(utils.is_valid_win(win), true)
end

T["debounce()"] = MiniTest.new_set()

T["debounce()"]["returns a function"] = function()
  local debounced = utils.debounce(function() end, 100)
  MiniTest.expect.equality(type(debounced), "function")
end

return T
