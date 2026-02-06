#!/usr/bin/env lua
-- Generate doc/review.txt from README.md
-- Usage: lua scripts/generate-docs.lua
-- Or: nvim -l scripts/generate-docs.lua

local function read_file(path)
  local f = io.open(path, "r")
  if not f then
    error("Could not open " .. path)
  end
  local content = f:read("*a")
  f:close()
  return content
end

local function write_file(path, content)
  local f = io.open(path, "w")
  if not f then
    error("Could not write to " .. path)
  end
  f:write(content)
  f:close()
end

-- Convert markdown to vimdoc
local function convert(markdown)
  local output_lines = {}
  local in_code_block = false
  local code_lang = nil
  local skip_until_next_header = false
  local skip_license = false

  -- Track sections for table of contents
  local sections = {}

  local function add(line)
    table.insert(output_lines, line)
  end

  local function right_align(text, width)
    width = width or 78
    if #text >= width then return text end
    return string.rep(" ", width - #text) .. text
  end

  -- Add header
  add("*review.txt*  Code review plugin for Neovim with GitHub and AI integration")
  add("")
  add("Author:  psteinroe")
  add("License: MIT")
  add("")
  add(string.rep("=", 78))
  add("CONTENTS" .. right_align("*review-contents*", 78 - 8))
  add("")

  -- First pass: collect sections
  for line in markdown:gmatch("[^\r\n]+") do
    local h2 = line:match("^## (.+)$")
    if h2 and h2 ~= "License" then
      table.insert(sections, h2)
    end
  end

  -- Add TOC
  for i, section in ipairs(sections) do
    local tag_name = "review-" .. section:lower():gsub("%s+", "-"):gsub("[^%w-]", "")
    local dots = string.rep(".", 40 - #section - #tostring(i) - 4)
    add(string.format("    %d. %s %s |%s|", i, section, dots, tag_name))
  end
  add("")

  -- Second pass: convert content
  local source_lines = {}
  for line in markdown:gmatch("[^\r\n]*") do
    table.insert(source_lines, line)
  end

  local i = 1
  while i <= #source_lines do
    local line = source_lines[i]

    -- Skip title (h1)
    if line:match("^# ") then
      i = i + 1
      goto continue
    end

    -- Skip License section entirely
    if line:match("^## License") then
      skip_license = true
      i = i + 1
      goto continue
    end
    if skip_license then
      i = i + 1
      goto continue
    end

    -- Skip installation section details (lazy.nvim, packer.nvim headers)
    if line:match("^### lazy%.nvim") or line:match("^### packer%.nvim") then
      skip_until_next_header = true
      i = i + 1
      goto continue
    end

    if skip_until_next_header then
      if line:match("^##[^#]") then
        skip_until_next_header = false
      else
        i = i + 1
        goto continue
      end
    end

    -- Skip blank lines (we'll add them where needed)
    if line:match("^%s*$") then
      i = i + 1
      goto continue
    end

    -- Code blocks
    if line:match("^```") then
      if in_code_block then
        add("<")
        in_code_block = false
        code_lang = nil
      else
        code_lang = line:match("^```(%w+)") or ""
        if code_lang ~= "" then
          add(">" .. code_lang)
        else
          add(">")
        end
        in_code_block = true
      end
      i = i + 1
      goto continue
    end

    if in_code_block then
      add("    " .. line)
      i = i + 1
      goto continue
    end

    -- Headers
    local h2 = line:match("^## (.+)$")
    if h2 then
      add(string.rep("=", 78))
      local tag_name = h2:upper():gsub("%s+", " ")
      local tag_ref = "review-" .. h2:lower():gsub("%s+", "-"):gsub("[^%w-]", "")
      add(tag_name .. right_align("*" .. tag_ref .. "*", 78 - #tag_name))
      add("")
      i = i + 1
      goto continue
    end

    local h3 = line:match("^### (.+)$")
    if h3 then
      add("")
      add(h3:upper() .. " ~")
      add("")
      i = i + 1
      goto continue
    end

    local h4 = line:match("^#### (.+)$")
    if h4 then
      add("")
      add(h4 .. " ~")
      add("")
      i = i + 1
      goto continue
    end

    -- Tables - convert to simple format
    if line:match("^|.-|.-|$") then
      -- Skip separator lines
      if line:match("^|[-:|]+|$") then
        i = i + 1
        goto continue
      end
      -- Parse table cells
      local cells = {}
      for cell in line:gmatch("|([^|]+)") do
        cell = cell:match("^%s*(.-)%s*$") -- trim
        if cell ~= "" then
          table.insert(cells, cell)
        end
      end
      if #cells >= 2 then
        -- Format as "key    description"
        local key = cells[1]:gsub("`", "")
        local desc = cells[2]
        -- Remove markdown formatting
        desc = desc:gsub("`([^`]+)`", "%1")
        desc = desc:gsub("%*%*([^*]+)%*%*", "%1")
        desc = desc:gsub("%[([^%]]+)%]%([^)]+%)", "%1")

        local padding = math.max(1, 16 - #key)
        add("    " .. key .. string.rep(" ", padding) .. desc)
      end
      i = i + 1
      goto continue
    end

    -- Bold text
    line = line:gsub("%*%*([^*]+)%*%*", "%1")

    -- Inline code - keep backticks for vimdoc
    line = line:gsub("`([^`]+)`", "`%1`")

    -- Links
    line = line:gsub("%[([^%]]+)%]%([^)]+%)", "%1")

    -- List items
    if line:match("^%- ") then
      line = line:gsub("^%- ", "- ")
    end

    -- Numbered lists
    line = line:gsub("^(%d+)%. ", "%1. ")

    add(line)
    i = i + 1

    ::continue::
  end

  -- Add footer
  add(string.rep("=", 78))
  add("vim:tw=78:ts=8:ft=help:norl:")

  -- Post-process: collapse multiple blank lines into one
  local result = {}
  local prev_blank = false
  for _, line in ipairs(output_lines) do
    local is_blank = line:match("^%s*$")
    if is_blank then
      if not prev_blank then
        table.insert(result, "")
      end
      prev_blank = true
    else
      table.insert(result, line)
      prev_blank = false
    end
  end

  return table.concat(result, "\n")
end

-- Main
local script_dir = arg[0]:match("(.*/)")
local root_dir = script_dir and script_dir:gsub("scripts/$", "") or "./"

local readme_path = root_dir .. "README.md"
local doc_path = root_dir .. "doc/review.txt"

print("Reading " .. readme_path)
local readme = read_file(readme_path)

print("Converting to vimdoc format...")
local vimdoc = convert(readme)

print("Writing " .. doc_path)
write_file(doc_path, vimdoc)

print("Done! Generated doc/review.txt")
