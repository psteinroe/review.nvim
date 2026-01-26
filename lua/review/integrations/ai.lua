-- AI integration for review.nvim
-- Sends review comments to AI tools for background processing

local M = {}

local state = require("review.core.state")
local config = require("review.config")
local utils = require("review.utils")
local git = require("review.integrations.git")

---@class Review.AIJob
---@field id number Job ID
---@field provider string Provider name
---@field comment_ids string[] IDs of comments being processed
---@field start_time number Start timestamp
---@field watcher? userdata File watcher handle

---@type Review.AIJob?
local current_job = nil

---@type string[] Output lines from current/last job
local job_output = {}

---@type table<string, string> Provider to command mapping
-- Use $PROMPT_FILE as placeholder for the temp file path containing the prompt
local PROVIDER_COMMANDS = {
  claude = 'claude --allowedTools "Edit,Write,Read,Glob,Grep" -p "$(cat $PROMPT_FILE)"',
  opencode = 'opencode -p "$(cat $PROMPT_FILE)"',
  codex = 'codex --approval-mode auto-edit "$(cat $PROMPT_FILE)"',
}

-- ============================================================================
-- Provider Detection
-- ============================================================================

---Check if a command exists in PATH
---@param cmd string Command name
---@return boolean
local function command_exists(cmd)
  return vim.fn.executable(cmd) == 1
end

---Detect available AI provider
---@return string? provider name or nil if none found
local function detect_provider()
  local preference = { "opencode", "claude", "codex" }
  for _, provider in ipairs(preference) do
    if command_exists(provider) then
      return provider
    end
  end
  return nil
end

---Get the command for a provider
---@param provider string Provider name
---@return string? command or nil
function M.get_command(provider)
  local cfg = config.get("ai") or {}

  -- Custom command takes priority
  if cfg.command then
    return cfg.command
  end

  return PROVIDER_COMMANDS[provider]
end

---Get the current provider
---@return string? provider name or nil
function M.get_provider()
  local cfg = config.get("ai") or {}
  local provider = cfg.provider or "auto"

  if provider == "auto" then
    return detect_provider()
  elseif provider == "custom" then
    if cfg.command then
      return "custom"
    end
    vim.notify("AI provider set to 'custom' but no command configured", vim.log.levels.ERROR)
    return nil
  else
    if command_exists(provider) then
      return provider
    end
    vim.notify("AI provider '" .. provider .. "' not found in PATH", vim.log.levels.ERROR)
    return nil
  end
end

-- ============================================================================
-- Prompt Building
-- ============================================================================

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

---Build the prompt from pending comments
---@param comments Review.Comment[] Comments to include
---@param extra_instructions? string Additional user instructions
---@return string prompt
function M.build_prompt(comments, extra_instructions)
  local lines = {}

  table.insert(lines, "Review the following code changes and address the comments below.")
  table.insert(lines, "")

  if extra_instructions and extra_instructions ~= "" then
    table.insert(lines, "Additional instructions:")
    table.insert(lines, extra_instructions)
    table.insert(lines, "")
  end

  -- Group comments by file
  local by_file = {}
  for _, comment in ipairs(comments) do
    local file = comment.file or "unknown"
    if not by_file[file] then
      by_file[file] = {}
    end
    table.insert(by_file[file], comment)
  end

  -- Get git root for context
  local root = git.root_dir() or vim.fn.getcwd()

  for file, file_comments in pairs(by_file) do
    table.insert(lines, "---")
    table.insert(lines, "File: " .. file)
    table.insert(lines, "")

    -- Try to get file diff
    local base = state.state.base or "HEAD"
    local diff = git.diff(base, nil, file)
    if diff and diff ~= "" then
      table.insert(lines, "Diff:")
      table.insert(lines, "```diff")
      table.insert(lines, diff)
      table.insert(lines, "```")
      table.insert(lines, "")
    end

    table.insert(lines, "Comments to address:")
    for _, comment in ipairs(file_comments) do
      local line_info = ""
      if comment.start_line and comment.end_line and comment.start_line ~= comment.end_line then
        line_info = string.format("Lines %d-%d", comment.start_line, comment.end_line)
      elseif comment.line then
        line_info = string.format("Line %d", comment.line)
      end

      local type_str = M.get_type_label(comment.type)
      table.insert(lines, string.format("- %s [%s]: %s", line_info, type_str, comment.body or ""))
    end
    table.insert(lines, "")
  end

  table.insert(lines, "---")
  table.insert(lines, "Apply the necessary changes to resolve these comments.")
  table.insert(lines, "Working directory: " .. root)

  return table.concat(lines, "\n")
end

-- ============================================================================
-- Comment Status Management
-- ============================================================================

---Refresh UI after status change
local function refresh_ui()
  local signs = utils.safe_require("review.ui.signs")
  local virtual_text = utils.safe_require("review.ui.virtual_text")
  local file_tree = utils.safe_require("review.ui.file_tree")

  if signs then signs.refresh() end
  if virtual_text then virtual_text.refresh() end
  if file_tree then file_tree.render() end
end

---Mark comments as AI processing
---@param comment_ids string[]
local function mark_comments_processing(comment_ids)
  for _, id in ipairs(comment_ids) do
    local comment = state.find_comment(id)
    if comment then
      comment.status = "ai_processing"
    end
  end
  refresh_ui()
end

---Mark comments as AI complete
---@param comment_ids string[]
local function mark_comments_complete(comment_ids)
  for _, id in ipairs(comment_ids) do
    local comment = state.find_comment(id)
    if comment then
      comment.status = "ai_complete"
    end
  end
  refresh_ui()
end

---Reset comments to pending
---@param comment_ids string[]
local function reset_comments_pending(comment_ids)
  for _, id in ipairs(comment_ids) do
    local comment = state.find_comment(id)
    if comment then
      comment.status = "pending"
    end
  end
  refresh_ui()
end

-- ============================================================================
-- File Watching
-- ============================================================================

---Start file watcher for auto-reload
---@return userdata? watcher handle
local function start_file_watcher()
  local cfg = config.get("ai") or {}
  if cfg.auto_reload == false then
    return nil
  end

  local root = git.root_dir() or vim.fn.getcwd()

  -- Use vim.uv (libuv) for file watching
  local handle = vim.uv.new_fs_event()
  if not handle then
    return nil
  end

  local ok = pcall(function()
    handle:start(root, { recursive = true }, function(err, filename, events)
      if err then
        return
      end

      -- Schedule buffer reload on main thread
      vim.schedule(function()
        -- Trigger checktime to reload changed buffers
        pcall(vim.cmd, "checktime")

        -- Refresh diff if active
        local diff = utils.safe_require("review.ui.diff")
        if diff and state.is_active() then
          diff.refresh()
          diff.refresh_decorations()
        end
      end)
    end)
  end)

  if not ok then
    return nil
  end

  return handle
end

---Stop file watcher
---@param handle userdata Watcher handle
local function stop_file_watcher(handle)
  if handle then
    pcall(function()
      handle:stop()
      handle:close()
    end)
  end
end

-- ============================================================================
-- Job Management
-- ============================================================================

---Escape prompt for shell
---@param prompt string
---@return string
local function escape_prompt(prompt)
  -- Escape single quotes by replacing ' with '\''
  return prompt:gsub("'", "'\\''")
end

---@type {win: number?, buf: number?, timer: userdata?}
local progress_indicator = {}

---Show floating progress indicator
---@param provider string
local function show_progress_indicator(provider)
  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"

  -- Create small floating window in top-right corner
  local width = 25
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = width,
    height = 1,
    col = vim.o.columns - width - 2,
    row = 1,
    style = "minimal",
    border = "rounded",
    focusable = false,
    zindex = 50,
  })

  -- Set highlight
  vim.api.nvim_set_option_value("winhl", "Normal:NormalFloat,FloatBorder:FloatBorder", { win = win })

  progress_indicator.win = win
  progress_indicator.buf = buf

  -- Spinner animation
  local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local spinner_idx = 1

  -- Update timer
  local timer = vim.uv.new_timer()
  progress_indicator.timer = timer

  timer:start(0, 100, vim.schedule_wrap(function()
    if not current_job then
      -- Job finished, close indicator
      if progress_indicator.timer then
        progress_indicator.timer:stop()
        progress_indicator.timer:close()
        progress_indicator.timer = nil
      end
      if progress_indicator.win and vim.api.nvim_win_is_valid(progress_indicator.win) then
        vim.api.nvim_win_close(progress_indicator.win, true)
        progress_indicator.win = nil
      end
      return
    end

    if not progress_indicator.buf or not vim.api.nvim_buf_is_valid(progress_indicator.buf) then
      return
    end

    local elapsed = os.time() - current_job.start_time
    local text = string.format(" %s 🤖 %s %ds ", spinner[spinner_idx], provider, elapsed)
    pcall(vim.api.nvim_buf_set_lines, progress_indicator.buf, 0, -1, false, { text })

    spinner_idx = spinner_idx % #spinner + 1
  end))
end

---Close progress indicator
local function close_progress_indicator()
  if progress_indicator.timer then
    progress_indicator.timer:stop()
    progress_indicator.timer:close()
    progress_indicator.timer = nil
  end
  if progress_indicator.win and vim.api.nvim_win_is_valid(progress_indicator.win) then
    vim.api.nvim_win_close(progress_indicator.win, true)
    progress_indicator.win = nil
  end
  progress_indicator.buf = nil
end

---Send comments to AI (background job with progress indicator)
---@param opts? {comments?: Review.Comment[], extra?: string}
function M.send(opts)
  opts = opts or {}

  if current_job then
    vim.notify("AI job already running", vim.log.levels.WARN)
    return
  end

  local provider = M.get_provider()
  if not provider then
    vim.notify("No AI provider available. Install opencode, claude, or codex.", vim.log.levels.ERROR)
    return
  end

  local command_template = M.get_command(provider)
  if not command_template then
    vim.notify("No command configured for provider: " .. provider, vim.log.levels.ERROR)
    return
  end

  -- Get comments to process
  local comments = opts.comments or state.get_pending_comments()
  if #comments == 0 then
    vim.notify("No pending comments to send to AI", vim.log.levels.INFO)
    return
  end

  -- Build prompt
  local prompt = M.build_prompt(comments, opts.extra)

  -- Write prompt to temp file
  local prompt_file = vim.fn.tempname()
  local f = io.open(prompt_file, "w")
  if not f then
    vim.notify("Failed to create temp file for prompt", vim.log.levels.ERROR)
    return
  end
  f:write(prompt)
  f:close()

  -- Build command - replace $PROMPT_FILE with temp file path
  local command = command_template:gsub("%$PROMPT_FILE", prompt_file)

  -- Get comment IDs
  local comment_ids = {}
  for _, comment in ipairs(comments) do
    table.insert(comment_ids, comment.id)
  end

  -- Mark comments as processing
  mark_comments_processing(comment_ids)

  -- Start file watcher
  local watcher = start_file_watcher()

  -- Determine working directory
  local cwd = git.root_dir() or vim.fn.getcwd()

  -- Clear previous output
  job_output = {}

  -- Log command for debugging
  table.insert(job_output, "=== Command ===")
  table.insert(job_output, command:sub(1, 500))
  table.insert(job_output, "=== CWD: " .. cwd .. " ===")
  table.insert(job_output, "=== Output ===")

  -- Run command in background with PTY for interactive CLI tools
  local job_id = vim.fn.jobstart(command, {
    cwd = cwd,
    pty = true,
    on_stdout = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(job_output, line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      vim.schedule(function()
        -- Close progress indicator
        close_progress_indicator()

        -- Stop file watcher
        if current_job and current_job.watcher then
          stop_file_watcher(current_job.watcher)
        end

        -- Clean up temp prompt file
        if current_job and current_job.prompt_file then
          pcall(os.remove, current_job.prompt_file)
        end

        -- Mark comments complete
        mark_comments_complete(comment_ids)

        -- Clear current job
        current_job = nil

        -- Notify user
        if exit_code == 0 then
          vim.notify(string.format("🤖 %s finished successfully", provider), vim.log.levels.INFO)
        else
          vim.notify(string.format("🤖 %s exited with code %d", provider, exit_code), vim.log.levels.WARN)
        end

        -- Trigger final reload
        pcall(vim.cmd, "checktime")

        -- Call on_complete callback if configured
        local cfg = config.get("ai") or {}
        if cfg.on_complete then
          pcall(cfg.on_complete)
        end

        -- Refresh UI
        local diff = utils.safe_require("review.ui.diff")
        if diff and state.is_active() then
          diff.refresh()
          diff.refresh_decorations()
        end
      end)
    end,
  })

  if job_id <= 0 then
    local err_msg = job_id == 0 and "invalid arguments" or "command not executable"
    vim.notify("Failed to start AI job: " .. err_msg, vim.log.levels.ERROR)
    table.insert(job_output, "=== FAILED TO START: " .. err_msg .. " ===")
    reset_comments_pending(comment_ids)
    if watcher then
      stop_file_watcher(watcher)
    end
    pcall(os.remove, prompt_file)
    return
  end

  table.insert(job_output, "=== Job started with ID: " .. job_id .. " ===")

  -- Store job info
  current_job = {
    id = job_id,
    provider = provider,
    comment_ids = comment_ids,
    start_time = os.time(),
    watcher = watcher,
    command = command,
    cwd = cwd,
    prompt_file = prompt_file,
  }

  -- Show progress indicator
  show_progress_indicator(provider)

  vim.notify(string.format("🤖 Sending %d comment(s) to %s (job %d)", #comments, provider, job_id), vim.log.levels.INFO)
end

---Get debug info about current job
---@return string?
function M.get_debug_info()
  if not current_job then
    local info = "No job running\nLast output lines: " .. #job_output
    if #job_output > 0 then
      info = info .. "\n\nLast 5 output lines:"
      for i = math.max(1, #job_output - 4), #job_output do
        info = info .. "\n  " .. (job_output[i] or "")
      end
    end
    return info
  end

  local lines = {
    "AI Job Debug Info:",
    "  Provider: " .. current_job.provider,
    "  Job ID: " .. current_job.id,
    "  Running for: " .. (os.time() - current_job.start_time) .. "s",
    "  CWD: " .. (current_job.cwd or "N/A"),
    "  Prompt file: " .. (current_job.prompt_file or "N/A"),
    "  Output lines: " .. #job_output,
    "",
    "Command:",
    "  " .. (current_job.command or "N/A"),
  }

  if #job_output > 0 then
    table.insert(lines, "")
    table.insert(lines, "Last 5 output lines:")
    for i = math.max(1, #job_output - 4), #job_output do
      table.insert(lines, "  " .. (job_output[i] or ""))
    end
  end

  return table.concat(lines, "\n")
end

---Copy the full command to clipboard for manual testing
function M.copy_command()
  if current_job then
    local info = "# CWD: " .. (current_job.cwd or "unknown") .. "\n"
    info = info .. "# Prompt file: " .. (current_job.prompt_file or "unknown") .. "\n"
    info = info .. "cd " .. vim.fn.shellescape(current_job.cwd or ".") .. " && " .. current_job.command
    vim.fn.setreg("+", info)
    vim.fn.setreg("*", info)
    vim.notify("Command copied to clipboard (with cd)", vim.log.levels.INFO)
  else
    vim.notify("No command to copy (start an AI job first)", vim.log.levels.WARN)
  end
end

---Cancel running AI job
function M.cancel()
  if not current_job then
    vim.notify("No AI job running", vim.log.levels.INFO)
    return
  end

  -- Stop the job
  vim.fn.jobstop(current_job.id)

  -- Close progress indicator
  close_progress_indicator()

  -- Stop file watcher
  if current_job.watcher then
    stop_file_watcher(current_job.watcher)
  end

  -- Clean up temp prompt file
  if current_job.prompt_file then
    pcall(os.remove, current_job.prompt_file)
  end

  -- Reset comment status
  reset_comments_pending(current_job.comment_ids)

  vim.notify("🤖 AI job cancelled", vim.log.levels.INFO)
  current_job = nil
end

---Check if AI job is running
---@return boolean
function M.is_running()
  return current_job ~= nil
end

---Get current job info
---@return Review.AIJob?
function M.get_current_job()
  return current_job
end

---Get status string for statusline
---@return string?
function M.get_status()
  if not current_job then
    return nil
  end

  local elapsed = os.time() - current_job.start_time
  return string.format("🤖 %s (%ds)", current_job.provider, elapsed)
end

---Get output from current/last job
---@return string[]
function M.get_output()
  return job_output
end

---Show output in a floating window
function M.show_output()
  local lines = job_output
  if #lines == 0 then
    vim.notify("No AI output yet", vim.log.levels.INFO)
    return
  end

  -- Create buffer for output
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false

  -- Calculate window size
  local width = math.min(100, vim.o.columns - 10)
  local height = math.min(30, #lines + 2, vim.o.lines - 10)

  -- Create floating window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = current_job and string.format(" 🤖 %s Output ", current_job.provider) or " 🤖 AI Output ",
    title_pos = "center",
  })

  -- Jump to end
  vim.api.nvim_win_set_cursor(win, { #lines, 0 })

  -- Keymaps to close
  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })

  -- Auto-refresh if job is still running
  if current_job then
    local timer = vim.uv.new_timer()
    timer:start(1000, 1000, vim.schedule_wrap(function()
      if not vim.api.nvim_win_is_valid(win) then
        timer:stop()
        timer:close()
        return
      end
      if not current_job then
        timer:stop()
        timer:close()
        return
      end
      -- Update buffer with new output
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, job_output)
      vim.bo[buf].modifiable = false
      -- Scroll to bottom
      pcall(vim.api.nvim_win_set_cursor, win, { #job_output, 0 })
    end))
  end
end

-- ============================================================================
-- User Interface
-- ============================================================================

---Prompt user for extra instructions and send to AI
---@param opts? {comments?: Review.Comment[]}
function M.send_with_prompt(opts)
  opts = opts or {}

  local float = utils.safe_require("review.ui.float")
  if not float then
    -- Fallback to simple input
    vim.ui.input({ prompt = "Additional instructions (optional): " }, function(extra)
      if extra == nil then
        return -- User cancelled
      end
      M.send({ comments = opts.comments, extra = extra ~= "" and extra or nil })
    end)
    return
  end

  float.multiline_input({
    prompt = "Additional instructions for AI (optional, leave empty to skip)",
    filetype = "markdown",
  }, function(lines)
    local extra = nil
    if lines and #lines > 0 then
      local text = table.concat(lines, "\n")
      if text:match("%S") then -- Has non-whitespace
        extra = text
      end
    end
    M.send({ comments = opts.comments, extra = extra })
  end)
end

-- ============================================================================
-- Clipboard Fallback
-- ============================================================================

---Copy prompt to clipboard (for manual use with AI)
---@param opts? {comments?: Review.Comment[], extra?: string}
function M.send_to_clipboard(opts)
  opts = opts or {}

  local comments = opts.comments or state.get_pending_comments()
  if #comments == 0 then
    vim.notify("No pending comments to copy", vim.log.levels.INFO)
    return
  end

  local prompt = M.build_prompt(comments, opts.extra)
  vim.fn.setreg("+", prompt)
  vim.fn.setreg("*", prompt)
  vim.notify(string.format("Copied %d comment(s) to clipboard", #comments), vim.log.levels.INFO)
end

-- ============================================================================
-- Provider Info
-- ============================================================================

---Get list of available providers
---@return table[] List of {name: string, available: boolean, command: string?}
function M.get_available_providers()
  local result = {}
  for name, cmd in pairs(PROVIDER_COMMANDS) do
    table.insert(result, {
      name = name,
      available = command_exists(name),
      command = cmd,
    })
  end
  table.sort(result, function(a, b)
    return a.name < b.name
  end)
  return result
end

---Show picker to select AI provider
function M.pick_provider()
  local providers = M.get_available_providers()
  local items = {}

  for _, p in ipairs(providers) do
    table.insert(items, {
      name = p.name,
      available = p.available,
      display = string.format("%s %s", p.available and "✓" or "✗", p.name),
    })
  end

  vim.ui.select(items, {
    prompt = "Select AI Provider:",
    format_item = function(item)
      return item.display
    end,
  }, function(choice)
    if choice then
      if not choice.available then
        vim.notify(choice.name .. " is not installed", vim.log.levels.WARN)
        return
      end
      -- Temporarily override provider and send
      local original = config.get("ai.provider")
      config.config.ai.provider = choice.name
      M.send_with_prompt()
      config.config.ai.provider = original
    end
  end)
end

return M
