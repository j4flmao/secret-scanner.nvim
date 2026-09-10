return {
  scan_on_text_change = true,
  scan_on_save = true,
  debounce_ms = 150,
  text_change_debounce_ms = 1500,
  pre_push_hook = true,
  block_commit_on_finding = true,
  custom_config_path = vim.fn.getcwd() .. "/gitleaks.extend.toml",
  severity = {
    rules = {
      -- The generic rule fires on a lot of placeholder text in Spring
      -- config; make it visible without letting it block commits.
      ["generic-api-key"] = vim.diagnostic.severity.INFO,
    },
  },
}