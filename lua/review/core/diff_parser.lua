-- Diff parser for review.nvim
-- Parses git diff output into structured data
local M = {}

---Parse git diff output into structured file data
---@param diff_output string Raw git diff output
---@return Review.File[]
function M.parse(diff_output)
  if not diff_output or diff_output == "" then
    return {}
  end

  local files = {}
  local current_file = nil
  local current_hunk = nil
  local old_line = 0
  local new_line = 0

  for line in diff_output:gmatch("[^\r\n]+") do
    -- File header: diff --git a/path b/path
    local file_a, file_b = line:match("^diff %-%-git a/(.-) b/(.-)$")
    if file_a then
      -- Save previous file
      if current_file then
        if current_hunk then
          table.insert(current_file.hunks, current_hunk)
        end
        table.insert(files, current_file)
      end

      -- Start new file
      current_file = {
        path = file_b,
        status = "modified",
        additions = 0,
        deletions = 0,
        old_path = nil,
        comment_count = 0,
        hunks = {},
      }
      current_hunk = nil
      goto continue
    end

    -- New file mode
    if line:match("^new file mode") then
      if current_file then
        current_file.status = "added"
      end
      goto continue
    end

    -- Deleted file mode
    if line:match("^deleted file mode") then
      if current_file then
        current_file.status = "deleted"
      end
      goto continue
    end

    -- Rename from
    local old_path = line:match("^rename from (.+)$")
    if old_path then
      if current_file then
        current_file.status = "renamed"
        current_file.old_path = old_path
      end
      goto continue
    end

    -- Rename to (updates path)
    local new_path = line:match("^rename to (.+)$")
    if new_path then
      if current_file then
        current_file.path = new_path
      end
      goto continue
    end

    -- Hunk header: @@ -old_start,old_count +new_start,new_count @@ context
    local old_start, old_count, new_start, new_count = line:match(
      "^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@"
    )
    if old_start then
      -- Save previous hunk
      if current_hunk and current_file then
        table.insert(current_file.hunks, current_hunk)
      end

      -- Start new hunk
      old_count = old_count ~= "" and tonumber(old_count) or 1
      new_count = new_count ~= "" and tonumber(new_count) or 1

      current_hunk = {
        old_start = tonumber(old_start),
        old_count = old_count,
        new_start = tonumber(new_start),
        new_count = new_count,
        header = line,
        lines = {},
      }
      old_line = tonumber(old_start)
      new_line = tonumber(new_start)
      goto continue
    end

    -- Diff lines (context, add, delete)
    if current_hunk then
      local first_char = line:sub(1, 1)
      local content = line:sub(2)

      if first_char == "+" then
        -- Added line
        table.insert(current_hunk.lines, {
          type = "add",
          content = content,
          old_line = nil,
          new_line = new_line,
        })
        new_line = new_line + 1
        if current_file then
          current_file.additions = current_file.additions + 1
        end
      elseif first_char == "-" then
        -- Deleted line
        table.insert(current_hunk.lines, {
          type = "delete",
          content = content,
          old_line = old_line,
          new_line = nil,
        })
        old_line = old_line + 1
        if current_file then
          current_file.deletions = current_file.deletions + 1
        end
      elseif first_char == " " then
        -- Context line
        table.insert(current_hunk.lines, {
          type = "context",
          content = content,
          old_line = old_line,
          new_line = new_line,
        })
        old_line = old_line + 1
        new_line = new_line + 1
      elseif first_char == "\\" then
        -- No newline at end of file marker - skip
        goto continue
      end
    end

    ::continue::
  end

  -- Save last file and hunk
  if current_file then
    if current_hunk then
      table.insert(current_file.hunks, current_hunk)
    end
    table.insert(files, current_file)
  end

  return files
end

---Parse a single hunk from text
---@param hunk_text string Hunk text including header
---@return Review.Hunk?
function M.parse_hunk(hunk_text)
  if not hunk_text or hunk_text == "" then
    return nil
  end

  local lines_iter = hunk_text:gmatch("[^\r\n]+")
  local header = lines_iter()

  if not header then
    return nil
  end

  local old_start, old_count, new_start, new_count = header:match(
    "^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@"
  )

  if not old_start then
    return nil
  end

  old_count = old_count ~= "" and tonumber(old_count) or 1
  new_count = new_count ~= "" and tonumber(new_count) or 1

  local hunk = {
    old_start = tonumber(old_start),
    old_count = old_count,
    new_start = tonumber(new_start),
    new_count = new_count,
    header = header,
    lines = {},
  }

  local old_line = hunk.old_start
  local new_line = hunk.new_start

  for line in lines_iter do
    local first_char = line:sub(1, 1)
    local content = line:sub(2)

    if first_char == "+" then
      table.insert(hunk.lines, {
        type = "add",
        content = content,
        old_line = nil,
        new_line = new_line,
      })
      new_line = new_line + 1
    elseif first_char == "-" then
      table.insert(hunk.lines, {
        type = "delete",
        content = content,
        old_line = old_line,
        new_line = nil,
      })
      old_line = old_line + 1
    elseif first_char == " " then
      table.insert(hunk.lines, {
        type = "context",
        content = content,
        old_line = old_line,
        new_line = new_line,
      })
      old_line = old_line + 1
      new_line = new_line + 1
    end
  end

  return hunk
end

---Get diff for a specific file
---@param file string File path
---@param base? string Base ref (default: HEAD)
---@return string diff_output
function M.get_file_diff(file, base)
  base = base or "HEAD"
  local result = vim.system({ "git", "diff", base, "--", file }, { text = true }):wait()
  return result.stdout or ""
end

---Get diff between two refs
---@param base string Base ref
---@param head? string Head ref (default: working tree)
---@return string diff_output
function M.get_diff(base, head)
  local args = { "git", "diff", base }
  if head then
    table.insert(args, head)
  end
  local result = vim.system(args, { text = true }):wait()
  return result.stdout or ""
end

---Get changed files as parsed File structures
---@param base? string Base ref
---@param head? string Head ref
---@return Review.File[]
function M.get_changed_files(base, head)
  local diff_output = M.get_diff(base or "HEAD", head)
  return M.parse(diff_output)
end

---Find the hunk containing a specific line number
---@param hunks Review.Hunk[] List of hunks
---@param line number Line number in new file
---@return Review.Hunk?
---@return number? hunk_index
function M.find_hunk_for_line(hunks, line)
  for i, hunk in ipairs(hunks) do
    local hunk_end = hunk.new_start + hunk.new_count - 1
    if line >= hunk.new_start and line <= hunk_end then
      return hunk, i
    end
  end
  return nil, nil
end

---Convert a new file line number to old file line number
---Returns nil if the line was added (doesn't exist in old file)
---@param hunk Review.Hunk Hunk containing the line
---@param new_line number Line number in new file
---@return number? old_line
function M.new_to_old_line(hunk, new_line)
  for _, diff_line in ipairs(hunk.lines) do
    if diff_line.new_line == new_line then
      -- Found the line - return old_line (nil for added lines)
      return diff_line.old_line
    end
  end
  return nil
end

---Convert an old file line number to new file line number
---Returns nil if the line was deleted (doesn't exist in new file)
---@param hunk Review.Hunk Hunk containing the line
---@param old_line number Line number in old file
---@return number? new_line
function M.old_to_new_line(hunk, old_line)
  for _, diff_line in ipairs(hunk.lines) do
    if diff_line.old_line == old_line then
      -- Found the line - return new_line (nil for deleted lines)
      return diff_line.new_line
    end
  end
  return nil
end

---Get the diff side for a line (LEFT for old/deleted, RIGHT for new/added)
---@param hunk Review.Hunk Hunk containing the line
---@param line number Line number in new file
---@return "LEFT" | "RIGHT"
function M.get_line_side(hunk, line)
  for _, diff_line in ipairs(hunk.lines) do
    if diff_line.new_line == line then
      if diff_line.type == "delete" then
        return "LEFT"
      end
      return "RIGHT"
    end
  end
  return "RIGHT" -- Default to right side
end

---Check whether commenting should be restricted to diff hunks for a file
---Returns true when the file's comments would be submitted to GitHub
---(i.e., lines outside hunks would be rejected by the GitHub API).
---@param file_path string File path to check
---@return boolean
function M.should_restrict_to_hunks(file_path)
  local ok, st = pcall(require, "review.core.state")
  if not ok then
    return false
  end

  local mode = st.state.mode
  if mode == "local" then
    return false
  end

  if mode == "pr" then
    return true
  end

  -- hybrid mode: restrict only for pushed / both provenance
  if mode == "hybrid" then
    local file = st.find_file(file_path)
    if file and (file.provenance == "pushed" or file.provenance == "both") then
      return true
    end
    return false
  end

  return false
end

---Calculate total additions and deletions across all files
---@param files Review.File[]
---@return {additions: number, deletions: number}
function M.get_total_stats(files)
  local additions = 0
  local deletions = 0

  for _, file in ipairs(files) do
    additions = additions + file.additions
    deletions = deletions + file.deletions
  end

  return {
    additions = additions,
    deletions = deletions,
  }
end

return M
