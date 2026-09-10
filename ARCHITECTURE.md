# ARCHITECTURE.md

## Design Principles

1. **We are a UX layer, not a detection engine.** All secret-detection logic lives in gitleaks. Our Lua code is responsible for: invoking it correctly, parsing its output, and presenting results in the most useful place in the editor. This keeps our surface area small and our maintenance burden low relative to the value delivered.
2. **Never block the editor thread.** All calls to `gitleaks` run through `vim.system(..., { text = true }, callback)` — fully async. A large repo scan must never freeze typing.
3. **Fail open with a loud warning, never fail silently.** If gitleaks is missing, misconfigured, or crashes, the user must be told clearly — a security tool that fails silently is worse than no tool, because it creates false confidence.
4. **Everything is overridable.** Patterns, allowlists, blocking behavior, and UI presentation are all configurable — we are opinionated in defaults, not in what's possible.

## Module Breakdown

```
lua/secret-scanner/
├── init.lua              -- public API surface, setup(opts)
├── config.lua            -- default config + merge with user opts, validation
├── engine/
│   ├── gitleaks.lua      -- shells out to gitleaks via vim.system, builds CLI args
│   └── parser.lua        -- parses gitleaks JSON output into internal Finding[] shape
├── scan/
│   ├── buffer.lua        -- triggers scan for current buffer contents (on save / on demand)
│   ├── staged.lua        -- triggers scan for `git diff --staged` (pre-commit path)
│   └── diff.lua          -- shared helper: extract changed line ranges for a given diff
├── ui/
│   ├── diagnostics.lua   -- publishes Finding[] into Neovim's native vim.diagnostic
│   ├── signs.lua         -- optional custom sign column icons (if not using diagnostics signs)
│   └── float.lua         -- floating window with finding detail (rule matched, entropy, snippet)
├── git/
│   ├── hooks.lua         -- installs/manages the pre-commit and pre-push git hook scripts
│   └── commit.lua        -- hooks into a commit command flow to block/warn before commit completes
├── allowlist.lua         -- manages false-positive allowlist (per-repo .secretscannerignore or inline comment markers)
└── health.lua            -- powers `:checkhealth secret-scanner` (verifies gitleaks install, version, config validity)
```

## Data Flow — Buffer Scan (on save)

```
BufWritePost autocmd
        │
        ▼
scan/buffer.lua: gather buffer text + filetype
        │
        ▼
engine/gitleaks.lua: write buffer text to cache temp file, then
  vim.system({ "gitleaks", "dir", <tempfile>, "--config", <config>, "--report-format", "json", "--report-path", "-" }, async)
        │
        ▼ (on exit, async callback)
engine/parser.lua: parse stdout JSON → Finding[] { line, col, rule_id, secret_snippet(masked), severity }
        │
        ▼
allowlist.lua: filter out findings matching allowlist entries
        │
        ▼
ui/diagnostics.lua: vim.diagnostic.set(namespace, bufnr, findings)
```

## Data Flow — Pre-Commit Block

```
User runs :Git commit (or plain `git commit` from a terminal inside nvim, or external terminal
if the git hook is installed at the repo level rather than only inside nvim)
        │
        ▼
git/hooks.lua-installed pre-commit hook shells out to a headless nvim (or directly to gitleaks
CLI — see "Two Enforcement Layers" below) scanning `git diff --staged`
        │
        ▼
Findings found?
   ├── No  → commit proceeds normally
   └── Yes → commit is aborted (non-zero exit from hook), user sees a clear terminal message
             listing file:line and rule matched, plus a hint on how to allowlist a false positive
```

## Two Enforcement Layers (Important Design Decision)

We deliberately implement protection at **two independent layers**, because they catch different situations:

1. **In-editor, real-time (buffer diagnostics)** — catches the secret the moment it's typed, before it's even staged. This is the "shift left as far as possible" layer, and it's Neovim-specific (only works if you're editing in Neovim).
2. **Git hook, repo-level (pre-commit/pre-push)** — catches anything that slipped through, including changes staged from outside Neovim (a teammate using VS Code, a script, `git add -A` on files never opened in the editor this session). This layer must work **even without Neovim running** — implemented as a standalone shell script wrapping `gitleaks` directly, installed by our plugin via `:SecretScannerInstallHooks`, not dependent on Neovim being open at commit time.

This distinction matters: layer 2 is what makes this a credible "production" security tool rather than a cosmetic editor feature, and it must be documented clearly so users understand the plugin protects the *repository*, not just their *editing session*.

## Configuration Schema (draft)

```lua
require("secret-scanner").setup({
  gitleaks_path = "gitleaks",         -- resolved via vim.fn.exepath, overridable
  scan_on_save = true,
  scan_on_commit = true,              -- installs/manages the git hook
  block_commit_on_finding = true,     -- false = warn only, don't block
  custom_config_path = nil,           -- path to a custom gitleaks.toml, merged with our sane defaults
  allowlist_file = ".secretscannerignore",
  severity = { default = vim.diagnostic.severity.ERROR },
  ui = {
    virtual_text = true,
    signs = true,
    float_on_cursor_hold = true,
  },
})
```

## Key Risks & Mitigations

| Risk | Mitigation |
|---|---|
| gitleaks not installed / wrong version | `:checkhealth` surfaces this explicitly; setup() emits one clear warning (not spammy repeated notifications) |
| False positives frustrate users, they disable the tool entirely | First-class, easy allowlist workflow (Phase 5) — friction here directly threatens retention |
| Large repo / large diff scan is slow | Always scan the *diff*, never the whole repo history, for the interactive paths; full-repo scan is an explicit opt-in command, not a default trigger |
| Git hook conflicts with an existing pre-commit setup (e.g. the user already uses the `pre-commit` framework) | Detect existing hooks, offer to chain rather than overwrite, document the interaction clearly |
