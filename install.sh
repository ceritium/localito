#!/bin/sh
# Installs localito from a GitHub release:
#   curl -fsSL https://raw.githubusercontent.com/ceritium/localito/master/install.sh | sh
# LOCALITO_VERSION=v0.2.0 picks a release (default: the latest); LOCALITO_PREFIX
# where it goes (default: ~/.local, the binary linked from ~/.local/bin).
set -eu

repo=ceritium/localito
prefix="${LOCALITO_PREFIX:-$HOME/.local}"
version="${LOCALITO_VERSION:-}"

fail() { echo "localito: $*" >&2; exit 1; }

case "$(uname -s)" in
  Darwin) os=macos ;;
  Linux) os=linux ;;
  *) fail "no build for $(uname -s)" ;;
esac
case "$(uname -m)" in
  arm64 | aarch64) arch=arm64 ;;
  x86_64 | amd64) arch=x86_64 ;;
  *) fail "no build for $(uname -m)" ;;
esac
[ "$os-$arch" != macos-x86_64 ] || fail "no build for Intel Macs yet"

if [ -z "$version" ]; then
  # /releases/latest redirects to /releases/tag/<version>.
  latest=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest")
  version="${latest##*/}"
  case "$version" in v*) ;; *) fail "couldn't find the latest release" ;; esac
fi

name="localito-$version-$os-$arch"
url="https://github.com/$repo/releases/download/$version"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "localito: downloading $name"
curl -fsSL -o "$tmp/$name.tar.gz" "$url/$name.tar.gz" || fail "no $name.tar.gz in release $version"
curl -fsSL -o "$tmp/SHA256SUMS" "$url/SHA256SUMS" || fail "no SHA256SUMS in release $version"
expected=$(grep " $name.tar.gz\$" "$tmp/SHA256SUMS" | cut -d ' ' -f 1)
if command -v sha256sum >/dev/null; then
  actual=$(sha256sum "$tmp/$name.tar.gz" | cut -d ' ' -f 1)
else
  actual=$(shasum -a 256 "$tmp/$name.tar.gz" | cut -d ' ' -f 1)
fi
[ -n "$expected" ] && [ "$expected" = "$actual" ] || fail "checksum mismatch for $name.tar.gz"

dest="$prefix/share/localito"
rm -rf "$dest"
mkdir -p "$dest" "$prefix/bin"
tar -xzf "$tmp/$name.tar.gz" -C "$dest" --strip-components=1
ln -sf "$dest/bin/localito" "$prefix/bin/localito"
echo "localito: $version installed in $dest, linked from $prefix/bin/localito"

if [ "$os" = macos ] && [ ! -e /opt/homebrew/opt/openssl@3/lib/libssl.3.dylib ]; then
  echo "localito: needs OpenSSL from Homebrew: brew install openssl@3" >&2
fi
case ":$PATH:" in
  *":$prefix/bin:"*) ;;
  *) echo "localito: add $prefix/bin to your PATH" >&2 ;;
esac
