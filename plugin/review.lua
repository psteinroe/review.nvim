-- Plugin loader for review.nvim
-- Minimal bootstrapping - just prevents double-loading and exposes setup

if vim.g.loaded_review then
  return
end
vim.g.loaded_review = true

-- Require Neovim 0.10+
if vim.fn.has("nvim-0.10") ~= 1 then
  vim.notify("review.nvim requires Neovim 0.10+", vim.log.levels.ERROR)
  return
end
