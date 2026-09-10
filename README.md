# secret-scanner.nvim

> Catch secrets in your editor — before they're in your git history.

Badges:
[![CI](https://img.shields.io/github/actions/workflow/status/j4flmao/secret-scanner.nvim/ci.yml?branch=main&label=CI)](https://github.com/j4flmao/secret-scanner.nvim/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Powered by gitleaks](https://img.shields.io/badge/detection%20engine-gitleaks-000000?logo=git)](https://github.com/gitleaks/gitleaks)

---

<!--
  TODO: add the demo GIF here, within the first screen-height.
  Show: typing a fake access key -> diagnostic appears inline -> :g commit
  attempt blocked in the terminal by the installed hook.
-->

Developers leak API keys, tokens, and passwords into git history every day —
not because they don't know better, but because nothing warns them *inside the
editor, before the commit happens*. `gitleaks` and friends catch secrets fine,
but they live *outside* the editor: you find out the hard way on `git push`, in
CI, or after the incident.

secret-scanner.nvim puts the detection exactly where you're already looking —
**in the buffer, on the line, under your cursor** — and blocks the leak at the
two moments that matter: `git commit` and `git push`.

```text
function deploy() {
  const key = "AKIAIOSFODNN7EXAMPLE"   -- ⚠ secret detected · press <leader>sa to allowlist
                                                      │
        <leader>ss to scan                      <leader>sa to allowlist
```

## Features

- **Inline diagnostics as you save** — findings render as native Neovim
  diagnostics (virtual text + sign column) the moment you `:w`.
- **Optional live scanning** — `scan_on_text_change = true` re-scans while you
  type, debounced.
- **Pre-commit + pre-push blocks** — installs a standalone git hook (no Neovim
  needed at commit time) that blocks leaking commits from *any* terminal.
- **Full repo scan** — scan commit history and jump through findings in the
  quickfix list (`:SecretScannerScanRepo`).
- **Whole-project scan** — scan every file in the working tree, tracked or not
  (`.gitignore`d dependency trees skipped), with `<leader>sp` /
  `:SecretScannerScanProject`.
- **Broad detection** — JWT, GitHub/GitLab tokens, private keys, connection
  strings (postgres/mysql/mongo/redis/jdbc...), and more, out of the box.
- **False-positive workflow** — `<leader>sa` allowlists a finding into
  `.secretscannerignore` (a reviewable diff), or drop a `secret-scanner:ignore`
  comment on the line.
- **Team-policy config** — a committed `.secretscanner.lua` overrides personal
  config, and `custom_config_path` **extends** gitleaks' rules with your
  company's secret formats.
- **Never blocks the editor** — scans run async via `vim.system`; secrets are
  masked in the UI and never printed in full.

## Install

Requires Neovim >= 0.10 and [gitleaks](https://github.com/gitleaks/gitleaks) ≥ 8.19 on `PATH`.

[lazy.nvim](https://github.com/folke/lazy.nvim):
```lua
{ "j4flmao/secret-scanner.nvim", build = false, opts = {} }
```

[packer.nvim](https://github.com/wbthomason/packer.nvim):
```lua
use { "j4flmao/secret-scanner.nvim", requires = {} }
```

Native [vim.pack](https://neovim.io/doc/user/repeat.html#packages):
```sh
mkdir -p ~/.local/share/nvim/site/pack/plugins/start
git clone https://github.com/j4flmao/secret-scanner.nvim ~/.local/share/nvim/site/pack/plugins/start/secret-scanner.nvim
```

## Quick start

```lua
require("secret-scanner").setup()
```

That's it — buffer scans are on by default. Then, once per repo:

```
:SecretScannerInstallHooks
```

and from then on, leaked secrets **cannot be committed** from any terminal.

| Key | Action |
|---|---|
| `<leader>ss` | Scan current buffer |
| `<leader>sp` | Scan the whole project working tree → quickfix list |
| `<leader>sa` | Allowlist the finding under the cursor + rescan |

| Command | Action |
|---|---|
| `:SecretScannerScan` | Scan current buffer |
| `:SecretScannerScanStaged` | Scan staged changes |
| `:SecretScannerScanRepo` | Scan full history → quickfix list |
| `:SecretScannerScanProject` | Scan whole project incl. untracked files → quickfix list |
| `:SecretScannerInstallHooks` | Install pre-commit (and pre-push) hooks |
| `:SecretScannerUninstallHooks` | Remove hooks, restoring any legacy hook |

## Configuration

```lua
require("secret-scanner").setup({
  scan_on_save = true,        -- scan on BufWritePost
  scan_on_text_change = false,-- scan while typing (debounced)
  block_commit_on_finding = true, -- block commits? or just warn
  pre_push_hook = false,      -- also guard `git push`
  bundled_rules = true,       -- extra rules for JWT/GitHub PAT/private keys/... (see below)
  custom_config_path = nil,   -- extend/replace gitleaks rules (see below)
  severity = {
    rules = { ["generic-api-key"] = vim.diagnostic.severity.INFO },
  },
  ui = {
    virtual_text = true,
    signs = true,
    float_on_cursor_hold = true,
  },
})
```

Full reference: `:h secret-scanner`.

### Bundled extended rules

By default the plugin layers a shipped ruleset on top of gitleaks' embedded
defaults, so common formats that upstream misses are still caught — JWT tokens,
JWT signing secrets in `.env` (`JWT_SECRET=...`) and in `.NET` appsettings JSON
(`"Jwt": { "Key": ... }`), GitHub tokens (`ghp_...` / `github_pat_...`), GitLab
PATs, Slack tokens, Telegram/SendGrid keys, embedded private keys
(`-----BEGIN ... PRIVATE KEY-----`), credentials in URL connection strings
(`postgres://user:pass@...`), ADO.NET/`web.config` connection strings
(`Server=...;Password=...`), secret-like keys in `.json`/`.config`
(`"ClientSecret": ...`, `<add key="..." value="..."/>`), Java/JSP & servlet
credentials (web.xml `param-name/param-value`, Tomcat context.xml
`name=... value=...`, `<password>...</password>`, hardcoded `String ... =
"..."`), YAML/.properties/`KEY=value` secrets (`password: ...`,
`MY_TOKEN=...`), HashiCorp Vault tokens (`hvs.`), `.netrc` machine passwords,
Kubernetes `Secret` `stringData` blocks, hardcoded CI/CD pipeline variables,
and a keyword-scoped, high-entropy catch-all for unknown secret formats. Set
`bundled_rules = false` to use only gitleaks' native rules.

### Team rules & merge strategy

A `custom_config_path` gitleaks `.toml` **extends** the effective ruleset by
default (via `[extend] useDefault = true`) — add your internal API key formats
without losing upstream or bundled coverage. Set `override_default_rules = true`
to fully replace them. See `:h secret-scanner-merging` and the `examples/`
directory for ready-to-adapt Spring Boot and Go setups.

### False positives

Two ways to silence one:

1. **Inline, reviewable in code:**
   ```lua
   local key = "AKIAIOSFODNN7EXAMPLE" -- secret-scanner:ignore
   ```
2. **Repo-wide, in `.secretscannerignore`:**
   ```
   testdata/fixtures/aws.json:aws-access-key
   ```
   ...or press `<leader>sa` on the finding and it's written for you.

## Comparisons

- **gitleaks CLI**: keep using it for CI. secret-scanner.nvim is the in-editor
  layer; you're not choosing between them.
- **Other editor gitleaks integrations**: most push a floating window or a
  separate pane. We push into native diagnostics + block at the hook level,
  where the leak actually happens.

## Status & roadmap

- Phases 1–6 of the plan (see `ARCHITECTURE.md`) are implemented: foundation,
  detection core, in-buffer UX, git hooks, extensibility, and this launch
  surface. 64 tests across 8 suites, CI on stable + nightly Neovim.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — especially if you want to add a
`examples/` config for your stack, or help tune noisy rules.

## License

MIT — see [LICENSE](LICENSE).

Detection engine: [gitleaks](https://github.com/gitleaks/gitleaks), MIT. If you
find the plugin useful, [star gitleaks too](https://github.com/gitleaks/gitleaks).