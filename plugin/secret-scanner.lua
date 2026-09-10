if vim.g.loaded_secret_scanner then
  return
end
vim.g.loaded_secret_scanner = true

-- Don't call setup() automatically; require explicit setup() call.
