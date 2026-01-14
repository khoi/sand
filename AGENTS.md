# About

sand orchestrates ephemeral macOS/Linux CI runners using Tart VMs with automatic GitHub Actions integration.

## Commands

```bash
swift build                          # debug build
swift build -c release               # release build
swift test                           # run tests (Swift Testing)
swift run sand --config config.yml   # run CLI
```

## Project Structure & Module Organization
- `Sources/sand` contains the CLI implementation, config parsing/validation, VM orchestration, and integrations. GitHub-specific logic lives in `Sources/sand/GitHub`.
- `Tests/sandTests` contains unit tests using Swift Testing (`@Test`, `#expect`).
- `fixtures/` holds sample configs, including `fixtures/sample_full_config.yml` for full schema coverage.
- `Package.swift` and `Package.resolved` define SwiftPM build settings and dependencies.
- `Formula/` contains the Homebrew formula for distribution.

## Testing Guidelines
- Use Swift Testing assertions (`#expect`) and keep test inputs close to fixtures or inline YAML strings.
- When changing the config schema, update or add fixture coverage and the relevant config tests.

## Configuration & Operations
- Configuration is YAML loaded via `--config`; see `fixtures/*.yml` for example configurations
