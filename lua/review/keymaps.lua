-- Keymaps for review.nvim
-- Sets up all keybindings for the review plugin

local M = {}

local state = require("review.core.state")
local config = require("review.config")
local utils = require("review.utils")

---@class Review.KeymapDefaults
---@field tree_next string Navigate to next file in tree
---@field tree_prev string Navigate to previous file in tree
---@field file_next string Open next file
---@field file_prev string Open previous file
---@field comment_next string Next comment (all files)
---@field comment_prev string Previous comment (all files)
---@field unresolved_next string Next unresolved comment
---@field unresolved_prev string Previous unresolved comment
---@field pending_next string Next pending comment
---@field pending_prev string Previous pending comment
---@field hunk_next string Next hunk
---@field hunk_prev string Previous hunk
---@field toggle_panel string Toggle PR panel
---@field focus_tree string Focus file tree
---@field focus_diff string Focus diff view
---@field close string Close review
---@field add_comment string Add note comment
---@field add_issue string Add issue comment
---@field add_suggestion string Add suggestion comment
---@field add_praise string Add praise comment
---@field edit_comment string Edit comment at cursor
---@field delete_comment string Delete comment at cursor
---@field show_comment string Show comment popup
---@field reply string Reply to comment
---@field resolve string Toggle resolve status
---@field add_conversation string Add conversation comment
---@field send_to_ai string Send to AI
---@field pick_ai_provider string Pick AI provider
---@field ai_cancel string Cancel AI job
---@field send_to_clipboard string Copy to clipboard
---@field submit_to_github string Submit to GitHub
---@field approve string Approve PR
---@field request_changes string Request changes
---@field pick_review_requests string Pick from review requests
---@field pick_open_prs string Pick from open PRs

---@type Review.KeymapDefaults
M.defaults = {
  -- File navigation (global when review active)
  tree_next = "<C-j>",
  tree_prev = "<C-k>",
  file_next = "<Tab>",
  file_prev = "<S-Tab>",

  -- Comment navigation
  comment_next = "]c",
  comment_prev = "[c",
  unresolved_next = "]u",
  unresolved_prev = "[u",
  pending_next = "]m",
  pending_prev = "[m",

  -- Hunk navigation
  hunk_next = "]h",
  hunk_prev = "[h",

  -- Views
  toggle_panel = "<leader>rp",
  focus_tree = "<leader>rf",
  focus_diff = "<leader>rd",
  toggle_diff = "<leader>rD",
  close = "<leader>rq",
  accept_and_next = "<leader>rn",

  -- Comment actions
  add_comment = "<leader>cc",
  add_issue = "<leader>ci",
  add_suggestion = "<leader>cs",
  add_praise = "<leader>cp",
  edit_comment = "<leader>ce",
  delete_comment = "<leader>cd",
  show_comment = "K",
  reply = "r",
  resolve = "R",

  -- PR actions
  add_conversation = "<leader>rC",
  send_to_ai = "<leader>rs",
  pick_ai_provider = "<leader>rS",
  ai_cancel = "<leader>rX",
  send_to_clipboard = "<leader>ry",
  submit_to_github = "<leader>rg",
  approve = "<leader>ra",
  request_changes = "<leader>rx",

  -- Picker
  pick_review_requests = "<leader>rr",
  pick_open_prs = "<leader>rl",
}

-- Store original mappings to restore later
---@type table<string, table>
local original_mappings = {}

-- Augroup for keymap-related autocmds
local augroup_id = nil

---Get merged keymaps (defaults + user config)
---@return Review.KeymapDefaults
function M.get_keymaps()
  local user_keymaps = config.get("keymaps") or {}
  return vim.tbl_deep_extend("force", {}, M.defaults, user_keymaps)
end

---Helper: Only execute function when review is active
---@param fn function Function to wrap
---@return function Wrapped function
local function when_active(fn)
  return function()
    if state.is_active() then
      fn()
    end
  end
end

---Helper: Only execute function when in diff window
---@param fn function Function to wrap
---@return function Wrapped function
local function when_in_diff(fn)
  return function()
    if not state.is_active() then
      return
    end
    local layout = utils.safe_require("review.ui.layout")
    if layout and layout.is_diff_focused() then
      fn()
    end
  end
end

---Add a comment at cursor or selection with specified type
---@param comment_type "note" | "issue" | "suggestion" | "praise"
---@param start_line? number Start line (for visual selection)
---@param end_line? number End line (for visual selection)
local function add_comment(comment_type, start_line, end_line)
  local current_file = state.state.current_file
  if not current_file then
    vim.notify("No file open", vim.log.levels.WARN)
    return
  end

  -- If no range provided, use cursor line
  if not start_line then
    start_line = vim.api.nvim_win_get_cursor(0)[1]
  end
  if not end_line then
    end_line = start_line
  end

  -- Ensure start <= end
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  -- Block comments outside diff hunks when targeting GitHub
  local diff_parser = require("review.core.diff_parser")
  if diff_parser.should_restrict_to_hunks(current_file) then
    local file_data = state.find_file(current_file)
    if file_data and file_data.status ~= "added" then
      local hunk = diff_parser.find_hunk_for_line(file_data.hunks or {}, start_line)
      if not hunk then
        vim.notify(
          "Cannot comment here — line is outside the PR diff (only changed lines + context are commentable)",
          vim.log.levels.WARN
        )
        return
      end
    end
  end

  local original_win = vim.api.nvim_get_current_win()
  local float = utils.safe_require("review.ui.float")
  local comments = require("review.core.comments")

  local is_multiline = start_line ~= end_line
  local line_info = is_multiline
    and string.format("lines %d-%d", start_line, end_line)
    or string.format("line %d", start_line)

  if float then
    float.multiline_input({
      prompt = string.format("Comment (%s) %s", comment_type, line_info),
      file = current_file,
      line = start_line,
      filetype = "markdown",
    }, function(lines)
      if lines and #lines > 0 then
        local body = table.concat(lines, "\n")
        if is_multiline then
          comments.add_multiline(current_file, start_line, end_line, body, comment_type)
        else
          comments.add(current_file, start_line, body, comment_type)
        end
        vim.schedule(function()
          M.refresh_ui()
          -- Restore cursor to comment line
          if vim.api.nvim_win_is_valid(original_win) then
            vim.api.nvim_set_current_win(original_win)
            pcall(vim.api.nvim_win_set_cursor, original_win, { start_line, 0 })
          end
          vim.notify(string.format("Added %s comment at %s", comment_type, line_info), vim.log.levels.INFO)
        end)
      end
    end)
  end
end

---Add comment from visual selection
---@param comment_type "note" | "issue" | "suggestion" | "praise"
local function add_comment_visual(comment_type)
  -- Exit visual mode first to set '< and '> marks
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
  -- Schedule to ensure marks are set after exiting visual mode
  vim.schedule(function()
    local start_line = vim.fn.line("'<")
    local end_line = vim.fn.line("'>")
    -- Validate lines
    if start_line < 1 or end_line < 1 then
      vim.notify("Invalid selection", vim.log.levels.WARN)
      return
    end
    add_comment(comment_type, start_line, end_line)
  end)
end

---Edit comment at cursor
local function edit_comment_at_cursor()
  local nav = utils.safe_require("review.core.navigation")
  if not nav then
    return
  end

  local comment = nav.get_comment_at_cursor()
  if not comment then
    vim.notify("No comment at cursor", vim.log.levels.INFO)
    return
  end

  if comment.kind ~= "local" then
    vim.notify("Can only edit local comments", vim.log.levels.WARN)
    return
  end

  local float = utils.safe_require("review.ui.float")
  local comments = require("review.core.comments")

  if float then
    float.multiline_input({
      prompt = "Edit comment",
      default = comment.body,
    }, function(lines)
      if lines and #lines > 0 then
        local body = table.concat(lines, "\n")
        comments.edit(comment.id, body)
        M.refresh_ui()
        vim.notify("Comment updated", vim.log.levels.INFO)
      end
    end)
  end
end

---Delete comment at cursor
local function delete_comment_at_cursor()
  local nav = utils.safe_require("review.core.navigation")
  if not nav then
    return
  end

  local comment = nav.get_comment_at_cursor()
  if not comment then
    vim.notify("No comment at cursor", vim.log.levels.INFO)
    return
  end

  if comment.kind ~= "local" then
    vim.notify("Can only delete local comments", vim.log.levels.WARN)
    return
  end

  local float = utils.safe_require("review.ui.float")
  local comments = require("review.core.comments")

  if float then
    float.confirm("Delete this comment?", function(confirmed)
      if confirmed then
        comments.delete(comment.id)
        M.refresh_ui()
        vim.notify("Comment deleted", vim.log.levels.INFO)
      end
    end)
  end
end

---Show comment at cursor
local function show_comment_at_cursor()
  local nav = utils.safe_require("review.core.navigation")
  if not nav then
    return
  end

  local comment = nav.get_comment_at_cursor()
  if comment then
    local float = utils.safe_require("review.ui.float")
    if float then
      float.show_comment(comment)
    end
  end
end

---Reply to comment at cursor
local function reply_to_comment()
  local nav = utils.safe_require("review.core.navigation")
  if not nav then
    return
  end

  local comment = nav.get_comment_at_cursor()
  if not comment then
    vim.notify("No comment at cursor", vim.log.levels.INFO)
    return
  end

  local float = utils.safe_require("review.ui.float")
  local comments = require("review.core.comments")

  if float then
    float.multiline_input({
      prompt = "Reply",
    }, function(lines)
      if lines and #lines > 0 then
        local body = table.concat(lines, "\n")
        comments.reply(comment.id, body)
        M.refresh_ui()
        vim.notify("Reply added", vim.log.levels.INFO)
      end
    end)
  end
end

---Toggle resolve status of comment at cursor
local function toggle_resolve()
  local nav = utils.safe_require("review.core.navigation")
  if not nav then
    return
  end

  local comment = nav.get_comment_at_cursor()
  if not comment then
    vim.notify("No comment at cursor", vim.log.levels.INFO)
    return
  end

  if comment.kind ~= "review" then
    vim.notify("Only review comments can be resolved", vim.log.levels.WARN)
    return
  end

  local comments = require("review.core.comments")
  local new_state = not comment.resolved
  if comments.set_resolved(comment.id, new_state) then
    M.refresh_ui()
    vim.notify(new_state and "Comment resolved" or "Comment unresolved", vim.log.levels.INFO)
  end
end

---Refresh UI components after changes
function M.refresh_ui()
  local signs = utils.safe_require("review.ui.signs")
  local virtual_text = utils.safe_require("review.ui.virtual_text")
  local file_tree = utils.safe_require("review.ui.file_tree")

  if signs then
    signs.refresh()
  end
  if virtual_text then
    virtual_text.refresh()
  end
  if file_tree then
    file_tree.render()
  end
end

---Store an original keymap before overriding
---@param mode string Mode
---@param lhs string Key sequence
local function store_original(mode, lhs)
  local key = mode .. ":" .. lhs
  if original_mappings[key] == nil then
    local existing = vim.fn.maparg(lhs, mode, false, true)
    if existing and next(existing) then
      original_mappings[key] = existing
    else
      original_mappings[key] = false -- Mark as "no mapping"
    end
  end
end

---Restore an original keymap
---@param mode string Mode
---@param lhs string Key sequence
local function restore_original(mode, lhs)
  local key = mode .. ":" .. lhs
  local original = original_mappings[key]

  if original == false then
    -- No original mapping, just delete
    pcall(vim.keymap.del, mode, lhs)
  elseif original then
    -- Restore original mapping
    local opts = {
      noremap = original.noremap == 1,
      silent = original.silent == 1,
      expr = original.expr == 1,
      nowait = original.nowait == 1,
      desc = original.desc,
    }
    if original.callback then
      vim.keymap.set(mode, lhs, original.callback, opts)
    elseif original.rhs then
      vim.keymap.set(mode, lhs, original.rhs, opts)
    end
  end

  original_mappings[key] = nil
end

---Set up global keymaps (active when review session is open)
function M.setup()
  if not config.get("keymaps.enabled") then
    return
  end

  local keymaps = M.get_keymaps()
  local nav = require("review.core.navigation")
  local layout = require("review.ui.layout")

  -- Define all keymap bindings
  local bindings = {
    -- File navigation
    { "n", keymaps.tree_next, when_active(nav.tree_next), "Review: Next in tree" },
    { "n", keymaps.tree_prev, when_active(nav.tree_prev), "Review: Prev in tree" },
    { "n", keymaps.file_next, when_active(nav.open_next_file), "Review: Open next file" },
    { "n", keymaps.file_prev, when_active(nav.open_prev_file), "Review: Open prev file" },

    -- Comment navigation
    { "n", keymaps.comment_next, when_active(nav.next_comment), "Review: Next comment" },
    { "n", keymaps.comment_prev, when_active(nav.prev_comment), "Review: Prev comment" },
    { "n", keymaps.unresolved_next, when_active(nav.next_unresolved), "Review: Next unresolved" },
    { "n", keymaps.unresolved_prev, when_active(nav.prev_unresolved), "Review: Prev unresolved" },
    { "n", keymaps.pending_next, when_active(nav.next_pending), "Review: Next pending" },
    { "n", keymaps.pending_prev, when_active(nav.prev_pending), "Review: Prev pending" },

    -- Hunk navigation
    { "n", keymaps.hunk_next, when_active(nav.next_hunk), "Review: Next hunk" },
    { "n", keymaps.hunk_prev, when_active(nav.prev_hunk), "Review: Prev hunk" },

    -- Views
    {
      "n",
      keymaps.toggle_panel,
      when_active(function()
        local panel = require("review.ui.panel")
        panel.toggle()
      end),
      "Review: Toggle panel",
    },
    { "n", keymaps.focus_tree, when_active(layout.focus_tree), "Review: Focus tree" },
    { "n", keymaps.focus_diff, when_active(layout.focus_diff), "Review: Focus diff" },
    {
      "n",
      keymaps.toggle_diff,
      when_active(function()
        local diff = require("review.ui.diff")
        diff.toggle_diff()
      end),
      "Review: Toggle diff split",
    },
    {
      "n",
      keymaps.close,
      when_active(function()
        layout.close()
      end),
      "Review: Close",
    },
    {
      "n",
      keymaps.accept_and_next,
      when_active(function()
        local file_tree = require("review.ui.file_tree")
        local current_file = state.state.current_file
        if current_file then
          -- Mark current file as reviewed
          state.set_file_reviewed(current_file, true)
          -- In local mode, also stage the file
          if state.state.mode == "local" then
            local git = require("review.integrations.git")
            git.stage_file(current_file)
          end
          -- Move to next file and open it
          file_tree.select_next()
          file_tree.open_selected()
          -- Jump to first hunk after file loads
          vim.schedule(function()
            local diff = require("review.ui.diff")
            diff.jump_to_first_hunk()
          end)
        end
      end),
      "Review: Accept and next",
    },

    -- Comment actions (normal mode)
    {
      "n",
      keymaps.add_comment,
      when_active(function()
        add_comment("note")
      end),
      "Review: Add comment",
    },
    {
      "n",
      keymaps.add_issue,
      when_active(function()
        add_comment("issue")
      end),
      "Review: Add issue",
    },
    {
      "n",
      keymaps.add_suggestion,
      when_active(function()
        add_comment("suggestion")
      end),
      "Review: Add suggestion",
    },
    {
      "n",
      keymaps.add_praise,
      when_active(function()
        add_comment("praise")
      end),
      "Review: Add praise",
    },
    -- Comment actions (visual mode - for multi-line selections)
    {
      "v",
      keymaps.add_comment,
      function()
        if state.is_active() then
          add_comment_visual("note")
        end
      end,
      "Review: Add comment (selection)",
    },
    {
      "v",
      keymaps.add_issue,
      function()
        if state.is_active() then
          add_comment_visual("issue")
        end
      end,
      "Review: Add issue (selection)",
    },
    {
      "v",
      keymaps.add_suggestion,
      function()
        if state.is_active() then
          add_comment_visual("suggestion")
        end
      end,
      "Review: Add suggestion (selection)",
    },
    {
      "v",
      keymaps.add_praise,
      function()
        if state.is_active() then
          add_comment_visual("praise")
        end
      end,
      "Review: Add praise (selection)",
    },
    { "n", keymaps.edit_comment, when_active(edit_comment_at_cursor), "Review: Edit comment" },
    { "n", keymaps.delete_comment, when_active(delete_comment_at_cursor), "Review: Delete comment" },
    { "n", keymaps.show_comment, when_active(show_comment_at_cursor), "Review: Show comment" },
    { "n", keymaps.reply, when_in_diff(reply_to_comment), "Review: Reply" },
    { "n", keymaps.resolve, when_in_diff(toggle_resolve), "Review: Resolve" },

    -- PR actions
    {
      "n",
      keymaps.add_conversation,
      when_active(function()
        vim.notify("Conversation comments not yet implemented", vim.log.levels.INFO)
      end),
      "Review: Add conversation",
    },
    {
      "n",
      keymaps.send_to_ai,
      when_active(function()
        local ai = require("review.integrations.ai")
        ai.send_with_prompt()
      end),
      "Review: Send to AI",
    },
    {
      "n",
      keymaps.pick_ai_provider,
      when_active(function()
        local ai = require("review.integrations.ai")
        ai.pick_provider()
      end),
      "Review: Pick AI provider",
    },
    {
      "n",
      keymaps.ai_cancel,
      when_active(function()
        local ai = require("review.integrations.ai")
        ai.cancel()
      end),
      "Review: Cancel AI job",
    },
    {
      "n",
      keymaps.send_to_clipboard,
      when_active(function()
        local ai = require("review.integrations.ai")
        ai.send_to_clipboard()
      end),
      "Review: Copy to clipboard",
    },
    {
      "n",
      keymaps.submit_to_github,
      when_active(function()
        if state.state.mode ~= "pr" then
          vim.notify("GitHub submission only available in PR mode", vim.log.levels.WARN)
          return
        end
        local github = require("review.integrations.github")
        github.submit_review("COMMENT")
      end),
      "Review: Submit to GitHub",
    },
    {
      "n",
      keymaps.approve,
      when_active(function()
        if state.state.mode ~= "pr" then
          vim.notify("PR approval only available in PR mode", vim.log.levels.WARN)
          return
        end
        local github = require("review.integrations.github")
        github.submit_review("APPROVE")
      end),
      "Review: Approve PR",
    },
    {
      "n",
      keymaps.request_changes,
      when_active(function()
        if state.state.mode ~= "pr" then
          vim.notify("Request changes only available in PR mode", vim.log.levels.WARN)
          return
        end
        local github = require("review.integrations.github")
        github.submit_review("REQUEST_CHANGES")
      end),
      "Review: Request changes",
    },

    -- Picker (these work even without active session)
    {
      "n",
      keymaps.pick_review_requests,
      function()
        vim.notify("Review request picker not yet implemented", vim.log.levels.INFO)
      end,
      "Review: Pick review requests",
    },
    {
      "n",
      keymaps.pick_open_prs,
      function()
        vim.notify("Open PRs picker not yet implemented", vim.log.levels.INFO)
      end,
      "Review: Pick open PRs",
    },
  }

  -- Set up all keymaps
  for _, binding in ipairs(bindings) do
    local mode, lhs, rhs, desc = binding[1], binding[2], binding[3], binding[4]
    store_original(mode, lhs)
    vim.keymap.set(mode, lhs, rhs, { desc = desc, silent = true })
  end

  -- Create augroup for buffer-local keymaps
  augroup_id = vim.api.nvim_create_augroup("ReviewKeymaps", { clear = true })
end

---Remove global keymaps (restore originals)
function M.teardown()
  local keymaps = M.get_keymaps()

  -- List all keymaps to restore
  local all_keys = {
    keymaps.tree_next,
    keymaps.tree_prev,
    keymaps.file_next,
    keymaps.file_prev,
    keymaps.comment_next,
    keymaps.comment_prev,
    keymaps.unresolved_next,
    keymaps.unresolved_prev,
    keymaps.pending_next,
    keymaps.pending_prev,
    keymaps.hunk_next,
    keymaps.hunk_prev,
    keymaps.toggle_panel,
    keymaps.focus_tree,
    keymaps.focus_diff,
    keymaps.toggle_diff,
    keymaps.close,
    keymaps.accept_and_next,
    keymaps.add_comment,
    keymaps.add_issue,
    keymaps.add_suggestion,
    keymaps.add_praise,
    keymaps.edit_comment,
    keymaps.delete_comment,
    keymaps.show_comment,
    keymaps.reply,
    keymaps.resolve,
    keymaps.add_conversation,
    keymaps.send_to_ai,
    keymaps.pick_ai_provider,
    keymaps.ai_cancel,
    keymaps.send_to_clipboard,
    keymaps.submit_to_github,
    keymaps.approve,
    keymaps.request_changes,
    keymaps.pick_review_requests,
    keymaps.pick_open_prs,
  }

  for _, lhs in ipairs(all_keys) do
    restore_original("n", lhs)
  end

  -- Also restore visual mode comment keymaps
  local visual_keys = {
    keymaps.add_comment,
    keymaps.add_issue,
    keymaps.add_suggestion,
    keymaps.add_praise,
  }
  for _, lhs in ipairs(visual_keys) do
    restore_original("v", lhs)
  end

  -- Clear augroup
  if augroup_id then
    pcall(vim.api.nvim_del_augroup_by_id, augroup_id)
    augroup_id = nil
  end
end

---Set up buffer-local keymaps for file tree buffer
---@param buf number Buffer handle
function M.setup_tree_keymaps(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local file_tree = require("review.ui.file_tree")

  local tree_bindings = {
    { "n", "<CR>", file_tree.open_selected, "Open file" },
    { "n", "o", file_tree.open_selected, "Open file" },
    { "n", "j", file_tree.select_next, "Next file" },
    { "n", "k", file_tree.select_prev, "Prev file" },
    { "n", "q", function() require("review.ui.layout").close() end, "Close review" },
  }

  for _, binding in ipairs(tree_bindings) do
    local mode, lhs, rhs, desc = binding[1], binding[2], binding[3], binding[4]
    vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc, silent = true, nowait = true })
  end
end

---Set up buffer-local keymaps for diff buffer
---@param buf number Buffer handle
function M.setup_diff_keymaps(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  -- Diff-specific keymaps can be added here
  -- Most are global already, but some might be buffer-specific
end

---Check if keymaps are set up
---@return boolean
function M.is_setup()
  return augroup_id ~= nil
end

---Get the default keymap for a specific action
---@param action string Action name (e.g., "add_comment", "next_comment")
---@return string? keymap The default keymap or nil if not found
function M.get_default(action)
  return M.defaults[action]
end

---Get all keymap definitions for documentation/help
---@return table<string, {key: string, desc: string}[]>
function M.get_all_definitions()
  local keymaps = M.get_keymaps()

  return {
    ["File Navigation"] = {
      { key = keymaps.tree_next, desc = "Navigate to next file in tree" },
      { key = keymaps.tree_prev, desc = "Navigate to previous file in tree" },
      { key = keymaps.file_next, desc = "Open next file" },
      { key = keymaps.file_prev, desc = "Open previous file" },
    },
    ["Comment Navigation"] = {
      { key = keymaps.comment_next, desc = "Next comment (all files)" },
      { key = keymaps.comment_prev, desc = "Previous comment (all files)" },
      { key = keymaps.unresolved_next, desc = "Next unresolved comment" },
      { key = keymaps.unresolved_prev, desc = "Previous unresolved comment" },
      { key = keymaps.pending_next, desc = "Next pending comment" },
      { key = keymaps.pending_prev, desc = "Previous pending comment" },
    },
    ["Hunk Navigation"] = {
      { key = keymaps.hunk_next, desc = "Next hunk" },
      { key = keymaps.hunk_prev, desc = "Previous hunk" },
    },
    ["Views"] = {
      { key = keymaps.toggle_panel, desc = "Toggle PR panel" },
      { key = keymaps.focus_tree, desc = "Focus file tree" },
      { key = keymaps.focus_diff, desc = "Focus diff view" },
    },
    ["Comment Actions"] = {
      { key = keymaps.add_comment, desc = "Add note comment" },
      { key = keymaps.add_issue, desc = "Add issue comment" },
      { key = keymaps.add_suggestion, desc = "Add suggestion comment" },
      { key = keymaps.add_praise, desc = "Add praise comment" },
      { key = keymaps.edit_comment, desc = "Edit comment at cursor" },
      { key = keymaps.delete_comment, desc = "Delete comment at cursor" },
      { key = keymaps.show_comment, desc = "Show comment popup (with actions)" },
      { key = keymaps.reply, desc = "Reply to comment" },
      { key = keymaps.resolve, desc = "Toggle resolve status" },
    },
    ["PR Actions"] = {
      { key = keymaps.add_conversation, desc = "Add conversation comment" },
      { key = keymaps.send_to_ai, desc = "Send to AI" },
      { key = keymaps.pick_ai_provider, desc = "Pick AI provider" },
      { key = keymaps.ai_cancel, desc = "Cancel AI job" },
      { key = keymaps.send_to_clipboard, desc = "Copy to clipboard" },
      { key = keymaps.submit_to_github, desc = "Submit to GitHub" },
      { key = keymaps.approve, desc = "Approve PR" },
      { key = keymaps.request_changes, desc = "Request changes" },
    },
    ["Picker"] = {
      { key = keymaps.pick_review_requests, desc = "Pick from review requests" },
      { key = keymaps.pick_open_prs, desc = "Pick from open PRs" },
    },
  }
end

return M
