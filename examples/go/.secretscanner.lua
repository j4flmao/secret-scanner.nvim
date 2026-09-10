return {
  scan_on_save = true,
  block_commit_on_finding = true,
  pre_push_hook = true,
  custom_config_path = vim.fn.getcwd() .. "/gitleaks.extend.toml",
  severity = {
    rules = {
      -- Generated/embedded-looking strings in Go hit generic rules often;
      -- keep them visible without blocking.
      ["generic-api-key"] = vim.diagnostic.severity.WARN,
    },
  },
}