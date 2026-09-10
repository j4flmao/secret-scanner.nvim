# secret-scanner.nvim examples

Reference configs for common stacks. Each subdirectory is a self-contained
snapshot you can copy into a real repo's root:

| Directory      | Stack                               | Typical false positives handled |
| -------------- | ----------------------------------- | ------------------------------- |
| `spring-boot/` | Java / Spring Boot services         | `${PLACEHOLDER}` password refs, application.yml, test fixtures, `.env.example` |
| `go/`          | Go services & CLIs                  | `testdata/` fixtures, mock keys, docs/golden files, `.env.example` |

To use one, copy the files into your repo root and adjust the paths to match
your layout:

```
cp examples/spring-boot/.secretscanner.lua .
cp examples/spring-boot/.secretscannerignore .
```

## How the pieces work together

- `.secretscanner.lua` — team-wide plugin options, committed to the repo.
  Merged over each developer's personal config at scan time, so team policy
  wins without anyone hand-editing their `init.lua`.
- `.secretscannerignore` — allowlist entries in `<file>:<rule_id>` (or
  `<file>:<rule_id>:<sha8>` for one specific secret). Press `<leader>sa` on a
  finding to append an entry instead of hand-editing.
- `gitleaks.extend.toml` — team rule set that **extends** gitleaks' built-in
  rules via `[extend] useDefault = true`. Point `custom_config_path` at it and
  your team-specific secret formats (internal API key prefixes, etc.) are
  caught on top of the defaults.

## Merge strategy (extend vs replace)

- By default a custom config **extends** the embedded gitleaks rules — the
  config file is merged with the defaults through `[extend] useDefault = true`.
  New rules are added, and rules whose `id` matches a built-in one override it
  per-field while appending tags/keywords/allowlists.
- To **replace** the built-in rules entirely (e.g. a locked-down ruleset), set
  `override_default_rules = true` in the config. Use this carefully: it
  disables every rule not listed in your `custom_config_path`.

The plugin generates the extended config under Neovim's cache dir, so gitleaks
always reads a plain TOML file — no changes to your committed file are needed.

## Keep the noise down

A finding you decide is a false positive should only need one of two actions:

1. `<leader>sa` to allowlist it in `.secretscannerignore`, or
2. append `secret-scanner:ignore` to the offending line — visible in code
   review, using the same ergonomics as `-- luacheck: ignore`.