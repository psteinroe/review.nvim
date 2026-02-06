-- File tree panel for review.nvim
-- Directory-grouped layout with collapsible sections

local M = {}

local state = require("review.core.state")
local config = require("review.config")
local utils = require("review.utils")

-- Namespace for highlights
local ns_id = vim.api.nvim_create_namespace("review_file_tree")
local ns_selection = vim.api.nvim_create_namespace("review_file_tree_selection")

---@type number Current selected index (1-indexed, refers to selectable items)
local selected_idx = 1

---@type table<number, {type: "dir"|"file", path: string, dir?: string}> Line number to item mapping
local line_to_item = {}

---@type string[] Ordered list of selectable items (file paths only)
local selectable_items = {}

---@type table<string, boolean> Expanded state for directories (true = expanded)
local expanded_dirs = {}

---@type number Header line count (for calculating file line offsets)
local header_lines_count = 0

---@type string? Current filter pattern
local filter_pattern = nil

---Get status letter for file status
---@param status string
---@return string letter Single letter status
---@return string highlight
function M.get_status_letter(status)
  local mapping = {
    added = { letter = "A", hl = "ReviewTreeAdded" },
    modified = { letter = "M", hl = "ReviewTreeModified" },
    deleted = { letter = "D", hl = "ReviewTreeDeleted" },
    renamed = { letter = "R", hl = "ReviewTreeRenamed" },
  }
  local result = mapping[status] or { letter = "?", hl = "ReviewTreeFile" }
  return result.letter, result.hl
end

---Get provenance letter for file provenance
---@param provenance? Review.Provenance
---@return string letter Single letter provenance
---@return string highlight
function M.get_provenance_letter(provenance)
  local mapping = {
    pushed = { letter = "P", hl = "ReviewTreePushed" },
    ["local"] = { letter = "L", hl = "ReviewTreeLocal" },
    uncommitted = { letter = "U", hl = "ReviewTreeUncommitted" },
    both = { letter = "B", hl = "ReviewTreeBoth" },
  }
  local result = mapping[provenance] or { letter = " ", hl = "ReviewTreeFile" }
  return result.letter, result.hl
end

---Get reviewed icon
---@param reviewed boolean
---@return string icon
---@return string highlight
function M.get_reviewed_icon(reviewed)
  if reviewed then
    return "✓", "ReviewTreeReviewed"
  else
    return "·", "ReviewTreePending"
  end
end

---Check if a file matches the current filter
---@param file Review.File
---@return boolean
function M.matches_filter(file)
  -- Check provenance filter first (from state, set by gP/gL/gU/gA keybindings)
  local prov_filter = state.state.provenance_filter
  if prov_filter then
    if file.provenance ~= prov_filter then
      return false
    end
  end

  if not filter_pattern or filter_pattern == "" then
    return true
  end

  local pattern = filter_pattern:lower()

  -- Status prefix filter (e.g., "A:", "M:", "D:")
  local status_prefix = pattern:match("^([amdrc]):(.*)$")
  if status_prefix then
    local status_map = { a = "added", m = "modified", d = "deleted", r = "renamed", c = "comment" }
    local required_status = status_map[status_prefix]
    local rest = pattern:match("^[amdrc]:(.*)$") or ""

    if required_status == "comment" then
      -- Filter for files with comments
      local count, _ = state.get_file_comment_info(file.path)
      if count == 0 then
        return false
      end
    elseif file.status ~= required_status then
      return false
    end

    -- If there's more pattern after status, match against path
    if rest ~= "" then
      return file.path:lower():find(rest, 1, true) ~= nil
    end
    return true
  end

  -- Simple substring match on path
  return file.path:lower():find(pattern, 1, true) ~= nil
end

---Get directory from file path
---@param path string
---@return string dir Directory path (empty string for root files)
---@return string filename Just the filename
function M.split_path(path)
  local last_slash = path:match(".*/()")
  if last_slash then
    -- last_slash is position after the slash, so -2 to exclude the slash itself
    return path:sub(1, last_slash - 2), path:sub(last_slash)
  end
  return "", path
end

---Group files by directory
---@param files Review.File[]
---@return table<string, Review.File[]> Grouped files by directory
---@return string[] Sorted directory list
function M.group_files_by_directory(files)
  -- Sort all files by full path first (oil.nvim style)
  local sorted_files = vim.tbl_map(function(f) return f end, files)
  table.sort(sorted_files, function(a, b)
    return a.path < b.path
  end)

  local groups = {}
  local dirs = {}
  local seen_dirs = {}

  for _, file in ipairs(sorted_files) do
    local dir, _ = M.split_path(file.path)
    if not seen_dirs[dir] then
      seen_dirs[dir] = true
      groups[dir] = {}
      table.insert(dirs, dir)
    end
    table.insert(groups[dir], file)
  end

  -- Directories are already in sorted order since files were sorted by path

  return groups, dirs
end

---Check if a directory is expanded
---@param dir string Directory path
---@return boolean
function M.is_expanded(dir)
  -- Default to expanded
  if expanded_dirs[dir] == nil then
    return true
  end
  return expanded_dirs[dir]
end

---Build selectable items from state files (for use without full render)
---@private
local function build_selectable_items()
  selectable_items = {}

  local files = state.state.files or {}
  local filtered_files = {}
  for _, file in ipairs(files) do
    if M.matches_filter(file) then
      table.insert(filtered_files, file)
    end
  end

  -- Group files by directory
  local groups, dirs = M.group_files_by_directory(filtered_files)

  -- Add files from expanded directories (all expanded by default)
  for _, dir in ipairs(dirs) do
    local is_expanded = M.is_expanded(dir)
    if is_expanded then
      local dir_files = groups[dir]
      for _, file in ipairs(dir_files) do
        table.insert(selectable_items, file.path)
      end
    end
  end

  -- Clamp selected index
  if #selectable_items > 0 then
    selected_idx = math.max(1, math.min(selected_idx, #selectable_items))
  else
    selected_idx = 1
  end
end

---Toggle directory expansion
---@param dir string Directory path
function M.toggle_directory(dir)
  if expanded_dirs[dir] == nil then
    expanded_dirs[dir] = false -- Was expanded (default), now collapse
  else
    expanded_dirs[dir] = not expanded_dirs[dir]
  end

  -- Update selectable items to reflect expansion change
  build_selectable_items()
  M.render()

  -- Move cursor to the toggled directory line
  local win = state.state.layout.file_tree_win
  if win and vim.api.nvim_win_is_valid(win) then
    for line_nr, item in pairs(line_to_item) do
      if item.type == "dir" and item.path == dir then
        vim.api.nvim_win_set_cursor(win, { line_nr, 0 })
        break
      end
    end
  end
end

---Expand all directories
function M.expand_all()
  for dir, _ in pairs(expanded_dirs) do
    expanded_dirs[dir] = true
  end
  -- Update selectable items to reflect expansion change
  build_selectable_items()
  M.render()
end

---Collapse all directories
function M.collapse_all()
  -- Get all directories from current state
  local groups, dirs = M.group_files_by_directory(state.state.files)
  for _, dir in ipairs(dirs) do
    expanded_dirs[dir] = false
  end
  -- Update selectable items to reflect expansion change
  build_selectable_items()
  M.render()
end

---Render the header based on mode
---@return string[] lines
---@return table[] highlights
function M.render_header()
  local lines = {}
  local highlights = {}

  if state.state.mode == "hybrid" and state.state.pr then
    -- Hybrid Mode header
    local pr = state.state.pr
    local line1 = string.format("PR #%d (%d files)", pr.number, #state.state.files)
    table.insert(lines, line1)
    table.insert(highlights, {
      line = 1,
      col_start = 0,
      col_end = #line1,
      hl_group = "ReviewTreeHeader",
    })

    -- Branch info
    local line2 = string.format("%s ← %s", pr.base, pr.branch)
    table.insert(lines, line2)
    table.insert(highlights, {
      line = 2,
      col_start = 0,
      col_end = #line2,
      hl_group = "ReviewTreeStats",
    })
  elseif state.state.mode == "pr" and state.state.pr then
    -- PR Mode header
    local pr = state.state.pr
    local line1 = string.format("PR #%d (%d files)", pr.number, #state.state.files)
    table.insert(lines, line1)
    table.insert(highlights, {
      line = 1,
      col_start = 0,
      col_end = #line1,
      hl_group = "ReviewTreeHeader",
    })

    -- Branch info
    local line2 = string.format("%s ← %s", pr.base, pr.branch)
    table.insert(lines, line2)
    table.insert(highlights, {
      line = 2,
      col_start = 0,
      col_end = #line2,
      hl_group = "ReviewTreeStats",
    })
  else
    -- Local mode header
    local base = state.state.base or "HEAD"
    local line1 = string.format("Local • %s (%d files)", base, #state.state.files)
    table.insert(lines, line1)
    table.insert(highlights, {
      line = 1,
      col_start = 0,
      col_end = #line1,
      hl_group = "ReviewTreeHeader",
    })
  end

  -- Progress line
  local stats = state.get_stats()
  local line3 = string.format("%d/%d reviewed", stats.reviewed_files, stats.total_files)
  table.insert(lines, line3)
  table.insert(highlights, {
    line = #lines,
    col_start = 0,
    col_end = #line3,
    hl_group = "ReviewTreeStats",
  })

  -- Filter line (if active)
  if filter_pattern and filter_pattern ~= "" then
    local filter_line = string.format("Filter: %s", filter_pattern)
    table.insert(lines, filter_line)
    table.insert(highlights, {
      line = #lines,
      col_start = 0,
      col_end = 7, -- "Filter:"
      hl_group = "ReviewTreeStats",
    })
    table.insert(highlights, {
      line = #lines,
      col_start = 8,
      col_end = #filter_line,
      hl_group = "ReviewTreeComments",
    })
  end

  -- Provenance filter indicator (if active)
  local prov_filter = state.state.provenance_filter
  if prov_filter then
    local prov_names = {
      pushed = "Pushed only",
      ["local"] = "Local only",
      uncommitted = "Uncommitted only",
      both = "Both only",
    }
    local prov_line = string.format("Showing: %s", prov_names[prov_filter] or prov_filter)
    table.insert(lines, prov_line)
    table.insert(highlights, {
      line = #lines,
      col_start = 0,
      col_end = #prov_line,
      hl_group = "ReviewTreeStats",
    })
  end

  -- Blank line separator
  table.insert(lines, "")

  return lines, highlights
end

---Render a directory header line
---@param dir string Directory path
---@param file_count number Number of files in directory
---@param line_nr number Line number (1-indexed)
---@param buf_width number Buffer width
---@return string line
---@return table[] highlights
function M.render_directory_header(dir, file_count, line_nr, buf_width)
  local highlights = {}
  local is_expanded = M.is_expanded(dir)

  -- Expand/collapse indicator
  local indicator = is_expanded and "▼" or "▶"

  -- Directory name (use ./ for root files)
  local dir_display = dir ~= "" and (dir .. "/") or "./"

  -- File count suffix
  local count_suffix = string.format("%d", file_count)

  -- Build line with right-aligned count
  local prefix = indicator .. " "
  local main_content = prefix .. dir_display
  local available = buf_width - #main_content - #count_suffix - 1
  local padding = ""
  if available > 0 then
    padding = string.rep(" ", available)
  else
    padding = " "
  end

  local line = main_content .. padding .. count_suffix

  -- Highlights
  local col = 0

  -- Indicator highlight
  table.insert(highlights, {
    line = line_nr,
    col_start = col,
    col_end = col + #indicator,
    hl_group = "ReviewTreeDirIndicator",
  })
  col = col + #prefix

  -- Directory name highlight
  table.insert(highlights, {
    line = line_nr,
    col_start = col,
    col_end = col + #dir_display,
    hl_group = "ReviewTreeDir",
  })

  -- Count highlight
  table.insert(highlights, {
    line = line_nr,
    col_start = #line - #count_suffix,
    col_end = #line,
    hl_group = "ReviewTreeStats",
  })

  return line, highlights
end

---Render a single file line (filename only, indented)
---@param file Review.File
---@param line_nr number Line number (1-indexed)
---@param buf_width number Buffer width for right-alignment
---@return string line
---@return table[] highlights
function M.render_file_line(file, line_nr, buf_width)
  local highlights = {}

  -- Get icons and status
  local reviewed_icon, reviewed_hl = M.get_reviewed_icon(file.reviewed or false)
  local status_letter, status_hl = M.get_status_letter(file.status)

  -- Get provenance letter (only shown in hybrid mode)
  local provenance_letter, provenance_hl = "", "ReviewTreeFile"
  local show_provenance = state.state.mode == "hybrid" and file.provenance
  if show_provenance then
    provenance_letter, provenance_hl = M.get_provenance_letter(file.provenance)
  end

  -- Get comment info
  local comment_count, has_pending = state.get_file_comment_info(file.path)

  -- Get just the filename (directory is shown in header)
  local _, filename = M.split_path(file.path)

  -- Build the line with indent: "  {reviewed} {provenance} {status} {filename}"
  local indent = "  "
  local prefix
  if show_provenance then
    prefix = reviewed_icon .. " " .. provenance_letter .. " " .. status_letter .. " "
  else
    prefix = reviewed_icon .. " " .. status_letter .. " "
  end
  local main_content = indent .. prefix .. filename

  -- Build comment suffix
  local comment_suffix = ""
  if comment_count > 0 then
    if has_pending then
      comment_suffix = string.format("%d*", comment_count)
    else
      comment_suffix = string.format("%d", comment_count)
    end
  end

  -- Calculate padding for right-alignment
  local min_padding = 1
  local available_width = buf_width - #main_content - #comment_suffix - min_padding
  local padding = ""
  if available_width > 0 and #comment_suffix > 0 then
    padding = string.rep(" ", available_width)
  elseif #comment_suffix > 0 then
    padding = " "
  end

  local line = main_content .. padding .. comment_suffix

  -- Highlights
  local col = #indent

  -- Reviewed icon highlight
  table.insert(highlights, {
    line = line_nr,
    col_start = col,
    col_end = col + #reviewed_icon,
    hl_group = reviewed_hl,
  })
  col = col + #reviewed_icon + 1 -- +1 for space

  -- Provenance letter highlight (only in hybrid mode)
  if show_provenance then
    table.insert(highlights, {
      line = line_nr,
      col_start = col,
      col_end = col + #provenance_letter,
      hl_group = provenance_hl,
    })
    col = col + #provenance_letter + 1 -- +1 for space
  end

  -- Status letter highlight
  table.insert(highlights, {
    line = line_nr,
    col_start = col,
    col_end = col + #status_letter,
    hl_group = status_hl,
  })
  col = col + #status_letter + 1 -- +1 for space

  -- Filename highlight
  local file_hl = "ReviewTreeFileName"
  if file.path == state.state.current_file then
    file_hl = "ReviewTreeCurrent"
  end
  table.insert(highlights, {
    line = line_nr,
    col_start = col,
    col_end = col + #filename,
    hl_group = file_hl,
  })

  -- Comment count highlight
  if #comment_suffix > 0 then
    table.insert(highlights, {
      line = line_nr,
      col_start = #line - #comment_suffix,
      col_end = #line,
      hl_group = "ReviewTreeComments",
    })
  end

  return line, highlights
end

---Render the footer with totals
---@return string[] lines
---@return table[] highlights
function M.render_footer()
  local lines = {}
  local highlights = {}

  -- Blank line separator
  table.insert(lines, "")

  -- Provenance summary for hybrid mode
  if state.state.mode == "hybrid" then
    local prov_stats = state.get_provenance_stats()
    local prov_parts = {}
    if prov_stats.pushed > 0 then
      table.insert(prov_parts, string.format("%d pushed", prov_stats.pushed))
    end
    if prov_stats.local_commits > 0 then
      table.insert(prov_parts, string.format("%d local", prov_stats.local_commits))
    end
    if prov_stats.uncommitted > 0 then
      table.insert(prov_parts, string.format("%d uncommitted", prov_stats.uncommitted))
    end

    if #prov_parts > 0 then
      local prov_line = table.concat(prov_parts, " • ")
      table.insert(lines, prov_line)
      table.insert(highlights, {
        line = #lines,
        col_start = 0,
        col_end = #prov_line,
        hl_group = "ReviewTreeStats",
      })
    end
  end

  -- Count comments
  local thread_count = 0
  local pending_count = 0
  for _, comment in ipairs(state.state.comments) do
    if comment.kind == "local" and comment.status == "pending" then
      pending_count = pending_count + 1
    else
      thread_count = thread_count + 1
    end
  end

  -- Footer line
  local footer_parts = {}
  if state.state.mode == "pr" or state.state.mode == "hybrid" then
    if thread_count > 0 then
      table.insert(footer_parts, string.format("%d threads", thread_count))
    end
  end
  if pending_count > 0 then
    table.insert(footer_parts, string.format("%d pending", pending_count))
  end

  if #footer_parts > 0 then
    local footer_line = table.concat(footer_parts, " • ")
    table.insert(lines, footer_line)
    table.insert(highlights, {
      line = #lines,
      col_start = 0,
      col_end = #footer_line,
      hl_group = "ReviewTreeStats",
    })
  end

  return lines, highlights
end

---Get buffer width for the file tree
---@return number
function M.get_buf_width()
  local win = state.state.layout.file_tree_win
  if win and vim.api.nvim_win_is_valid(win) then
    return vim.api.nvim_win_get_width(win)
  end
  return 30 -- Default width
end

---Render the full file tree
function M.render()
  local buf = state.state.layout.file_tree_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  -- Sync reviewed state with git for local mode
  if state.state.mode == "local" then
    state.sync_reviewed_with_staged()
  end

  -- Clear mappings
  line_to_item = {}
  selectable_items = {}

  local all_lines = {}
  local all_highlights = {}
  local buf_width = M.get_buf_width()

  -- Header
  local header_lines, header_hl = M.render_header()
  header_lines_count = #header_lines
  for _, line in ipairs(header_lines) do
    table.insert(all_lines, line)
  end
  for _, hl in ipairs(header_hl) do
    table.insert(all_highlights, hl)
  end

  -- Get and filter files
  local files = vim.tbl_map(function(f)
    return f
  end, state.state.files)
  local filtered_files = {}
  for _, file in ipairs(files) do
    if M.matches_filter(file) then
      table.insert(filtered_files, file)
    end
  end

  -- Group files by directory
  local groups, dirs = M.group_files_by_directory(filtered_files)

  -- Render each directory group
  for _, dir in ipairs(dirs) do
    local dir_files = groups[dir]
    local is_expanded = M.is_expanded(dir)

    -- Directory header line
    local line_nr = #all_lines + 1
    local dir_line, dir_hl = M.render_directory_header(dir, #dir_files, line_nr, buf_width)
    table.insert(all_lines, dir_line)

    -- Map this line to directory
    line_to_item[line_nr] = { type = "dir", path = dir }

    for _, h in ipairs(dir_hl) do
      table.insert(all_highlights, h)
    end

    -- Render files if expanded
    if is_expanded then
      for _, file in ipairs(dir_files) do
        line_nr = #all_lines + 1
        local file_line, file_hl = M.render_file_line(file, line_nr, buf_width)
        table.insert(all_lines, file_line)

        -- Map this line to file
        line_to_item[line_nr] = { type = "file", path = file.path, dir = dir }

        -- Add to selectable items
        table.insert(selectable_items, file.path)

        for _, h in ipairs(file_hl) do
          table.insert(all_highlights, h)
        end
      end
    end
  end

  -- Clamp selected index to valid range
  if #selectable_items > 0 then
    selected_idx = math.max(1, math.min(selected_idx, #selectable_items))
  else
    selected_idx = 1
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

  -- Find line number for selected file
  if #selectable_items == 0 or selected_idx < 1 or selected_idx > #selectable_items then
    return
  end

  local selected_path = selectable_items[selected_idx]
  local target_line = nil

  for line_nr, item in pairs(line_to_item) do
    if item.type == "file" and item.path == selected_path then
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

---Set the selected index (display order)
---@param idx number
function M.set_selected_idx(idx)
  local num_files = #selectable_items
  if num_files == 0 then
    selected_idx = 1
    return
  end
  selected_idx = math.max(1, math.min(idx, num_files))
  M.highlight_selected()
end

---Move cursor down to next item line (file or directory)
function M.cursor_down()
  local win = state.state.layout.file_tree_win
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(win)
  local current_line = cursor[1]
  local line_count = vim.api.nvim_buf_line_count(state.state.layout.file_tree_buf)

  -- Find next line that has an item (file or directory)
  for line_nr = current_line + 1, line_count do
    if line_to_item[line_nr] then
      vim.api.nvim_win_set_cursor(win, { line_nr, 0 })
      return
    end
  end
end

---Move cursor up to previous item line (file or directory)
function M.cursor_up()
  local win = state.state.layout.file_tree_win
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(win)
  local current_line = cursor[1]

  -- Find previous line that has an item (file or directory)
  for line_nr = current_line - 1, 1, -1 do
    if line_to_item[line_nr] then
      vim.api.nvim_win_set_cursor(win, { line_nr, 0 })
      return
    end
  end
end

---Select next file
function M.select_next()
  local num_files = #selectable_items
  if num_files == 0 then
    return
  end

  selected_idx = selected_idx + 1
  if selected_idx > num_files then
    selected_idx = 1 -- Wrap around
  end
  M.highlight_selected()
end

---Select previous file
function M.select_prev()
  local num_files = #selectable_items
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
  if #selectable_items == 0 or selected_idx < 1 or selected_idx > #selectable_items then
    return nil
  end
  local path = selectable_items[selected_idx]
  local file, _ = state.find_file(path)
  return file
end

---Open currently selected file
---@return boolean success
function M.open_selected()
  local file = M.get_selected_file()
  if not file then
    vim.notify("No file selected", vim.log.levels.WARN)
    return false
  end

  -- Open the file in diff view
  local diff = require("review.ui.diff")
  local success = diff.open_file(file.path)

  if success then
    M.render() -- Refresh to show current file highlight

    local on_file_select = config.get("callbacks.on_file_select")
    if on_file_select and type(on_file_select) == "function" then
      on_file_select(file)
    end
  end

  return success
end

---Toggle reviewed status for selected file
---@return boolean? new_status New reviewed status, or nil if failed
function M.toggle_reviewed()
  local file = M.get_selected_file()
  if not file then
    return nil
  end

  if state.state.mode == "local" then
    -- Local mode: stage/unstage the file
    local git = require("review.integrations.git")
    local success, err
    if file.reviewed then
      success, err = git.unstage_file(file.path)
    else
      success, err = git.stage_file(file.path)
    end

    if not success then
      vim.notify("Failed to toggle: " .. (err or "unknown error"), vim.log.levels.ERROR)
      return nil
    end
  end

  -- Toggle in state
  local new_status = state.toggle_file_reviewed(file.path)

  -- Re-render
  M.render()

  return new_status
end

---Get item at cursor position
---@return {type: "dir"|"file", path: string, dir?: string}?
function M.get_item_at_cursor()
  local win = state.state.layout.file_tree_win
  if not win or not vim.api.nvim_win_is_valid(win) then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(win)
  local line_nr = cursor[1]
  return line_to_item[line_nr]
end

---Get file at cursor position
---@return Review.File?
function M.get_file_at_cursor()
  local item = M.get_item_at_cursor()
  if not item or item.type ~= "file" then
    return nil
  end
  local file, _ = state.find_file(item.path)
  return file
end

---Handle action at cursor (open file or toggle directory)
---@return boolean success
function M.action_at_cursor()
  local item = M.get_item_at_cursor()
  if not item then
    return false
  end

  if item.type == "dir" then
    M.toggle_directory(item.path)
    return true
  else
    -- Update selection to match cursor
    for i, path in ipairs(selectable_items) do
      if path == item.path then
        selected_idx = i
        break
      end
    end
    return M.open_selected()
  end
end

---Open file at cursor position (if it's a file)
---@return boolean success
function M.open_at_cursor()
  local item = M.get_item_at_cursor()
  if not item then
    return false
  end

  if item.type == "dir" then
    -- On directory, toggle it
    M.toggle_directory(item.path)
    return true
  end

  -- Update selection to match cursor
  for i, path in ipairs(selectable_items) do
    if path == item.path then
      selected_idx = i
      break
    end
  end

  return M.open_selected()
end

---Toggle reviewed for file at cursor
---@return boolean? new_status
function M.toggle_reviewed_at_cursor()
  local file = M.get_file_at_cursor()
  if not file then
    return nil
  end

  -- Update selection to match cursor
  for i, path in ipairs(selectable_items) do
    if path == file.path then
      selected_idx = i
      break
    end
  end

  return M.toggle_reviewed()
end

---Select file by path
---@param path string
---@return boolean success
function M.select_by_path(path)
  -- First ensure the directory is expanded
  local dir, _ = M.split_path(path)
  if not M.is_expanded(dir) then
    expanded_dirs[dir] = true
    M.render()
  end

  for i, p in ipairs(selectable_items) do
    if p == path then
      selected_idx = i
      M.highlight_selected()
      return true
    end
  end
  return false
end

---Get line number for a file path
---@param path string
---@return number?
function M.get_line_for_file(path)
  for line_nr, item in pairs(line_to_item) do
    if item.type == "file" and item.path == path then
      return line_nr
    end
  end
  return nil
end

---Get sorted file paths (display order, only from expanded directories)
---@return string[]
function M.get_sorted_paths()
  return selectable_items
end

---Get display index for a file path
---@param path string
---@return number? display index (1-indexed)
function M.get_display_idx_for_path(path)
  for i, p in ipairs(selectable_items) do
    if p == path then
      return i
    end
  end
  return nil
end

---Setup keymaps for file tree buffer (Fugitive-style)
function M.setup_keymaps()
  local buf = state.state.layout.file_tree_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local opts = { buffer = buf, nowait = true, silent = true }

  -- Navigation (j/k moves cursor through all lines including directories)
  vim.keymap.set("n", "j", function()
    M.cursor_down()
  end, opts)
  vim.keymap.set("n", "k", function()
    M.cursor_up()
  end, opts)
  vim.keymap.set("n", "<Down>", function()
    M.cursor_down()
  end, opts)
  vim.keymap.set("n", "<Up>", function()
    M.cursor_up()
  end, opts)

  -- File-only navigation with ( and ) like Fugitive
  vim.keymap.set("n", ")", function()
    M.select_next()
  end, opts)
  vim.keymap.set("n", "(", function()
    M.select_prev()
  end, opts)

  -- Open file (like Fugitive: <CR>, o)
  vim.keymap.set("n", "<CR>", function()
    M.action_at_cursor()
  end, opts)
  vim.keymap.set("n", "o", function()
    M.action_at_cursor()
  end, opts)

  -- Toggle expand/collapse with = (like Fugitive inline diff toggle)
  vim.keymap.set("n", "=", function()
    local item = M.get_item_at_cursor()
    if item then
      if item.type == "dir" then
        M.toggle_directory(item.path)
      elseif item.dir then
        -- On file: toggle parent directory
        M.toggle_directory(item.dir)
      end
    end
  end, opts)

  -- Collapse with h, expand with l (tree-style navigation)
  vim.keymap.set("n", "h", function()
    local item = M.get_item_at_cursor()
    if item then
      if item.type == "dir" then
        if M.is_expanded(item.path) then
          M.toggle_directory(item.path)
        end
      elseif item.dir then
        if M.is_expanded(item.dir) then
          M.toggle_directory(item.dir)
        end
      end
    end
  end, opts)
  vim.keymap.set("n", "l", function()
    local item = M.get_item_at_cursor()
    if item then
      if item.type == "dir" then
        if not M.is_expanded(item.path) then
          M.toggle_directory(item.path)
        else
          -- Already expanded, move to first file in dir
          M.cursor_down()
        end
      else
        M.open_selected()
      end
    end
  end, opts)

  -- Stage/unstage toggle with - (like Fugitive)
  vim.keymap.set("n", "-", function()
    M.toggle_reviewed_at_cursor()
  end, opts)

  -- Stage with s (like Fugitive)
  vim.keymap.set("n", "s", function()
    local file = M.get_file_at_cursor()
    if file and not file.reviewed then
      M.toggle_reviewed_at_cursor()
    end
  end, opts)

  -- Unstage with u (like Fugitive)
  vim.keymap.set("n", "u", function()
    local file = M.get_file_at_cursor()
    if file and file.reviewed then
      M.toggle_reviewed_at_cursor()
    end
  end, opts)

  -- Keep Space and x as aliases for toggle
  vim.keymap.set("n", "<Space>", function()
    M.toggle_reviewed_at_cursor()
  end, opts)
  vim.keymap.set("n", "x", function()
    M.toggle_reviewed_at_cursor()
  end, opts)

  -- Expand/collapse all (vim fold-style)
  vim.keymap.set("n", "zM", function()
    M.collapse_all()
  end, opts)
  vim.keymap.set("n", "zR", function()
    M.expand_all()
  end, opts)

  -- Mouse click to open file
  vim.keymap.set("n", "<LeftRelease>", function()
    M.action_at_cursor()
  end, opts)
  vim.keymap.set("n", "<2-LeftMouse>", function()
    M.action_at_cursor()
  end, opts)

  -- Cross-file hunk navigation with Tab/S-Tab
  vim.keymap.set("n", "<Tab>", function()
    local nav = require("review.core.navigation")
    nav.next_hunk_across_files()
  end, opts)
  vim.keymap.set("n", "<S-Tab>", function()
    local nav = require("review.core.navigation")
    nav.prev_hunk_across_files()
  end, opts)

  -- Refresh files from git
  vim.keymap.set("n", "R", function()
    require("review.commands").refresh()
  end, opts)

  -- Filter (inline search within tree)
  vim.keymap.set("n", "/", function()
    M.filter_input()
  end, opts)

  -- Clear filter
  vim.keymap.set("n", "<Esc>", function()
    if filter_pattern and filter_pattern ~= "" then
      M.clear_filter()
    elseif state.state.provenance_filter then
      M.clear_provenance_filter()
    end
  end, opts)

  -- Provenance filters (only functional in hybrid mode)
  vim.keymap.set("n", "gP", function()
    M.set_provenance_filter("pushed")
  end, opts)
  vim.keymap.set("n", "gL", function()
    M.set_provenance_filter("local")
  end, opts)
  vim.keymap.set("n", "gU", function()
    M.set_provenance_filter("uncommitted")
  end, opts)
  vim.keymap.set("n", "gA", function()
    M.clear_provenance_filter()
  end, opts)

  -- Close review
  vim.keymap.set("n", "q", function()
    local layout = require("review.ui.layout")
    layout.close()
  end, opts)
end

---Build selectable items from state files (for use without full render)
---@private
---Reset file tree state
function M.reset()
  selected_idx = 1
  line_to_item = {}
  selectable_items = {}
  expanded_dirs = {}
  header_lines_count = 0
  filter_pattern = nil
  -- Note: provenance_filter is stored in state.state, not here

  -- Rebuild selectable items from current state files
  build_selectable_items()
end

---Get current filter
---@return string?
function M.get_filter()
  return filter_pattern
end

---Set filter and re-render
---@param pattern string?
function M.set_filter(pattern)
  filter_pattern = pattern
  selected_idx = 1 -- Reset selection when filter changes
  M.render()
end

---Clear filter
function M.clear_filter()
  M.set_filter(nil)
end

---Set provenance filter
---@param provenance Review.Provenance?
function M.set_provenance_filter(provenance)
  if state.state.mode ~= "hybrid" then
    vim.notify("Provenance filters only available in hybrid mode", vim.log.levels.WARN)
    return
  end
  state.set_provenance_filter(provenance)
  selected_idx = 1 -- Reset selection when filter changes
  M.render()

  local prov_names = {
    pushed = "pushed",
    ["local"] = "local",
    uncommitted = "uncommitted",
    both = "both",
  }
  vim.notify(string.format("Showing %s files", prov_names[provenance] or "all"), vim.log.levels.INFO)
end

---Clear provenance filter
function M.clear_provenance_filter()
  if state.state.provenance_filter then
    state.set_provenance_filter(nil)
    selected_idx = 1
    M.render()
    vim.notify("Showing all files", vim.log.levels.INFO)
  end
end

---Start interactive filter mode within the file tree
---Types filter in the cmdline and updates tree live
function M.start_filter()
  local win = state.state.layout.file_tree_win
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end

  -- Save original filter to restore on cancel
  local original_filter = filter_pattern

  -- Enter cmdline mode with live updating
  local input = ""

  -- Function to update filter as user types
  local function update_preview()
    M.set_filter(input ~= "" and input or nil)
  end

  -- Use vim.fn.input with a callback approach via feedkeys
  -- This allows live filtering as user types
  vim.api.nvim_feedkeys(":lua require('review.ui.file_tree').filter_input()\r", "n", false)
end

---Handle filter input (called from cmdline)
function M.filter_input()
  local win = state.state.layout.file_tree_win
  local original_filter = filter_pattern

  -- Create a small floating input window at the bottom of file tree
  local buf = vim.api.nvim_create_buf(false, true)
  local tree_win_config = vim.api.nvim_win_get_config(win)
  local tree_height = vim.api.nvim_win_get_height(win)
  local tree_width = vim.api.nvim_win_get_width(win)

  local input_win = vim.api.nvim_open_win(buf, true, {
    relative = "win",
    win = win,
    row = tree_height - 1,
    col = 0,
    width = tree_width,
    height = 1,
    style = "minimal",
    border = "none",
  })

  -- Set buffer options
  vim.bo[buf].buftype = "prompt"
  vim.fn.prompt_setprompt(buf, "/")

  -- Set up prompt callback
  vim.fn.prompt_setcallback(buf, function(text)
    -- Close input window
    if vim.api.nvim_win_is_valid(input_win) then
      vim.api.nvim_win_close(input_win, true)
    end
    -- Apply filter
    if text and text ~= "" then
      M.set_filter(text)
    else
      M.clear_filter()
    end
    -- Refocus tree
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
    end
  end)

  -- Handle interrupt (Ctrl-C or Escape)
  vim.fn.prompt_setinterrupt(buf, function()
    if vim.api.nvim_win_is_valid(input_win) then
      vim.api.nvim_win_close(input_win, true)
    end
    -- Restore original filter
    filter_pattern = original_filter
    M.render()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
    end
  end)

  -- Live update as user types
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = buf,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, 1, false)
      local text = lines[1] or ""
      -- Remove the prompt character
      if text:sub(1, 1) == "/" then
        text = text:sub(2)
      end
      -- Update filter live
      if text ~= "" then
        filter_pattern = text
      else
        filter_pattern = nil
      end
      M.render()
    end,
  })

  -- Helper to close and cancel
  local function cancel_search()
    if vim.api.nvim_win_is_valid(input_win) then
      vim.api.nvim_win_close(input_win, true)
    end
    -- Restore original filter
    filter_pattern = original_filter
    M.render()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
    end
  end

  -- Map Escape to cancel (works in both normal and insert mode)
  vim.keymap.set("i", "<Esc>", cancel_search, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", cancel_search, { buffer = buf, nowait = true })
  vim.keymap.set("n", "q", cancel_search, { buffer = buf, nowait = true })

  -- Start in insert mode
  vim.cmd("startinsert!")
end

---Refresh files from git and re-render
---Lightweight refresh: re-diff and re-render without fetching or notifications
---Used by auto-refresh on BufEnter
function M.refresh_files()
  if state.state.mode == "pr" then
    M.render()
    return
  end

  local git = require("review.integrations.git")
  local diff_parser = require("review.core.diff_parser")

  local base = state.state.base or "HEAD"

  local diff_output = git.diff(base)
  local files = diff_parser.parse(diff_output or "")

  -- Include untracked files
  local untracked = git.get_untracked_files()
  local seen = {}
  for _, f in ipairs(files) do
    seen[f.path] = true
  end
  for _, path in ipairs(untracked) do
    if not seen[path] then
      table.insert(files, {
        path = path,
        status = "added",
        additions = 0,
        deletions = 0,
        comment_count = 0,
        hunks = {},
        reviewed = false,
      })
    end
  end

  -- Preserve reviewed status
  local old_reviewed = {}
  for _, f in ipairs(state.state.files) do
    old_reviewed[f.path] = f.reviewed
  end
  for _, f in ipairs(files) do
    if old_reviewed[f.path] ~= nil then
      f.reviewed = old_reviewed[f.path]
    end
  end

  -- Recompute provenance for hybrid mode
  if state.state.mode == "hybrid" and state.state.origin_head then
    git.compute_provenance(files, state.state.base, state.state.origin_head)
  end

  state.set_files(files)
  M.render()
end

---Initialize file tree (called after layout.open)
function M.init()
  M.reset()
  M.setup_keymaps()
  M.render()
  M.setup_auto_refresh()
end

---Setup auto-refresh on entering file tree
function M.setup_auto_refresh()
  local buf = state.state.layout.file_tree_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = buf,
    callback = function()
      if state.is_active() then
        M.refresh_files()
      end
    end,
  })
end

return M
