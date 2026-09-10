local M = {}

local config = require("secret-scanner.config")
local diagnostics = require("secret-scanner.ui.diagnostics")

local severities = {
  [vim.diagnostic.severity.ERROR] = "ERROR",
  [vim.diagnostic.severity.WARN] = "WARN",
  [vim.diagnostic.severity.INFO] = "INFO",
  [vim.diagnostic.severity.HINT] = "HINT",
}

--- Close the currently open detail window, if any.
function M.close()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, true)
  end
  M.win = nil
end

--- Show a floating detail window for the finding under the cursor.
---@param bufnr integer
---@param line integer
function M.show(bufnr, line)
  local finding = diagnostics.finding_at(bufnr, line)
  if not finding then
    return
  end

  local cfg = config.get()
  local hint = cfg.allowlist_hint or "press <leader>sa to allowlist this finding if it's a false positive"
  local width = 62
  local content = {
    "  " .. string.rep("=", width - 4),
    "  Secret detected by secret-scanner",
    "  " .. string.rep("=", width - 4),
    "",
    string.format("  Rule:     %s", finding.rule_id or "unknown"),
    string.format("  Severity: %s", severities[finding.severity] or "unknown"),
    string.format("  File:     %s", finding.file or "?"),
    string.format("  Line:     %d", finding.line or 0),
    string.format("  Secret:   %s", finding.secret_masked or ""),
    "",
    "  " .. (finding.description or ""),
    "",
    "  " .. hint,
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "cursor",
    width = width,
    height = #content,
    border = "rounded",
    row = 1,
    col = 0,
    style = "minimal",
    zindex = 50,
  })
  vim.api.nvim_win_set_option(win, "winhl", "Normal:NormalFloat,FloatBorder:DiagnosticWarn")

  M.win = win
end

return M
