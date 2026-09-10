# KIT.md — Tech Stack & Tooling

## Language & Runtime

- **Lua (LuaJIT via Neovim's built-in runtime)** — 100% of plugin logic.
- **Neovim >= 0.10** as minimum supported version (need stable `vim.system`, introduced 0.10, for async external process calls — do NOT use the older `vim.loop`/`jobstart` API as the primary path, though a `jobstart` fallback path is acceptable for 0.9 support if we decide to extend backward compatibility later).
- No Rust/Go/C companion binary is written or shipped by this project. We are a pure-Lua *client* to an external tool.

## External Dependency (Required, User-Installed)

- **gitleaks** (Go binary, MIT licensed, actively maintained, ~20k+ stars) — the detection engine we shell out to. User installs it via their OS package manager / `go install` / release binary; we do not vendor or auto-install it in v1 (auto-install of a Go binary via Lua is possible in later phases via GitHub Releases API + checksum verification, but this is a Phase 5+ nice-to-have, not core).
- We detect gitleaks' presence at plugin setup and give the user a clear, actionable error message with install instructions if it's missing — never a silent no-op.

## Development Tooling

| Tool | Purpose |
|---|---|
| `stylua` | Lua formatter — enforced in CI, config committed as `.stylua.toml` |
| `luacheck` | Static analysis / linting for Lua |
| `busted` (via `plenary.nvim`'s test harness, `plenary.test_harness`) | Unit + integration test runner, the de-facto standard for Neovim plugin testing |
| `plenary.nvim` | Test harness + async utility functions (job control helpers, path utilities) — this is the one Lua dependency we take on, since it's the community standard (used by telescope, null-ls, and most serious plugins) and dramatically reduces boilerplate |
| GitHub Actions | CI: lint, format-check, run test suite against multiple Neovim versions (stable + nightly) on Linux and macOS runners |
| `mini.test` (alternative to plenary, evaluate both) | Newer, lighter-weight test framework gaining adoption — worth a spike in Phase 1 to decide vs plenary before committing |
| LuaLS (`lua-language-server`) + `.luarc.json` | Type annotations (`---@class`, `---@field`) for editor-assisted development and to generate accurate `:h` style docs later |
| `panvimdoc` | Converts a Markdown README/doc source into proper Neovim `:h secret-scanner` vimdoc — keeps docs in Markdown (easier to maintain, renders on GitHub) while still shipping proper `:help` support |

## Runtime Dependencies (Lua, declared in plugin spec)

- `nvim-lua/plenary.nvim` (test harness + job/path utilities)
- Optional, soft dependency: `nvim-tree/nvim-web-devicons` (purely cosmetic, for float window icons) — must degrade gracefully if absent.

## Distribution / Installation Surface

- Standard plugin repo structure (`lua/secret-scanner/`, `plugin/secret-scanner.lua`, `doc/secret-scanner.txt`).
- Must install cleanly via lazy.nvim, packer.nvim, and native `vim.pack` (test against all three in CI or at minimum manually before each release — this project's own author has firsthand experience with vim.pack migration pain, so there is no excuse for us shipping a plugin that doesn't work cleanly with it).

## Dev Environment Setup (for contributors)

1. Clone repo.
2. Install `gitleaks` locally (documented one-liner per OS in `CONTRIBUTING.md`).
3. Install `stylua`, `luacheck` via cargo/npm/OS package manager (documented per-OS).
4. Run `make test` (wraps `plenary.test_harness` invocation via a headless `nvim --headless`).
5. Run `make lint` and `make fmt-check` before opening a PR — enforced identically in CI so there are no surprises.

## Versioning & Release

- Semantic versioning (`vX.Y.Z`) via Git tags.
- `CHANGELOG.md` maintained by hand (or via `git-cliff`/conventional commits if we adopt that convention from day one — decide in Phase 1 and stick to it, since retrofitting conventional commits onto an existing history is painful).
