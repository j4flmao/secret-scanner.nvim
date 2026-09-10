local config = require("secret-scanner.config")
local allowlist = require("secret-scanner.allowlist")
local parser = require("secret-scanner.engine.parser")

config.setup({ allowlist_file = ".secretscannerignore" })

local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, "p")
local repo = tmpdir .. "/r"
vim.fn.mkdir(repo, "p")

local function write_lines(path, lines)
  vim.fn.writefile(lines, path)
end

local function clear_ignore(repo_root)
  local path = repo_root .. "/.secretscannerignore"
  if vim.fn.filereadable(path) == 1 then
    vim.fn.delete(path)
  end
end

describe("allowlist", function()
  before_each(function()
    clear_ignore(repo)
  end)

  it("load returns an empty set when no ignore file", function()
    assert.same({}, allowlist.load(repo))
  end)

  it("load ignores blank lines and comments", function()
    write_lines(repo .. "/.secretscannerignore", {
      "# this is a comment",
      "",
      "config.py:aws-access-key",
      " .env:github-pat ",
    })
    local set = allowlist.load(repo)
    assert.is_true(set["config.py:aws-access-key"])
    assert.is_true(set[".env:github-pat"])
    assert.is_nil(set["# this is a comment"])
  end)

  it("is_allowed matches file:rule entries", function()
    local finding = { file = "config.py", rule_id = "aws-access-key" }
    assert.is_true(allowlist.is_allowed(finding, { ["config.py:aws-access-key"] = true }))
    assert.is_false(allowlist.is_allowed(finding, {}))
  end)

  it("is_allowed matches granular secret-hash entries", function()
    local finding =
      parser.parse(vim.json.encode({ { File = "x.yml", RuleID = "generic", Secret = "tok_secret_123" } }))[1]
    local sha8 = finding.secret_hash:sub(1, 8)
    assert.is_true(allowlist.is_allowed(finding, { ["x.yml:generic:" .. sha8] = true }))
    assert.is_false(allowlist.is_allowed(finding, { ["x.yml:generic:deadbeef"] = true }))
  end)

  it("is_inline_ignored detects the marker", function()
    assert.is_true(allowlist.is_inline_ignored("-- secret-scanner:ignore"))
    assert.is_true(allowlist.is_inline_ignored("x = 1 -- secret-scanner:ignore then more"))
    assert.is_false(allowlist.is_inline_ignored("x = 1"))
    assert.is_false(allowlist.is_inline_ignored(nil))
  end)

  it("add appends an entry and returns the key", function()
    local finding = parser.parse(vim.json.encode({ { File = "a.py", RuleID = "r", Secret = "abc123" } }))[1]
    local key, added = allowlist.add(repo, finding)
    assert.is_true(added)
    assert.is_equal("a.py:r:" .. finding.secret_hash:sub(1, 8), key)

    local content = vim.fn.readfile(repo .. "/.secretscannerignore")
    assert.same({ key }, content)
  end)

  it("add is idempotent", function()
    local finding = parser.parse(vim.json.encode({ { File = "a.py", RuleID = "r", Secret = "abc123" } }))[1]
    allowlist.add(repo, finding)
    local key, added = allowlist.add(repo, finding)
    assert.is_false(added)
    assert.equal(1, #vim.fn.readfile(repo .. "/.secretscannerignore"))
  end)

  it("filter drops allowlisted and inline-ignored findings only", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "line one",
      "key = AKIAIOSFODNN7EXAMPLE -- secret-scanner:ignore",
      "line three",
      "line four",
    })
    local entries = { ["b.txt:github-pat"] = true }
    local findings = {
      { line = 1, rule_id = "aws-access-key" },
      { line = 2, rule_id = "aws-access-key" },
      { line = 3, rule_id = "github-pat" },
      { line = 4, rule_id = "aws-access-key" },
    }
    findings[3].file = "b.txt"
    local result = allowlist.filter(findings, entries, bufnr)
    local lines = {}
    for _, f in ipairs(result) do
      table.insert(lines, f.line)
    end
    assert.same({ 1, 4 }, lines)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
