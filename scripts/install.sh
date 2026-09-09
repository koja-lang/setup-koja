#!/usr/bin/env bash
# Installs a Koja release into the runner tool cache and puts it on
# PATH. Inputs arrive as environment variables set by action.yml:
#   KOJA_VERSION_INPUT   exact or partial version, "latest", or empty
#   KOJA_VERSION_FILE    path to .tool-versions or koja.toml, or empty
#
# Versions resolve through the release catalog, a set of static files
# that lists every release with prebuilt binaries.

set -euo pipefail

GH_REPO="https://github.com/koja-lang/koja"
CATALOG="https://releases.kojalang.org"

fail() {
  echo "::error::setup-koja: $*" >&2
  exit 1
}

# The release asset platform suffix. Linux reports arm64 as aarch64,
# so it is mapped to the arm64 name the release tarballs use.
platform() {
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  case "$os-$arch" in
    darwin-arm64 | linux-x86_64)
      echo "$os-$arch"
      ;;
    linux-aarch64)
      echo "linux-arm64"
      ;;
    darwin-x86_64)
      fail "no prebuilt Koja binary for Intel macOS. Use an arm64 macOS runner (macos-14 or newer)."
      ;;
    *)
      fail "no prebuilt Koja binary for $os-$arch. Koja supports Linux (x86_64, arm64) and macOS (arm64) runners."
      ;;
  esac
}

version_from_file() {
  local file="$1" version=""
  [ -f "$file" ] || fail "version file not found: $file"
  case "$(basename "$file")" in
    .tool-versions)
      version="$(awk '$1 == "koja" { print $2 }' "$file")"
      ;;
    koja.toml)
      version="$(sed -n 's/^[[:space:]]*koja[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$file" | head -n 1)"
      ;;
    *)
      fail "unsupported version file: $file (expected .tool-versions or koja.toml)"
      ;;
  esac
  [ -n "$version" ] || fail "no koja version found in $file"
  echo "$version"
}

# Asks the catalog for the newest release, or for the newest release
# that matches a version. "0.16" resolves to the newest 0.16.x the
# way setup-go resolves "1.21" to 1.21.x, and an exact version
# resolves to itself. The catalog answers 404 for a version with no
# release.
resolve_remote() {
  local requested="$1" path version
  if [ "$requested" = "latest" ]; then
    path="latest"
  else
    path="resolve/$requested"
  fi
  version="$(curl -fsSL --retry 3 "$CATALOG/$path")" ||
    fail "no koja release matches $requested (asked $CATALOG/$path)"
  [ -n "$version" ] || fail "empty response from $CATALOG/$path"
  echo "$version"
}

resolve_version() {
  local input="${KOJA_VERSION_INPUT:-}" file="${KOJA_VERSION_FILE:-}" requested
  if [ -n "$input" ]; then
    if [ -n "$file" ]; then
      echo "::warning::setup-koja: both koja-version and koja-version-file are set, using koja-version $input" >&2
    fi
    requested="$input"
  elif [ -n "$file" ]; then
    # `|| exit` because errexit does not reach into command
    # substitutions (and macOS bash 3.2 lacks inherit_errexit).
    requested="$(version_from_file "$file")" || exit 1
  else
    requested="latest"
  fi
  requested="${requested#v}"
  [[ "$requested" =~ ^(latest|[0-9]+(\.[0-9]+){0,2})$ ]] ||
    fail "invalid koja version: $requested"
  resolve_remote "$requested"
}

verify_checksum() {
  local checksum_file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c "$checksum_file" || fail "checksum verification failed"
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -c "$checksum_file" || fail "checksum verification failed"
  else
    fail "neither sha256sum nor shasum is available to verify the download"
  fi
}

install_release() {
  local version="$1" dest="$2"
  local filename url tmp_dir staging
  filename="koja-v${version}-$(platform).tar.gz"
  url="$GH_REPO/releases/download/v${version}/${filename}"
  tmp_dir="$(mktemp -d)"
  staging="${dest}.tmp.$$"

  echo "Downloading $url"
  curl -fsSL --retry 3 -o "$tmp_dir/$filename" "$url" ||
    fail "could not download $url (does v$version exist?)"
  curl -fsSL --retry 3 -o "$tmp_dir/$filename.sha256" "$url.sha256" ||
    fail "could not download $url.sha256"
  (cd "$tmp_dir" && verify_checksum "$filename.sha256")

  # The tarball wraps everything in a koja-v{version}-{platform}/
  # directory. Strip it and stage the install, then move it into
  # place in one step so a cancelled run never leaves a half cache.
  tar -xzf "$tmp_dir/$filename" -C "$tmp_dir" --strip-components=1 ||
    fail "could not extract $filename"
  mkdir -p "$staging/bin"
  cp "$tmp_dir/koja" "$tmp_dir/koja-lsp" "$staging/bin/"
  chmod +x "$staging/bin/koja" "$staging/bin/koja-lsp"
  rm -rf "$tmp_dir"
  mv "$staging" "$dest"
}

main() {
  local version dest
  version="$(resolve_version)"
  dest="${RUNNER_TOOL_CACHE}/koja/${version}/$(platform)"

  if [ -x "$dest/bin/koja" ]; then
    echo "Using cached koja $version from $dest"
  else
    install_release "$version" "$dest"
  fi

  "$dest/bin/koja" --version >/dev/null ||
    fail "installed koja binary does not run on this machine"

  echo "$dest/bin" >>"$GITHUB_PATH"
  {
    echo "koja-version=$version"
    echo "koja-path=$dest"
  } >>"$GITHUB_OUTPUT"
  echo "Installed koja $version"
}

main
