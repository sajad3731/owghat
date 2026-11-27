# Contributing to Owghat

Thank you for contributing to Owghat! Please review the guidelines below before opening an issue or pull request.

## Architecture Principles

- **Keep business logic in `Packages/OwghatCore`:** All astronomical math, calendar conversion, occasion matching, settings persistence, and networking belong in `OwghatCore` with zero UIKit/AppKit/SwiftUI dependencies so tests stay fast and portable.
- **Swift 6 strict concurrency:** New types and functions must compile cleanly under `SWIFT_VERSION = 6.0` and `SWIFT_STRICT_CONCURRENCY = complete`.
- **Bilingual first:** User-facing copy belongs in `Owghat/Resources/Localizable.xcstrings` with both Persian (`fa`, RTL) and English (`en`, LTR) strings.

## Development Workflow

1. Run the core test suite before making changes:
   ```bash
   cd Packages/OwghatCore
   swift test
   ```
2. If you add or remove files in `Owghat/`, `OwghatWidget/`, or `OwghatTests/`, update `project.yml` if needed and regenerate `Owghat.xcodeproj`:
   ```bash
   xcodegen generate
   ```
3. Verify the macOS app and widget build cleanly:
   ```bash
   xcodebuild build -project Owghat.xcodeproj -scheme Owghat -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO
   ```

## Commit Style

Use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat: ...` for new features
- `fix: ...` for bug fixes
- `test: ...` for test additions or updates
- `docs: ...` for documentation updates
- `chore: ...` for build, CI, or project housekeeping

## Audio & Assets Policy

Do **not** submit copyrighted Adhan recordings, third-party app icons, or proprietary texts. Only commit original or properly licensed assets compatible with the MIT license.
