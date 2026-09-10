local M = {}

function M.check()
  M.start_group = vim.api.nvim_create_namespace("secret-scanner.health")

  -- Neovim version check
  local nvim_version = vim.version()
  if nvim_version.major > 0 or (nvim_version.major == 0 and nvim_version.minor >= 10) then
    vim.health.ok(string.format("Neovim version: %d.%d.%d", nvim_version.major, nvim_version.minor, nvim_version.patch))
  else
    vim.health.error(
      string.format(
        "Neovim version too old: %d.%d.%d (need >= 0.10.0)",
        nvim_version.major,
        nvim_version.minor,
        nvim_version.patch
      )
    )
  end

  -- gitleaks binary check
  local gitleaks_path = vim.fn.exepath("gitleaks")
  if gitleaks_path ~= "" then
    vim.health.ok("gitleaks found: " .. gitleaks_path)
    local version_output = vim.fn.system({ "gitleaks", "version" })
    if vim.v.shell_error == 0 then
      local version = version_output:gsub("%s+$", "")
      vim.health.ok("gitleaks version: " .. version)
    end
  else
    vim.health.error("gitleaks not found on PATH", {
      "Install gitleaks: https://github.com/gitleaks/gitleaks#installation",
      "  brew install gitleaks          # macOS",
      "  go install github.com/gitleaks/gitleaks/v8@latest  # Go",
      "  docker pull ghcr.io/gitleaks/gitleaks  # Docker",
    })
  end

  -- Config check
  local ok, config = pcall(require, "secret-scanner.config")
  if ok and config.values then
    vim.health.ok("Config loaded")
    local cfg = config.get()
    if cfg.custom_config_path then
      if vim.fn.filereadable(cfg.custom_config_path) == 1 then
        local _, err = require("secret-scanner.engine.gitleaks").effective_config_path()
        if err then
          vim.health.error(err)
        else
          local mode = cfg.override_default_rules and "replace" or "extend"
          vim.health.ok(string.format("custom_config_path (%s mode): %s", mode, cfg.custom_config_path))
        end
      else
        vim.health.error(
          "custom_config_path not found: " .. cfg.custom_config_path,
          { "Point custom_config_path at a readable gitleaks TOML file." }
        )
      end
    end

    if cfg.bundled_rules then
      local rules = require("secret-scanner.engine.gitleaks").bundled_rules_path()
      if rules then
        vim.health.ok("bundled_rules (extended ruleset): " .. rules)
      else
        vim.health.warn(
          "bundled_rules is enabled but rules/secret-scanner.extend.toml was not found;"
            .. " gitleaks will fall back to its embedded defaults"
        )
      end
    end
  else
    vim.health.warn("Config not initialized — call require('secret-scanner').setup() first")
  end
end

return M
