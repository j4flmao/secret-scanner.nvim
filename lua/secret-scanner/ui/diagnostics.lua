local M = {}

local config = require("secret-scanner.config")

local ns = vim.api.nvim_create_namespace("secret-scanner")
local buffer_findings = {}

--- Resolve the severity for a finding, honoring per-rule overrides.
---@param finding table
---@return integer
local function resolve_severity(finding)
  local cfg = config.get()
  local overrides = cfg.severity.rules or {}
  local severity
  if finding.rule_id and overrides[finding.rule_id] then
    severity = overrides[finding.rule_id]
  else
    severity = finding.severity or cfg.severity.default or vim.diagnostic.severity.WARN
  end
  if type(severity) == "string" then
    local map = {
      ERROR = vim.diagnostic.severity.ERROR,
      WARN = vim.diagnostic.severity.WARN,
      INFO = vim.diagnostic.severity.INFO,
      HINT = vim.diagnostic.severity.HINT,
    }
    severity = map[severity:upper()] or vim.diagnostic.severity.WARN
  end
  return severity
end

--- Publish findings as native diagnostics for a buffer.
---@param bufnr integer
---@param findings table[]
function M.publish(bufnr, findings)
  local diagnostics = {}
  for _, f in ipairs(findings) do
    table.insert(diagnostics, {
      lnum = f.line - 1,
      col = (f.col or 1) - 1,
      end_lnum = (f.end_line or f.line) - 1,
      end_col = f.end_col or f.col or 1,
      severity = resolve_severity(f),
      source = "secret-scanner",
      message = string.format("[%s] %s", f.rule_id, f.description),
    })
  end
  vim.diagnostic.set(ns, bufnr, diagnostics)
  buffer_findings[bufnr] = findings
end

--- Clear diagnostics for a buffer.
---@param bufnr integer
function M.clear(bufnr)
  vim.diagnostic.set(ns, bufnr, {})
  buffer_findings[bufnr] = nil
end

--- Get the last published findings for a buffer.
---@param bufnr integer
---@return table[]
function M.get_findings(bufnr)
  return buffer_findings[bufnr] or {}
end

--- Find the finding covering a 1-indexed line.
---@param bufnr integer
---@param line integer
---@return table|nil
function M.finding_at(bufnr, line)
  for _, f in ipairs(M.get_findings(bufnr)) do
    local start_line = f.line or 1
    local end_line = f.end_line or f.line or start_line
    if line >= start_line and line <= end_line then
      return f
    end
  end
  return nil
end

--- Get the total finding count within a buffer (optionally filtering by severity threshold).
---@param bufnr integer
---@param severity? integer
---@return integer
function M.count(bufnr, severity)
  local findings = M.get_findings(bufnr)
  if not severity then
    return #findings
  end
  local n = 0
  for _, f in ipairs(findings) do
    if (f.severity or config.get().severity.default) <= severity then
      n = n + 1
    end
  end
  return n
end

--- Namespace used for diagnostics.
function M.namespace()
  return ns
end

return M
