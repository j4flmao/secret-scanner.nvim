# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
via git tags.

## [Unreleased]

### Added

- `examples/` reference configs: Spring Boot and Go, covering their typical
  false positives plus a team `gitleaks.extend.toml`.
- Project-local config (`.secretscanner.lua`) merged at scan time, invalidated
  on file change; `override_default_rules` for replace-mode merging.
- Allowlist workflow: `.secretscannerignore` entries (`file:rule` and the more
  precise `file:rule:sha8` secret fingerprint), inline `secret-scanner:ignore`
  marker, and the `<leader>sa` keymap that writes entries for you.
- Custom gitleaks rulesets: `custom_config_path` now **extends** the embedded
  defaults via `[extend] useDefault = true` by default; the derived config is
  materialized under the cache dir and hooks fall back to the committed file if
  the cache is cleared.
- Full-repo scan (`:SecretScannerScanRepo`) — scans history, filters the
  allowlist, and fills the quickfix list.
- Per-rule severity overrides (`severity.rules`).
- Broadened the allowlist health/validation checks (`:checkhealth` reports an
  unreadable `custom_config_path`).
- Bundled extended ruleset (`rules/secret-scanner.extend.toml`, enabled by
  default via `bundled_rules`): catches formats missing from gitleaks' embedded
  defaults — JWT tokens and signing secrets, GitHub/GitLab PATs, Slack,
  Telegram and SendGrid keys, embedded private keys, URI credentials, an
  AWS secret-access-key matcher, and a keyword-scoped high-entropy catch-all.
- `:SecretScannerScanStaged` explains that the scan needs a first commit when
  the repo has no HEAD yet, instead of reporting a misleading all-clear.
- Whole-project scan (`:SecretScannerScanProject` / `<leader>sp`) — `gitleaks
  dir` over the git root, covering tracked, modified, and untracked files;
  honors `.gitignore` so dependency trees are skipped. Findings land in the
  quickfix list alongside the existing repo-history scan.
- Widen URI credential detection to all common connection strings (mysql,
  mariadb, mongodb+srv, redis, amqp, sqlserver, ...), empty-user credentials
  (`redis://:pass@host`), JDBC URLs, plus an allowlist for `${ENV}`-style
  templates — so different database URLs are caught without flagging
  placeholders.
- .NET/.NET Core coverage: ADO.NET connection strings
  (`Server=...;User Id=...;Password=...` in `appsettings.json`/`web.config`),
  secret-like keys in JSON configs (`"ClientSecret": ...`,
  `"Password": ...`) via a colon-aware rule with a `secretGroup` so entropy is
  judged on the value only, `"Jwt": { "Key": ... }` blocks, and XML
  `<add key="..." value="..."/>` entries in `.config` files.
- Java/JSP & servlet coverage: sensitive elements
  (`<password>...</password>`, Jenkins `credentials.xml`), web.xml
  `param-name`/`param-value` pairs, Tomcat `context.xml` `name=... value=...`
  attributes, and hardcoded `String apiToken = "..."` in JSP/Java source.
- Broad configuration scanning: colon-form secrets in YAML/TOML-style configs
  (`password: ...` in `application.yml`, `values.yaml`, compose env), short
  `KEY=value` secret assignments (`dotenv`, `.properties`, `.npmrc`), a
  strict-placeholder allowlist (`${ENV}`, `${{ secrets.X }}`, masked/from-vault
  values), HashiCorp Vault tokens (`hvs./hvb./hvr.`), `.netrc` machine
  passwords, Kubernetes `Secret` `stringData` blocks, and hardcoded CI/CD
  pipeline variables.
- Skip unnamed buffers in buffer scans — scanning `:enew`-style buffers
  previously raised "E32: No file name" from `fnamemodify("")`.
- `:SecretScannerScanStaged` / `:SecretScannerScanRepo` now detect a non-git
  directory up front and point at the buffer/folder scans instead of surfacing
  gitleaks' raw "not a git repository" stderr.

### Changed

- Buffer scans run `gitleaks dir` over a temp file with `--report-path -`
  instead of streamed stdin — streamed scans are unreliable when Neovim's
  stdin-pipe EOF handling is broken (Windows) and `detect --no-git --pipe`
  regressed to scanning the cwd on some versions (gitleaks#2054).
- Staged-diff scans now use the `git --pre-commit --staged` subcommand
  (requires gitleaks >= 8.19) instead of the deprecated `detect --source .`,
  which previously scanned the whole working tree.
- CI installs the latest gitleaks release, asserting `>= 8.19`.
- Findings carry a `secret_hash` (SHA-256 of the raw secret) to keep allowlist
  entries stable across unrelated file edits.

### Fixed

- `setup({ custom_config_path = ... })` was rejected as "unknown config key"
  because a `nil` default removes the key from the defaults table; it is now
  explicitly registered as valid.
- Project-config cache now keys on mtime nsec + size, so edits landing in the
  same wall-clock second are still picked up.

## [0.1.0] - 2026-09-10

### Added

- Foundation (repo layout, `setup()`, health check, CI, Makefile).
- Detection core: async gitleaks wrapping, JSON parsing, secret masking.
- In-buffer UX: diagnostics, virtual text, signs, floating detail window,
  statusline, `<leader>ss`.
- Git hooks: install/uninstall with legacy-hook backup & chaining, block and
  warn modes, standalone POSIX scripts with no Neovim dependency.
- Custom gitleaks config path baked into installed hooks.