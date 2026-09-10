local config = require("secret-scanner.config")
local hooks = require("secret-scanner.git.hooks")

local MARKER = "# MANAGED BY secret-scanner.nvim -- do not edit"

local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, "p")
local repo = tmpdir .. "/repo"
vim.fn.mkdir(repo, "p")
vim.system({ "git", "init", "-q" }, { cwd = repo }):wait()
vim
  .system(
    { "git", "-c", "user.email=test@example.com", "-c", "user.name=Test", "commit", "--allow-empty", "-m", "init" },
    { cwd = repo }
  )
  :wait()

local function git(args)
  return vim.system(args, { text = true, cwd = repo }):wait()
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

describe("git/hooks", function()
  it("fails cleanly outside a git repo", function()
    local non_repo = tmpdir .. "/nonrepo"
    vim.fn.mkdir(non_repo, "p")
    local ok, err = hooks.hooks_dir(non_repo)
    assert.is_nil(ok)
    assert.is_not_nil(err)
  end)

  it("installs a pre-commit hook with the marker", function()
    config.setup({ block_commit_on_finding = true, gitleaks_path = "/bin/true", pre_push_hook = false })
    assert.is_true(hooks.install(repo))

    local hook = read_file(repo .. "/.git/hooks/pre-commit")
    assert.is_not_nil(hook)
    assert.is_true(hook:find(MARKER, 1, true) ~= nil)
    assert.is_true(hook:find("gitleaks", 1, true) ~= nil)
    assert.is_true(hook:find("--pre-commit", 1, true) ~= nil)
    assert.is_true(hook:find("--staged", 1, true) ~= nil)
    assert.is_true(hook:find('exit "$status"', 1, true) ~= nil)
  end)

  it("bakes an extended custom config with a fallback into the hook", function()
    local custom = tmpdir .. "/custom.toml"
    vim.fn.writefile({ "[[rules]]", 'id = "my-rule"', "regex = '''abc'''" }, custom, "")

    config.setup({
      block_commit_on_finding = true,
      gitleaks_path = "/bin/true",
      pre_push_hook = false,
      custom_config_path = custom,
    })
    assert.is_true(hooks.install(repo))

    local hook = read_file(repo .. "/.git/hooks/pre-commit")
    assert.is_not_nil(hook)
    assert.is_true(hook:find('CONFIG="', 1, true) ~= nil, "derived config path is baked in")
    assert.is_true(hook:find('--config "$CONFIG"', 1, true) ~= nil, "hook uses the resolved config")
    assert.is_true(
      hook:find('if [ ! -r "$CONFIG" ] && [ -r "' .. custom .. '" ]; then', 1, true) ~= nil,
      "hook falls back to the original file when the cache is cleared"
    )

    config.setup({ block_commit_on_finding = true, gitleaks_path = "/bin/true", pre_push_hook = false })
    assert.is_true(hooks.install(repo))
  end)

  it("backs up and chains an existing hook", function()
    vim.fn.writefile({ "#!/bin/sh", "echo legacy-ran", "exit 0" }, repo .. "/.git/hooks/precommit-legacy", "")
    vim.fn.writefile({ "#!/bin/sh", "echo legacy-ran", "exit 0" }, repo .. "/.git/hooks/pre-commit", "")
    vim.fn.delete(repo .. "/.git/hooks/pre-commit~legacy")

    assert.is_true(hooks.install(repo))

    local legacy = read_file(repo .. "/.git/hooks/pre-commit~legacy")
    assert.is_not_nil(legacy)
    assert.is_true(legacy:find("legacy-ran", 1, true) ~= nil)

    local hook = read_file(repo .. "/.git/hooks/pre-commit")
    assert.is_true(hook:find("pre-commit~legacy", 1, true) ~= nil)
    assert.is_true(hook:find("legacy_status", 1, true) ~= nil)
    assert.is_true(hook:find(MARKER, 1, true) ~= nil)
  end)

  it("replaces a previously-managed hook without double backup", function()
    assert.is_true(hooks.install(repo))
    assert.is_true(hooks.install(repo))

    local legacy = read_file(repo .. "/.git/hooks/pre-commit~legacy")
    assert.is_not_nil(legacy)
    assert.is_true(legacy:find("legacy-ran", 1, true) ~= nil)
  end)

  it("installs pre-push when enabled", function()
    config.setup({ pre_push_hook = true, gitleaks_path = "/bin/true" })
    assert.is_true(hooks.install(repo))
    local push = read_file(repo .. "/.git/hooks/pre-push")
    assert.is_not_nil(push)
    assert.is_true(push:find("--pre-push", 1, true) ~= nil)
  end)

  it("warn mode never blocks", function()
    config.setup({ block_commit_on_finding = false, gitleaks_path = "/bin/true" })
    assert.is_true(hooks.install(repo))
    local hook = read_file(repo .. "/.git/hooks/pre-commit")
    assert.is_not_nil(hook)
    assert.is_true(hook:find('exit "$status"', 1, true) == nil)
    assert.is_true(hook:find("exit 0", 1, true) ~= nil)
  end)

  it("uninstall restores the legacy hook", function()
    config.setup({ block_commit_on_finding = true, gitleaks_path = "/bin/true" })
    assert.is_true(hooks.install(repo))
    assert.is_true(hooks.uninstall(repo))

    local restored = read_file(repo .. "/.git/hooks/pre-commit")
    assert.is_not_nil(restored)
    assert.is_true(restored:find("legacy-ran", 1, true) ~= nil)
    assert.is_true(restored:find(MARKER, 1, true) == nil)
  end)

  it("uninstall removes a hook with no legacy backup", function()
    vim.fn.delete(repo .. "/.git/hooks/pre-commit~legacy")
    vim.fn.delete(repo .. "/.git/hooks/pre-commit")
    assert.is_true(hooks.install(repo))
    assert.is_true(hooks.uninstall(repo))
    assert.is_true(vim.fn.filereadable(repo .. "/.git/hooks/pre-commit") == 0)
  end)
end)
