# Contributing to secret-scanner.nvim

Thanks for stopping by. This project's value is a great in-editor experience on
top of a proven detection engine — and the fastest way to help is by sharing
the real-world stuff only you know: your stack, your rules, your false
positives.

## What this project most wants from you

1. **A new stack example config** (highest value). Copy `examples/go/` as a
   starting point and send a PR for your stack (Spring Boot, .NET, Rails, Rust,
   PHP, ...) containing:
   - `.secretscanner.lua` — sane team defaults for that ecosystem,
   - `.secretscannerignore` — the *actual* false positives you hit (with short
     comments saying why each one is safe),
   - optional `gitleaks.extend.toml` for stack-specific secret formats.
   These are the reference material that turns a generic plugin into a team
   tool, and they're a small, mergeable, low-risk PR.
2. **Rule-tuning documentation.** A noisy rule costs every user a few seconds a
   day. Record in the docs how your team tames it (downgrade vs allowlist vs
   inline marker), and raise a PR to the relevant section.
3. **Bug reports with fixture repos.** A minimal repro (a tiny git repo or a
   file + config that triggers the wrong behavior) makes the issue instantly
   actionable. See `tests/fixtures/` for the shape we like.

## Before you open a PR

### Setup

```sh
git clone https://github.com/j4flmao/secret-scanner.nvim
cd secret-scanner.nvim
make test         # runs the plenary/busted suite headless
make fmt          # stylua format
make fmt-check    # format check (CI runs this)
make lint         # luacheck (CI runs this)
```

If you don't have the toolchain:

- **gitleaks** (only needed if you're exercising real scans):
  - macOS: `brew install gitleaks`
  - Linux: `go install github.com/gitleaks/gitleaks/v8@latest`
  - Windows: `winget install gitleaks.gitleaks`
  - or the release binary: <https://github.com/gitleaks/gitleaks/releases>
  - Note: gitleaks >= 8.19 is required (the `git` subcommand).
- **stylua**: `cargo install stylua` or via your package manager.
- **luacheck**: `luarocks install luacheck` (or `brew install luacheck`).
- **plenary.nvim**: not needed for dev — `make test` clones it into `deps/`.

### The 3 checks

1. `stylua --check .` clean ✓
2. `luacheck lua/` clean ✓
3. New/modified behavior covered by a test in `tests/`, and the full suite
   passes on Neovim stable **and** nightly ✓

### Style notes

- Pure Lua; no companion binaries. We shell out to gitleaks via `vim.system`
  only — never in the `:help`-free, blocking path.
- Async only. Editor must never block on a scan.
- Secrets are masked in the UI; don't print full secret values in notifications
  or logs.
- Keep `:h secret-scanner` in sync when user-facing options change
  (`doc/secret-scanner.txt`).

## Contribution guidelines

- One logical change per PR; keep diffs reviewable.
- Write a story in the PR description: *what you hit, what you changed, how it
  behaves now.* We merge faster when the "why" is obvious.
- Be nice and specific in review threads; we'd rather teach than rewrite.

## Recognition

Example-contributors get added to `CHANGELOG.md` under the release that
absorbed their stack, credited by name/Nitter handle if they want.