-- review.nvim main module
-- A Neovim plugin for efficient code reviews with GitHub integration and AI feedback loops

local M = {}

---@type boolean Whether the plugin has been set up
local is_setup = false

---Setup the plugin
---@param opts? Review.Config User configuration
function M.setup(opts)
  if is_setup then
    return
  end

  -- Setup configuration first (other modules depend on it)
  local config = require("review.config")
  config.setup(opts)

  -- Setup highlights
  local highlights = require("review.ui.highlights")
  highlights.setup()

  -- Setup commands
  local commands = require("review.commands")
  commands.setup()

  -- Setup keymaps
  local keymaps = require("review.keymaps")
  keymaps.setup()

  -- Setup autocommands
  M.setup_autocmds()

  is_setup = true
end

---Setup autocommands
function M.setup_autocmds()
  local augroup = vim.api.nvim_create_augroup("ReviewNvim", { clear = true })

  -- Clean up when tabpage is closed
  vim.api.nvim_create_autocmd("TabClosed", {
    group = augroup,
    callback = function()
      local state = require("review.core.state")
      if state.is_active() and state.state.layout.tabpage then
        -- Check if our tabpage still exists
        local tabs = vim.api.nvim_list_tabpages()
        local found = false
        for _, tab in ipairs(tabs) do
          if tab == state.state.layout.tabpage then
            found = true
            break
          end
        end
        if not found then
          state.reset()
        end
      end
    end,
  })

  -- Refresh signs/virtual text on buffer write
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = augroup,
    callback = function(args)
      local state = require("review.core.state")
      if state.is_active() and state.state.current_file then
        local signs = require("review.ui.signs")
        local virtual_text = require("review.ui.virtual_text")
        signs.refresh()
        virtual_text.refresh()
      end
    end,
  })
end

-- =============================================================================
-- Public API
-- =============================================================================

---Open review - auto-detects PR branch for hybrid mode, else local mode
---@param base? string Base ref to diff against (default: auto-detect or HEAD)
function M.open(base)
  if not is_setup then
    vim.notify("review.nvim not set up. Call require('review').setup() first.", vim.log.levels.ERROR)
    return
  end

  local commands = require("review.commands")

  -- If no explicit base provided, check for PR and use hybrid mode
  if not base then
    local github = require("review.integrations.github")
    if github.is_available() then
      local pr_number = github.get_current_pr_number()
      if pr_number then
        commands.open_hybrid(pr_number)
        return
      end
    end
  end

  commands.open_local(base)
end

---Open PR review
---@param pr_number number PR number
function M.open_pr(pr_number)
  if not is_setup then
    vim.notify("review.nvim not set up. Call require('review').setup() first.", vim.log.levels.ERROR)
    return
  end

  local commands = require("review.commands")
  commands.open_pr(pr_number)
end

---Open PR picker
function M.pick_pr()
  if not is_setup then
    vim.notify("review.nvim not set up. Call require('review').setup() first.", vim.log.levels.ERROR)
    return
  end

  local commands = require("review.commands")
  commands.pick_pr()
end

---Close active review session
function M.close()
  local commands = require("review.commands")
  commands.close()
end

---Toggle PR panel
function M.toggle_panel()
  local commands = require("review.commands")
  commands.toggle_panel()
end

---Refresh current review
function M.refresh()
  local commands = require("review.commands")
  commands.refresh()
end

---Show review status
function M.status()
  local commands = require("review.commands")
  commands.show_status()
end

---Add comment at current cursor position
---@param comment_type? "note" | "issue" | "suggestion" | "praise" Comment type (default: note)
function M.add_comment(comment_type)
  local commands = require("review.commands")
  commands.add_comment(comment_type or "note")
end

---Send review to AI provider
---@param provider? string Specific provider to use
function M.send_to_ai(provider)
  local commands = require("review.commands")
  commands.send_to_ai(provider)
end

---Copy review to clipboard
function M.send_to_clipboard()
  local commands = require("review.commands")
  commands.send_to_clipboard()
end

---Check if a review session is active
---@return boolean
function M.is_active()
  local state = require("review.core.state")
  return state.is_active()
end

---Get current state (read-only)
---@return Review.State
function M.get_state()
  local state = require("review.core.state")
  return state.state
end

---Get configuration
---@return Review.Config
function M.get_config()
  local config = require("review.config")
  return config.config
end

---Check if plugin is set up
---@return boolean
function M.is_setup()
  return is_setup
end

return M
