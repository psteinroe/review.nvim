-- Tests for review.nvim commands module
local MiniTest = require("mini.test")
local expect = MiniTest.expect

local T = MiniTest.new_set()

-- Helper to get fresh modules
local function get_state()
  package.loaded["review.core.state"] = nil
  return require("review.core.state")
end

local function get_commands()
  package.loaded["review.commands"] = nil
  return require("review.commands")
end

-- Reset state before each test
T["setup"] = function()
  local state = get_state()
  state.reset()
  -- Suppress vim.notify messages during tests
  vim.notify = function() end
end

-- =============================================================================
-- Setup Tests
-- =============================================================================

T["setup"] = MiniTest.new_set()

T["setup"]["creates Review command"] = function()
  local commands = get_commands()
  commands.setup()

  -- Check command exists
  local cmd_info = vim.api.nvim_get_commands({})["Review"]
  expect.equality(cmd_info ~= nil, true)
end

T["setup"]["creates ReviewAI command"] = function()
  local commands = get_commands()
  commands.setup()

  local cmd_info = vim.api.nvim_get_commands({})["ReviewAI"]
  expect.equality(cmd_info ~= nil, true)
end

T["setup"]["creates ReviewComment command"] = function()
  local commands = get_commands()
  commands.setup()

  local cmd_info = vim.api.nvim_get_commands({})["ReviewComment"]
  expect.equality(cmd_info ~= nil, true)
end

-- =============================================================================
-- Command Completion Tests
-- =============================================================================

T["complete_review"] = MiniTest.new_set()

T["complete_review"]["returns base commands"] = function()
  local commands = get_commands()

  local completions = commands.complete_review("", "Review ", 7)
  expect.equality(vim.tbl_contains(completions, "close"), true)
  expect.equality(vim.tbl_contains(completions, "pr"), true)
  expect.equality(vim.tbl_contains(completions, "panel"), true)
  expect.equality(vim.tbl_contains(completions, "refresh"), true)
  expect.equality(vim.tbl_contains(completions, "status"), true)
end

T["complete_review"]["filters by prefix"] = function()
  local commands = get_commands()

  local completions = commands.complete_review("cl", "Review cl", 10)
  expect.equality(vim.tbl_contains(completions, "close"), true)
  expect.equality(vim.tbl_contains(completions, "pr"), false)
end

T["complete_review"]["returns empty for PR numbers"] = function()
  local commands = get_commands()

  -- When typing "Review pr 1", args = ["Review", "pr", "1"], #args == 3
  local completions = commands.complete_review("1", "Review pr 1", 11)
  expect.equality(#completions, 0)
end

T["complete_ai"] = MiniTest.new_set()

T["complete_ai"]["returns AI providers"] = function()
  local commands = get_commands()

  local completions = commands.complete_ai("", "ReviewAI ", 9)
  expect.equality(vim.tbl_contains(completions, "pick"), true)
  expect.equality(vim.tbl_contains(completions, "list"), true)
  expect.equality(vim.tbl_contains(completions, "clipboard"), true)
  expect.equality(vim.tbl_contains(completions, "opencode"), true)
  expect.equality(vim.tbl_contains(completions, "claude"), true)
end

T["complete_ai"]["filters by prefix"] = function()
  local commands = get_commands()

  local completions = commands.complete_ai("cl", "ReviewAI cl", 11)
  expect.equality(vim.tbl_contains(completions, "clipboard"), true)
  expect.equality(vim.tbl_contains(completions, "claude"), true)
  expect.equality(vim.tbl_contains(completions, "pick"), false)
end

T["complete_comment"] = MiniTest.new_set()

T["complete_comment"]["returns comment types"] = function()
  local commands = get_commands()

  local completions = commands.complete_comment("", "ReviewComment ", 14)
  expect.equality(vim.tbl_contains(completions, "note"), true)
  expect.equality(vim.tbl_contains(completions, "issue"), true)
  expect.equality(vim.tbl_contains(completions, "suggestion"), true)
  expect.equality(vim.tbl_contains(completions, "praise"), true)
end

T["complete_comment"]["filters by prefix"] = function()
  local commands = get_commands()

  local completions = commands.complete_comment("i", "ReviewComment i", 15)
  expect.equality(vim.tbl_contains(completions, "issue"), true)
  expect.equality(vim.tbl_contains(completions, "note"), false)
end

-- =============================================================================
-- handle_review_command Tests
-- =============================================================================

T["handle_review_command"] = MiniTest.new_set()

T["handle_review_command"]["close requires active session"] = function()
  local state = get_state()
  local commands = get_commands()

  state.state.active = false

  local notified = false
  vim.notify = function(msg)
    if msg:find("No active") then
      notified = true
    end
  end

  commands.handle_review_command("close")
  -- Should not error
end

T["handle_review_command"]["panel requires active session"] = function()
  local state = get_state()
  local commands = get_commands()

  state.state.active = false

  local notified = false
  vim.notify = function(msg)
    if msg:find("No active") then
      notified = true
    end
  end

  commands.handle_review_command("panel")
  expect.equality(notified, true)
end

T["handle_review_command"]["refresh requires active session"] = function()
  local state = get_state()
  local commands = get_commands()

  state.state.active = false

  local notified = false
  vim.notify = function(msg)
    if msg:find("No active") then
      notified = true
    end
  end

  commands.handle_review_command("refresh")
  expect.equality(notified, true)
end

T["handle_review_command"]["status shows no active session"] = function()
  local state = get_state()
  local commands = get_commands()

  state.state.active = false

  local notified = false
  vim.notify = function(msg)
    if msg:find("No active") then
      notified = true
    end
  end

  commands.handle_review_command("status")
  expect.equality(notified, true)
end

T["handle_review_command"]["pr with invalid number shows error"] = function()
  local commands = get_commands()

  local error_notified = false
  vim.notify = function(msg, level)
    if level == vim.log.levels.ERROR and msg:find("Invalid PR number") then
      error_notified = true
    end
  end

  commands.handle_review_command("pr invalid")
  expect.equality(error_notified, true)
end

T["handle_review_command"]["pr with valid number calls open_pr"] = function()
  local commands = get_commands()

  local opened_pr = nil
  commands.open_pr = function(num)
    opened_pr = num
  end

  commands.handle_review_command("pr 123")
  expect.equality(opened_pr, 123)
end

T["handle_review_command"]["pr without number calls pick_pr"] = function()
  local commands = get_commands()

  local picker_called = false
  commands.pick_pr = function()
    picker_called = true
  end

  commands.handle_review_command("pr")
  expect.equality(picker_called, true)
end

T["handle_review_command"]["unknown arg calls open_local with base"] = function()
  local commands = get_commands()

  local base_used = nil
  commands.open_local = function(base)
    base_used = base
  end

  commands.handle_review_command("develop")
  expect.equality(base_used, "develop")
end

T["handle_review_command"]["no args calls open_local"] = function()
  local commands = get_commands()

  local open_local_called = false
  commands.open_local = function()
    open_local_called = true
  end

  commands.handle_review_command("")
  expect.equality(open_local_called, true)
end

-- =============================================================================
-- handle_ai_command Tests
-- =============================================================================

T["handle_ai_command"] = MiniTest.new_set()

T["handle_ai_command"]["requires active session"] = function()
  local state = get_state()
  local commands = get_commands()

  state.state.active = false

  local warned = false
  vim.notify = function(msg, level)
    if level == vim.log.levels.WARN and msg:find("No active") then
      warned = true
    end
  end

  commands.handle_ai_command("")
  expect.equality(warned, true)
end

T["handle_ai_command"]["pick calls pick_ai_provider"] = function()
  local state = get_state()
  local commands = get_commands()

  state.state.active = true

  local picker_called = false
  commands.pick_ai_provider = function()
    picker_called = true
  end

  commands.handle_ai_command("pick")
  expect.equality(picker_called, true)
end

T["handle_ai_command"]["list calls list_ai_providers"] = function()
  local state = get_state()
  local commands = get_commands()

  state.state.active = true

  local list_called = false
  commands.list_ai_providers = function()
    list_called = true
  end

  commands.handle_ai_command("list")
  expect.equality(list_called, true)
end

T["handle_ai_command"]["clipboard calls send_to_clipboard"] = function()
  local state = get_state()
  local commands = get_commands()

  state.state.active = true

  local clipboard_called = false
  commands.send_to_clipboard = function()
    clipboard_called = true
  end

  commands.handle_ai_command("clipboard")
  expect.equality(clipboard_called, true)
end

T["handle_ai_command"]["provider name calls send_to_ai"] = function()
  local state = get_state()
  local commands = get_commands()

  state.state.active = true

  local sent_provider = nil
  commands.send_to_ai = function(provider)
    sent_provider = provider
  end

  commands.handle_ai_command("claude")
  expect.equality(sent_provider, "claude")
end

T["handle_ai_command"]["no args calls send_to_ai"] = function()
  local state = get_state()
  local commands = get_commands()

  state.state.active = true

  local send_called = false
  commands.send_to_ai = function()
    send_called = true
  end

  commands.handle_ai_command("")
  expect.equality(send_called, true)
end

-- =============================================================================
-- handle_comment_command Tests
-- =============================================================================

T["handle_comment_command"] = MiniTest.new_set()

T["handle_comment_command"]["requires active session"] = function()
  local state = get_state()
  local commands = get_commands()

  state.state.active = false

  local warned = false
  vim.notify = function(msg, level)
    if level == vim.log.levels.WARN and msg:find("No active") then
      warned = true
    end
  end

  commands.handle_comment_command("note")
  expect.equality(warned, true)
end

T["handle_comment_command"]["rejects invalid type"] = function()
  local state = get_state()
  local commands = get_commands()

  state.state.active = true

  local error_shown = false
  vim.notify = function(msg, level)
    if level == vim.log.levels.ERROR and msg:find("Invalid comment type") then
      error_shown = true
    end
  end

  commands.handle_comment_command("invalid")
  expect.equality(error_shown, true)
end

T["handle_comment_command"]["accepts valid types"] = function()
  local state = get_state()
  local commands = get_commands()

  state.state.active = true

  local add_comment_type = nil
  commands.add_comment = function(ctype)
    add_comment_type = ctype
  end

  commands.handle_comment_command("note")
  expect.equality(add_comment_type, "note")

  commands.handle_comment_command("issue")
  expect.equality(add_comment_type, "issue")

  commands.handle_comment_command("suggestion")
  expect.equality(add_comment_type, "suggestion")

  commands.handle_comment_command("praise")
  expect.equality(add_comment_type, "praise")
end

T["handle_comment_command"]["defaults to note"] = function()
  local state = get_state()
  local commands = get_commands()

  state.state.active = true

  local add_comment_type = nil
  commands.add_comment = function(ctype)
    add_comment_type = ctype
  end

  commands.handle_comment_command("")
  expect.equality(add_comment_type, "note")
end

-- =============================================================================
-- close Tests
-- =============================================================================

T["close"] = MiniTest.new_set()

T["close"]["shows message when no active session"] = function()
  local state = get_state()
  local commands = get_commands()

  state.state.active = false

  local notified = false
  vim.notify = function(msg)
    if msg:find("No active") then
      notified = true
    end
  end

  commands.close()
  expect.equality(notified, true)
end

-- =============================================================================
-- show_status Tests
-- =============================================================================

T["show_status"] = MiniTest.new_set()

T["show_status"]["shows no active session when inactive"] = function()
  local state = get_state()
  local commands = get_commands()

  state.state.active = false

  local notified = false
  vim.notify = function(msg)
    if msg:find("No active") then
      notified = true
    end
  end

  commands.show_status()
  expect.equality(notified, true)
end

T["show_status"]["shows status when active"] = function()
  local state = get_state()
  local commands = get_commands()

  state.state.active = true
  state.state.mode = "local"
  state.state.base = "main"
  state.set_files({
    { path = "a.lua", status = "modified" },
    { path = "b.lua", status = "added" },
  })

  local status_msg = nil
  vim.notify = function(msg)
    status_msg = msg
  end

  commands.show_status()

  expect.equality(status_msg ~= nil, true)
  expect.equality(status_msg:find("Mode: local") ~= nil, true)
  expect.equality(status_msg:find("Base: main") ~= nil, true)
  expect.equality(status_msg:find("Files: 2") ~= nil, true)
end

T["show_status"]["includes PR info when in PR mode"] = function()
  local state = get_state()
  local commands = get_commands()

  state.state.active = true
  state.state.mode = "pr"
  state.state.pr = {
    number = 123,
    title = "Test PR",
  }

  local status_msg = nil
  vim.notify = function(msg)
    status_msg = msg
  end

  commands.show_status()

  expect.equality(status_msg ~= nil, true)
  expect.equality(status_msg:find("PR: #123") ~= nil, true)
end

-- =============================================================================
-- send_to_clipboard Tests
-- =============================================================================

T["send_to_clipboard"] = MiniTest.new_set()

T["send_to_clipboard"]["requires active session"] = function()
  local state = get_state()
  local commands = get_commands()

  state.state.active = false

  local warned = false
  vim.notify = function(msg, level)
    if level == vim.log.levels.WARN and msg:find("No active") then
      warned = true
    end
  end

  commands.send_to_clipboard()
  expect.equality(warned, true)
end

T["send_to_clipboard"]["copies to clipboard"] = function()
  local state = get_state()
  local commands = get_commands()

  state.state.active = true
  state.set_files({
    { path = "test.lua", status = "modified" },
  })

  -- Clear clipboard
  vim.fn.setreg("+", "")
  vim.fn.setreg("*", "")

  commands.send_to_clipboard()

  local clipboard = vim.fn.getreg("+")
  expect.equality(clipboard:find("Code Review") ~= nil, true)
  expect.equality(clipboard:find("test.lua") ~= nil, true)
end

T["send_to_clipboard"]["includes pending comments"] = function()
  local state = get_state()
  local commands = get_commands()

  state.state.active = true
  state.set_files({
    { path = "test.lua", status = "modified" },
  })
  state.set_comments({
    {
      id = "1",
      kind = "local",
      status = "pending",
      type = "issue",
      file = "test.lua",
      line = 10,
      body = "This needs fixing",
    },
  })

  commands.send_to_clipboard()

  local clipboard = vim.fn.getreg("+")
  expect.equality(clipboard:find("Review Comments") ~= nil, true)
  expect.equality(clipboard:find("This needs fixing") ~= nil, true)
end

-- =============================================================================
-- list_ai_providers Tests
-- =============================================================================

T["list_ai_providers"] = MiniTest.new_set()

T["list_ai_providers"]["shows provider list"] = function()
  local commands = get_commands()

  local msg = nil
  vim.notify = function(m)
    msg = m
  end

  commands.list_ai_providers()

  expect.equality(msg ~= nil, true)
  expect.equality(msg:find("opencode") ~= nil, true)
  expect.equality(msg:find("claude") ~= nil, true)
  expect.equality(msg:find("clipboard") ~= nil, true)
end

-- =============================================================================
-- add_comment Tests
-- =============================================================================

T["add_comment"] = MiniTest.new_set()

T["add_comment"]["requires current file"] = function()
  local state = get_state()
  local commands = get_commands()

  state.state.active = true
  state.state.current_file = nil

  local warned = false
  vim.notify = function(msg, level)
    if level == vim.log.levels.WARN and msg:find("No file") then
      warned = true
    end
  end

  commands.add_comment("note")
  expect.equality(warned, true)
end

-- =============================================================================
-- send_to_ai Tests
-- =============================================================================

T["send_to_ai"] = MiniTest.new_set()

T["send_to_ai"]["requires active session"] = function()
  local state = get_state()
  local commands = get_commands()

  state.state.active = false

  local warned = false
  vim.notify = function(msg, level)
    if level == vim.log.levels.WARN and msg:find("No active") then
      warned = true
    end
  end

  commands.send_to_ai()
  expect.equality(warned, true)
end

T["send_to_ai"]["shows info with provider"] = function()
  local state = get_state()
  local commands = get_commands()

  state.state.active = true

  local notified = false
  vim.notify = function(msg)
    if msg:find("claude") then
      notified = true
    end
  end

  commands.send_to_ai("claude")
  expect.equality(notified, true)
end

return T
