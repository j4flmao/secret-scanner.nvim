local config = require("secret-scanner.config")
config.setup({
  severity = {
    default = vim.diagnostic.severity.WARN,
    rules = {
      ["noisy-rule"] = vim.diagnostic.severity.INFO,
    },
  },
})

local diagnostics = require("secret-scanner.ui.diagnostics")
local buffer = require("secret-scanner.scan.buffer")

describe("ui/diagnostics", function()
  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
  end)

  after_each(function()
    diagnostics.clear(bufnr)
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("publishes findings as native diagnostics", function()
    diagnostics.publish(bufnr, {
      {
        line = 1,
        end_line = 1,
        col = 1,
        end_col = 5,
        rule_id = "aws-key",
        description = "found",
        severity = vim.diagnostic.severity.ERROR,
      },
    })
    local result = vim.diagnostic.get(bufnr, { namespace = diagnostics.namespace() })
    assert.equal(1, #result)
    assert.equal("secret-scanner", result[1].source)
    assert.equal(0, result[1].lnum)
  end)

  it("clears diagnostics", function()
    diagnostics.publish(bufnr, {
      { line = 1, rule_id = "x", description = "y", severity = vim.diagnostic.severity.ERROR },
    })
    assert.equal(1, #vim.diagnostic.get(bufnr, { namespace = diagnostics.namespace() }))
    diagnostics.clear(bufnr)
    assert.equal(0, #vim.diagnostic.get(bufnr, { namespace = diagnostics.namespace() }))
  end)

  it("tracks findings per buffer", function()
    local finding = { line = 2, rule_id = "k", description = "d", severity = vim.diagnostic.severity.WARN }
    diagnostics.publish(bufnr, { finding })
    local tracked = diagnostics.get_findings(bufnr)
    assert.equal(1, #tracked)
    assert.equal("k", tracked[1].rule_id)
  end)

  it("counts findings", function()
    diagnostics.publish(bufnr, {
      { line = 1, rule_id = "a", description = "d", severity = vim.diagnostic.severity.ERROR },
      { line = 2, rule_id = "b", description = "d", severity = vim.diagnostic.severity.WARN },
    })
    assert.equal(2, diagnostics.count(bufnr))
    assert.equal(1, diagnostics.count(bufnr, vim.diagnostic.severity.ERROR))
  end)

  it("applies per-rule severity override", function()
    diagnostics.publish(bufnr, {
      { line = 5, rule_id = "noisy-rule", description = "d", severity = vim.diagnostic.severity.ERROR },
    })
    local result = vim.diagnostic.get(bufnr, { namespace = diagnostics.namespace() })
    assert.equal(vim.diagnostic.severity.INFO, result[1].severity)
  end)
end)

describe("scan/buffer", function()
  it("findings_equal compares lists", function()
    local a = { { line = 1, rule_id = "x", secret_masked = "s" } }
    local b = { { line = 1, rule_id = "x", secret_masked = "s" } }
    local c = { { line = 2, rule_id = "x", secret_masked = "s" } }
    assert.is_true(buffer.findings_equal(a, b))
    assert.is_false(buffer.findings_equal(a, c))
    assert.is_false(buffer.findings_equal(a, {}))
  end)

  it("cancel_pending does not error on unknown buffer", function()
    assert.has_no.errors(function()
      buffer.cancel_pending(99999)
    end)
  end)

  it("skips unnamed buffers without raising E32", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "aws_secret_access_key = SOMELONGKEY" })
    assert.equal("", vim.api.nvim_buf_get_name(buf))
    assert.has_no.errors(function()
      buffer.scan_buffer_nr(buf)
    end)
    assert.equal(0, #diagnostics.get_findings(buf))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
