local M = {}

local config = require("secret-scanner.config")

--- Inline marker placed in a comment on a line to suppress findings on it.
M.inline_marker = "secret-scanner:ignore"

--- Path to the repo allowlist file.
---@param repo_root string
---@return string
local function entries_path(repo_root)
  return repo_root .. "/" .. config.get().allowlist_file
end

--- Load allowlist entries into a lookup set.
--- Line format: `<file>:<rule_id>` or `<file>:<rule_id>:<sha8>`.
--- Blank lines and lines starting with `#` are ignored.
---@param repo_root string
---@return table set
function M.load(repo_root)
  local path = entries_path(repo_root)
  local set = {}
  if vim.fn.filereadable(path) == 0 then
    return set
  end
  for _, line in ipairs(vim.fn.readfile(path)) do
    local trimmed = vim.trim(line)
    if trimmed ~= "" and not trimmed:match("^#") then
      set[trimmed] = true
    end
  end
  return set
end

--- Check whether a finding matches an allowlist entry.
---@param finding table
---@param allowlist table
---@return boolean
function M.is_allowed(finding, allowlist)
  if not allowlist or not finding then
    return false
  end
  local key = (finding.file or "") .. ":" .. (finding.rule_id or "")
  if allowlist[key] then
    return true
  end
  if finding.secret_hash and finding.secret_hash ~= "" then
    local granular = key .. ":" .. finding.secret_hash:sub(1, 8)
    if allowlist[granular] then
      return true
    end
  end
  return false
end

--- Check whether a line's content carries the inline ignore marker.
---@param line_content string|nil
---@return boolean
function M.is_inline_ignored(line_content)
  if not line_content then
    return false
  end
  return line_content:find(M.inline_marker, 1, true) ~= nil
end

--- Append a finding to the allowlist file. Returns the key written and
--- whether it was newly added.
---@param repo_root string
---@param finding table
---@return string key
---@return boolean added
function M.add(repo_root, finding)
  local path = entries_path(repo_root)
  local key = (finding.file or "") .. ":" .. (finding.rule_id or "unknown")
  if finding.secret_hash and finding.secret_hash ~= "" then
    key = key .. ":" .. finding.secret_hash:sub(1, 8)
  end

  local lines = {}
  if vim.fn.filereadable(path) == 1 then
    lines = vim.fn.readfile(path)
    for _, line in ipairs(lines) do
      if vim.trim(line) == key then
        return key, false
      end
    end
  end

  lines[#lines + 1] = key
  local dir = vim.fn.fnamemodify(path, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
  vim.fn.writefile(lines, path)
  return key, true
end

--- Filter findings down to the ones not suppressed by the allowlist
--- (file entries and inline markers).
---@param findings table[]
---@param allowlist table
---@param bufnr integer
---@return table[] filtered
function M.filter(findings, allowlist, bufnr)
  local filtered = {}
  local line_cache = {}
  for _, f in ipairs(findings) do
    if not M.is_allowed(f, allowlist) then
      local line = f.line or 1
      local content = line_cache[line]
      if content == nil then
        content = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""
        line_cache[line] = content
      end
      if not M.is_inline_ignored(content) then
        table.insert(filtered, f)
      end
    end
  end
  return filtered
end

return M
