# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-09-09

### Changed

- Versions now resolve through the release catalog at `releases.kojalang.org` instead of the GitHub releases API, so resolution needs no token and is not rate limited.
- The `token` input is no longer used. It stays accepted so existing workflows keep working.
- A version with no release fails at resolution with the version named, instead of at download.
- The Marketplace icon is now `download`.

## [1.0.1] - 2026-08-05

### Added

- A version like `0.16` now installs the newest matching release, for the `koja-version` input and both version file formats.

## [1.0.0] - 2026-08-05

### Added

- Install a Koja release into the runner tool cache and add it to `PATH`.
- Resolve the version from the `koja-version` input, `.tool-versions`, `koja.toml`, or the latest release.
- Verify release checksums before install.
- Register a problem matcher so compile diagnostics annotate pull requests.
- Support Linux x86_64, Linux arm64, and macOS arm64 runners.

[Unreleased]: https://github.com/koja-lang/setup-koja/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/koja-lang/setup-koja/releases/tag/v1.1.0
[1.0.1]: https://github.com/koja-lang/setup-koja/releases/tag/v1.0.1
[1.0.0]: https://github.com/koja-lang/setup-koja/releases/tag/v1.0.0
