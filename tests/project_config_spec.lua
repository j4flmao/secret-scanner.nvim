local config = require("secret-scanner.config")

config.setup({ gitleaks_path = "gitleaks", timeout = 111 })

local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, "p")

local function project_path(root)
  return root .. "/.secretscanner.lua"
end

describe("config.apply_project", function()
  before_each(function()
    local p = project_path(tmpdir)
    if vim.fn.filereadable(p) == 1 then
      vim.fn.delete(p)
    end
    config.setup({ gitleaks_path = "gitleaks", timeout = 111 })
  end)

  after_each(function()
    local p = project_path(tmpdir)
    if vim.fn.filereadable(p) == 1 then
      vim.fn.delete(p)
    end
    config.setup()
  end)

  it("leaves user config alone when no project file exists", function()
    local cfg = config.apply_project(tmpdir)
    assert.equal("gitleaks", cfg.gitleaks_path)
    assert.equal(111, cfg.timeout)
  end)

  it("merges project file over user config", function()
    vim.fn.writefile({ "return { timeout = 999, scan_on_save = false }" }, project_path(tmpdir))
    local cfg = config.apply_project(tmpdir)
    assert.equal(999, cfg.timeout)
    assert.is_false(cfg.scan_on_save)
    assert.equal("gitleaks", cfg.gitleaks_path)
  end)

  it("caches and refreshes when the file changes", function()
    vim.fn.writefile({ "return { timeout = 1 }" }, project_path(tmpdir))
    assert.equal(1, config.apply_project(tmpdir).timeout)
    assert.equal(1, config.apply_project(tmpdir).timeout)

    vim.uv.fs_utime(project_path(tmpdir), 1700000000, 1700000000)
    vim.fn.writefile({ "return { timeout = 2 }" }, project_path(tmpdir))
    assert.equal(2, config.apply_project(tmpdir).timeout)
  end)

  it("falls back to user config on invalid file", function()
    vim.fn.writefile({ "return { timeout = , broken" }, project_path(tmpdir))
    local cfg = config.apply_project(tmpdir)
    assert.equal(111, cfg.timeout)
  end)

  it("falls back when project file does not return a table", function()
    vim.fn.writefile({ "return 42" }, project_path(tmpdir))
    local cfg = config.apply_project(tmpdir)
    assert.equal(111, cfg.timeout)
  end)

  it("override_default_rules replaces user config with project values", function()
    config.setup({ gitleaks_path = "gitleaks", timeout = 111, override_default_rules = true })
    vim.fn.writefile({ "return { timeout = 999, gitleaks_path = 'gitx' }" }, project_path(tmpdir))
    local cfg = config.apply_project(tmpdir)
    assert.equal(999, cfg.timeout)
    assert.equal("gitx", cfg.gitleaks_path)
    assert.is_true(cfg.scan_on_save)
  end)
end)
