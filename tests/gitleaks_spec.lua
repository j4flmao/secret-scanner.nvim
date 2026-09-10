local config = require("secret-scanner.config")

-- Set up config before requiring gitleaks module
config.setup({
  gitleaks_path = "gitleaks",
  timeout = 5000,
})

describe("engine/gitleaks", function()
  describe("build commands", function()
    it("resolves gitleaks path", function()
      local gitleaks = require("secret-scanner.engine.gitleaks")
      local available, _ = gitleaks.check()
      -- Will be false in CI without gitleaks, true locally
      assert.is_boolean(available)
    end)
  end)

  describe("project_root", function()
    it("falls back to the current directory outside a git repo", function()
      local gitleaks = require("secret-scanner.engine.gitleaks")
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")
      assert.equal(tmp, gitleaks.project_root(tmp))
    end)

    it("resolves to the git top-level inside a repo", function()
      local gitleaks = require("secret-scanner.engine.gitleaks")
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")
      local ok = pcall(function()
        vim.fn.system({ "git", "-C", tmp, "init", "-q" })
        assert.equal(0, vim.v.shell_error, "git init failed; git not available?")
      end)
      if ok then
        -- git reports the real path, so follow symlinks too (macOS /var -> /private/var)
        local real = vim.loop.fs_realpath(tmp)
        local want = (real or tmp):gsub("\\", "/"):gsub("/+$", "")
        assert.equal(want, gitleaks.project_root(tmp))
      end
    end)
  end)

  describe("is_git_repo", function()
    it("is false outside a git repo", function()
      local gitleaks = require("secret-scanner.engine.gitleaks")
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")
      assert.is_false(gitleaks.is_git_repo(tmp))
    end)

    it("is true inside a git repo", function()
      local gitleaks = require("secret-scanner.engine.gitleaks")
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")
      local ok = pcall(function()
        vim.fn.system({ "git", "-C", tmp, "init", "-q" })
        assert.equal(0, vim.v.shell_error, "git init failed; git not available?")
      end)
      if ok then
        assert.is_true(gitleaks.is_git_repo(tmp))
      end
    end)
  end)

  describe("effective_config_path", function()
    local tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
    local custom = tmpdir .. "/custom.toml"

    before_each(function()
      vim.fn.writefile({ "# team rules", "[[rules]]", 'id = "my-rule"', "regex = '''abc'''" }, custom, "")
      require("secret-scanner.config").setup({ gitleaks_path = "gitleaks" })
    end)

    it("extends gitleaks defaults with the bundled ruleset by default", function()
      local gitleaks = require("secret-scanner.engine.gitleaks")
      local path, err = gitleaks.effective_config_path()
      assert.is_nil(err)
      assert.is_not_nil(path)
      assert.is_true(vim.fn.filereadable(path) == 1)

      local content = table.concat(vim.fn.readfile(path), "\n")
      assert.is_true(content:find("[extend]", 1, true) ~= nil)
      assert.is_nil(content:find("useDefault = true", 1, true))
      assert.is_true(content:find('path = "', 1, true) ~= nil)
      assert.is_true(content:find("rules/secret-scanner.extend.toml", 1, true) ~= nil)
      vim.uv.fs_unlink(path)
    end)

    it("returns nil when the bundled ruleset is disabled and no custom config is set", function()
      local gitleaks = require("secret-scanner.engine.gitleaks")
      config.setup({ gitleaks_path = "gitleaks", bundled_rules = false })
      local path, err = gitleaks.effective_config_path()
      assert.is_nil(path)
      assert.is_nil(err)
    end)

    it("passes the file through verbatim in replace mode", function()
      local gitleaks = require("secret-scanner.engine.gitleaks")
      config.setup({ gitleaks_path = "gitleaks", custom_config_path = custom, override_default_rules = true })
      local path, err = gitleaks.effective_config_path()
      assert.is_nil(err)
      assert.equal(custom, path)
    end)

    it("derives an extended config in extend mode without the bundled ruleset", function()
      local gitleaks = require("secret-scanner.engine.gitleaks")
      config.setup({ gitleaks_path = "gitleaks", custom_config_path = custom, bundled_rules = false })
      local path, err = gitleaks.effective_config_path()
      assert.is_nil(err)
      assert.is_not_nil(path)
      assert.not_equal(custom, path)
      assert.is_true(vim.fn.filereadable(path) == 1)

      local content = table.concat(vim.fn.readfile(path), "\n")
      assert.is_true(content:find("[extend]", 1, true) ~= nil)
      assert.is_true(content:find("useDefault = true", 1, true) ~= nil)
      assert.is_true(content:find('id = "my-rule"', 1, true) ~= nil)
      vim.uv.fs_unlink(path)
    end)

    it("chains a derived config through the bundled ruleset when both are present", function()
      local gitleaks = require("secret-scanner.engine.gitleaks")
      config.setup({ gitleaks_path = "gitleaks", custom_config_path = custom })
      local path, err = gitleaks.effective_config_path()
      assert.is_nil(err)
      assert.is_not_nil(path)
      assert.is_true(vim.fn.filereadable(path) == 1)

      local content = table.concat(vim.fn.readfile(path), "\n")
      assert.is_true(content:find("[extend]", 1, true) ~= nil)
      assert.is_true(content:find('id = "my-rule"', 1, true) ~= nil)
      assert.is_true(content:find("rules/secret-scanner.extend.toml", 1, true) ~= nil)
      vim.uv.fs_unlink(path)
    end)

    it("exposes a readable bundled ruleset file that extends the defaults", function()
      local gitleaks = require("secret-scanner.engine.gitleaks")
      local rules = gitleaks.bundled_rules_path()
      assert.is_not_nil(rules)
      assert.is_true(vim.fn.filereadable(rules) == 1)
      local content = table.concat(vim.fn.readfile(rules), "\n")
      assert.is_true(content:find("[extend]", 1, true) ~= nil)
      assert.is_true(content:find("useDefault = true", 1, true) ~= nil)
      for _, id in ipairs({
        "jwt",
        "github-pat",
        "private-key",
        "generic-secret-assignment",
        "dotnet-adonet-connection-string",
        "json-secret-key-value",
        "jwt-key-json",
        "xml-key-value-secret",
        "xml-element-secret",
        "xml-name-value-credential",
        "xml-init-param-secret",
        "yaml-colon-secret",
        "env-assignment-secret",
        "java-inline-credentials",
        "vault-token",
        "netrc-password",
        "kubernetes-secret-stringdata",
      }) do
        assert.is_true(content:find('id = "' .. id .. '"', 1, true) ~= nil)
      end
    end)

    it("respects a user-defined [extend] section", function()
      vim.fn.writefile(
        { "# team rules", "[extend]", 'path = "../common.toml"', "[[rules]]", 'id = "my-rule"' },
        custom,
        ""
      )
      local gitleaks = require("secret-scanner.engine.gitleaks")
      config.setup({ gitleaks_path = "gitleaks", custom_config_path = custom })
      local path, err = gitleaks.effective_config_path()
      assert.is_nil(err)
      assert.equal(custom, path)
    end)

    it("reports an unreadable custom config", function()
      local gitleaks = require("secret-scanner.engine.gitleaks")
      config.setup({ gitleaks_path = "gitleaks", custom_config_path = tmpdir .. "/missing.toml" })
      local path, err = gitleaks.effective_config_path()
      assert.is_nil(path)
      assert.is_not_nil(err)
      assert.is_true(err:find("not readable", 1, true) ~= nil)
    end)
  end)

  describe("scan_stdin", function()
    it("returns error when gitleaks not found", function()
      config.setup({ gitleaks_path = "nonexistent-binary-12345" })
      local gitleaks = require("secret-scanner.engine.gitleaks")
      local callback_ok, callback_err
      gitleaks.scan_stdin("hello", "text", function(findings, err)
        callback_ok = findings
        callback_err = err
      end)
      assert.same({}, callback_ok)
      assert.is_not_nil(callback_err)
      -- Reset config
      config.setup({ gitleaks_path = "gitleaks" })
    end)

    it("handles empty input gracefully", function()
      config.setup({ gitleaks_path = "gitleaks" })
      local gitleaks = require("secret-scanner.engine.gitleaks")
      local callback_findings, callback_err
      local fired = false
      gitleaks.scan_stdin("", "text", function(findings, err)
        fired = true
        callback_findings = findings
        callback_err = err
      end)
      if gitleaks.check() then
        -- gitleaks installed: the scan completes asynchronously.
        assert(vim.wait(10000, function()
          return fired
        end))
      end
      assert.is_table(callback_findings)
    end)
  end)

  describe("scan_staged_diff", function()
    it("returns error when gitleaks not found", function()
      config.setup({ gitleaks_path = "nonexistent-binary-12345" })
      local gitleaks = require("secret-scanner.engine.gitleaks")
      local callback_ok, callback_err
      gitleaks.scan_staged_diff("/tmp", function(findings, err)
        callback_ok = findings
        callback_err = err
      end)
      assert.same({}, callback_ok)
      assert.is_not_nil(callback_err)
      config.setup({ gitleaks_path = "gitleaks" })
    end)
  end)

  describe("scan_repo", function()
    it("returns error when gitleaks not found", function()
      config.setup({ gitleaks_path = "nonexistent-binary-12345" })
      local gitleaks = require("secret-scanner.engine.gitleaks")
      local callback_ok, callback_err
      gitleaks.scan_repo("/tmp", function(findings, err)
        callback_ok = findings
        callback_err = err
      end)
      assert.same({}, callback_ok)
      assert.is_not_nil(callback_err)
      config.setup({ gitleaks_path = "gitleaks" })
    end)
  end)
end)
