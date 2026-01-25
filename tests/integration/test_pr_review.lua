-- Integration tests for PR review workflow
-- Tests the flow: PR data, comments fetching, filtering, state management
--
-- NOTE: These tests mock both git and github modules to test PR review
-- functionality without requiring actual GitHub API calls.

local MiniTest = require("mini.test")
local expect = MiniTest.expect

local T = MiniTest.new_set()

-- Setup mocks before tests
local mock_git = require("mocks.git")
local mock_github = require("mocks.github")

-- Sample PR data
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
  review_decision = nil,
  url = "https://github.com/owner/repo/pull/142",
}

-- Sample PR diff
local SAMPLE_PR_DIFF = [[
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
diff --git a/src/utils/theme-helper.ts b/src/utils/theme-helper.ts
new file mode 100644
index 0000000..1234567
--- /dev/null
+++ b/src/utils/theme-helper.ts
@@ -0,0 +1,10 @@
+export function getBuiltInThemeStyles(id: string) {
+  const themes = {
+    dark: { name: "Dark", styles: { bg: "#000" } },
+    light: { name: "Light", styles: { bg: "#fff" } },
+  };
+  return themes[id];
+}
diff --git a/src/types/theme.ts b/src/types/theme.ts
new file mode 100644
index 0000000..abcdefg
--- /dev/null
+++ b/src/types/theme.ts
@@ -0,0 +1,5 @@
+export interface ThemeStyles {
+  bg: string;
+  fg?: string;
+}
]]

-- Sample GitHub comments
local SAMPLE_CONVERSATION_COMMENTS = {
  {
    id = "gh_conv_1",
    kind = "conversation",
    body = "Looks good overall! Can you add some tests?",
    author = "maintainer",
    created_at = "2024-01-15T11:00:00Z",
    github_id = 1001,
  },
  {
    id = "gh_conv_2",
    kind = "conversation",
    body = "@maintainer Sure, I'll add unit tests for the registry lookup.",
    author = "colleague",
    created_at = "2024-01-15T12:00:00Z",
    github_id = 1002,
  },
}

local SAMPLE_REVIEW_COMMENTS = {
  {
    id = "gh_review_1",
    kind = "review",
    body = "Missing error handling here. What happens if getTheme throws?",
    author = "reviewer",
    created_at = "2024-01-15T13:00:00Z",
    file = "src/route.ts",
    line = 15,
    side = "RIGHT",
    resolved = false,
    github_id = 2001,
    replies = {},
  },
  {
    id = "gh_review_2",
    kind = "review",
    body = "Consider using early return pattern here",
    author = "reviewer",
    created_at = "2024-01-15T13:05:00Z",
    file = "src/route.ts",
    line = 23,
    side = "RIGHT",
    resolved = false,
    github_id = 2002,
    replies = {},
  },
  {
    id = "gh_review_3",
    kind = "review",
    body = "Nice helper function!",
    author = "maintainer",
    created_at = "2024-01-15T13:10:00Z",
    file = "src/utils/theme-helper.ts",
    line = 1,
    side = "RIGHT",
    resolved = true,
    github_id = 2003,
    replies = {},
  },
}

local SAMPLE_REVIEWS = {
  {
    id = "gh_summary_1",
    kind = "review_summary",
    body = "Nice work! A few things to address before merging.",
    author = "reviewer",
    created_at = "2024-01-15T13:30:00Z",
    review_state = "CHANGES_REQUESTED",
    github_id = 3001,
  },
}

-- Helper to reset all modules
local function reset_modules()
  mock_git.reset()
  mock_github.reset()

  -- Clear loaded modules
  package.loaded["review"] = nil
  package.loaded["review.core.state"] = nil
  package.loaded["review.core.comments"] = nil
  package.loaded["review.core.diff_parser"] = nil
  package.loaded["review.config"] = nil
  package.loaded["review.commands"] = nil
  package.loaded["review.ui.layout"] = nil
  package.loaded["review.ui.file_tree"] = nil
  package.loaded["review.ui.diff"] = nil
  package.loaded["review.ui.signs"] = nil
  package.loaded["review.ui.virtual_text"] = nil
  package.loaded["review.ui.highlights"] = nil
  package.loaded["review.keymaps"] = nil
  package.loaded["review.integrations.git"] = nil
  package.loaded["review.integrations.github"] = nil
end

-- Helper to setup plugin with PR mocks
local function setup_plugin_with_pr()
  reset_modules()

  -- Install mocks
  mock_git.install()
  mock_github.install()

  -- Setup git mock with PR diff
  mock_git.setup({
    diff_output = SAMPLE_PR_DIFF,
    changed_files = { "src/route.ts", "src/utils/theme-helper.ts", "src/types/theme.ts" },
    changed_files_status = {
      { path = "src/route.ts", status = "modified" },
      { path = "src/utils/theme-helper.ts", status = "added" },
      { path = "src/types/theme.ts", status = "added" },
    },
    diff_stats = { additions = 142, deletions = 38, files_changed = 3 },
    remote_url = "git@github.com:owner/repo.git",
  })

  -- Setup github mock with PR data
  mock_github.add_pr(SAMPLE_PR)
  mock_github.set_pr_diff(SAMPLE_PR.number, SAMPLE_PR_DIFF)
  mock_github.add_comments(SAMPLE_PR.number, SAMPLE_CONVERSATION_COMMENTS, "conversation")
  mock_github.add_comments(SAMPLE_PR.number, SAMPLE_REVIEW_COMMENTS, "review")
  mock_github.add_comments(SAMPLE_PR.number, SAMPLE_REVIEWS, "review_summary")

  local review = require("review")
  review.setup()

  return review
end

-- Helper to setup state for PR mode manually
local function setup_pr_state()
  local state = require("review.core.state")
  local diff_parser = require("review.core.diff_parser")
  local layout = require("review.ui.layout")

  -- Parse diff
  local files = diff_parser.parse(SAMPLE_PR_DIFF)

  -- Setup PR state
  state.reset()
  state.set_mode("pr", {
    base = SAMPLE_PR.base,
    pr = SAMPLE_PR,
    pr_mode = "remote",
  })
  state.set_files(files)
  state.state.active = true

  -- Open layout
  layout.open()

  -- Set current file
  if #files > 0 then
    state.set_current_file(files[1].path)
  end

  return state
end

-- Helper to cleanup after tests
local function cleanup()
  local state = package.loaded["review.core.state"]
  if state and state.is_active() then
    local layout = require("review.ui.layout")
    pcall(layout.close)
  end

  -- Reset state module explicitly if loaded
  if state then
    pcall(function()
      state.reset()
    end)
  end

  mock_git.restore()
  mock_github.restore()

  -- Close all tabs except the first
  while vim.fn.tabpagenr("$") > 1 do
    vim.cmd("tabclose!")
  end

  -- Clear all loaded review modules to ensure fresh state
  reset_modules()
end

-- =============================================================================
-- Setup/Teardown
-- =============================================================================

T["setup"] = function()
  cleanup()
end

T["teardown"] = function()
  cleanup()
end

-- =============================================================================
-- PR State Management Tests
-- =============================================================================

T["PR state"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      cleanup()
    end,
    post_case = cleanup,
  },
})

T["PR state"]["set_mode with PR sets PR data"] = function()
  setup_plugin_with_pr()
  local state = require("review.core.state")

  state.set_mode("pr", {
    base = "main",
    pr = SAMPLE_PR,
    pr_mode = "remote",
  })

  expect.equality(state.state.mode, "pr")
  expect.equality(state.state.pr ~= nil, true)
  expect.equality(state.state.pr.number, 142)
  expect.equality(state.state.pr.title, "Add theme support for custom styles")
  expect.equality(state.state.pr_mode, "remote")
end

T["PR state"]["PR contains all required fields"] = function()
  setup_plugin_with_pr()
  local state = require("review.core.state")

  state.set_mode("pr", { pr = SAMPLE_PR })

  local pr = state.state.pr
  expect.equality(pr.number, 142)
  expect.equality(pr.title, "Add theme support for custom styles")
  expect.equality(pr.author, "colleague")
  expect.equality(pr.branch, "feature/themes")
  expect.equality(pr.base, "main")
  expect.equality(pr.additions, 142)
  expect.equality(pr.deletions, 38)
  expect.equality(pr.changed_files, 3)
  expect.equality(pr.state, "open")
  expect.equality(type(pr.description), "string")
  expect.equality(type(pr.url), "string")
end

T["PR state"]["reset clears PR data"] = function()
  setup_plugin_with_pr()
  local state = require("review.core.state")

  state.set_mode("pr", { pr = SAMPLE_PR })
  expect.equality(state.state.pr ~= nil, true)

  state.reset()

  expect.equality(state.state.pr, nil)
  expect.equality(state.state.mode, "local")
  expect.equality(state.state.pr_mode, nil)
end

T["PR state"]["pr_mode can be remote or local"] = function()
  setup_plugin_with_pr()
  local state = require("review.core.state")

  state.set_mode("pr", { pr = SAMPLE_PR, pr_mode = "remote" })
  expect.equality(state.state.pr_mode, "remote")

  state.set_mode("pr", { pr = SAMPLE_PR, pr_mode = "local" })
  expect.equality(state.state.pr_mode, "local")
end

-- =============================================================================
-- PR Diff Parsing Tests
-- =============================================================================

T["PR diff"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      cleanup()
    end,
    post_case = cleanup,
  },
})

T["PR diff"]["parses PR diff into files"] = function()
  setup_plugin_with_pr()
  local diff_parser = require("review.core.diff_parser")

  local files = diff_parser.parse(SAMPLE_PR_DIFF)

  expect.equality(#files, 3)
end

T["PR diff"]["identifies modified and added files"] = function()
  setup_plugin_with_pr()
  local diff_parser = require("review.core.diff_parser")

  local files = diff_parser.parse(SAMPLE_PR_DIFF)

  local route_file, helper_file, types_file
  for _, f in ipairs(files) do
    if f.path == "src/route.ts" then
      route_file = f
    elseif f.path == "src/utils/theme-helper.ts" then
      helper_file = f
    elseif f.path == "src/types/theme.ts" then
      types_file = f
    end
  end

  expect.equality(route_file.status, "modified")
  expect.equality(helper_file.status, "added")
  expect.equality(types_file.status, "added")
end

T["PR diff"]["parses hunks from PR diff"] = function()
  setup_plugin_with_pr()
  local diff_parser = require("review.core.diff_parser")

  local files = diff_parser.parse(SAMPLE_PR_DIFF)

  local route_file
  for _, f in ipairs(files) do
    if f.path == "src/route.ts" then
      route_file = f
      break
    end
  end

  expect.equality(route_file ~= nil, true)
  expect.equality(#route_file.hunks, 2)
end

-- =============================================================================
-- GitHub Comment Tests
-- =============================================================================

T["GitHub comments"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      cleanup()
    end,
    post_case = cleanup,
  },
})

T["GitHub comments"]["fetch_conversation_comments returns conversation comments"] = function()
  setup_plugin_with_pr()
  local github = require("review.integrations.github")

  local comments = github.fetch_conversation_comments(142)

  expect.equality(#comments, 2)
  expect.equality(comments[1].kind, "conversation")
  expect.equality(comments[1].author, "maintainer")
end

T["GitHub comments"]["fetch_review_comments returns code comments"] = function()
  setup_plugin_with_pr()
  local github = require("review.integrations.github")

  local comments = github.fetch_review_comments(142)

  expect.equality(#comments, 3)
  expect.equality(comments[1].kind, "review")
  expect.equality(comments[1].file, "src/route.ts")
end

T["GitHub comments"]["fetch_reviews returns review summaries"] = function()
  setup_plugin_with_pr()
  local github = require("review.integrations.github")

  local reviews = github.fetch_reviews(142)

  expect.equality(#reviews, 1)
  expect.equality(reviews[1].kind, "review_summary")
  expect.equality(reviews[1].review_state, "CHANGES_REQUESTED")
end

T["GitHub comments"]["comment has required fields for code comments"] = function()
  setup_plugin_with_pr()
  local github = require("review.integrations.github")

  local comments = github.fetch_review_comments(142)
  local comment = comments[1]

  expect.equality(comment.id ~= nil, true)
  expect.equality(comment.body ~= nil, true)
  expect.equality(comment.author ~= nil, true)
  expect.equality(comment.file ~= nil, true)
  expect.equality(comment.line ~= nil, true)
end

T["GitHub comments"]["resolved field is preserved"] = function()
  setup_plugin_with_pr()
  local github = require("review.integrations.github")

  local comments = github.fetch_review_comments(142)

  local unresolved = vim.tbl_filter(function(c)
    return c.resolved == false
  end, comments)
  local resolved = vim.tbl_filter(function(c)
    return c.resolved == true
  end, comments)

  expect.equality(#unresolved, 2)
  expect.equality(#resolved, 1)
end

-- =============================================================================
-- Comment State Integration Tests
-- =============================================================================

T["comment state"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      cleanup()
    end,
    post_case = cleanup,
  },
})

T["comment state"]["can combine GitHub and local comments"] = function()
  setup_plugin_with_pr()
  local state = setup_pr_state()
  local comments = require("review.core.comments")

  -- Add GitHub comments to state
  state.set_comments(vim.deepcopy(SAMPLE_REVIEW_COMMENTS))

  -- Add local comments
  comments.add("src/route.ts", 45, "Should we memoize this?", "suggestion")
  comments.add("src/route.ts", 50, "Nice implementation!", "praise")

  local all_comments = state.state.comments
  expect.equality(#all_comments, 5) -- 3 GitHub + 2 local
end

T["comment state"]["get_comments_for_file filters by file"] = function()
  setup_plugin_with_pr()
  local state = setup_pr_state()

  state.set_comments(vim.deepcopy(SAMPLE_REVIEW_COMMENTS))

  local route_comments = state.get_comments_for_file("src/route.ts")
  local helper_comments = state.get_comments_for_file("src/utils/theme-helper.ts")

  expect.equality(#route_comments, 2)
  expect.equality(#helper_comments, 1)
end

T["comment state"]["get_unresolved_comments filters by resolved status"] = function()
  setup_plugin_with_pr()
  local state = setup_pr_state()

  state.set_comments(vim.deepcopy(SAMPLE_REVIEW_COMMENTS))

  local unresolved = state.get_unresolved_comments()

  expect.equality(#unresolved, 2)
  for _, c in ipairs(unresolved) do
    expect.equality(c.resolved, false)
  end
end

T["comment state"]["get_pending_comments returns local pending only"] = function()
  setup_plugin_with_pr()
  local state = setup_pr_state()
  local comments = require("review.core.comments")

  -- Add GitHub comments
  state.set_comments(vim.deepcopy(SAMPLE_REVIEW_COMMENTS))

  -- Add local pending comments
  comments.add("src/route.ts", 45, "My pending note", "note")

  local pending = state.get_pending_comments()

  expect.equality(#pending, 1)
  expect.equality(pending[1].kind, "local")
  expect.equality(pending[1].status, "pending")
end

T["comment state"]["get_comments_sorted orders by file then line"] = function()
  setup_plugin_with_pr()
  local state = setup_pr_state()
  local comments = require("review.core.comments")

  state.set_comments(vim.deepcopy(SAMPLE_REVIEW_COMMENTS))
  comments.add("src/route.ts", 5, "Early comment", "note")

  local sorted = state.get_comments_sorted()

  -- All should have file and line
  for _, c in ipairs(sorted) do
    expect.equality(c.file ~= nil, true)
    expect.equality(c.line ~= nil, true)
  end

  -- Should be sorted by file then line
  for i = 2, #sorted do
    local prev = sorted[i - 1]
    local curr = sorted[i]
    if prev.file == curr.file then
      expect.equality(prev.line <= curr.line, true)
    else
      expect.equality(prev.file < curr.file, true)
    end
  end
end

-- =============================================================================
-- Comment CRUD with PR Mode Tests
-- =============================================================================

T["PR comment CRUD"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      cleanup()
    end,
    post_case = cleanup,
  },
})

T["PR comment CRUD"]["add local comment in PR mode"] = function()
  setup_plugin_with_pr()
  local state = setup_pr_state()
  local comments = require("review.core.comments")

  local comment = comments.add("src/route.ts", 20, "Consider error handling", "issue")

  expect.equality(comment.kind, "local")
  expect.equality(comment.status, "pending")
  expect.equality(comment.type, "issue")
  expect.equality(comment.author, "you")
end

T["PR comment CRUD"]["edit local comment in PR mode"] = function()
  setup_plugin_with_pr()
  local state = setup_pr_state()
  local comments = require("review.core.comments")

  local comment = comments.add("src/route.ts", 20, "Original", "note")
  local success = comments.edit(comment.id, "Updated text")

  expect.equality(success, true)

  local updated = state.find_comment(comment.id)
  expect.equality(updated.body, "Updated text")
end

T["PR comment CRUD"]["delete local comment in PR mode"] = function()
  setup_plugin_with_pr()
  local state = setup_pr_state()
  local comments = require("review.core.comments")

  local comment = comments.add("src/route.ts", 20, "To delete", "note")
  expect.equality(#state.get_pending_comments(), 1)

  local success = comments.delete(comment.id)

  expect.equality(success, true)
  expect.equality(#state.get_pending_comments(), 0)
end

T["PR comment CRUD"]["reply to local comment"] = function()
  setup_plugin_with_pr()
  setup_pr_state()
  local comments = require("review.core.comments")

  local parent = comments.add("src/route.ts", 20, "Parent comment", "note")
  local reply = comments.reply(parent.id, "Reply text")

  expect.equality(reply.in_reply_to_id, parent.id)
  expect.equality(reply.file, parent.file)
  expect.equality(reply.line, parent.line)
end

T["PR comment CRUD"]["mark_submitted changes status"] = function()
  setup_plugin_with_pr()
  setup_pr_state()
  local comments = require("review.core.comments")

  local comment = comments.add("src/route.ts", 20, "Pending", "note")
  expect.equality(comment.status, "pending")

  local success = comments.mark_submitted(comment.id, 12345)

  expect.equality(success, true)
  expect.equality(comment.status, "submitted")
  expect.equality(comment.github_id, 12345)
end

-- =============================================================================
-- File Comment Counts Tests
-- =============================================================================

T["file comment counts"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      cleanup()
    end,
    post_case = cleanup,
  },
})

T["file comment counts"]["updates counts from GitHub comments"] = function()
  setup_plugin_with_pr()
  local state = setup_pr_state()

  state.set_comments(vim.deepcopy(SAMPLE_REVIEW_COMMENTS))
  state.update_file_comment_counts()

  local route_file = state.find_file("src/route.ts")
  local helper_file = state.find_file("src/utils/theme-helper.ts")

  expect.equality(route_file.comment_count, 2)
  expect.equality(helper_file.comment_count, 1)
end

T["file comment counts"]["includes local comments in counts"] = function()
  setup_plugin_with_pr()
  local state = setup_pr_state()
  local comments = require("review.core.comments")

  state.set_comments(vim.deepcopy(SAMPLE_REVIEW_COMMENTS))
  comments.add("src/route.ts", 50, "My comment", "note")
  state.update_file_comment_counts()

  local route_file = state.find_file("src/route.ts")

  expect.equality(route_file.comment_count, 3) -- 2 GitHub + 1 local
end

-- =============================================================================
-- Statistics Tests
-- =============================================================================

T["PR stats"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      cleanup()
    end,
    post_case = cleanup,
  },
})

T["PR stats"]["get_stats returns correct counts"] = function()
  setup_plugin_with_pr()
  local state = setup_pr_state()
  local comments = require("review.core.comments")

  state.set_comments(vim.deepcopy(SAMPLE_REVIEW_COMMENTS))
  comments.add("src/route.ts", 50, "Pending 1", "note")
  comments.add("src/route.ts", 60, "Pending 2", "issue")

  local stats = state.get_stats()

  expect.equality(stats.total_files, 3)
  expect.equality(stats.total_comments, 5) -- 3 GitHub + 2 local
  expect.equality(stats.pending_comments, 2)
  expect.equality(stats.unresolved_comments, 2) -- Only GitHub unresolved
end

-- =============================================================================
-- GitHub Mock Tests
-- =============================================================================

T["GitHub mock"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      cleanup()
    end,
    post_case = cleanup,
  },
})

T["GitHub mock"]["fetch_pr returns PR data"] = function()
  setup_plugin_with_pr()
  local github = require("review.integrations.github")

  local pr = github.fetch_pr(142)

  expect.equality(pr ~= nil, true)
  expect.equality(pr.number, 142)
  expect.equality(pr.title, "Add theme support for custom styles")
end

T["GitHub mock"]["fetch_pr returns nil for non-existent PR"] = function()
  setup_plugin_with_pr()
  local github = require("review.integrations.github")

  local pr = github.fetch_pr(999)

  expect.equality(pr, nil)
end

T["GitHub mock"]["fetch_pr_diff returns diff content"] = function()
  setup_plugin_with_pr()
  local github = require("review.integrations.github")

  local diff = github.fetch_pr_diff(142)

  expect.equality(type(diff), "string")
  expect.equality(diff:find("src/route.ts") ~= nil, true)
end

T["GitHub mock"]["fetch_review_requests returns PRs"] = function()
  reset_modules()
  mock_git.install()
  mock_github.install()

  mock_github.setup({
    review_requests = {
      { number = 100, title = "PR 1", author = "user1", created_at = "2024-01-15T10:00:00Z" },
      { number = 101, title = "PR 2", author = "user2", created_at = "2024-01-15T11:00:00Z" },
    },
  })

  local review = require("review")
  review.setup()

  local github = require("review.integrations.github")
  local prs = github.fetch_review_requests()

  expect.equality(#prs, 2)
  expect.equality(prs[1].number, 100)
end

T["GitHub mock"]["fetch_open_prs returns all open PRs"] = function()
  reset_modules()
  mock_git.install()
  mock_github.install()

  mock_github.setup({
    open_prs = {
      { number = 100, title = "PR 1", author = "user1", created_at = "2024-01-15T10:00:00Z" },
      { number = 101, title = "PR 2", author = "user2", created_at = "2024-01-15T11:00:00Z" },
      { number = 102, title = "PR 3", author = "user3", created_at = "2024-01-15T12:00:00Z" },
    },
  })

  local review = require("review")
  review.setup()

  local github = require("review.integrations.github")
  local prs = github.fetch_open_prs()

  expect.equality(#prs, 3)
end

T["GitHub mock"]["group_into_threads groups replies"] = function()
  setup_plugin_with_pr()
  local github = require("review.integrations.github")

  local comments = {
    { id = "1", github_id = 1, body = "Root comment", author = "user1" },
    { id = "2", github_id = 2, body = "Reply 1", author = "user2", in_reply_to_id = 1 },
    { id = "3", github_id = 3, body = "Reply 2", author = "user1", in_reply_to_id = 1 },
  }

  local threads = github.group_into_threads(comments)

  expect.equality(#threads, 1)
  expect.equality(#threads[1].replies, 2)
end

-- =============================================================================
-- Layout with PR Mode Tests
-- =============================================================================

T["PR layout"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      cleanup()
    end,
    post_case = cleanup,
  },
})

T["PR layout"]["opens in new tabpage"] = function()
  setup_plugin_with_pr()
  local state = require("review.core.state")
  local layout = require("review.ui.layout")

  local initial_tabs = vim.fn.tabpagenr("$")

  state.set_mode("pr", { pr = SAMPLE_PR })
  state.state.active = true
  layout.open()

  expect.equality(vim.fn.tabpagenr("$"), initial_tabs + 1)
end

T["PR layout"]["creates file tree and diff windows"] = function()
  setup_plugin_with_pr()
  local state = setup_pr_state()

  expect.equality(vim.api.nvim_win_is_valid(state.state.layout.file_tree_win), true)
  expect.equality(vim.api.nvim_win_is_valid(state.state.layout.diff_win), true)
end

-- =============================================================================
-- File Tree with PR Mode Tests
-- =============================================================================

T["PR file tree"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      cleanup()
    end,
    post_case = cleanup,
  },
})

T["PR file tree"]["renders PR files"] = function()
  setup_plugin_with_pr()
  local state = setup_pr_state()
  local file_tree = require("review.ui.file_tree")

  file_tree.render()

  local buf = state.state.layout.file_tree_buf
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  expect.equality(#lines > 0, true)
end

T["PR file tree"]["shows comment counts"] = function()
  setup_plugin_with_pr()
  local state = setup_pr_state()
  local file_tree = require("review.ui.file_tree")

  state.set_comments(vim.deepcopy(SAMPLE_REVIEW_COMMENTS))
  state.update_file_comment_counts()
  file_tree.render()

  local buf = state.state.layout.file_tree_buf
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local content = table.concat(lines, "\n")

  -- Should contain comment indicator for files with comments
  expect.equality(content:find("2") ~= nil or content:find("comments") ~= nil, true)
end

-- =============================================================================
-- Edge Cases
-- =============================================================================

T["PR edge cases"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      cleanup()
    end,
    post_case = cleanup,
  },
})

T["PR edge cases"]["handles PR with no comments"] = function()
  reset_modules()
  mock_git.install()
  mock_github.install()

  mock_github.add_pr(SAMPLE_PR)
  mock_github.set_pr_diff(SAMPLE_PR.number, SAMPLE_PR_DIFF)
  -- Don't add any comments

  local review = require("review")
  review.setup()

  local state = setup_pr_state()
  local github = require("review.integrations.github")

  local conversation = github.fetch_conversation_comments(142)
  local reviews = github.fetch_review_comments(142)

  expect.equality(#conversation, 0)
  expect.equality(#reviews, 0)
  expect.equality(#state.state.comments, 0)
end

T["PR edge cases"]["handles empty PR diff"] = function()
  reset_modules()
  mock_git.install()
  mock_github.install()

  mock_github.add_pr(SAMPLE_PR)
  mock_github.set_pr_diff(SAMPLE_PR.number, "")

  local review = require("review")
  review.setup()

  local github = require("review.integrations.github")
  local diff = github.fetch_pr_diff(142)

  expect.equality(diff, "")
end

T["PR edge cases"]["handles PR with long description"] = function()
  setup_plugin_with_pr()
  local state = require("review.core.state")

  local long_description = string.rep("This is a very long line. ", 100)
  local pr_with_long_desc = vim.tbl_extend("force", SAMPLE_PR, {
    description = long_description,
  })

  state.set_mode("pr", { pr = pr_with_long_desc })

  expect.equality(#state.state.pr.description > 1000, true)
end

T["PR edge cases"]["handles comments on deleted files"] = function()
  setup_plugin_with_pr()
  local state = setup_pr_state()

  -- Add comment for a file that doesn't exist in state
  local comment = {
    id = "gh_review_99",
    kind = "review",
    body = "Comment on deleted file",
    author = "reviewer",
    created_at = "2024-01-15T13:00:00Z",
    file = "deleted/file.ts",
    line = 10,
    resolved = false,
  }

  state.add_comment(comment)

  local deleted_comments = state.get_comments_for_file("deleted/file.ts")
  expect.equality(#deleted_comments, 1)

  -- File won't be in files list
  local file = state.find_file("deleted/file.ts")
  expect.equality(file, nil)
end

T["PR edge cases"]["handles multiple comment types on same line"] = function()
  setup_plugin_with_pr()
  local state = setup_pr_state()
  local comments = require("review.core.comments")

  -- Add GitHub comment
  state.add_comment({
    id = "gh_review_1",
    kind = "review",
    body = "GitHub comment",
    author = "reviewer",
    file = "src/route.ts",
    line = 15,
  })

  -- Add local comment on same line
  comments.add("src/route.ts", 15, "Local note", "note")

  local line_comments = comments.get_at_line("src/route.ts", 15)

  expect.equality(#line_comments, 2)
end

return T
