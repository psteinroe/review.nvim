-- Shared test utilities for review.nvim
local H = {}

local MiniTest = require("mini.test")

-- Create child Neovim process for isolation
H.new_child = function()
  local child = MiniTest.new_child_neovim()
  child.setup()
  child.lua([[
    -- Load plugin
    vim.opt.rtp:prepend(".")
    require("review").setup()
  ]])
  return child
end

-- Create temporary git repo for testing
H.create_test_repo = function()
  local tmp_dir = vim.fn.tempname()
  vim.fn.mkdir(tmp_dir, "p")

  -- Initialize git repo
  vim.fn.system({ "git", "init", tmp_dir })
  vim.fn.system({ "git", "-C", tmp_dir, "config", "user.email", "test@test.com" })
  vim.fn.system({ "git", "-C", tmp_dir, "config", "user.name", "Test User" })

  -- Create initial commit
  local file = tmp_dir .. "/test.lua"
  vim.fn.writefile({ "local M = {}", "return M" }, file)
  vim.fn.system({ "git", "-C", tmp_dir, "add", "." })
  vim.fn.system({ "git", "-C", tmp_dir, "commit", "-m", "Initial commit" })

  return tmp_dir
end

-- Clean up test repo
H.cleanup_repo = function(dir)
  vim.fn.delete(dir, "rf")
end

-- Create mock diff output
H.mock_diff = function()
  return [[
diff --git a/src/route.ts b/src/route.ts
index 1234567..abcdefg 100644
--- a/src/route.ts
+++ b/src/route.ts
@@ -1,5 +1,7 @@
 import { NextResponse } from "next/server";
 import { getTheme } from "@/actions/themes";
+import { getBuiltInThemeStyles } from "@/utils/theme-preset-helper";
+import { ThemeStyles } from "@/types/theme";

 export const dynamic = "force-static";

@@ -10,7 +12,15 @@ export async function GET(_req: Request, { params }: { params: Promise<
   const { id } = await params;

   try {
-    const theme = await getTheme(id);
+    let themeName: string;
+    let themeStyles: ThemeStyles;
+
+    const builtInTheme = getBuiltInThemeStyles(id.replace(/\.json$/, ""));
+    if (builtInTheme) {
+      themeName = builtInTheme.name;
+      themeStyles = builtInTheme.styles;
+    }
]]
end

-- Create mock PR response
H.mock_pr = function()
  return {
    number = 142,
    title = "Add theme support",
    description = "This PR adds theme support",
    author = "testuser",
    branch = "feature/themes",
    base = "main",
    created_at = "2024-01-15T10:00:00Z",
    updated_at = "2024-01-15T12:00:00Z",
    additions = 142,
    deletions = 38,
    changed_files = 3,
    state = "open",
    url = "https://github.com/test/repo/pull/142",
  }
end

-- Create mock comments
H.mock_comments = function()
  return {
    {
      id = "gh_conv_1",
      kind = "conversation",
      body = "Looks good overall!",
      author = "reviewer",
      created_at = "2024-01-15T11:00:00Z",
    },
    {
      id = "gh_review_1",
      kind = "review",
      body = "Missing error handling",
      author = "reviewer",
      created_at = "2024-01-15T11:30:00Z",
      file = "src/route.ts",
      line = 15,
      resolved = false,
      replies = {},
    },
  }
end

-- Assert helpers
H.expect = MiniTest.expect

H.expect_lines = function(buf, expected)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  H.expect.equality(lines, expected)
end

H.expect_contains = function(str, substr)
  local found = str:find(substr, 1, true) ~= nil
  if not found then
    error(string.format("Expected %q to contain %q", str, substr))
  end
end

H.expect_sign_at = function(buf, line, sign_name)
  local signs = vim.fn.sign_getplaced(buf, { lnum = line, group = "review" })
  local found = false
  for _, placement in ipairs(signs[1].signs or {}) do
    if placement.name == sign_name then
      found = true
      break
    end
  end
  if not found then
    error(string.format("Expected sign %q at line %d", sign_name, line))
  end
end

return H
