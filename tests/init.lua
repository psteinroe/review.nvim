-- Test runner setup for review.nvim
-- Uses mini.test from mini.nvim

-- Add project to runtime path
vim.opt.rtp:prepend(".")
vim.opt.rtp:prepend("./tests")

-- Set up mini.test
local mini_path = vim.fn.stdpath("data") .. "/site/pack/deps/start/mini.nvim"
if not vim.loop.fs_stat(mini_path) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "--single-branch",
    "https://github.com/echasnovski/mini.nvim",
    mini_path,
  })
  vim.cmd("packadd mini.nvim")
end

require("mini.test").setup()

-- Load helpers (will be created in next task)
-- _G.H = require("tests.helpers")
