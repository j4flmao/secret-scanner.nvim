# Spring Boot example

Copy these files to your Spring Boot repo root and adjust paths to your
layout. This is a *starting point* — add an entry whenever you allowlist a
finding with `<leader>sa`.

## Typical false positives in Spring Boot codebases

- `application.yml` / `application.properties` where a placeholder reference is
  used in place of a secret, e.g. `password: ${DB_PASSWORD}`. gitleaks sees the
  placeholder-looking string and flags it.
- `src/test/resources/application-test.yml` with throwaway values.
- `.env.example` and `docker-compose.yml` shipping demo credentials.
- README / ADR files quoting example tokens such as AWS access keys.

The `generic-api-key` rule is the usual source of these; this config also
downgrades it so it never *blocks* a commit, only warns.

## Files

- `.secretscanner.lua` — team options: live scanning on text change and a
  fresh scan on every write, a pre-push hook, and `generic-api-key`
  downgraded to informational severity so it can't block the build.
- `.secretscannerignore` — allowlist entries for the placeholder and fixture
  files above.
- `gitleaks.extend.toml` — extends the embedded defaults with an internal
  `nimbus_*` credential rule, and allowlists the matching *demo* strings so
  documentation examples don't fire.