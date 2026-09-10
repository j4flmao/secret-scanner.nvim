local config = require("secret-scanner.config")
local parser = require("secret-scanner.engine.parser")

local M = {}

--- Absolute path to the shipped extended ruleset, resolved via the runtime
--- path (works under lazy.nvim, packer, vim-pack, and local dev dirs).
---@return string|nil
function M.bundled_rules_path()
  local ok, rtp = pcall(function()
    return vim.fn.split(vim.o.runtimepath, ",")
  end)
  if not ok or type(rtp) ~= "table" then
    return nil
  end
  for _, dir in ipairs(rtp) do
    local candidate = dir .. "/rules/secret-scanner.extend.toml"
    if vim.fn.filereadable(candidate) == 1 then
      return vim.fn.fnamemodify(candidate, ":p"):gsub("\\", "/")
    end
  end
  return nil
end

--- Derive and materialize a TOML file whose `[extend] path` points at the
--- bundled ruleset. gitleaks forbids combining useDefault and path, so the
--- chain is: derived -> bundled (which sets useDefault = true) -> defaults.
---@param cache_dir string
---@param bundled string
---@return string derived path
local function materialize_bundled(cache_dir, bundled)
  vim.fn.mkdir(cache_dir, "p")
  local path = cache_dir .. "/extend-rules.toml"
  vim.fn.writefile({ "[extend]", string.format('path = "%s"', bundled) }, path)
  return path
end

--- Resolve the gitleaks config file the plugin should pass via `--config`,
--- honoring the extend-vs-replace merge strategy:
---   - no custom config        -> the bundled ruleset (via [extend]) when
---                                enabled, else gitleaks embedded defaults
---   - override_default_rules  -> the custom config verbatim (pure replace)
---   - otherwise               -> the custom config extended with the embedded
---                                defaults (and the bundled ruleset), unless it
---                                already defines its own `[extend]` section.
--- The derived config is materialized under stdpath("cache") so gitleaks only
--- ever reads a plain, self-contained TOML file.
---@return string|nil path config path to pass via --config
---@return string|nil error
function M.effective_config_path()
  local cfg = config.get()
  local custom = cfg.custom_config_path
  if cfg.override_default_rules then
    if custom then
      return custom, nil
    end
    return nil, nil
  end

  local bundled = cfg.bundled_rules and M.bundled_rules_path()

  if custom then
    if vim.fn.filereadable(custom) == 0 then
      return nil, string.format("custom_config_path is not readable: %s", custom)
    end
    local text = table.concat(vim.fn.readfile(custom), "\n")
    if text:find("[extend]", 1, true) then
      -- The file already controls its own inheritance; respect it.
      return custom, nil
    end

    local dir = vim.fn.stdpath("cache") .. "/secret-scanner"
    vim.fn.mkdir(dir, "p")
    local derived = dir .. "/extend-" .. vim.fn.sha256(custom):sub(1, 12) .. ".toml"
    local lines = vim.fn.readfile(custom)
    local header = { "[extend]" }
    if bundled then
      -- Chain through the bundled ruleset (which brings in useDefault).
      table.insert(header, string.format('path = "%s"', bundled))
    else
      table.insert(header, "useDefault = true")
    end
    for i = #header, 1, -1 do
      table.insert(lines, 1, header[i])
    end
    vim.fn.writefile(lines, derived)
    return derived, nil
  end

  if bundled then
    return materialize_bundled(vim.fn.stdpath("cache") .. "/secret-scanner", bundled), nil
  end

  return nil, nil
end

--- Build the gitleaks command for staged diff scanning.
---@param config_path string|nil
---@return string[]
local function build_staged_cmd(config_path)
  local cmd =
    { config.get().gitleaks_path, "git", "--pre-commit", "--staged", "--report-format", "json", "--report-path", "-" }
  if config_path then
    table.insert(cmd, "--config")
    table.insert(cmd, config_path)
  end
  return cmd
end

--- Check if gitleaks binary is available.
---@return boolean
---@return string|nil path
function M.check()
  local path = vim.fn.exepath(config.get().gitleaks_path)
  if path == "" then
    return false, nil
  end
  return true, path
end

--- Detect whether a directory is inside a git repository.
---@param cwd string
---@return boolean
function M.is_git_repo(cwd)
  vim.fn.system({ "git", "-C", cwd, "rev-parse", "--is-inside-work-tree" })
  return vim.v.shell_error == 0
end

--- Run a vim.system gitleaks command and deliver parsed findings.
---@param cmd string[]
---@param cwd string
---@param opts table
---@param callback fun(findings: Finding[], error: string|nil)
local function run(cmd, opts, callback)
  local cfg = config.get()
  vim.system(cmd, opts, function(result)
    vim.schedule(function()
      if result.code == -1 then
        local stderr = result.stderr or ""
        if stderr:match("timeout") or stderr:match("signal") then
          callback({}, "gitleaks timed out after " .. cfg.timeout .. "ms")
          return
        end
        callback({}, "gitleaks crashed: " .. (stderr or "unknown error"))
        return
      end

      -- Exit code 1 means findings were found, which is expected.
      if result.code > 1 then
        callback({}, string.format("gitleaks exited with code %d: %s", result.code, result.stderr or ""))
        return
      end

      callback(parser.parse(result.stdout or ""), nil)
    end)
  end)
end

--- Resolve the config path once and delegate to run().
---@param callback fun(findings: Finding[], error: string|nil)
---@param build fun(config_path: string|nil): string[]
---@param cwd string
---@return vim.SystemObj|nil the job handle when a process was spawned
local function run_with_config(build, cwd, callback)
  local available = M.check()
  if not available then
    callback({}, "gitleaks not found on PATH")
    return nil
  end

  local config_path, config_err = M.effective_config_path()
  if config_err then
    callback({}, config_err)
    return nil
  end

  return run(build(config_path), { text = true, cwd = cwd, timeout = config.get().timeout }, callback)
end

--- Scan buffer text. The text is written to a per-content temp file and
--- scanned with `gitleaks dir` — vim.system's stdin pipe handling is
--- unreliable across platforms (notably Windows, where the child may never
--- see EOF), while a direct file scan behaves identically everywhere.
---@param text string
---@param filetype string
---@param callback fun(findings: Finding[], error: string|nil)
function M.scan_stdin(text, _filetype, callback)
  local scan_dir = vim.fn.stdpath("cache") .. "/secret-scanner/scans"
  vim.fn.mkdir(scan_dir, "p")
  local path = scan_dir .. "/buffer-" .. (vim.fn.sha256(text):sub(1, 16)) .. ".txt"

  local ok, write_err = pcall(function()
    local f = io.open(path, "w")
    if not f then
      error("failed to create " .. path)
    end
    f:write(text)
    f:close()
  end)
  if not ok then
    callback({}, write_err)
    return
  end

  run_with_config(
    function(config_path)
      local cmd = { config.get().gitleaks_path, "dir", path, "--report-format", "json", "--report-path", "-" }
      if config_path then
        table.insert(cmd, "--config")
        table.insert(cmd, config_path)
      end
      return cmd
    end,
    vim.fn.getcwd(),
    function(findings, err)
      pcall(vim.uv.fs_unlink, path)
      callback(findings, err)
    end
  )
end

--- Scan staged diff via gitleaks (async).
---@param cwd string
---@param callback fun(findings: Finding[], error: string|nil)
function M.scan_staged_diff(cwd, callback)
  run_with_config(build_staged_cmd, cwd, callback)
end

--- Scan the full repo (commit history) via gitleaks (async).
---@param cwd string
---@param callback fun(findings: Finding[], error: string|nil)
function M.scan_repo(cwd, callback)
  run_with_config(function(config_path)
    local cmd = { config.get().gitleaks_path, "git", "--report-format", "json", "--report-path", "-" }
    if config_path then
      table.insert(cmd, "--config")
      table.insert(cmd, config_path)
    end
    return cmd
  end, cwd, callback)
end

--- Resolve the project root to scan: the git work-tree top-level when inside a
--- repo, otherwise the current directory. The trailing separator (which
--- `git rev-parse --show-toplevel` appends on Windows) is stripped.
---@param cwd string
---@return string
function M.project_root(cwd)
  local out = vim.fn.system({ "git", "-C", cwd, "rev-parse", "--show-toplevel" })
  if vim.v.shell_error == 0 and out ~= "" then
    local root = out:gsub("[\r\n]+$", ""):gsub("\\", "/")
    root = root:gsub("/+$", "")
    if root ~= "" then
      return root
    end
  end
  return cwd:gsub("[/\\]+$", "")
end

--- Scan the whole project working tree via `gitleaks dir` (async). Honors
--- .gitignore, so dependency/build trees are skipped.
---@param cwd string
---@param callback fun(findings: Finding[], error: string|nil)
function M.scan_project(cwd, callback)
  local root = M.project_root(cwd)
  run_with_config(function(config_path)
    local cmd = { config.get().gitleaks_path, "dir", root, "--report-format", "json", "--report-path", "-" }
    if config_path then
      table.insert(cmd, "--config")
      table.insert(cmd, config_path)
    end
    return cmd
  end, cwd, callback)
end

return M
