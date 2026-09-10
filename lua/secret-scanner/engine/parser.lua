local M = {}

---@class Finding
---@field file string
---@field line integer
---@field end_line integer
---@field col integer
---@field end_col integer
---@field rule_id string
---@field description string
---@field secret_masked string
---@field secret_hash string|nil
---@field severity integer

--- Mask a raw secret value. Never store or display the raw form.
--- Shows first 4 and last 2 chars with asterisks in between.
---@param secret string
---@return string
function M.mask_secret(secret)
  if not secret or secret == "" then
    return ""
  end
  local len = #secret
  if len <= 8 then
    return string.rep("*", len)
  end
  local prefix = secret:sub(1, 4)
  local suffix = secret:sub(-2)
  local masked_len = len - 6
  return prefix .. string.rep("*", masked_len) .. suffix
end

--- Map gitleaks severity string to vim.diagnostic.severity.
---@param severity string|nil
---@return integer
local function map_severity(severity)
  if not severity then
    return vim.diagnostic.severity.WARN
  end
  local lower = severity:lower()
  if lower == "high" or lower == "critical" then
    return vim.diagnostic.severity.ERROR
  elseif lower == "medium" then
    return vim.diagnostic.severity.WARN
  else
    return vim.diagnostic.severity.INFO
  end
end

--- Parse gitleaks JSON report output into internal Finding[] shape.
---@param json_output string
---@return Finding[]
function M.parse(json_output)
  if not json_output or json_output == "" then
    return {}
  end

  local ok, decoded = pcall(vim.json.decode, json_output)
  if not ok or type(decoded) ~= "table" then
    vim.notify("[secret-scanner] failed to parse gitleaks JSON output", vim.log.levels.WARN)
    return {}
  end

  ---@type Finding[]
  local findings = {}

  for _, item in ipairs(decoded) do
    if type(item) == "table" then
      local secret = item.Secret or ""
      local secret_hash
      if secret ~= "" then
        secret_hash = vim.fn.sha256(secret)
      end
      local finding = {
        file = item.File or "",
        line = tonumber(item.StartLine) or 0,
        end_line = tonumber(item.EndLine) or 0,
        col = tonumber(item.StartColumn) or 1,
        end_col = tonumber(item.EndColumn) or 1,
        rule_id = item.RuleID or "unknown",
        description = item.Description or item.RuleID or "secret detected",
        secret_masked = M.mask_secret(secret),
        secret_hash = secret_hash,
        severity = map_severity(item.Severity),
      }
      table.insert(findings, finding)
    end
  end

  return findings
end

return M
