-- Integration tests for AI prompt generation
-- Tests the complete workflow of building AI prompts from review state
--
-- These tests verify that the AI module correctly:
-- 1. Builds prompts from local review state
-- 2. Builds prompts from PR review state with GitHub comments
-- 3. Includes appropriate sections based on options
-- 4. Handles edge cases and complex scenarios

local MiniTest = require("mini.test")
local expect = MiniTest.expect

local T = MiniTest.new_set()

-- Setup mocks before tests
local mock_git = require("mocks.git")
local mock_github = require("mocks.github")

-- Sample PR data matching what we'd get from GitHub
local SAMPLE_PR = {
  number = 142,
  title = "Add theme support for custom styles",
  description = "This PR adds support for custom themes by:\n- Adding a theme registry lookup\n- Supporting built-in and user-saved themes\n\nFixes #98",
  author = "colleague",
  branch = "feature/themes",
  base = "main",
  created_at = "2024-01-15T10:00:00Z",
  updated_at = "2024-01-15T14:00:00Z",
  additions = 142,
  deletions = 38,
  changed_files = 3,
  state = "open",
  url = "https://github.com/owner/repo/pull/142",
}

-- Sample diff for testing
local SAMPLE_DIFF = [[
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

-- ============================================================================
-- Setup and Teardown
-- ============================================================================
T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Reset all modules
      package.loaded["review.integrations.ai"] = nil
      package.loaded["review.integrations.git"] = nil
      package.loaded["review.integrations.github"] = nil
      package.loaded["review.config"] = nil
      package.loaded["review.core.state"] = nil

      -- Setup config
      local config = require("review.config")
      config.setup()

      -- Reset state
      local state = require("review.core.state")
      state.reset()

      -- Reset mocks
      mock_git.reset()
      mock_github.reset()
    end,
    post_case = function()
      -- Clean up
      mock_git.restore()
      mock_github.restore()
    end,
  },
})

-- ============================================================================
-- Local Review Workflow Tests
-- ============================================================================
T["local_review"] = MiniTest.new_set()

T["local_review"]["builds prompt for local review with diff"] = function()
  -- Setup mock git diff
  mock_git.setup({ diff_output = SAMPLE_DIFF })
  mock_git.install()

  local state = require("review.core.state")
  state.state.mode = "local"
  state.state.base = "HEAD~1"
  state.state.files = {
    { path = "src/route.ts", status = "modified", additions = 10, deletions = 2, hunks = {} },
  }

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt()

  -- Verify structure
  expect.equality(prompt:find("# Code Review") ~= nil, true)
  expect.equality(prompt:find("## Changes") ~= nil, true)
  expect.equality(prompt:find("```diff") ~= nil, true)
  expect.equality(prompt:find("## Instructions") ~= nil, true)

  mock_git.restore()
end

T["local_review"]["includes pending comments in prompt"] = function()
  mock_git.setup({ diff_output = SAMPLE_DIFF })
  mock_git.install()

  local state = require("review.core.state")
  state.state.mode = "local"
  state.state.base = "HEAD~1"

  -- Add local comments
  state.add_comment({
    id = "local_1",
    kind = "local",
    body = "Missing error handling for getBuiltInThemeStyles",
    author = "you",
    created_at = "2024-01-15T15:00:00Z",
    file = "src/route.ts",
    line = 15,
    type = "issue",
    status = "pending",
  })
  state.add_comment({
    id = "local_2",
    kind = "local",
    body = "Consider memoizing theme lookup",
    author = "you",
    created_at = "2024-01-15T15:05:00Z",
    file = "src/route.ts",
    line = 20,
    type = "suggestion",
    status = "pending",
  })

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt()

  -- Verify comments section
  expect.equality(prompt:find("## Review Comments") ~= nil, true)
  expect.equality(prompt:find("Missing error handling") ~= nil, true)
  expect.equality(prompt:find("Consider memoizing") ~= nil, true)
  expect.equality(prompt:find("%[ISSUE%]") ~= nil, true)
  expect.equality(prompt:find("%[SUGGESTION%]") ~= nil, true)

  mock_git.restore()
end

T["local_review"]["excludes submitted comments from prompt"] = function()
  mock_git.setup({ diff_output = SAMPLE_DIFF })
  mock_git.install()

  local state = require("review.core.state")
  state.state.mode = "local"

  -- Add submitted comment (should be excluded)
  state.add_comment({
    id = "submitted_1",
    kind = "local",
    body = "This was already submitted",
    author = "you",
    created_at = "2024-01-15T14:00:00Z",
    file = "src/route.ts",
    line = 10,
    type = "note",
    status = "submitted",
  })

  -- Add pending comment (should be included)
  state.add_comment({
    id = "pending_1",
    kind = "local",
    body = "This is still pending",
    author = "you",
    created_at = "2024-01-15T15:00:00Z",
    file = "src/route.ts",
    line = 15,
    type = "note",
    status = "pending",
  })

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt()

  expect.equality(prompt:find("This was already submitted"), nil)
  expect.equality(prompt:find("This is still pending") ~= nil, true)

  mock_git.restore()
end

T["local_review"]["handles empty state gracefully"] = function()
  mock_git.setup({ diff_output = "" })
  mock_git.install()

  local state = require("review.core.state")
  state.state.mode = "local"
  state.state.base = "HEAD"

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt()

  -- Should still produce valid prompt structure
  expect.equality(prompt:find("# Code Review") ~= nil, true)
  expect.equality(prompt:find("## Instructions") ~= nil, true)

  mock_git.restore()
end

-- ============================================================================
-- PR Review Workflow Tests
-- ============================================================================
T["pr_review"] = MiniTest.new_set()

T["pr_review"]["builds prompt with PR information"] = function()
  mock_github.setup({
    prs = { [142] = SAMPLE_PR },
    pr_diffs = { [142] = SAMPLE_DIFF },
  })
  mock_github.install()

  local state = require("review.core.state")
  state.state.mode = "pr"
  state.state.pr = SAMPLE_PR
  state.state.base = "main"

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  -- Verify PR info section
  expect.equality(prompt:find("## PR Information") ~= nil, true)
  expect.equality(prompt:find("PR #142") ~= nil, true)
  expect.equality(prompt:find("Add theme support") ~= nil, true)
  expect.equality(prompt:find("@colleague") ~= nil, true)
  expect.equality(prompt:find("feature/themes") ~= nil, true)
  expect.equality(prompt:find("-> main") ~= nil, true)

  mock_github.restore()
end

T["pr_review"]["includes PR description"] = function()
  mock_github.setup({
    prs = { [142] = SAMPLE_PR },
    pr_diffs = { [142] = SAMPLE_DIFF },
  })
  mock_github.install()

  local state = require("review.core.state")
  state.state.mode = "pr"
  state.state.pr = SAMPLE_PR

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  expect.equality(prompt:find("### Description") ~= nil, true)
  expect.equality(prompt:find("Adding a theme registry lookup") ~= nil, true)
  expect.equality(prompt:find("Fixes #98") ~= nil, true)

  mock_github.restore()
end

T["pr_review"]["includes PR diff from GitHub"] = function()
  mock_github.setup({
    prs = { [142] = SAMPLE_PR },
    pr_diffs = { [142] = SAMPLE_DIFF },
  })
  mock_github.install()

  local state = require("review.core.state")
  state.state.mode = "pr"
  state.state.pr = SAMPLE_PR

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = true })

  expect.equality(prompt:find("## Changes") ~= nil, true)
  expect.equality(prompt:find("```diff") ~= nil, true)
  -- The diff content should be present
  expect.equality(prompt:find("getBuiltInThemeStyles") ~= nil, true)

  mock_github.restore()
end

T["pr_review"]["combines local comments with PR context"] = function()
  mock_github.setup({
    prs = { [142] = SAMPLE_PR },
    pr_diffs = { [142] = SAMPLE_DIFF },
  })
  mock_github.install()

  local state = require("review.core.state")
  state.state.mode = "pr"
  state.state.pr = SAMPLE_PR

  -- Add local pending comments
  state.add_comment({
    id = "local_1",
    kind = "local",
    body = "Add try-catch block here",
    author = "you",
    created_at = "2024-01-15T16:00:00Z",
    file = "src/route.ts",
    line = 15,
    type = "issue",
    status = "pending",
  })
  state.add_comment({
    id = "local_2",
    kind = "local",
    body = "Nice refactor!",
    author = "you",
    created_at = "2024-01-15T16:05:00Z",
    file = "src/route.ts",
    line = 8,
    type = "praise",
    status = "pending",
  })

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  -- Should have both PR info and comments
  expect.equality(prompt:find("## PR Information") ~= nil, true)
  expect.equality(prompt:find("## Review Comments") ~= nil, true)
  expect.equality(prompt:find("Add try%-catch block") ~= nil, true)
  expect.equality(prompt:find("Nice refactor") ~= nil, true)
  expect.equality(prompt:find("%[ISSUE%]") ~= nil, true)
  expect.equality(prompt:find("%[PRAISE%]") ~= nil, true)

  mock_github.restore()
end

-- ============================================================================
-- Prompt Options Tests
-- ============================================================================
T["options"] = MiniTest.new_set()

T["options"]["excludes diff when include_diff is false"] = function()
  mock_git.setup({ diff_output = SAMPLE_DIFF })
  mock_git.install()

  local state = require("review.core.state")
  state.state.mode = "local"
  state.state.base = "HEAD"

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  expect.equality(prompt:find("## Changes"), nil)
  expect.equality(prompt:find("```diff"), nil)

  mock_git.restore()
end

T["options"]["excludes instructions when include_instructions is false"] = function()
  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_instructions = false })

  expect.equality(prompt:find("## Instructions"), nil)
end

T["options"]["excludes comments when include_comments is false"] = function()
  local state = require("review.core.state")
  state.add_comment({
    id = "test_1",
    kind = "local",
    body = "Should not appear",
    author = "you",
    created_at = "2024-01-15T16:00:00Z",
    type = "note",
    status = "pending",
  })

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_comments = false })

  expect.equality(prompt:find("## Review Comments"), nil)
  expect.equality(prompt:find("Should not appear"), nil)
end

T["options"]["can exclude all optional sections"] = function()
  mock_git.setup({ diff_output = SAMPLE_DIFF })
  mock_git.install()

  local state = require("review.core.state")
  state.state.mode = "local"
  state.add_comment({
    id = "test_1",
    kind = "local",
    body = "A comment",
    author = "you",
    created_at = "2024-01-15T16:00:00Z",
    type = "note",
    status = "pending",
  })

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({
    include_diff = false,
    include_comments = false,
    include_instructions = false,
  })

  -- Only the header should remain
  expect.equality(prompt:find("# Code Review") ~= nil, true)
  expect.equality(prompt:find("## Changes"), nil)
  expect.equality(prompt:find("## Review Comments"), nil)
  expect.equality(prompt:find("## Instructions"), nil)

  mock_git.restore()
end

-- ============================================================================
-- Custom Instructions Tests
-- ============================================================================
T["custom_instructions"] = MiniTest.new_set()

T["custom_instructions"]["uses custom instructions when configured"] = function()
  local config = require("review.config")
  config.setup({
    ai = {
      instructions = "Focus on security vulnerabilities and performance issues.",
    },
  })

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  expect.equality(prompt:find("Focus on security vulnerabilities") ~= nil, true)
  expect.equality(prompt:find("performance issues") ~= nil, true)
end

T["custom_instructions"]["multiline custom instructions work"] = function()
  local config = require("review.config")
  config.setup({
    ai = {
      instructions = [[Please review this code:
1. Check for bugs
2. Suggest improvements
3. Verify error handling]],
    },
  })

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  expect.equality(prompt:find("Check for bugs") ~= nil, true)
  expect.equality(prompt:find("Suggest improvements") ~= nil, true)
  expect.equality(prompt:find("Verify error handling") ~= nil, true)
end

-- ============================================================================
-- Comment Type Labels Tests
-- ============================================================================
T["comment_labels"] = MiniTest.new_set()

T["comment_labels"]["formats note type correctly"] = function()
  local state = require("review.core.state")
  state.add_comment({
    id = "note_1",
    kind = "local",
    body = "Just a note",
    author = "you",
    created_at = "2024-01-15T16:00:00Z",
    file = "test.lua",
    line = 10,
    type = "note",
    status = "pending",
  })

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  expect.equality(prompt:find("%[NOTE%]") ~= nil, true)
end

T["comment_labels"]["formats issue type correctly"] = function()
  local state = require("review.core.state")
  state.add_comment({
    id = "issue_1",
    kind = "local",
    body = "This is a bug",
    author = "you",
    created_at = "2024-01-15T16:00:00Z",
    file = "test.lua",
    line = 10,
    type = "issue",
    status = "pending",
  })

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  expect.equality(prompt:find("%[ISSUE%]") ~= nil, true)
end

T["comment_labels"]["formats suggestion type correctly"] = function()
  local state = require("review.core.state")
  state.add_comment({
    id = "suggestion_1",
    kind = "local",
    body = "Consider using async",
    author = "you",
    created_at = "2024-01-15T16:00:00Z",
    file = "test.lua",
    line = 10,
    type = "suggestion",
    status = "pending",
  })

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  expect.equality(prompt:find("%[SUGGESTION%]") ~= nil, true)
end

T["comment_labels"]["formats praise type correctly"] = function()
  local state = require("review.core.state")
  state.add_comment({
    id = "praise_1",
    kind = "local",
    body = "Great work here",
    author = "you",
    created_at = "2024-01-15T16:00:00Z",
    file = "test.lua",
    line = 10,
    type = "praise",
    status = "pending",
  })

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  expect.equality(prompt:find("%[PRAISE%]") ~= nil, true)
end

-- ============================================================================
-- File Location in Comments Tests
-- ============================================================================
T["file_location"] = MiniTest.new_set()

T["file_location"]["includes file path and line in comment"] = function()
  local state = require("review.core.state")
  state.add_comment({
    id = "loc_1",
    kind = "local",
    body = "Fix this",
    author = "you",
    created_at = "2024-01-15T16:00:00Z",
    file = "src/utils/helper.ts",
    line = 42,
    type = "issue",
    status = "pending",
  })

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  expect.equality(prompt:find("`src/utils/helper.ts:42`") ~= nil, true)
end

T["file_location"]["handles comment without file gracefully"] = function()
  local state = require("review.core.state")
  state.add_comment({
    id = "no_file_1",
    kind = "local",
    body = "General observation",
    author = "you",
    created_at = "2024-01-15T16:00:00Z",
    type = "note",
    status = "pending",
  })

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  -- Should not crash and should include the comment body
  expect.equality(prompt:find("General observation") ~= nil, true)
end

T["file_location"]["handles comment with file but no line"] = function()
  local state = require("review.core.state")
  state.add_comment({
    id = "no_line_1",
    kind = "local",
    body = "File-level comment",
    author = "you",
    created_at = "2024-01-15T16:00:00Z",
    file = "README.md",
    type = "note",
    status = "pending",
  })

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  -- Should show file with line 0
  expect.equality(prompt:find("`README%.md:0`") ~= nil, true)
  expect.equality(prompt:find("File%-level comment") ~= nil, true)
end

-- ============================================================================
-- Multiple Comments Ordering Tests
-- ============================================================================
T["comment_ordering"] = MiniTest.new_set()

T["comment_ordering"]["numbers comments sequentially"] = function()
  local state = require("review.core.state")

  -- Add comments in specific order
  state.add_comment({
    id = "first",
    kind = "local",
    body = "First comment",
    author = "you",
    created_at = "2024-01-15T16:00:00Z",
    file = "a.lua",
    line = 1,
    type = "note",
    status = "pending",
  })
  state.add_comment({
    id = "second",
    kind = "local",
    body = "Second comment",
    author = "you",
    created_at = "2024-01-15T16:01:00Z",
    file = "b.lua",
    line = 1,
    type = "note",
    status = "pending",
  })
  state.add_comment({
    id = "third",
    kind = "local",
    body = "Third comment",
    author = "you",
    created_at = "2024-01-15T16:02:00Z",
    file = "c.lua",
    line = 1,
    type = "note",
    status = "pending",
  })

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  -- Verify numbering pattern
  expect.equality(prompt:find("1%. %*%*%[NOTE%]%*%*") ~= nil, true)
  expect.equality(prompt:find("2%. %*%*%[NOTE%]%*%*") ~= nil, true)
  expect.equality(prompt:find("3%. %*%*%[NOTE%]%*%*") ~= nil, true)
end

-- ============================================================================
-- Clipboard Export Tests
-- ============================================================================
T["clipboard"] = MiniTest.new_set()

T["clipboard"]["send_to_clipboard copies full prompt"] = function()
  -- Clear registers
  vim.fn.setreg("+", "")
  vim.fn.setreg("*", "")

  local state = require("review.core.state")
  state.state.mode = "local"
  state.add_comment({
    id = "clip_1",
    kind = "local",
    body = "Clipboard test comment",
    author = "you",
    created_at = "2024-01-15T16:00:00Z",
    type = "note",
    status = "pending",
  })

  local ai = require("review.integrations.ai")
  ai.send_to_clipboard()

  local plus_content = vim.fn.getreg("+")
  local star_content = vim.fn.getreg("*")

  expect.equality(plus_content:find("# Code Review") ~= nil, true)
  expect.equality(plus_content:find("Clipboard test comment") ~= nil, true)
  expect.equality(star_content:find("# Code Review") ~= nil, true)
end

T["clipboard"]["clipboard provider works same as send_to_clipboard"] = function()
  vim.fn.setreg("+", "")

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt()

  ai.providers.clipboard.send(prompt, {})

  expect.equality(vim.fn.getreg("+"), prompt)
end

-- ============================================================================
-- Edge Cases Tests
-- ============================================================================
T["edge_cases"] = MiniTest.new_set()

T["edge_cases"]["handles PR without description"] = function()
  local pr_no_desc = vim.deepcopy(SAMPLE_PR)
  pr_no_desc.description = ""

  mock_github.setup({
    prs = { [142] = pr_no_desc },
    pr_diffs = { [142] = SAMPLE_DIFF },
  })
  mock_github.install()

  local state = require("review.core.state")
  state.state.mode = "pr"
  state.state.pr = pr_no_desc

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  -- Should not have description section
  expect.equality(prompt:find("### Description"), nil)

  mock_github.restore()
end

T["edge_cases"]["handles nil PR description"] = function()
  local pr_nil_desc = vim.deepcopy(SAMPLE_PR)
  pr_nil_desc.description = nil

  mock_github.setup({
    prs = { [142] = pr_nil_desc },
    pr_diffs = { [142] = SAMPLE_DIFF },
  })
  mock_github.install()

  local state = require("review.core.state")
  state.state.mode = "pr"
  state.state.pr = pr_nil_desc

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  -- Should not crash and should not have description section
  expect.equality(prompt:find("### Description"), nil)

  mock_github.restore()
end

T["edge_cases"]["handles special characters in comment body"] = function()
  local state = require("review.core.state")
  state.add_comment({
    id = "special_1",
    kind = "local",
    body = "Handle <script> tags & escape \"quotes\" properly",
    author = "you",
    created_at = "2024-01-15T16:00:00Z",
    type = "issue",
    status = "pending",
  })

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  -- Should include the full text
  expect.equality(prompt:find("<script>") ~= nil, true)
  expect.equality(prompt:find("&") ~= nil, true)
end

T["edge_cases"]["handles very long comment body"] = function()
  local state = require("review.core.state")
  local long_body = string.rep("This is a very long comment. ", 100)

  state.add_comment({
    id = "long_1",
    kind = "local",
    body = long_body,
    author = "you",
    created_at = "2024-01-15T16:00:00Z",
    type = "note",
    status = "pending",
  })

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  -- Should include the full long body (no truncation in prompt)
  expect.equality(prompt:find("This is a very long comment") ~= nil, true)
end

T["edge_cases"]["handles multiline comment body"] = function()
  local state = require("review.core.state")
  state.add_comment({
    id = "multiline_1",
    kind = "local",
    body = "Line 1\nLine 2\nLine 3",
    author = "you",
    created_at = "2024-01-15T16:00:00Z",
    type = "note",
    status = "pending",
  })

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  expect.equality(prompt:find("Line 1") ~= nil, true)
end

T["edge_cases"]["handles no pending comments"] = function()
  local state = require("review.core.state")
  -- No comments added

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  -- Should not have review comments section when empty
  expect.equality(prompt:find("## Review Comments"), nil)
end

T["edge_cases"]["handles mixed pending and non-pending comments"] = function()
  local state = require("review.core.state")

  -- GitHub comment (not local, should be excluded from AI prompt)
  state.add_comment({
    id = "gh_1",
    kind = "review",
    body = "GitHub comment",
    author = "reviewer",
    created_at = "2024-01-15T14:00:00Z",
    file = "test.lua",
    line = 5,
  })

  -- Local submitted (should be excluded)
  state.add_comment({
    id = "local_submitted",
    kind = "local",
    body = "Already submitted",
    author = "you",
    created_at = "2024-01-15T15:00:00Z",
    type = "note",
    status = "submitted",
  })

  -- Local pending (should be included)
  state.add_comment({
    id = "local_pending",
    kind = "local",
    body = "Still pending",
    author = "you",
    created_at = "2024-01-15T16:00:00Z",
    type = "note",
    status = "pending",
  })

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  expect.equality(prompt:find("GitHub comment"), nil)
  expect.equality(prompt:find("Already submitted"), nil)
  expect.equality(prompt:find("Still pending") ~= nil, true)
end

return T
