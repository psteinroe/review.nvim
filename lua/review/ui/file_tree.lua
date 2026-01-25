-- File tree panel for review.nvim
-- Displays changed files with comment counts and status icons

local M = {}

local state = require("review.core.state")
local config = require("review.config")
local utils = require("review.utils")

-- Namespace for highlights
local ns_id = vim.api.nvim_create_namespace("review_file_tree")
local ns_selection = vim.api.nvim_create_namespace("review_file_tree_selection")

---@type number Current selected index in tree (1-indexed, maps to files)
local selected_idx = 1

---@type table<number, number> Line number to file index mapping
local line_to_file_idx = {}

---Get icon for file status
---@param status string
---@return string icon
---@return string highlight
function M.get_status_icon(status)
  local icons = config.get("ui.icons") or {}
  local mapping = {
    added = { icon = icons.added or "+", hl = "ReviewTreeAdded" },
    modified = { icon = icons.modified or "~", hl = "ReviewTreeModified" },
    deleted = { icon = icons.deleted or "-", hl = "ReviewTreeDeleted" },
    renamed = { icon = icons.renamed or "R", hl = "ReviewTreeRenamed" },
  }
  local result = mapping[status] or { icon = "?", hl = "ReviewTreeFile" }
  return result.icon, result.hl
end

---Build tree structure from flat file list
---Groups files by directory for hierarchical display
---@param files Review.File[]
---@return table tree structure
function M.build_tree(files)
  local tree = {}
  for _, file in ipairs(files) do
    local parts = vim.split(file.path, "/", { plain = true })
    local current = tree
    for i, part in ipairs(parts) do
      if i == #parts then
        -- File leaf node
        current[part] = { type = "file", data = file, name = part }
      else
        -- Directory node
        if not current[part] then
          current[part] = { type = "dir", children = {}, name = part }
        end
        current = current[part].children
      end
    end
  end
  return tree
end

---Sort tree nodes: directories first, then alphabetically
---@param tree table
---@return table[] sorted nodes
function M.sort_tree_nodes(tree)
  local sorted = {}
  for name, node in pairs(tree) do
    table.insert(sorted, { name = name, node = node })
  end
  table.sort(sorted, function(a, b)
    if a.node.type ~= b.node.type then
      return a.node.type == "dir"
    end
    return a.name < b.name
  end)
  return sorted
end

---Render tree recursively into lines
---@param tree table
---@param lines string[]
---@param highlights table[]
---@param depth number
---@param file_indices table Maps line numbers to file indices
---@param current_file_idx table Mutable counter for file index
function M.render_tree_recursive(tree, lines, highlights, depth, file_indices, current_file_idx)
  local sorted = M.sort_tree_nodes(tree)
  local icons = config.get("ui.icons") or {}
  local dir_icon = icons.dir_open or ">"

  for _, item in ipairs(sorted) do
    local indent = string.rep("  ", depth)
    local line_nr = #lines + 1

    if item.node.type == "dir" then
      local line = indent .. dir_icon .. " " .. item.name .. "/"
      table.insert(lines, line)
      table.insert(highlights, {
        line = line_nr,
        col_start = #indent,
        col_end = #line,
        hl_group = "ReviewTreeDir",
      })
      M.render_tree_recursive(item.node.children, lines, highlights, depth + 1, file_indices, current_file_idx)
    else
      local file = item.node.data
      current_file_idx[1] = current_file_idx[1] + 1
      local file_idx = current_file_idx[1]
      file_indices[line_nr] = file_idx

      local status_icon, status_hl = M.get_status_icon(file.status)
      local comment_indicator = ""
      if file.comment_count and file.comment_count > 0 then
        local comment_icon = icons.comment or "#"
        comment_indicator = string.format(" %s%d", comment_icon, file.comment_count)
      end

      local line = indent .. status_icon .. " " .. item.name .. comment_indicator
      table.insert(lines, line)

      -- Status icon highlight
      table.insert(highlights, {
        line = line_nr,
        col_start = #indent,
        col_end = #indent + #status_icon,
        hl_group = status_hl,
      })

      -- Filename highlight (current file gets special highlight)
      local name_hl = "ReviewTreeFile"
      if file.path == state.state.current_file then
        name_hl = "ReviewTreeCurrent"
      end
      table.insert(highlights, {
        line = line_nr,
        col_start = #indent + #status_icon + 1,
        col_end = #indent + #status_icon + 1 + #item.name,
        hl_group = name_hl,
      })

      -- Comment indicator highlight
      if #comment_indicator > 0 then
        table.insert(highlights, {
          line = line_nr,
          col_start = #line - #comment_indicator,
          col_end = #line,
          hl_group = "ReviewTreeComment",
        })
      end
    end
  end
end

---Render the file tree header
---@return string[] lines
---@return table[] highlights
function M.render_header()
  local lines = {}
  local highlights = {}
  local icons = config.get("ui.icons") or {}

  -- Header
  if state.state.mode == "pr" and state.state.pr then
    local pr = state.state.pr
    table.insert(lines, string.format("PR #%d (%d files)", pr.number, #state.state.files))
  else
    table.insert(lines, string.format("Review (%d files)", #state.state.files))
  end

  table.insert(highlights, {
    line = 1,
    col_start = 0,
    col_end = #lines[1],
    hl_group = "ReviewTreeHeader",
  })

  table.insert(lines, "") -- Blank line separator

  return lines, highlights
end

---Render the file tree footer with stats
---@return string[] lines
---@return table[] highlights
function M.render_footer()
  local lines = {}
  local highlights = {}
  local icons = config.get("ui.icons") or {}

  local comment_icon = icons.comment or "#"
  local pending_icon = icons.pending or "*"

  table.insert(lines, "") -- Blank line separator

  -- Count comments
  local github_count = 0
  local local_count = 0
  for _, comment in ipairs(state.state.comments) do
    if comment.kind == "local" then
      local_count = local_count + 1
    else
      github_count = github_count + 1
    end
  end

  local line_nr = #lines + 1
  local line1 = string.format("%s %d comments", comment_icon, github_count)
  table.insert(lines, line1)
  table.insert(highlights, {
    line = line_nr,
    col_start = 0,
    col_end = #line1,
    hl_group = "ReviewTreeStats",
  })

  line_nr = #lines + 1
  local line2 = string.format("%s %d pending", pending_icon, local_count)
  table.insert(lines, line2)
  table.insert(highlights, {
    line = line_nr,
    col_start = 0,
    col_end = #line2,
    hl_group = "ReviewTreeStats",
  })

  return lines, highlights
end

---Render the full file tree
function M.render()
  local buf = state.state.layout.file_tree_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  -- Clear line mapping
  line_to_file_idx = {}

  local all_lines = {}
  local all_highlights = {}

  -- Header
  local header_lines, header_hl = M.render_header()
  for _, line in ipairs(header_lines) do
    table.insert(all_lines, line)
  end
  for _, hl in ipairs(header_hl) do
    table.insert(all_highlights, hl)
  end

  -- File tree
  local tree = M.build_tree(state.state.files)
  local file_indices = {}
  local current_file_idx = { 0 }
  local tree_start_line = #all_lines

  M.render_tree_recursive(tree, all_lines, all_highlights, 0, file_indices, current_file_idx)

  -- Adjust line indices (they were 1-indexed within tree)
  for line_nr, file_idx in pairs(file_indices) do
    line_to_file_idx[line_nr + tree_start_line] = file_idx
  end

  -- Fix highlight line numbers (add offset for header)
  for i, hl in ipairs(all_highlights) do
    if hl.line > #header_lines then
      -- Already correct, highlights were added with correct line numbers
    end
  end

  -- Footer
  local footer_lines, footer_hl = M.render_footer()
  local footer_start = #all_lines
  for _, line in ipairs(footer_lines) do
    table.insert(all_lines, line)
  end
  for _, hl in ipairs(footer_hl) do
    hl.line = hl.line + footer_start
    table.insert(all_highlights, hl)
  end

  -- Set buffer content
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, all_lines)
  vim.bo[buf].modifiable = false

  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

  -- Apply highlights
  for _, hl in ipairs(all_highlights) do
    pcall(vim.api.nvim_buf_add_highlight, buf, ns_id, hl.hl_group, hl.line - 1, hl.col_start, hl.col_end)
  end

  -- Highlight selected line
  M.highlight_selected()
end

---Highlight the currently selected line
function M.highlight_selected()
  local buf = state.state.layout.file_tree_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  -- Clear previous selection highlight
  vim.api.nvim_buf_clear_namespace(buf, ns_selection, 0, -1)

  -- Find line number for selected index
  local target_line = nil
  for line_nr, file_idx in pairs(line_to_file_idx) do
    if file_idx == selected_idx then
      target_line = line_nr
      break
    end
  end

  if target_line then
    -- Use extmark for selection (full line highlight)
    vim.api.nvim_buf_set_extmark(buf, ns_selection, target_line - 1, 0, {
      line_hl_group = "ReviewTreeSelected",
      priority = 100,
    })

    -- Move cursor to selected line if in tree window
    local win = state.state.layout.file_tree_win
    if win and vim.api.nvim_win_is_valid(win) then
      local current_win = vim.api.nvim_get_current_win()
      if current_win == win then
        pcall(vim.api.nvim_win_set_cursor, win, { target_line, 0 })
      end
    end
  end
end

---Get the selected index
---@return number
function M.get_selected_idx()
  return selected_idx
end

---Set the selected index
---@param idx number
function M.set_selected_idx(idx)
  local num_files = #state.state.files
  if num_files == 0 then
    selected_idx = 1
    return
  end
  selected_idx = math.max(1, math.min(idx, num_files))
  M.highlight_selected()
end

---Select next file in tree
function M.select_next()
  local num_files = #state.state.files
  if num_files == 0 then
    return
  end

  selected_idx = selected_idx + 1
  if selected_idx > num_files then
    selected_idx = 1 -- Wrap around
  end
  M.highlight_selected()
end

---Select previous file in tree
function M.select_prev()
  local num_files = #state.state.files
  if num_files == 0 then
    return
  end

  selected_idx = selected_idx - 1
  if selected_idx < 1 then
    selected_idx = num_files -- Wrap around
  end
  M.highlight_selected()
end

---Get currently selected file
---@return Review.File?
function M.get_selected_file()
  local files = state.state.files
  if #files == 0 or selected_idx < 1 or selected_idx > #files then
    return nil
  end
  return files[selected_idx]
end

---Open currently selected file
---@return boolean success
function M.open_selected()
  local file = M.get_selected_file()
  if not file then
    vim.notify("No file selected", vim.log.levels.WARN)
    return false
  end

  -- This will be implemented by ui/diff.lua
  -- For now, just set current file and trigger callback if configured
  state.set_current_file(file.path)
  M.render() -- Refresh to show current file highlight

  local on_file_select = config.get("callbacks.on_file_select")
  if on_file_select and type(on_file_select) == "function" then
    on_file_select(file)
  end

  return true
end

---Get file at cursor position
---@return Review.File?
function M.get_file_at_cursor()
  local win = state.state.layout.file_tree_win
  if not win or not vim.api.nvim_win_is_valid(win) then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(win)
  local line_nr = cursor[1]
  local file_idx = line_to_file_idx[line_nr]

  if file_idx then
    return state.state.files[file_idx]
  end
  return nil
end

---Open file at cursor position
---@return boolean success
function M.open_at_cursor()
  local file = M.get_file_at_cursor()
  if not file then
    return false
  end

  -- Update selection to match cursor
  local win = state.state.layout.file_tree_win
  if win and vim.api.nvim_win_is_valid(win) then
    local cursor = vim.api.nvim_win_get_cursor(win)
    local file_idx = line_to_file_idx[cursor[1]]
    if file_idx then
      selected_idx = file_idx
    end
  end

  return M.open_selected()
end

---Select file by path
---@param path string
---@return boolean success
function M.select_by_path(path)
  for i, file in ipairs(state.state.files) do
    if file.path == path then
      selected_idx = i
      M.highlight_selected()
      return true
    end
  end
  return false
end

---Get line number for file index
---@param file_idx number
---@return number?
function M.get_line_for_file(file_idx)
  for line_nr, idx in pairs(line_to_file_idx) do
    if idx == file_idx then
      return line_nr
    end
  end
  return nil
end

---Setup keymaps for file tree buffer
function M.setup_keymaps()
  local buf = state.state.layout.file_tree_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local opts = { buffer = buf, nowait = true, silent = true }

  -- Navigation
  vim.keymap.set("n", "j", function()
    M.select_next()
  end, opts)
  vim.keymap.set("n", "k", function()
    M.select_prev()
  end, opts)
  vim.keymap.set("n", "<Down>", function()
    M.select_next()
  end, opts)
  vim.keymap.set("n", "<Up>", function()
    M.select_prev()
  end, opts)

  -- Open file
  vim.keymap.set("n", "<CR>", function()
    M.open_at_cursor()
  end, opts)
  vim.keymap.set("n", "o", function()
    M.open_at_cursor()
  end, opts)
  vim.keymap.set("n", "l", function()
    M.open_at_cursor()
  end, opts)

  -- Focus diff
  vim.keymap.set("n", "<Tab>", function()
    local layout = require("review.ui.layout")
    layout.focus_diff()
  end, opts)

  -- Refresh
  vim.keymap.set("n", "R", function()
    M.render()
  end, opts)

  -- Close review
  vim.keymap.set("n", "q", function()
    local layout = require("review.ui.layout")
    layout.close()
  end, opts)
end

---Reset file tree state
function M.reset()
  selected_idx = 1
  line_to_file_idx = {}
end

---Initialize file tree (called after layout.open)
function M.init()
  M.reset()
  M.setup_keymaps()
  M.render()
end

return M
