local M = {}

local config = require("secret-scanner.config")
local gitleaks = require("secret-scanner.engine.gitleaks")
local diagnostics = require("secret-scanner.ui.diagnostics")
local allowlist = require("secret-scanner.allowlist")

local buffered_timers = {}

--- Compare two finding lists for equality (ignores order).
---@param a table[]
---@param b table[]
---@return boolean
local function findings_equal(a, b)
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    local fa, fb = a[i], b[i]
    if fa.line ~= fb.line or fa.rule_id ~= fb.rule_id or fa.secret_masked ~= fb.secret_masked then
      return false
    end
  end
  return true
end

M.findings_equal = findings_equal

--- Run a scan for a specific buffer and publish diagnostics.
---@param bufnr integer
function M.scan_buffer_nr(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if vim.b[bufnr].secret_scanner_enabled == false then
    return
  end
  -- Unnamed buffers (e.g. `:enew`) have no path to key allowlists on, and
  -- fnamemodify("") raises E32, so skip them entirely.
  if vim.api.nvim_buf_get_name(bufnr) == "" then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = table.concat(lines, "\n")
  local filetype = vim.bo[bufnr].filetype

  gitleaks.scan_stdin(text, filetype, function(findings, err)
    if err then
      vim.notify(string.format("[secret-scanner] %s", err), vim.log.levels.ERROR)
      return
    end

    -- stdin scans report File as "stdin"; use the buffer's relative path so
    -- allowlist entries keyed on file paths line up.
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    local rel = vim.fn.fnamemodify(bufname, ":.")
    if rel ~= "" then
      for _, f in ipairs(findings) do
        f.file = rel
      end
    end

    local repo_root = vim.fn.getcwd()
    local allowlist_entries = allowlist.load(repo_root)
    local filtered = allowlist.filter(findings, allowlist_entries, bufnr)

    local prev = diagnostics.get_findings(bufnr)
    diagnostics.publish(bufnr, filtered)

    if #prev ~= #filtered then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= "" then
        local short = vim.fn.fnamemodify(name, ":t")
        if #filtered > 0 then
          vim.notify(string.format("[secret-scanner] found %d secret(s) in %s", #filtered, short), vim.log.levels.WARN)
        else
          vim.notify(string.format("[secret-scanner] no secrets found in %s", short), vim.log.levels.INFO)
        end
      end
    end
  end)
end

--- Scan the current buffer.
function M.scan_buffer()
  M.scan_buffer_nr(vim.api.nvim_get_current_buf())
end

--- Debounce a scan for a buffer by `delay` ms.
---@param bufnr integer
---@param delay integer
local function schedule_scan(bufnr, delay)
  local timer = buffered_timers[bufnr]
  if timer then
    timer:stop()
    timer:close()
  end
  timer = vim.uv.new_timer()
  buffered_timers[bufnr] = timer
  timer:start(
    delay,
    0,
    vim.schedule_wrap(function()
      if buffered_timers[bufnr] == timer then
        buffered_timers[bufnr] = nil
      end
      timer:close()
      M.scan_buffer_nr(bufnr)
    end)
  )
end

--- Register autocmds for save/text-change triggered scans.
function M.setup()
  local cfg = config.get()
  local group = vim.api.nvim_create_augroup("secret-scanner", { clear = true })

  if cfg.scan_on_save then
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = group,
      pattern = "*",
      callback = function(args)
        schedule_scan(args.buf, cfg.debounce_ms)
      end,
    })
  end

  if cfg.scan_on_text_change then
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      group = group,
      pattern = "*",
      callback = function(args)
        schedule_scan(args.buf, cfg.text_change_debounce_ms)
      end,
    })
  end
end

--- Cancel any pending debounced scan for a buffer.
---@param bufnr integer
function M.cancel_pending(bufnr)
  local timer = buffered_timers[bufnr]
  if timer then
    timer:stop()
    timer:close()
    buffered_timers[bufnr] = nil
  end
end

return M
