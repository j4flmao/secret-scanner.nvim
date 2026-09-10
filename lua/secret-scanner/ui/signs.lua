local M = {}

local config = require("secret-scanner.config")
local diagnostics = require("secret-scanner.ui.diagnostics")

--- Apply namespace-scoped diagnostic display config (respects user globals).
function M.setup()
  local cfg = config.get().ui
  if not cfg then
    return
  end
  vim.diagnostic.config({
    virtual_text = cfg.virtual_text,
    signs = cfg.signs,
  }, diagnostics.namespace())
end

return M
