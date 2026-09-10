local M = {}

local plugin_name = "secret-scanner"
local config = require("secret-scanner.config")
local gitleaks = require("secret-scanner.engine.gitleaks")
local diagnostics = require("secret-scanner.ui.diagnostics")
local signs = require("secret-scanner.ui.signs")
local float = require("secret-scanner.ui.float")
local buffer = require("secret-scanner.scan.buffer")
local hooks = require("secret-scanner.git.hooks")
local allowlist = require("secret-scanner.allowlist")

--- Guard against double-load and ensure setup() was called.
local function ensure_setup()
  if not config.values then
    vim.notify(string.format("[secret-scanner] call require(%q).setup() first", plugin_name), vim.log.levels.WARN)
    return false
  end
  config.apply_project(vim.fn.getcwd())
  return true
end

--- Setup the plugin.
---@param opts? table
function M.setup(opts)
  config.setup(opts)
  config.apply_project(vim.fn.getcwd())

  signs.setup()
  buffer.setup()

  local group = vim.api.nvim_create_augroup("secret-scanner", { clear = true })

  vim.api.nvim_create_autocmd("CursorHold", {
    group = group,
    callback = function(args)
      if not config.get().ui.float_on_cursor_hold then
        return
      end
      local row = vim.api.nvim_win_get_cursor(0)[1]
      float.show(args.buf, row)
    end,
  })

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    callback = function()
      float.close()
    end,
  })

  vim.keymap.set("n", "<leader>ss", function()
    M.scan()
  end, { desc = "Scan buffer for secrets" })

  vim.keymap.set("n", "<leader>sp", function()
    M.scan_project()
  end, { desc = "Scan whole project for secrets" })

  vim.keymap.set("n", "<leader>sa", function()
    M.allowlist_finding()
  end, { desc = "Allowlist finding under cursor" })
end

--- Allowlist the finding under the cursor and rescan.
function M.allowlist_finding()
  if not ensure_setup() then
    return
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local finding = diagnostics.finding_at(bufnr, row)
  if not finding then
    vim.notify("[secret-scanner] no finding under cursor to allowlist", vim.log.levels.INFO)
    return
  end
  local repo_root = vim.fn.getcwd()
  local key, added = allowlist.add(repo_root, finding)
  if added then
    vim.notify(string.format("[secret-scanner] allowlisted %s", key), vim.log.levels.INFO)
  else
    vim.notify(string.format("[secret-scanner] already allowlisted %s", key), vim.log.levels.INFO)
  end
  buffer.scan_buffer()
end

--- Scan the current buffer.
function M.scan()
  if not ensure_setup() then
    return
  end
  buffer.scan_buffer()
end

--- Scan the staged diff.
function M.scan_staged()
  if not ensure_setup() then
    return
  end

  local cwd = vim.fn.getcwd()
  if not gitleaks.is_git_repo(cwd) then
    vim.notify(
      "[secret-scanner] not inside a git repository"
        .. " — use :SecretScannerScan (buffer) or :SecretScannerScanProject (folder) here",
      vim.log.levels.ERROR
    )
    return
  end
  gitleaks.scan_staged_diff(cwd, function(findings, err)
    if err then
      vim.notify("[secret-scanner] " .. err, vim.log.levels.ERROR)
      return
    end

    -- gitleaks diffs against HEAD; a repo with no commits yet can never
    -- produce findings. Surface that instead of a misleading "all clear".
    local has_head = vim.fn.system({ "git", "rev-parse", "--verify", "--quiet", "HEAD" }) ~= ""

    if #findings == 0 and not has_head then
      vim.notify(
        "[secret-scanner] the staged scan needs at least one commit to diff against — make an initial commit first",
        vim.log.levels.INFO
      )
      return
    end

    local lines = {}
    for _, f in ipairs(findings) do
      table.insert(lines, string.format("  %s:%d [%s] %s", f.file, f.line, f.rule_id, f.secret_masked))
    end
    if #findings > 0 then
      vim.notify(
        string.format("[secret-scanner] found %d secret(s) in staged diff:\n%s", #findings, table.concat(lines, "\n")),
        vim.log.levels.WARN
      )
    else
      vim.notify("[secret-scanner] no secrets found in staged diff", vim.log.levels.INFO)
    end
  end)
end

--- Publish allowlist-filtered findings to the quickfix list.
---@param cwd string working directory used to build absolute filenames
---@param findings Finding[]
---@param scope string "repo" or "project", for the completion message
local function publish_to_qf(cwd, findings, scope)
  local allowlist_entries = allowlist.load(cwd)
  local filtered = {}
  for _, f in ipairs(findings) do
    if not allowlist.is_allowed(f, allowlist_entries) then
      table.insert(filtered, f)
    end
  end

  local list = {}
  for _, f in ipairs(filtered) do
    table.insert(list, {
      filename = (cwd .. "/" .. f.file):gsub("//", "/"),
      lnum = f.line or 1,
      text = string.format("[%s] %s", f.rule_id, f.secret_masked),
    })
  end
  vim.fn.setqflist(list, "r")

  if #filtered > 0 then
    vim.notify(
      string.format("[secret-scanner] found %d secret(s) in %s — see :copen", #filtered, scope),
      vim.log.levels.WARN
    )
    vim.cmd.copen()
  else
    vim.notify(string.format("[secret-scanner] no secrets found in %s", scope), vim.log.levels.INFO)
  end
end

--- Scan the full repo (explicit opt-in): git history plus the working tree as
--- gitleaks diffs it against HEAD. Findings are published to the quickfix list
--- so they can be navigated with `:cnext` / `:copen`.
function M.scan_repo()
  if not ensure_setup() then
    return
  end

  local cwd = vim.fn.getcwd()
  if not gitleaks.is_git_repo(cwd) then
    vim.notify(
      "[secret-scanner] not inside a git repository"
        .. " — use :SecretScannerScan (buffer) or :SecretScannerScanProject (folder) here",
      vim.log.levels.ERROR
    )
    return
  end
  vim.notify("[secret-scanner] scanning full repo history…", vim.log.levels.INFO)

  gitleaks.scan_repo(cwd, function(findings, err)
    if err then
      vim.notify("[secret-scanner] " .. err, vim.log.levels.ERROR)
      return
    end
    publish_to_qf(vim.fn.getcwd(), findings, "repo")
  end)
end

--- Scan the entire project working tree (explicit opt-in) — every file under
--- the git root (or the current directory outside a repo), tracked, modified,
--- and untracked alike. `gitleaks dir` honors .gitignore, so dependency/build
--- trees are skipped. Findings are published to the quickfix list.
function M.scan_project()
  if not ensure_setup() then
    return
  end

  local cwd = vim.fn.getcwd()
  vim.notify("[secret-scanner] scanning whole project…", vim.log.levels.INFO)

  gitleaks.scan_project(cwd, function(findings, err)
    if err then
      vim.notify("[secret-scanner] " .. err, vim.log.levels.ERROR)
      return
    end
    publish_to_qf(vim.fn.getcwd(), findings, "project")
  end)
end

--- Install git hooks for the current repo.
---@param repo_root? string
---@return boolean
function M.install_hooks(repo_root)
  if not ensure_setup() then
    return false
  end
  return hooks.install(repo_root)
end

--- Uninstall git hooks.
---@param repo_root? string
---@return boolean
function M.uninstall_hooks(repo_root)
  if not ensure_setup() then
    return false
  end
  return hooks.uninstall(repo_root)
end

--- Statusline component. Returns "⚠ n" or "" for a given buffer.
---@param bufnr? integer
---@return string
function M.statusline(bufnr)
  if not config.values then
    return ""
  end
  local buf = bufnr or vim.api.nvim_get_current_buf()
  local n = diagnostics.count(buf)
  if n == 0 then
    return ""
  end
  return string.format("⚠ %d secret%s", n, n == 1 and "" or "s")
end

-- Commands
vim.api.nvim_create_user_command("SecretScannerScan", function()
  M.scan()
end, { desc = "Scan current buffer for secrets" })

vim.api.nvim_create_user_command("SecretScannerScanStaged", function()
  M.scan_staged()
end, { desc = "Scan staged diff for secrets" })

vim.api.nvim_create_user_command("SecretScannerScanRepo", function()
  M.scan_repo()
end, { desc = "Scan full repo for secrets (opt-in)" })

vim.api.nvim_create_user_command("SecretScannerScanProject", function()
  M.scan_project()
end, { desc = "Scan whole project working tree for secrets (opt-in)" })

vim.api.nvim_create_user_command("SecretScannerInstallHooks", function()
  M.install_hooks()
end, { desc = "Install git pre-commit hook" })

vim.api.nvim_create_user_command("SecretScannerUninstallHooks", function()
  M.uninstall_hooks()
end, { desc = "Uninstall git hooks" })

return M
