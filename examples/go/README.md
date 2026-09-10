# Go example

Copy these files to your Go repo root and adjust paths to your layout. This is
a *starting point* — add an entry whenever you allowlist a finding with
`<leader>sa`.

## Typical false positives in Go codebases

- `testdata/` and fixtures that embed fake credentials (mocked AWS/GCP calls,
  golden files, `httptest` payloads).
- `.env.example`, `compose.yaml`, and goreleaser sample configs shipping demo
  values.
- Docs quoting `AKIAIOSFODNN7EXAMPLE`-style examples, which the built-in
  `aws-access-key` rule catches by shape.

`go.mod` / `go.sum` and `vendor/` are already excluded by gitleaks' global
allowlist, so they are not repeated here. `testdata/` is *not* excluded by
gitleaks by default — entries below cover it.

## Files

- `.secretscanner.lua` — team options: block commits on findings, install a
  pre-push hook, and downgrade `generic-api-key` so vendored-looking generated
  code can't hard-block a commit.
- `.secretscannerignore` — allowlist entries for fixture, mock, and demo files.
- `gitleaks.extend.toml` — extends embedded defaults with an internal
  `acmecorp_internal_` credential rule, plus an extra allowlist for mock keys
  living under `internal/`.

## Tip: keep fake keys obviously fake

The plugin's inline marker makes suppress-in-code explicit and reviewable:

```go
// mockS3Secret is a fake credential for tests only.
const mockS3Secret = "AKIAIOSFODNN7EXAMPLE" // secret-scanner:ignore
```