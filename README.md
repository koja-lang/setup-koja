# setup-koja

GitHub Action that installs the [Koja](https://github.com/koja-lang/koja) compiler toolchain and adds it to `PATH`.

The action downloads a prebuilt release tarball, verifies its checksum, installs `koja` and `koja-lsp` into the runner tool cache, and registers a problem matcher. With the matcher, compile diagnostics annotate pull request diffs inline.

## Usage

Install the version your project declares in `koja.toml`:

```yaml
steps:
  - uses: actions/checkout@v6
  - uses: koja-lang/setup-koja@v1
    with:
      koja-version-file: koja.toml
  - run: koja deps get
  - run: koja test
```

Install the latest release by omitting the version:

```yaml
- uses: koja-lang/setup-koja@v1
```

## Inputs

| Input               | Default        | Description                                                                            |
| ------------------- | -------------- | -------------------------------------------------------------------------------------- |
| `koja-version`      | latest release | Version to install: exact (`major.minor.patch`), partial (`major.minor`), or `latest`. |
| `koja-version-file` | none           | File that names the version: `.tool-versions` or `koja.toml`.                          |
| `token`             | none           | No longer used. Kept so existing workflows keep working.                               |

If both `koja-version` and `koja-version-file` are set, `koja-version` wins and the action prints a warning.

A partial version installs the newest patch release in that line. Versions resolve through the [release catalog](https://releases.kojalang.org), so no GitHub API call or token is involved.

For `koja.toml`, the action reads the `[project]` `koja` key, which declares a minimum compiler version.

## Outputs

| Output         | Description                                 |
| -------------- | ------------------------------------------- |
| `koja-version` | The resolved version that was installed.    |
| `koja-path`    | Directory the toolchain was installed into. |

## Supported runners

- Linux x86_64 and arm64 (`ubuntu-24.04`, `ubuntu-24.04-arm`, and compatible)
- macOS arm64 (`macos-14` and newer)

Intel macOS runners and Windows are not supported because no prebuilt binaries exist for them. The earliest installable version is `0.12.1`, the first release with prebuilt binaries.

## Problem matcher

Koja prints one-line diagnostics in CI (`path:line:col: severity: message`). The action registers a matcher for that format, so errors and warnings from `koja build`, `koja run`, and `koja test` appear as annotations on the pull request.

## License

Copyright (c) 2026 Henry Popp

This project is MIT licensed. See the [LICENSE](LICENSE) for details.
