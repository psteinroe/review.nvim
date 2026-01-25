-- Tests for review.config module
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Reset config module before each test
      package.loaded["review.config"] = nil
    end,
  },
})

local function get_config()
  return require("review.config")
end

T["defaults"] = MiniTest.new_set()

T["defaults"]["has ui settings"] = function()
  local config = get_config()
  MiniTest.expect.equality(type(config.defaults.ui), "table")
  MiniTest.expect.equality(config.defaults.ui.tree_width, 30)
  MiniTest.expect.equality(config.defaults.ui.panel_width, 80)
  MiniTest.expect.equality(config.defaults.ui.panel_height, 40)
end

T["defaults"]["has signs settings"] = function()
  local config = get_config()
  MiniTest.expect.equality(type(config.defaults.signs), "table")
  MiniTest.expect.equality(type(config.defaults.signs.comment_github), "string")
  MiniTest.expect.equality(type(config.defaults.signs.comment_local), "string")
  MiniTest.expect.equality(type(config.defaults.signs.comment_issue), "string")
  MiniTest.expect.equality(type(config.defaults.signs.comment_suggestion), "string")
  MiniTest.expect.equality(type(config.defaults.signs.comment_praise), "string")
  MiniTest.expect.equality(type(config.defaults.signs.comment_resolved), "string")
end

T["defaults"]["has keymaps settings"] = function()
  local config = get_config()
  MiniTest.expect.equality(type(config.defaults.keymaps), "table")
  MiniTest.expect.equality(config.defaults.keymaps.enabled, true)
end

T["defaults"]["has github settings"] = function()
  local config = get_config()
  MiniTest.expect.equality(type(config.defaults.github), "table")
  MiniTest.expect.equality(config.defaults.github.enabled, true)
end

T["defaults"]["has ai settings"] = function()
  local config = get_config()
  MiniTest.expect.equality(type(config.defaults.ai), "table")
  MiniTest.expect.equality(config.defaults.ai.provider, "auto")
  MiniTest.expect.equality(type(config.defaults.ai.preference), "table")
  MiniTest.expect.equality(type(config.defaults.ai.terminal), "table")
  MiniTest.expect.equality(config.defaults.ai.terminal.height, 15)
  MiniTest.expect.equality(config.defaults.ai.terminal.position, "bottom")
end

T["setup()"] = MiniTest.new_set()

T["setup()"]["uses defaults when called with no args"] = function()
  local config = get_config()
  config.setup()
  MiniTest.expect.equality(config.config.ui.tree_width, 30)
  MiniTest.expect.equality(config.config.signs.comment_github, "G")
end

T["setup()"]["uses defaults when called with empty table"] = function()
  local config = get_config()
  config.setup({})
  MiniTest.expect.equality(config.config.ui.tree_width, 30)
end

T["setup()"]["merges user options with defaults"] = function()
  local config = get_config()
  config.setup({
    ui = { tree_width = 40 },
  })
  MiniTest.expect.equality(config.config.ui.tree_width, 40)
  MiniTest.expect.equality(config.config.ui.panel_width, 80) -- default preserved
end

T["setup()"]["deep merges nested options"] = function()
  local config = get_config()
  config.setup({
    ai = {
      provider = "claude",
      terminal = { height = 20 },
    },
  })
  MiniTest.expect.equality(config.config.ai.provider, "claude")
  MiniTest.expect.equality(config.config.ai.terminal.height, 20)
  MiniTest.expect.equality(config.config.ai.terminal.position, "bottom") -- default preserved
end

T["setup()"]["allows custom ai preference order"] = function()
  local config = get_config()
  config.setup({
    ai = {
      preference = { "claude", "clipboard" },
    },
  })
  MiniTest.expect.equality(#config.config.ai.preference, 2)
  MiniTest.expect.equality(config.config.ai.preference[1], "claude")
  MiniTest.expect.equality(config.config.ai.preference[2], "clipboard")
end

T["setup()"]["allows custom handler function"] = function()
  local config = get_config()
  local handler = function() end
  config.setup({
    ai = {
      provider = "custom",
      custom_handler = handler,
    },
  })
  MiniTest.expect.equality(config.config.ai.provider, "custom")
  MiniTest.expect.equality(config.config.ai.custom_handler, handler)
end

T["get()"] = MiniTest.new_set()

T["get()"]["returns nil when config not setup"] = function()
  local config = get_config()
  -- config not setup yet
  MiniTest.expect.equality(config.get("ui.tree_width"), nil)
end

T["get()"]["returns value for top-level key"] = function()
  local config = get_config()
  config.setup()
  MiniTest.expect.equality(type(config.get("ui")), "table")
end

T["get()"]["returns value for nested key"] = function()
  local config = get_config()
  config.setup()
  MiniTest.expect.equality(config.get("ui.tree_width"), 30)
end

T["get()"]["returns value for deeply nested key"] = function()
  local config = get_config()
  config.setup()
  MiniTest.expect.equality(config.get("ai.terminal.height"), 15)
end

T["get()"]["returns nil for non-existent key"] = function()
  local config = get_config()
  config.setup()
  MiniTest.expect.equality(config.get("nonexistent"), nil)
end

T["get()"]["returns nil for non-existent nested key"] = function()
  local config = get_config()
  config.setup()
  MiniTest.expect.equality(config.get("ui.nonexistent"), nil)
end

T["get()"]["returns nil for path through non-table"] = function()
  local config = get_config()
  config.setup()
  MiniTest.expect.equality(config.get("ui.tree_width.nested"), nil)
end

T["is_setup()"] = MiniTest.new_set()

T["is_setup()"]["returns false before setup"] = function()
  local config = get_config()
  MiniTest.expect.equality(config.is_setup(), false)
end

T["is_setup()"]["returns true after setup"] = function()
  local config = get_config()
  config.setup()
  MiniTest.expect.equality(config.is_setup(), true)
end

return T
