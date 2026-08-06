#!/usr/bin/env bash
# Installs a Koja release into the runner tool cache and puts it on
# PATH. Inputs arrive as environment variables set by action.yml:
#   KOJA_VERSION_INPUT   exact version, "latest", or empty
#   KOJA_VERSION_FILE    path to .tool-versions or koja.toml, or empty
#   GITHUB_TOKEN         token for the GitHub releases API

set -euo pipefail

GH_REPO="https://github.com/koja-lang/koja"
GH_API="https://api.github.com/repos/koja-lang/koja"

# Earliest release that publishes prebuilt binaries.
MIN_VERSION="0.12.1"

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

# True when version $1 sorts before version $2 (numeric, three parts).
version_lt() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    split(a, x, "."); split(b, y, ".")
    for (i = 1; i <= 3; i++) {
      if (x[i] + 0 < y[i] + 0) exit 0
      if (x[i] + 0 > y[i] + 0) exit 1
    }
    exit 1
  }'
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

latest_version() {
  local response tag
  response="$(curl -fsSL --retry 3 \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "$GH_API/releases/latest")" ||
    fail "could not query $GH_API/releases/latest"
  tag="$(echo "$response" | sed -n 's/.*"tag_name":[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' | head -n 1)"
  [ -n "$tag" ] || fail "could not read tag_name from the latest-release response"
  echo "$tag"
}

# Expands a partial version like "0.16" or "1" to the newest release
# that matches it, the way setup-go resolves "1.21" to 1.21.x.
expand_partial_version() {
  local prefix="$1" prefix_re response candidate best=""
  prefix_re="${prefix//./\\.}"
  response="$(curl -fsSL --retry 3 \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "$GH_API/releases?per_page=100")" ||
    fail "could not query $GH_API/releases"
  for candidate in $(echo "$response" |
    sed -n 's/.*"tag_name":[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' |
    grep -E "^${prefix_re}(\.[0-9]+)+$"); do
    if [ -z "$best" ] || version_lt "$best" "$candidate"; then
      best="$candidate"
    fi
  done
  [ -n "$best" ] || fail "no koja release matches $prefix"
  echo "$best"
}

resolve_version() {
  local input="${KOJA_VERSION_INPUT:-}" file="${KOJA_VERSION_FILE:-}" version
  if [ -n "$input" ] && [ "$input" != "latest" ]; then
    if [ -n "$file" ]; then
      echo "::warning::setup-koja: both koja-version and koja-version-file are set, using koja-version $input" >&2
    fi
    version="$input"
  elif [ -n "$file" ]; then
    # `|| exit` because errexit does not reach into command
    # substitutions (and macOS bash 3.2 lacks inherit_errexit).
    version="$(version_from_file "$file")" || exit 1
  else
    version="$(latest_version)" || exit 1
  fi
  version="${version#v}"
  if [[ "$version" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    version="$(expand_partial_version "$version")" || exit 1
  fi
  if version_lt "$version" "$MIN_VERSION"; then
    fail "koja $version predates prebuilt binaries (earliest is $MIN_VERSION)"
  fi
  echo "$version"
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
