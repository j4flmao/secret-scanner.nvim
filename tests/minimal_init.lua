vim.opt.rtp:prepend(".")
vim.opt.rtp:append("deps/plenary.nvim")

vim.cmd("runtime plugin/secret-scanner.lua")

require("plenary.busted")
