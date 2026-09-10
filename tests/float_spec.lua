local config = require("secret-scanner.config")
config.setup()

local float = require("secret-scanner.ui.float")

describe("ui/float", function()
  local bufnr
  local win

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line one", "line two", "line three" })
    win = vim.api.nvim_open_win(bufnr, false, {
      relative = "editor",
      row = 0,
      col = 0,
      width = 20,
      height = 3,
    })
    vim.api.nvim_set_current_win(win)
  end)

  after_each(function()
    float.close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("does nothing when no finding at line", function()
    local diagnostics = require("secret-scanner.ui.diagnostics")
    diagnostics.clear(bufnr)
    assert.has_no.errors(function()
      float.show(bufnr, 1)
    end)
    assert.is_nil(float.win)
  end)

  it("opens a float when a finding covers the line", function()
    local diagnostics = require("secret-scanner.ui.diagnostics")
    diagnostics.publish(bufnr, {
      { line = 2, end_line = 2, rule_id = "gh-pat", description = "found", secret_masked = "ghp**12" },
    })
    float.show(bufnr, 2)
    assert.is_true(vim.api.nvim_win_is_valid(float.win))
  end)

  it("renders masked secret in the float content", function()
    local diagnostics = require("secret-scanner.ui.diagnostics")
    diagnostics.publish(bufnr, {
      { line = 2, end_line = 2, rule_id = "gh-pat", description = "found", secret_masked = "ghp**12" },
    })
    float.show(bufnr, 2)
    local contents = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(float.win), 0, -1, false)
    local joined = table.concat(contents, "\n")
    assert.is_true(joined:match("ghp%*%*12") ~= nil)
  end)
end)
