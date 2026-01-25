-- Tests for review.ui.signs module
local T = MiniTest.new_set()

local signs = require("review.ui.signs")
local state = require("review.core.state")
local config = require("review.config")

-- Helper to create a test buffer
local function create_test_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "line 1",
    "line 2",
    "line 3",
    "line 4",
    "line 5",
    "line 6",
    "line 7",
    "line 8",
    "line 9",
    "line 10",
  })
  return buf
end

-- Helper to create a test comment
-- Use no_line = true to explicitly set line to nil
local function make_comment(opts)
  opts = opts or {}
  local line
  if opts.no_line then
    line = nil
  else
    line = opts.line or 1
  end
  return {
    id = opts.id or "test_" .. math.random(10000),
    kind = opts.kind or "local",
    body = opts.body or "Test comment",
    author = opts.author or "you",
    created_at = opts.created_at or "2025-01-01T00:00:00Z",
    file = opts.file or "test.lua",
    line = line,
    type = opts.type, -- note, issue, suggestion, praise
    resolved = opts.resolved,
    status = opts.status or "pending",
  }
end

-- Cleanup hooks
T["setup()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      signs.clear()
      config.setup({})
    end,
  },
})

T["setup()"]["defines all sign types"] = function()
  signs.setup()

  -- Check all signs are defined
  local defined = vim.fn.sign_getdefined()
  local sign_names = {}
  for _, s in ipairs(defined) do
    sign_names[s.name] = true
  end

  MiniTest.expect.equality(sign_names["Review_comment_github"], true)
  MiniTest.expect.equality(sign_names["Review_comment_local"], true)
  MiniTest.expect.equality(sign_names["Review_comment_issue"], true)
  MiniTest.expect.equality(sign_names["Review_comment_suggestion"], true)
  MiniTest.expect.equality(sign_names["Review_comment_praise"], true)
  MiniTest.expect.equality(sign_names["Review_comment_resolved"], true)
end

T["setup()"]["sets is_setup flag"] = function()
  MiniTest.expect.equality(signs.is_setup(), false)
  signs.setup()
  MiniTest.expect.equality(signs.is_setup(), true)
end

T["setup()"]["is idempotent"] = function()
  signs.setup()
  signs.setup()
  MiniTest.expect.equality(signs.is_setup(), true)
end

T["setup()"]["uses config values for sign text"] = function()
  config.setup({
    signs = {
      comment_github = "GH",
      comment_local = "LC",
      comment_issue = "!!",
      comment_suggestion = "**",
      comment_praise = "++",
      comment_resolved = "OK",
    },
  })
  signs.setup()

  -- Neovim pads sign text to 2 chars
  local defined = vim.fn.sign_getdefined("Review_comment_github")
  MiniTest.expect.equality(vim.trim(defined[1].text), "GH")
end

T["clear()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup({})
      signs.setup()
    end,
  },
})

T["clear()"]["undefines all signs"] = function()
  signs.clear()

  local defined = vim.fn.sign_getdefined("Review_comment_github")
  MiniTest.expect.equality(#defined, 0)
end

T["clear()"]["resets is_setup flag"] = function()
  MiniTest.expect.equality(signs.is_setup(), true)
  signs.clear()
  MiniTest.expect.equality(signs.is_setup(), false)
end

T["reset()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      signs.clear()
      config.setup({})
    end,
  },
})

T["reset()"]["clears and re-sets up signs"] = function()
  config.setup({
    signs = {
      comment_github = "X",
      comment_local = "L",
      comment_issue = "!",
      comment_suggestion = "*",
      comment_praise = "+",
      comment_resolved = "R",
    },
  })
  signs.setup()

  -- Verify setup (Neovim pads sign text to 2 chars, so "X" becomes "X ")
  local before = vim.fn.sign_getdefined("Review_comment_github")
  MiniTest.expect.equality(vim.trim(before[1].text), "X")

  -- Reset with new config
  config.setup({
    signs = {
      comment_github = "Y",
      comment_local = "L",
      comment_issue = "!",
      comment_suggestion = "*",
      comment_praise = "+",
      comment_resolved = "R",
    },
  })
  signs.reset()

  local after = vim.fn.sign_getdefined("Review_comment_github")
  MiniTest.expect.equality(vim.trim(after[1].text), "Y")
end

T["get_sign_name()"] = MiniTest.new_set()

T["get_sign_name()"]["returns resolved for resolved comments"] = function()
  local comment = make_comment({ resolved = true })
  MiniTest.expect.equality(signs.get_sign_name(comment), "Review_comment_resolved")
end

T["get_sign_name()"]["returns github for non-local comments"] = function()
  local comment = make_comment({ kind = "review" })
  MiniTest.expect.equality(signs.get_sign_name(comment), "Review_comment_github")
end

T["get_sign_name()"]["returns local for local note comments"] = function()
  local comment = make_comment({ kind = "local", type = "note" })
  MiniTest.expect.equality(signs.get_sign_name(comment), "Review_comment_local")
end

T["get_sign_name()"]["returns local for local comments without type"] = function()
  local comment = make_comment({ kind = "local" })
  MiniTest.expect.equality(signs.get_sign_name(comment), "Review_comment_local")
end

T["get_sign_name()"]["returns issue for local issue comments"] = function()
  local comment = make_comment({ kind = "local", type = "issue" })
  MiniTest.expect.equality(signs.get_sign_name(comment), "Review_comment_issue")
end

T["get_sign_name()"]["returns suggestion for local suggestion comments"] = function()
  local comment = make_comment({ kind = "local", type = "suggestion" })
  MiniTest.expect.equality(signs.get_sign_name(comment), "Review_comment_suggestion")
end

T["get_sign_name()"]["returns praise for local praise comments"] = function()
  local comment = make_comment({ kind = "local", type = "praise" })
  MiniTest.expect.equality(signs.get_sign_name(comment), "Review_comment_praise")
end

T["get_sign_name()"]["prioritizes resolved over type"] = function()
  local comment = make_comment({ kind = "local", type = "issue", resolved = true })
  MiniTest.expect.equality(signs.get_sign_name(comment), "Review_comment_resolved")
end

T["get_sign_def()"] = MiniTest.new_set()

T["get_sign_def()"]["returns definition for valid name"] = function()
  local def = signs.get_sign_def("comment_github")
  MiniTest.expect.no_equality(def, nil)
  MiniTest.expect.equality(type(def.text), "string")
  MiniTest.expect.equality(def.texthl, "ReviewSignGithub")
end

T["get_sign_def()"]["returns nil for invalid name"] = function()
  local def = signs.get_sign_def("nonexistent")
  MiniTest.expect.equality(def, nil)
end

T["get_sign_names()"] = MiniTest.new_set()

T["get_sign_names()"]["returns all sign names sorted"] = function()
  local names = signs.get_sign_names()
  MiniTest.expect.equality(#names, 6)
  -- Should be sorted
  local sorted = vim.deepcopy(names)
  table.sort(sorted)
  MiniTest.expect.equality(vim.deep_equal(names, sorted), true)
end

T["place_sign()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      signs.clear()
      config.setup({})
      signs.setup()
    end,
    post_case = function()
      -- Clean up any created buffers
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end,
  },
})

T["place_sign()"]["places sign at correct line"] = function()
  local buf = create_test_buffer()
  local comment = make_comment({ line = 5 })

  local sign_id = signs.place_sign(buf, comment)
  MiniTest.expect.no_equality(sign_id, nil)

  local placed = signs.get_signs(buf)
  MiniTest.expect.equality(#placed, 1)
  MiniTest.expect.equality(placed[1].lnum, 5)
end

T["place_sign()"]["returns nil for comment without line"] = function()
  local buf = create_test_buffer()
  local comment = make_comment({ no_line = true })

  local sign_id = signs.place_sign(buf, comment)
  MiniTest.expect.equality(sign_id, nil)
end

T["place_sign()"]["returns nil for invalid buffer"] = function()
  local comment = make_comment({ line = 5 })
  local sign_id = signs.place_sign(99999, comment)
  MiniTest.expect.equality(sign_id, nil)
end

T["place_sign()"]["places correct sign type"] = function()
  local buf = create_test_buffer()
  local comment = make_comment({ kind = "local", type = "issue", line = 3 })

  signs.place_sign(buf, comment)

  local placed = signs.get_signs(buf)
  MiniTest.expect.equality(placed[1].name, "Review_comment_issue")
end

T["remove_sign()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      signs.clear()
      config.setup({})
      signs.setup()
    end,
    post_case = function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end,
  },
})

T["remove_sign()"]["removes sign by id"] = function()
  local buf = create_test_buffer()
  local comment = make_comment({ line = 5 })

  local sign_id = signs.place_sign(buf, comment)
  MiniTest.expect.equality(signs.count_signs(buf), 1)

  signs.remove_sign(buf, sign_id)
  MiniTest.expect.equality(signs.count_signs(buf), 0)
end

T["remove_sign()"]["handles invalid buffer gracefully"] = function()
  -- Should not error
  signs.remove_sign(99999, 1)
end

T["clear_buffer()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      signs.clear()
      config.setup({})
      signs.setup()
    end,
    post_case = function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end,
  },
})

T["clear_buffer()"]["removes all signs from buffer"] = function()
  local buf = create_test_buffer()

  signs.place_sign(buf, make_comment({ line = 1 }))
  signs.place_sign(buf, make_comment({ line = 3 }))
  signs.place_sign(buf, make_comment({ line = 5 }))

  MiniTest.expect.equality(signs.count_signs(buf), 3)

  signs.clear_buffer(buf)
  MiniTest.expect.equality(signs.count_signs(buf), 0)
end

T["clear_buffer()"]["handles invalid buffer gracefully"] = function()
  -- Should not error
  signs.clear_buffer(99999)
end

T["clear_all()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      signs.clear()
      config.setup({})
      signs.setup()
    end,
    post_case = function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end,
  },
})

T["clear_all()"]["removes signs from all buffers"] = function()
  local buf1 = create_test_buffer()
  local buf2 = create_test_buffer()

  signs.place_sign(buf1, make_comment({ line = 1 }))
  signs.place_sign(buf2, make_comment({ line = 2 }))

  MiniTest.expect.equality(signs.count_signs(buf1), 1)
  MiniTest.expect.equality(signs.count_signs(buf2), 1)

  signs.clear_all()

  MiniTest.expect.equality(signs.count_signs(buf1), 0)
  MiniTest.expect.equality(signs.count_signs(buf2), 0)
end

T["refresh_buffer()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      signs.clear()
      config.setup({})
      signs.setup()
      state.reset()
    end,
    post_case = function()
      state.reset()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end,
  },
})

T["refresh_buffer()"]["places signs for all file comments"] = function()
  local buf = create_test_buffer()
  local file = "test.lua"

  state.set_current_file(file)
  state.add_comment(make_comment({ file = file, line = 1 }))
  state.add_comment(make_comment({ file = file, line = 3 }))
  state.add_comment(make_comment({ file = file, line = 5 }))

  signs.refresh_buffer(buf, file)

  MiniTest.expect.equality(signs.count_signs(buf), 3)
end

T["refresh_buffer()"]["clears old signs before placing new ones"] = function()
  local buf = create_test_buffer()
  local file = "test.lua"

  state.set_current_file(file)
  state.add_comment(make_comment({ file = file, line = 1 }))

  signs.refresh_buffer(buf, file)
  MiniTest.expect.equality(signs.count_signs(buf), 1)

  -- Clear comments and refresh
  state.reset()
  signs.refresh_buffer(buf, file)
  MiniTest.expect.equality(signs.count_signs(buf), 0)
end

T["refresh_buffer()"]["ignores comments for other files"] = function()
  local buf = create_test_buffer()
  local file = "test.lua"

  state.set_current_file(file)
  state.add_comment(make_comment({ file = file, line = 1 }))
  state.add_comment(make_comment({ file = "other.lua", line = 2 }))

  signs.refresh_buffer(buf, file)

  MiniTest.expect.equality(signs.count_signs(buf), 1)
end

T["refresh_buffer()"]["handles invalid buffer gracefully"] = function()
  state.set_current_file("test.lua")
  -- Should not error
  signs.refresh_buffer(99999, "test.lua")
end

T["refresh_buffer()"]["uses current_file when file not provided"] = function()
  local buf = create_test_buffer()
  local file = "test.lua"

  state.set_current_file(file)
  state.add_comment(make_comment({ file = file, line = 2 }))

  signs.refresh_buffer(buf) -- No file argument

  MiniTest.expect.equality(signs.count_signs(buf), 1)
end

T["refresh()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      signs.clear()
      config.setup({})
      signs.setup()
      state.reset()
    end,
    post_case = function()
      state.reset()
    end,
  },
})

T["refresh()"]["does nothing when no current file"] = function()
  -- Should not error
  signs.refresh()
end

T["get_signs()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      signs.clear()
      config.setup({})
      signs.setup()
    end,
    post_case = function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end,
  },
})

T["get_signs()"]["returns all placed signs"] = function()
  local buf = create_test_buffer()

  signs.place_sign(buf, make_comment({ line = 1 }))
  signs.place_sign(buf, make_comment({ line = 5 }))

  local placed = signs.get_signs(buf)
  MiniTest.expect.equality(#placed, 2)
end

T["get_signs()"]["returns empty table for buffer without signs"] = function()
  local buf = create_test_buffer()
  local placed = signs.get_signs(buf)
  MiniTest.expect.equality(#placed, 0)
end

T["get_signs()"]["returns empty table for invalid buffer"] = function()
  local placed = signs.get_signs(99999)
  MiniTest.expect.equality(#placed, 0)
end

T["get_sign_at_line()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      signs.clear()
      config.setup({})
      signs.setup()
    end,
    post_case = function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end,
  },
})

T["get_sign_at_line()"]["returns sign at specified line"] = function()
  local buf = create_test_buffer()

  signs.place_sign(buf, make_comment({ line = 5 }))

  local sign = signs.get_sign_at_line(buf, 5)
  MiniTest.expect.no_equality(sign, nil)
  MiniTest.expect.equality(sign.lnum, 5)
end

T["get_sign_at_line()"]["returns nil when no sign at line"] = function()
  local buf = create_test_buffer()

  signs.place_sign(buf, make_comment({ line = 5 }))

  local sign = signs.get_sign_at_line(buf, 3)
  MiniTest.expect.equality(sign, nil)
end

T["get_signed_lines()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      signs.clear()
      config.setup({})
      signs.setup()
    end,
    post_case = function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end,
  },
})

T["get_signed_lines()"]["returns sorted list of signed lines"] = function()
  local buf = create_test_buffer()

  signs.place_sign(buf, make_comment({ line = 7 }))
  signs.place_sign(buf, make_comment({ line = 2 }))
  signs.place_sign(buf, make_comment({ line = 5 }))

  local lines = signs.get_signed_lines(buf)
  MiniTest.expect.equality(lines, { 2, 5, 7 })
end

T["get_signed_lines()"]["deduplicates lines with multiple signs"] = function()
  local buf = create_test_buffer()

  signs.place_sign(buf, make_comment({ line = 5 }))
  signs.place_sign(buf, make_comment({ line = 5, kind = "review" }))

  local lines = signs.get_signed_lines(buf)
  MiniTest.expect.equality(lines, { 5 })
end

T["count_signs()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      signs.clear()
      config.setup({})
      signs.setup()
    end,
    post_case = function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end,
  },
})

T["count_signs()"]["returns correct count"] = function()
  local buf = create_test_buffer()

  MiniTest.expect.equality(signs.count_signs(buf), 0)

  signs.place_sign(buf, make_comment({ line = 1 }))
  MiniTest.expect.equality(signs.count_signs(buf), 1)

  signs.place_sign(buf, make_comment({ line = 2 }))
  MiniTest.expect.equality(signs.count_signs(buf), 2)
end

T["next_sign()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      signs.clear()
      config.setup({})
      signs.setup()
    end,
    post_case = function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end,
  },
})

T["next_sign()"]["finds next sign after current line"] = function()
  local buf = create_test_buffer()

  signs.place_sign(buf, make_comment({ line = 2 }))
  signs.place_sign(buf, make_comment({ line = 5 }))
  signs.place_sign(buf, make_comment({ line = 8 }))

  MiniTest.expect.equality(signs.next_sign(buf, 1), 2)
  MiniTest.expect.equality(signs.next_sign(buf, 3), 5)
  MiniTest.expect.equality(signs.next_sign(buf, 6), 8)
end

T["next_sign()"]["wraps to first sign when at end"] = function()
  local buf = create_test_buffer()

  signs.place_sign(buf, make_comment({ line = 2 }))
  signs.place_sign(buf, make_comment({ line = 5 }))

  MiniTest.expect.equality(signs.next_sign(buf, 5), 2)
  MiniTest.expect.equality(signs.next_sign(buf, 10), 2)
end

T["next_sign()"]["returns nil when wrap is false and at end"] = function()
  local buf = create_test_buffer()

  signs.place_sign(buf, make_comment({ line = 2 }))
  signs.place_sign(buf, make_comment({ line = 5 }))

  MiniTest.expect.equality(signs.next_sign(buf, 5, false), nil)
end

T["next_sign()"]["returns nil for empty buffer"] = function()
  local buf = create_test_buffer()
  MiniTest.expect.equality(signs.next_sign(buf, 1), nil)
end

T["prev_sign()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      signs.clear()
      config.setup({})
      signs.setup()
    end,
    post_case = function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end,
  },
})

T["prev_sign()"]["finds previous sign before current line"] = function()
  local buf = create_test_buffer()

  signs.place_sign(buf, make_comment({ line = 2 }))
  signs.place_sign(buf, make_comment({ line = 5 }))
  signs.place_sign(buf, make_comment({ line = 8 }))

  MiniTest.expect.equality(signs.prev_sign(buf, 10), 8)
  MiniTest.expect.equality(signs.prev_sign(buf, 7), 5)
  MiniTest.expect.equality(signs.prev_sign(buf, 4), 2)
end

T["prev_sign()"]["wraps to last sign when at beginning"] = function()
  local buf = create_test_buffer()

  signs.place_sign(buf, make_comment({ line = 2 }))
  signs.place_sign(buf, make_comment({ line = 5 }))

  MiniTest.expect.equality(signs.prev_sign(buf, 2), 5)
  MiniTest.expect.equality(signs.prev_sign(buf, 1), 5)
end

T["prev_sign()"]["returns nil when wrap is false and at beginning"] = function()
  local buf = create_test_buffer()

  signs.place_sign(buf, make_comment({ line = 2 }))
  signs.place_sign(buf, make_comment({ line = 5 }))

  MiniTest.expect.equality(signs.prev_sign(buf, 2, false), nil)
end

T["prev_sign()"]["returns nil for empty buffer"] = function()
  local buf = create_test_buffer()
  MiniTest.expect.equality(signs.prev_sign(buf, 5), nil)
end

return T
