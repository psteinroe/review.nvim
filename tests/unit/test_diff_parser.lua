-- Tests for diff_parser module
local T = MiniTest.new_set()

-- Load the module
local parser = require("review.core.diff_parser")

-- =============================================================================
-- parse() tests
-- =============================================================================

T["parse"] = MiniTest.new_set()

T["parse"]["returns empty array for empty input"] = function()
  MiniTest.expect.equality(parser.parse(""), {})
  MiniTest.expect.equality(parser.parse(nil), {})
end

T["parse"]["parses file header"] = function()
  local diff = _G.H.mock_diff()
  local files = parser.parse(diff)

  MiniTest.expect.equality(#files, 1)
  MiniTest.expect.equality(files[1].path, "src/route.ts")
  MiniTest.expect.equality(files[1].status, "modified")
end

T["parse"]["parses multiple files"] = function()
  local diff = [[
diff --git a/file1.ts b/file1.ts
index 1234567..abcdefg 100644
--- a/file1.ts
+++ b/file1.ts
@@ -1,3 +1,4 @@
 line1
+added
 line2
 line3
diff --git a/file2.ts b/file2.ts
index 1234567..abcdefg 100644
--- a/file2.ts
+++ b/file2.ts
@@ -1,2 +1,2 @@
-old
+new
 unchanged
]]
  local files = parser.parse(diff)

  MiniTest.expect.equality(#files, 2)
  MiniTest.expect.equality(files[1].path, "file1.ts")
  MiniTest.expect.equality(files[2].path, "file2.ts")
end

T["parse"]["parses hunk header"] = function()
  local diff = _G.H.mock_diff()
  local files = parser.parse(diff)

  MiniTest.expect.equality(#files[1].hunks, 2)
  MiniTest.expect.equality(files[1].hunks[1].old_start, 1)
  MiniTest.expect.equality(files[1].hunks[1].old_count, 5)
  MiniTest.expect.equality(files[1].hunks[1].new_start, 1)
  MiniTest.expect.equality(files[1].hunks[1].new_count, 7)
end

T["parse"]["parses hunk header with single line counts"] = function()
  local diff = [[
diff --git a/test.txt b/test.txt
index 1234567..abcdefg 100644
--- a/test.txt
+++ b/test.txt
@@ -1 +1 @@
-old
+new
]]
  local files = parser.parse(diff)

  MiniTest.expect.equality(files[1].hunks[1].old_count, 1)
  MiniTest.expect.equality(files[1].hunks[1].new_count, 1)
end

T["parse"]["parses line types"] = function()
  local diff = _G.H.mock_diff()
  local files = parser.parse(diff)

  local hunk = files[1].hunks[1]
  local additions = vim.tbl_filter(function(l)
    return l.type == "add"
  end, hunk.lines)
  local deletions = vim.tbl_filter(function(l)
    return l.type == "delete"
  end, hunk.lines)
  local context = vim.tbl_filter(function(l)
    return l.type == "context"
  end, hunk.lines)

  MiniTest.expect.equality(#additions, 2)
  MiniTest.expect.equality(#deletions, 0)
  -- mock_diff has 3 context lines in first hunk (2 imports + 1 export)
  MiniTest.expect.equality(#context, 3)
end

T["parse"]["tracks line numbers correctly"] = function()
  local diff = [[
diff --git a/test.ts b/test.ts
index 1234567..abcdefg 100644
--- a/test.ts
+++ b/test.ts
@@ -1,4 +1,5 @@
 context1
-deleted
+added1
+added2
 context2
 context3
]]
  local files = parser.parse(diff)
  local lines = files[1].hunks[1].lines

  -- context1: old=1, new=1
  MiniTest.expect.equality(lines[1].type, "context")
  MiniTest.expect.equality(lines[1].old_line, 1)
  MiniTest.expect.equality(lines[1].new_line, 1)

  -- deleted: old=2, new=nil
  MiniTest.expect.equality(lines[2].type, "delete")
  MiniTest.expect.equality(lines[2].old_line, 2)
  MiniTest.expect.equality(lines[2].new_line, nil)

  -- added1: old=nil, new=2
  MiniTest.expect.equality(lines[3].type, "add")
  MiniTest.expect.equality(lines[3].old_line, nil)
  MiniTest.expect.equality(lines[3].new_line, 2)

  -- added2: old=nil, new=3
  MiniTest.expect.equality(lines[4].type, "add")
  MiniTest.expect.equality(lines[4].old_line, nil)
  MiniTest.expect.equality(lines[4].new_line, 3)

  -- context2: old=3, new=4
  MiniTest.expect.equality(lines[5].type, "context")
  MiniTest.expect.equality(lines[5].old_line, 3)
  MiniTest.expect.equality(lines[5].new_line, 4)

  -- context3: old=4, new=5
  MiniTest.expect.equality(lines[6].type, "context")
  MiniTest.expect.equality(lines[6].old_line, 4)
  MiniTest.expect.equality(lines[6].new_line, 5)
end

T["parse"]["handles new files"] = function()
  local diff = [[
diff --git a/new_file.ts b/new_file.ts
new file mode 100644
index 0000000..1234567
--- /dev/null
+++ b/new_file.ts
@@ -0,0 +1,3 @@
+export const foo = "bar";
+export const baz = 42;
+export default foo;
]]
  local files = parser.parse(diff)

  MiniTest.expect.equality(files[1].status, "added")
  MiniTest.expect.equality(files[1].path, "new_file.ts")
  MiniTest.expect.equality(files[1].additions, 3)
  MiniTest.expect.equality(files[1].deletions, 0)
end

T["parse"]["handles deleted files"] = function()
  local diff = [[
diff --git a/deleted.ts b/deleted.ts
deleted file mode 100644
index 1234567..0000000
--- a/deleted.ts
+++ /dev/null
@@ -1,3 +0,0 @@
-export const foo = "bar";
-export const baz = 42;
-export default foo;
]]
  local files = parser.parse(diff)

  MiniTest.expect.equality(files[1].status, "deleted")
  MiniTest.expect.equality(files[1].additions, 0)
  MiniTest.expect.equality(files[1].deletions, 3)
end

T["parse"]["handles renamed files"] = function()
  local diff = [[
diff --git a/old_name.ts b/new_name.ts
similarity index 95%
rename from old_name.ts
rename to new_name.ts
index 1234567..abcdefg 100644
--- a/old_name.ts
+++ b/new_name.ts
@@ -1,3 +1,3 @@
 export const foo = "bar";
-export const baz = 42;
+export const baz = 43;
 export default foo;
]]
  local files = parser.parse(diff)

  MiniTest.expect.equality(files[1].status, "renamed")
  MiniTest.expect.equality(files[1].path, "new_name.ts")
  MiniTest.expect.equality(files[1].old_path, "old_name.ts")
end

T["parse"]["counts additions and deletions"] = function()
  local diff = [[
diff --git a/test.ts b/test.ts
index 1234567..abcdefg 100644
--- a/test.ts
+++ b/test.ts
@@ -1,5 +1,6 @@
 context
-deleted1
-deleted2
+added1
+added2
+added3
 context
 context
]]
  local files = parser.parse(diff)

  MiniTest.expect.equality(files[1].additions, 3)
  MiniTest.expect.equality(files[1].deletions, 2)
end

T["parse"]["preserves line content without prefix"] = function()
  local diff = [[
diff --git a/test.ts b/test.ts
index 1234567..abcdefg 100644
--- a/test.ts
+++ b/test.ts
@@ -1,2 +1,2 @@
-const x = 1;
+const x = 2;
 const y = 3;
]]
  local files = parser.parse(diff)
  local lines = files[1].hunks[1].lines

  MiniTest.expect.equality(lines[1].content, "const x = 1;")
  MiniTest.expect.equality(lines[2].content, "const x = 2;")
  MiniTest.expect.equality(lines[3].content, "const y = 3;")
end

T["parse"]["handles files with spaces in path"] = function()
  local diff = [[
diff --git a/path with spaces/file.ts b/path with spaces/file.ts
index 1234567..abcdefg 100644
--- a/path with spaces/file.ts
+++ b/path with spaces/file.ts
@@ -1,1 +1,1 @@
-old
+new
]]
  local files = parser.parse(diff)

  MiniTest.expect.equality(files[1].path, "path with spaces/file.ts")
end

T["parse"]["ignores no newline at end of file marker"] = function()
  local diff = [[
diff --git a/test.ts b/test.ts
index 1234567..abcdefg 100644
--- a/test.ts
+++ b/test.ts
@@ -1,1 +1,1 @@
-old
\ No newline at end of file
+new
\ No newline at end of file
]]
  local files = parser.parse(diff)
  local lines = files[1].hunks[1].lines

  -- Should have exactly 2 lines (delete and add), not the "no newline" markers
  MiniTest.expect.equality(#lines, 2)
  MiniTest.expect.equality(lines[1].type, "delete")
  MiniTest.expect.equality(lines[2].type, "add")
end

-- =============================================================================
-- parse_hunk() tests
-- =============================================================================

T["parse_hunk"] = MiniTest.new_set()

T["parse_hunk"]["returns nil for empty input"] = function()
  MiniTest.expect.equality(parser.parse_hunk(""), nil)
  MiniTest.expect.equality(parser.parse_hunk(nil), nil)
end

T["parse_hunk"]["parses hunk header"] = function()
  local hunk_text = [[
@@ -10,5 +12,7 @@ function test()
 context
+added
-deleted
 context
]]
  local hunk = parser.parse_hunk(hunk_text)

  MiniTest.expect.equality(hunk.old_start, 10)
  MiniTest.expect.equality(hunk.old_count, 5)
  MiniTest.expect.equality(hunk.new_start, 12)
  MiniTest.expect.equality(hunk.new_count, 7)
end

T["parse_hunk"]["parses lines correctly"] = function()
  local hunk_text = [[
@@ -1,3 +1,4 @@
 context
-deleted
+added1
+added2
 context
]]
  local hunk = parser.parse_hunk(hunk_text)

  MiniTest.expect.equality(#hunk.lines, 5)
  MiniTest.expect.equality(hunk.lines[1].type, "context")
  MiniTest.expect.equality(hunk.lines[2].type, "delete")
  MiniTest.expect.equality(hunk.lines[3].type, "add")
  MiniTest.expect.equality(hunk.lines[4].type, "add")
  MiniTest.expect.equality(hunk.lines[5].type, "context")
end

T["parse_hunk"]["returns nil for invalid header"] = function()
  local hunk = parser.parse_hunk("not a hunk header")
  MiniTest.expect.equality(hunk, nil)
end

-- =============================================================================
-- find_hunk_for_line() tests
-- =============================================================================

T["find_hunk_for_line"] = MiniTest.new_set()

T["find_hunk_for_line"]["finds correct hunk"] = function()
  local hunks = {
    { new_start = 1, new_count = 5 },
    { new_start = 10, new_count = 8 },
    { new_start = 25, new_count = 3 },
  }

  local hunk, idx = parser.find_hunk_for_line(hunks, 3)
  MiniTest.expect.equality(idx, 1)

  hunk, idx = parser.find_hunk_for_line(hunks, 12)
  MiniTest.expect.equality(idx, 2)

  hunk, idx = parser.find_hunk_for_line(hunks, 27)
  MiniTest.expect.equality(idx, 3)
end

T["find_hunk_for_line"]["returns nil for line outside hunks"] = function()
  local hunks = {
    { new_start = 1, new_count = 5 },
    { new_start = 10, new_count = 8 },
  }

  local hunk, idx = parser.find_hunk_for_line(hunks, 7)
  MiniTest.expect.equality(hunk, nil)
  MiniTest.expect.equality(idx, nil)
end

T["find_hunk_for_line"]["handles empty hunks list"] = function()
  local hunk, idx = parser.find_hunk_for_line({}, 5)
  MiniTest.expect.equality(hunk, nil)
  MiniTest.expect.equality(idx, nil)
end

-- =============================================================================
-- new_to_old_line() tests
-- =============================================================================

T["new_to_old_line"] = MiniTest.new_set()

T["new_to_old_line"]["converts context line"] = function()
  local diff = [[
diff --git a/test.ts b/test.ts
index 1234567..abcdefg 100644
--- a/test.ts
+++ b/test.ts
@@ -1,3 +1,4 @@
 context1
+added
 context2
 context3
]]
  local files = parser.parse(diff)
  local hunk = files[1].hunks[1]

  -- context1 at new_line=1 should be old_line=1
  MiniTest.expect.equality(parser.new_to_old_line(hunk, 1), 1)
  -- context2 at new_line=3 should be old_line=2
  MiniTest.expect.equality(parser.new_to_old_line(hunk, 3), 2)
end

T["new_to_old_line"]["returns nil for added line"] = function()
  local diff = [[
diff --git a/test.ts b/test.ts
index 1234567..abcdefg 100644
--- a/test.ts
+++ b/test.ts
@@ -1,2 +1,3 @@
 context1
+added
 context2
]]
  local files = parser.parse(diff)
  local hunk = files[1].hunks[1]

  -- added at new_line=2 has no old equivalent
  MiniTest.expect.equality(parser.new_to_old_line(hunk, 2), nil)
end

-- =============================================================================
-- old_to_new_line() tests
-- =============================================================================

T["old_to_new_line"] = MiniTest.new_set()

T["old_to_new_line"]["converts context line"] = function()
  local diff = [[
diff --git a/test.ts b/test.ts
index 1234567..abcdefg 100644
--- a/test.ts
+++ b/test.ts
@@ -1,3 +1,4 @@
 context1
+added
 context2
 context3
]]
  local files = parser.parse(diff)
  local hunk = files[1].hunks[1]

  -- context1 at old_line=1 should be new_line=1
  MiniTest.expect.equality(parser.old_to_new_line(hunk, 1), 1)
  -- context2 at old_line=2 should be new_line=3
  MiniTest.expect.equality(parser.old_to_new_line(hunk, 2), 3)
end

T["old_to_new_line"]["returns nil for deleted line"] = function()
  local diff = [[
diff --git a/test.ts b/test.ts
index 1234567..abcdefg 100644
--- a/test.ts
+++ b/test.ts
@@ -1,3 +1,2 @@
 context1
-deleted
 context2
]]
  local files = parser.parse(diff)
  local hunk = files[1].hunks[1]

  -- deleted at old_line=2 has no new equivalent
  MiniTest.expect.equality(parser.old_to_new_line(hunk, 2), nil)
end

-- =============================================================================
-- get_line_side() tests
-- =============================================================================

T["get_line_side"] = MiniTest.new_set()

T["get_line_side"]["returns RIGHT for added lines"] = function()
  local diff = [[
diff --git a/test.ts b/test.ts
index 1234567..abcdefg 100644
--- a/test.ts
+++ b/test.ts
@@ -1,1 +1,2 @@
 context
+added
]]
  local files = parser.parse(diff)
  local hunk = files[1].hunks[1]

  MiniTest.expect.equality(parser.get_line_side(hunk, 2), "RIGHT")
end

T["get_line_side"]["returns RIGHT for context lines"] = function()
  local diff = [[
diff --git a/test.ts b/test.ts
index 1234567..abcdefg 100644
--- a/test.ts
+++ b/test.ts
@@ -1,1 +1,1 @@
 context
]]
  local files = parser.parse(diff)
  local hunk = files[1].hunks[1]

  MiniTest.expect.equality(parser.get_line_side(hunk, 1), "RIGHT")
end

-- =============================================================================
-- get_total_stats() tests
-- =============================================================================

T["get_total_stats"] = MiniTest.new_set()

T["get_total_stats"]["sums stats across files"] = function()
  local files = {
    { additions = 10, deletions = 5 },
    { additions = 20, deletions = 8 },
    { additions = 5, deletions = 2 },
  }

  local stats = parser.get_total_stats(files)

  MiniTest.expect.equality(stats.additions, 35)
  MiniTest.expect.equality(stats.deletions, 15)
end

T["get_total_stats"]["handles empty files list"] = function()
  local stats = parser.get_total_stats({})

  MiniTest.expect.equality(stats.additions, 0)
  MiniTest.expect.equality(stats.deletions, 0)
end

-- =============================================================================
-- Integration with mock_diff
-- =============================================================================

T["integration"] = MiniTest.new_set()

T["integration"]["parses mock_diff correctly"] = function()
  local diff = _G.H.mock_diff()
  local files = parser.parse(diff)

  -- Verify file
  MiniTest.expect.equality(#files, 1)
  MiniTest.expect.equality(files[1].path, "src/route.ts")
  MiniTest.expect.equality(files[1].status, "modified")

  -- Verify hunks
  MiniTest.expect.equality(#files[1].hunks, 2)

  -- First hunk
  local h1 = files[1].hunks[1]
  MiniTest.expect.equality(h1.old_start, 1)
  MiniTest.expect.equality(h1.old_count, 5)
  MiniTest.expect.equality(h1.new_start, 1)
  MiniTest.expect.equality(h1.new_count, 7)

  -- Second hunk
  local h2 = files[1].hunks[2]
  MiniTest.expect.equality(h2.old_start, 10)
  MiniTest.expect.equality(h2.old_count, 7)
  MiniTest.expect.equality(h2.new_start, 12)
  MiniTest.expect.equality(h2.new_count, 15)
end

return T
