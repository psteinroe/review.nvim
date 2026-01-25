-- AI integration for review.nvim
-- Supports multiple providers: opencode, claude, codex, aider, avante, clipboard, custom
local M = {}

local config = require("review.config")

---@alias Review.AIProvider "opencode" | "claude" | "codex" | "aider" | "avante" | "clipboard" | "custom"

---@class Review.AIProviderConfig
---@field name string Display name
---@field check fun(): boolean Check if available
---@field send fun(prompt: string, opts: table) Send prompt to provider
---@field description string Help text

---@type table<Review.AIProvider, Review.AIProviderConfig>
M.providers = {}

-- ============================================================================
-- PROVIDER: OpenCode (CLI)
-- ============================================================================
M.providers.opencode = {
  name = "OpenCode",
  description = "OpenCode CLI tool for AI-assisted coding",

  check = function()
    return vim.fn.executable("opencode") == 1
  end,

  send = function(prompt, opts)
    opts = opts or {}

    -- Write prompt to temp file
    local tmp_file = vim.fn.tempname() .. ".md"
    vim.fn.writefile(vim.split(prompt, "\n"), tmp_file)

    -- Start opencode in terminal with prompt file
    local cmd = string.format("opencode --prompt-file %s", vim.fn.shellescape(tmp_file))
    M.open_terminal(cmd, {
      title = "OpenCode",
      cwd = vim.fn.getcwd(),
      on_exit = function()
        vim.fn.delete(tmp_file)
      end,
    })
  end,
}

-- ============================================================================
-- PROVIDER: Claude Code (Anthropic CLI)
-- ============================================================================
M.providers.claude = {
  name = "Claude Code",
  description = "Anthropic's Claude Code CLI tool",

  check = function()
    return vim.fn.executable("claude") == 1
  end,

  send = function(prompt, opts)
    opts = opts or {}

    -- Write prompt to temp file
    local tmp_file = vim.fn.tempname() .. ".md"
    vim.fn.writefile(vim.split(prompt, "\n"), tmp_file)

    -- For longer prompts, use file input via stdin
    local cmd = string.format("cat %s | claude", vim.fn.shellescape(tmp_file))

    -- Open in terminal buffer
    M.open_terminal(cmd, {
      title = "Claude Code",
      cwd = vim.fn.getcwd(),
      on_exit = function()
        vim.fn.delete(tmp_file)
      end,
    })
  end,
}

-- ============================================================================
-- PROVIDER: Codex (OpenAI CLI)
-- ============================================================================
M.providers.codex = {
  name = "Codex CLI",
  description = "OpenAI's Codex CLI tool",

  check = function()
    return vim.fn.executable("codex") == 1
  end,

  send = function(prompt, opts)
    opts = opts or {}

    -- Write prompt to temp file
    local tmp_file = vim.fn.tempname() .. ".md"
    vim.fn.writefile(vim.split(prompt, "\n"), tmp_file)

    -- Codex CLI - pipe from file
    local cmd = string.format("codex < %s", vim.fn.shellescape(tmp_file))

    M.open_terminal(cmd, {
      title = "Codex",
      cwd = vim.fn.getcwd(),
      on_exit = function()
        vim.fn.delete(tmp_file)
      end,
    })
  end,
}

-- ============================================================================
-- PROVIDER: Aider
-- ============================================================================
M.providers.aider = {
  name = "Aider",
  description = "AI pair programming in terminal",

  check = function()
    return vim.fn.executable("aider") == 1
  end,

  send = function(prompt, opts)
    opts = opts or {}

    -- Get list of changed files to add to aider
    local state = require("review.core.state")
    local files = vim.tbl_map(function(f)
      return f.path
    end, state.state.files)
    local files_arg = table.concat(files, " ")

    -- Write prompt to temp file for --message-file
    local tmp_file = vim.fn.tempname() .. ".md"
    vim.fn.writefile(vim.split(prompt, "\n"), tmp_file)

    -- Build aider command
    local cmd = string.format("aider --message-file %s %s", vim.fn.shellescape(tmp_file), files_arg)

    M.open_terminal(cmd, {
      title = "Aider",
      cwd = vim.fn.getcwd(),
      on_exit = function()
        vim.fn.delete(tmp_file)
      end,
    })
  end,
}

-- ============================================================================
-- PROVIDER: Avante.nvim
-- ============================================================================
M.providers.avante = {
  name = "Avante",
  description = "Avante.nvim plugin integration",

  check = function()
    local has_avante = pcall(require, "avante")
    return has_avante
  end,

  send = function(prompt, opts)
    local ok, avante = pcall(require, "avante.api")
    if not ok then
      vim.notify("Avante.nvim not available", vim.log.levels.ERROR)
      return
    end

    -- Open avante sidebar with the prompt
    avante.ask({ question = prompt })
  end,
}

-- ============================================================================
-- PROVIDER: Clipboard (Fallback)
-- ============================================================================
M.providers.clipboard = {
  name = "Clipboard",
  description = "Copy prompt to clipboard",

  check = function()
    return true -- Always available
  end,

  send = function(prompt, opts)
    vim.fn.setreg("+", prompt)
    vim.fn.setreg("*", prompt)
    vim.notify("Review prompt copied to clipboard", vim.log.levels.INFO)
  end,
}

-- ============================================================================
-- PROVIDER: Custom (User-defined)
-- ============================================================================
M.providers.custom = {
  name = "Custom",
  description = "User-defined AI integration",

  check = function()
    local custom_fn = config.get("ai.custom_handler")
    return custom_fn ~= nil
  end,

  send = function(prompt, opts)
    local custom_fn = config.get("ai.custom_handler")
    if custom_fn then
      custom_fn(prompt, opts)
    else
      vim.notify("No custom AI handler configured", vim.log.levels.ERROR)
    end
  end,
}

-- ============================================================================
-- Core Functions
-- ============================================================================

---Get the configured or best available provider
---@return Review.AIProviderConfig?
---@return string? provider_name
function M.get_provider()
  local configured = config.get("ai.provider")

  -- If explicitly configured, try that first
  if configured and configured ~= "auto" then
    local provider = M.providers[configured]
    if provider and provider.check() then
      return provider, configured
    else
      vim.notify(
        string.format("AI provider '%s' not available, falling back to auto-detect", configured),
        vim.log.levels.WARN
      )
    end
  end

  -- Auto-detect: try providers in preference order
  local preference_order = config.get("ai.preference")
    or { "opencode", "avante", "claude", "codex", "aider", "clipboard" }

  for _, name in ipairs(preference_order) do
    local provider = M.providers[name]
    if provider and provider.check() then
      return provider, name
    end
  end

  -- Ultimate fallback
  return M.providers.clipboard, "clipboard"
end

---Send review context to AI
---@param opts? {provider?: string}
function M.send_to_ai(opts)
  opts = opts or {}

  local provider, provider_name
  if opts.provider then
    provider = M.providers[opts.provider]
    provider_name = opts.provider
    if not provider then
      vim.notify("Unknown AI provider: " .. opts.provider, vim.log.levels.ERROR)
      return
    end
    if not provider.check() then
      vim.notify("AI provider not available: " .. opts.provider, vim.log.levels.ERROR)
      return
    end
  else
    provider, provider_name = M.get_provider()
  end

  if not provider then
    vim.notify("No AI provider available", vim.log.levels.ERROR)
    return
  end

  local prompt = M.build_prompt()

  vim.notify(string.format("Sending to %s...", provider.name), vim.log.levels.INFO)
  provider.send(prompt, { provider = provider_name })
end

---Show picker to select AI provider
function M.pick_provider()
  local items = {}
  for name, provider in pairs(M.providers) do
    local available = provider.check()
    table.insert(items, {
      name = name,
      provider = provider,
      available = available,
      display = string.format("%s %s - %s", available and "+" or "-", provider.name, provider.description),
    })
  end

  -- Sort: available first, then alphabetically
  table.sort(items, function(a, b)
    if a.available ~= b.available then
      return a.available
    end
    return a.name < b.name
  end)

  vim.ui.select(items, {
    prompt = "Select AI Provider:",
    format_item = function(item)
      return item.display
    end,
  }, function(choice)
    if choice then
      if not choice.available then
        vim.notify(choice.provider.name .. " is not available", vim.log.levels.WARN)
        return
      end
      M.send_to_ai({ provider = choice.name })
    end
  end)
end

---Build AI prompt from current review state
---@param opts? {include_diff?: boolean, include_comments?: boolean, include_instructions?: boolean}
---@return string
function M.build_prompt(opts)
  opts = vim.tbl_extend("force", {
    include_diff = true,
    include_comments = true,
    include_instructions = true,
  }, opts or {})

  local state = require("review.core.state")
  local git = require("review.integrations.git")

  local lines = {
    "# Code Review",
    "",
  }

  -- PR context if available
  if state.state.pr then
    table.insert(lines, "## PR Information")
    table.insert(lines, "")
    table.insert(lines, string.format("**PR #%d**: %s", state.state.pr.number, state.state.pr.title))
    table.insert(lines, string.format("**Author**: @%s", state.state.pr.author))
    table.insert(lines, string.format("**Branch**: %s -> %s", state.state.pr.branch, state.state.pr.base))
    table.insert(lines, "")
    if state.state.pr.description and state.state.pr.description ~= "" then
      table.insert(lines, "### Description")
      table.insert(lines, "")
      table.insert(lines, state.state.pr.description)
      table.insert(lines, "")
    end
  end

  -- Diff
  if opts.include_diff then
    table.insert(lines, "## Changes")
    table.insert(lines, "")
    table.insert(lines, "```diff")

    local diff
    if state.state.mode == "pr" and state.state.pr then
      local github = require("review.integrations.github")
      diff = github.fetch_pr_diff(state.state.pr.number)
    else
      diff = git.diff(state.state.base)
    end
    table.insert(lines, diff)
    table.insert(lines, "```")
    table.insert(lines, "")
  end

  -- Comments
  if opts.include_comments then
    local pending = state.get_pending_comments()
    if #pending > 0 then
      table.insert(lines, "## Review Comments")
      table.insert(lines, "")
      table.insert(lines, "Please address the following comments:")
      table.insert(lines, "")

      for i, comment in ipairs(pending) do
        local type_label = M.get_type_label(comment.type)
        local file_info = ""
        if comment.file then
          file_info = string.format("`%s:%d`", comment.file, comment.line or 0)
        end
        table.insert(lines, string.format("%d. **[%s]** %s", i, type_label, file_info))
        table.insert(lines, string.format("   %s", comment.body))
        table.insert(lines, "")
      end
    end
  end

  -- Instructions
  if opts.include_instructions then
    local custom_instructions = config.get("ai.instructions")
    if custom_instructions then
      table.insert(lines, "## Instructions")
      table.insert(lines, "")
      table.insert(lines, custom_instructions)
    else
      table.insert(lines, "## Instructions")
      table.insert(lines, "")
      table.insert(lines, "Please review the code changes and address any comments. For each issue:")
      table.insert(lines, "1. Explain what the problem is")
      table.insert(lines, "2. Provide the corrected code")
      table.insert(lines, "3. Explain your fix")
    end
    table.insert(lines, "")
  end

  return table.concat(lines, "\n")
end

---Get label for comment type
---@param type? string
---@return string
function M.get_type_label(type)
  local labels = {
    note = "NOTE",
    issue = "ISSUE",
    suggestion = "SUGGESTION",
    praise = "PRAISE",
  }
  return labels[type] or "COMMENT"
end

---Copy prompt to clipboard (convenience function)
function M.send_to_clipboard()
  local prompt = M.build_prompt()
  vim.fn.setreg("+", prompt)
  vim.fn.setreg("*", prompt)
  vim.notify("Review prompt copied to clipboard", vim.log.levels.INFO)
end

---Get list of available providers
---@return table[] List of {name: string, provider: Review.AIProviderConfig, available: boolean}
function M.get_available_providers()
  local result = {}
  for name, provider in pairs(M.providers) do
    table.insert(result, {
      name = name,
      provider = provider,
      available = provider.check(),
    })
  end
  table.sort(result, function(a, b)
    return a.name < b.name
  end)
  return result
end

-- ============================================================================
-- Helpers
-- ============================================================================

---Open a terminal buffer with command
---@param cmd string
---@param opts? {title?: string, cwd?: string, on_exit?: function, height?: number, position?: string}
function M.open_terminal(cmd, opts)
  opts = opts or {}

  -- Get terminal config
  local term_height = opts.height or config.get("ai.terminal.height") or 15
  local term_position = opts.position or config.get("ai.terminal.position") or "bottom"

  -- Create new split for terminal
  if term_position == "right" then
    vim.cmd("botright vsplit")
    vim.cmd("vertical resize 80")
  else
    vim.cmd("botright split")
    vim.cmd("resize " .. term_height)
  end

  -- Open terminal
  local term_opts = {
    cwd = opts.cwd,
    on_exit = function(_, exit_code, _)
      if opts.on_exit then
        opts.on_exit(exit_code)
      end
    end,
  }

  vim.fn.termopen(cmd, term_opts)

  -- Set buffer name
  if opts.title then
    pcall(vim.api.nvim_buf_set_name, 0, string.format("[%s]", opts.title))
  end

  -- Enter insert mode
  vim.cmd("startinsert")
end

---Escape string for shell
---@param str string
---@return string
function M.escape_for_shell(str)
  -- Replace single quotes with escaped version
  return str:gsub("'", "'\\''")
end

---Register a custom provider
---@param name string
---@param provider Review.AIProviderConfig
function M.register_provider(name, provider)
  M.providers[name] = provider
end

---Unregister a provider
---@param name string
function M.unregister_provider(name)
  M.providers[name] = nil
end

return M
