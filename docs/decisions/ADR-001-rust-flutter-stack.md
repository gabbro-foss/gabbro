# ADR-001: Use Flutter + Rust Hybrid Stack

## Status
Accepted

## Date
2026-03-16

## Context
We need a password manager that:
- Runs on Linux (Arch, Mint), Android, and eventually
  iOS/Windows/macOS
- Handles cryptographic operations with memory safety guarantees
- Is buildable and maintainable by a small team
  (initially one developer)
- Is FOSS-friendly

## Decision
Use Flutter (Dart) for the UI layer and Rust for the
security-critical backend, connected via flutter_rust_bridge.

## Reasons
- Flutter delivers genuine cross-platform UI from a single codebase
- Rust provides memory safety critical for handling secrets
- Rust has excellent PQC library support
- flutter_rust_bridge makes FFI manageable for a solo developer
- Both have strong FOSS ecosystems

## Alternatives Considered
- Pure Python: familiar but poor Android support,
  memory safety concerns
- Pure Flutter: simpler stack but weaker memory safety for crypto
- Electron: cross-platform but heavy, poor mobile story

## Consequences
- Two new languages to learn (Dart and Rust)
- Stronger security guarantees than pure Python or pure Flutter
- flutter_rust_bridge adds a dependency to manage
```

---

That's everything! Save those three files to their correct locations:
```
docs/ARCHITECTURE.md
docs/LEARNINGS.md
docs/decisions/ADR-001-rust-flutter-stack.md

