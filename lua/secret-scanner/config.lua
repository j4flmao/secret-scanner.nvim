---@class SecretScannerConfig
---@field gitleaks_path string
---@field scan_on_save boolean
---@field scan_on_text_change boolean
---@field scan_on_commit boolean
---@field block_commit_on_finding boolean
---@field pre_push_hook boolean
---@field custom_config_path string|nil
---@field override_default_rules boolean
---@field bundled_rules boolean
---@field allowlist_file string
---@field debounce_ms integer
---@field text_change_debounce_ms integer
---@field severity table
---@field ui table
---@field timeout integer
---@field project_config_file string

local M = {}

---@type SecretScannerConfig
local defaults = {
  gitleaks_path = "gitleaks",
  scan_on_save = true,
  scan_on_text_change = false,
  scan_on_commit = true,
  block_commit_on_finding = true,
  pre_push_hook = false,
  custom_config_path = nil,
  override_default_rules = false,
  bundled_rules = true,
  allowlist_file = ".secretscannerignore",
  project_config_file = ".secretscanner.lua",
  debounce_ms = 300,
  text_change_debounce_ms = 2000,
  severity = {
    default = vim.diagnostic.severity.WARN,
  },
  ui = {
    virtual_text = true,
    signs = true,
    float_on_cursor_hold = true,
  },
  timeout = 30000,
}

local valid_keys = {}
for k, _ in pairs(defaults) do
  valid_keys[k] = true
end
-- Keys whose default is `nil` are absent from the defaults table, so
-- `pairs(defaults)` cannot register them as valid either.
valid_keys.custom_config_path = true

--- Validate a config table. Returns (ok, errors).
---@param opts table
---@return boolean
---@return string[]
local function validate(opts)
  local errors = {}
  for k, _ in pairs(opts) do
    if not valid_keys[k] then
      table.insert(errors, string.format("unknown config key: %q", k))
    end
  end
  if opts.gitleaks_path ~= nil and type(opts.gitleaks_path) ~= "string" then
    table.insert(errors, "gitleaks_path must be a string")
  end
  if opts.scan_on_save ~= nil and type(opts.scan_on_save) ~= "boolean" then
    table.insert(errors, "scan_on_save must be a boolean")
  end
  if opts.scan_on_text_change ~= nil and type(opts.scan_on_text_change) ~= "boolean" then
    table.insert(errors, "scan_on_text_change must be a boolean")
  end
  if opts.scan_on_commit ~= nil and type(opts.scan_on_commit) ~= "boolean" then
    table.insert(errors, "scan_on_commit must be a boolean")
  end
  if opts.block_commit_on_finding ~= nil and type(opts.block_commit_on_finding) ~= "boolean" then
    table.insert(errors, "block_commit_on_finding must be a boolean")
  end
  if opts.pre_push_hook ~= nil and type(opts.pre_push_hook) ~= "boolean" then
    table.insert(errors, "pre_push_hook must be a boolean")
  end
  if opts.custom_config_path ~= nil and type(opts.custom_config_path) ~= "string" then
    table.insert(errors, "custom_config_path must be a string or nil")
  end
  if opts.override_default_rules ~= nil and type(opts.override_default_rules) ~= "boolean" then
    table.insert(errors, "override_default_rules must be a boolean")
  end
  if opts.bundled_rules ~= nil and type(opts.bundled_rules) ~= "boolean" then
    table.insert(errors, "bundled_rules must be a boolean")
  end
  if opts.allowlist_file ~= nil and type(opts.allowlist_file) ~= "string" then
    table.insert(errors, "allowlist_file must be a string")
  end
  if opts.project_config_file ~= nil and type(opts.project_config_file) ~= "string" then
    table.insert(errors, "project_config_file must be a string")
  end
  if opts.debounce_ms ~= nil and type(opts.debounce_ms) ~= "number" then
    table.insert(errors, "debounce_ms must be a number")
  end
  if opts.text_change_debounce_ms ~= nil and type(opts.text_change_debounce_ms) ~= "number" then
    table.insert(errors, "text_change_debounce_ms must be a number")
  end
  if opts.timeout ~= nil and type(opts.timeout) ~= "number" then
    table.insert(errors, "timeout must be a number")
  end
  if opts.severity ~= nil and type(opts.severity) ~= "table" then
    table.insert(errors, "severity must be a table")
  end
  if opts.ui ~= nil and type(opts.ui) ~= "table" then
    table.insert(errors, "ui must be a table")
  end
  return #errors == 0, errors
end

--- Merge user opts with defaults and store the result.
---@param opts? table
---@return SecretScannerConfig
function M.setup(opts)
  opts = opts or {}
  local ok, errors = validate(opts)
  if not ok then
    vim.notify(string.format("[secret-scanner] invalid config: %s", table.concat(errors, "; ")), vim.log.levels.ERROR)
  end
  ---@type SecretScannerConfig
  M.values = vim.tbl_deep_extend("force", defaults, opts)
  M.user_values = nil
  M.project_state = nil
  return M.values
end

--- Get the current config values. Errors if setup() hasn't been called.
---@return SecretScannerConfig
function M.get()
  if not M.values then
    error("[secret-scanner] config not initialized — call setup() first")
  end
  return M.values
end

--- Load the project-local config (`.secretscanner.lua`) for `root` on top of
--- the user config. Team policy wins over personal defaults. Cached by
--- (root, mtime) so repeated calls are cheap.
---@param root string repo root
---@return SecretScannerConfig
function M.apply_project(root)
  if not M.values then
    error("[secret-scanner] config not initialized — call setup() first")
  end

  M.user_values = M.user_values or vim.deepcopy(M.values)

  local path = root .. "/" .. M.user_values.project_config_file
  local stat = vim.uv.fs_stat(path)
  local token
  if stat then
    token = string.format("%d.%d.%d", stat.mtime.sec, stat.mtime.nsec, stat.size)
  end

  local state = M.project_state
  if state and state.root == root and state.token == token then
    return M.values
  end

  if not stat then
    M.project_state = { root = root, token = "" }
    M.values = M.user_values
    return M.values
  end

  local project = nil
  if stat then
    local chunk, err = loadfile(path)
    if chunk then
      local ok, res = pcall(chunk)
      if ok and type(res) == "table" then
        project = res
      else
        vim.notify(
          string.format("[secret-scanner] %s must return a config table", M.user_values.project_config_file),
          vim.log.levels.WARN
        )
      end
    else
      vim.notify(
        string.format(
          "[secret-scanner] failed to load %s: %s",
          M.user_values.project_config_file,
          err or "syntax error"
        ),
        vim.log.levels.WARN
      )
    end
  end

  M.project_state = { root = root, token = token or "" }

  if not project then
    if M.user_values.override_default_rules then
      M.values = vim.deepcopy(defaults)
    else
      M.values = M.user_values
    end
    return M.values
  end

  local base = M.user_values
  if project.override_default_rules or M.user_values.override_default_rules then
    base = vim.deepcopy(defaults)
  end
  M.values = vim.tbl_deep_extend("force", base, project)
  return M.values
end

return M
