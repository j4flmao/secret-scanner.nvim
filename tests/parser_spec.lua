local parser = require("secret-scanner.engine.parser")

local fixtures_dir = "tests/fixtures"

local function read_fixture(name)
  local path = fixtures_dir .. "/" .. name
  local f = io.open(path, "r")
  if not f then
    error("fixture not found: " .. path)
  end
  local content = f:read("*a")
  f:close()
  return content
end

describe("engine/parser", function()
  local function is_all_stars(s)
    return s:match("^%*+$") ~= nil
  end

  describe("mask_secret", function()
    it("masks short secrets fully", function()
      assert.equal("********", parser.mask_secret("abcdefgh"))
    end)

    it("masks empty string", function()
      assert.equal("", parser.mask_secret(""))
    end)

    it("masks nil", function()
      assert.equal("", parser.mask_secret(nil))
    end)

    it("preserves length and masks contents of long secrets", function()
      local secret = "AKIAIOSFODNN7EXAMPLE"
      local masked = parser.mask_secret(secret)
      assert.equal(#secret, #masked)
      assert.equal("AKIA", masked:sub(1, 4))
      assert.equal("LE", masked:sub(-2))
      assert.is_true(is_all_stars(masked:sub(5, -3)))
      assert.is_not.equal(secret, masked)
    end)

    it("preserves first 4 and last 2 chars for long secrets", function()
      local secret = "sk-proj-abcdefghijklmnopqrstuvwxyz1234"
      local masked = parser.mask_secret(secret)
      assert.equal(#secret, #masked)
      assert.equal("sk-p", masked:sub(1, 4))
      assert.equal("34", masked:sub(-2))
      assert.is_true(is_all_stars(masked:sub(5, -3)))
    end)
  end)

  describe("parse", function()
    it("returns empty table for nil input", function()
      local result = parser.parse(nil)
      assert.same({}, result)
    end)

    it("returns empty table for empty string", function()
      local result = parser.parse("")
      assert.same({}, result)
    end)

    it("returns empty table for empty JSON array", function()
      local json = read_fixture("gitleaks_empty.json")
      local result = parser.parse(json)
      assert.same({}, result)
    end)

    it("parses a single finding", function()
      local json = read_fixture("gitleaks_single.json")
      local result = parser.parse(json)
      assert.equal(1, #result)

      local f = result[1]
      assert.equal("config.py", f.file)
      assert.equal(12, f.line)
      assert.equal(12, f.end_line)
      assert.equal(21, f.col)
      assert.equal(42, f.end_col)
      assert.equal("aws-access-key", f.rule_id)
      assert.equal("AWS Access Key", f.description)
      local raw_secret = "AKIAIOSFODNN7EXAMPLE"
      assert.equal(raw_secret:sub(1, 4), f.secret_masked:sub(1, 4))
      assert.equal(raw_secret:sub(-2), f.secret_masked:sub(-2))
      assert.is_true(is_all_stars(f.secret_masked:sub(5, -3)))
      assert.is_not_nil(f.secret_hash)
      assert.equal(64, #f.secret_hash)
      assert.equal(vim.diagnostic.severity.ERROR, f.severity)
    end)

    it("parses multiple findings", function()
      local json = read_fixture("gitleaks_multiple.json")
      local result = parser.parse(json)
      assert.equal(3, #result)
      assert.equal("aws-access-key", result[1].rule_id)
      assert.equal("github-pat", result[2].rule_id)
      assert.equal("private-key", result[3].rule_id)
    end)

    it("handles malformed JSON gracefully", function()
      local json = read_fixture("gitleaks_malformed.json")
      local result = parser.parse(json)
      assert.same({}, result)
    end)

    it("handles partial entries with missing fields", function()
      local json = read_fixture("gitleaks_partial.json")
      local result = parser.parse(json)
      assert.equal(2, #result)

      assert.equal("config.py", result[1].file)
      assert.equal(12, result[1].line)
      assert.equal("aws-access-key", result[1].rule_id)

      assert.equal("partial.txt", result[2].file)
      assert.equal(0, result[2].line)
      assert.equal("unknown", result[2].rule_id)
    end)

    it("maps severity correctly", function()
      local json = read_fixture("gitleaks_multiple.json")
      local result = parser.parse(json)
      assert.equal(vim.diagnostic.severity.ERROR, result[1].severity) -- high
      assert.equal(vim.diagnostic.severity.ERROR, result[2].severity) -- high
      assert.equal(vim.diagnostic.severity.ERROR, result[3].severity) -- critical
    end)

    it("masks secrets in output", function()
      local json = read_fixture("gitleaks_long_secret.json")
      local result = parser.parse(json)
      assert.equal(1, #result)
      local raw = "sk-proj-abcdefghijklmnopqrstuvwxyz1234567890abcdefghijklmnop"
      assert.is_not.equal(raw, result[1].secret_masked)
      assert.equal(#raw, #result[1].secret_masked)
      assert.equal(raw:sub(1, 4), result[1].secret_masked:sub(1, 4))
      assert.equal(raw:sub(-2), result[1].secret_masked:sub(-2))
      assert.is_true(is_all_stars(result[1].secret_masked:sub(5, -3)))
    end)

    it("handles non-table array entries", function()
      local result = parser.parse('[1, "string", null, true]')
      assert.same({}, result)
    end)
  end)
end)
