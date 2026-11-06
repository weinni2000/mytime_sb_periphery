#!/usr/bin/env bash
# Install the official sitewarm release locally, after checking its SHA-256.
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
version=${SITEWARM_VERSION:-1.0.2}
version=${version#v}
if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "SITEWARM_VERSION must be a release such as 1.0.2." >&2
    exit 2
fi

case "$(uname -s)" in
    Linux) platform=linux ;;
    Darwin) platform=darwin ;;
    *) echo "This installer supports Linux and macOS." >&2; exit 2 ;;
esac
case "$(uname -m)" in
    x86_64|amd64) architecture=amd64 ;;
    aarch64|arm64) architecture=arm64 ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 2 ;;
esac

archive="sitewarm_${version}_${platform}_${architecture}.tar.gz"
release_url="https://github.com/sitewarm/sitewarm/releases/download/v${version}"
mkdir -p "$script_dir/.bin"
temp_dir=$(mktemp -d "$script_dir/.bin/install.XXXXXXXX")
trap 'rm -rf -- "$temp_dir"' EXIT

for filename in "$archive" checksums.txt; do
    curl --fail --location --silent --show-error --retry 2 \
        --connect-timeout 15 --max-time 180 \
        "$release_url/$filename" --output "$temp_dir/$filename"
done
expected=$(awk -v archive="$archive" '$2 == archive || $2 == "*" archive {print $1}' \
    "$temp_dir/checksums.txt")
if [[ ! $expected =~ ^[[:xdigit:]]{64}$ ]]; then
    echo "Missing or invalid checksum for $archive." >&2
    exit 1
fi
if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$temp_dir/$archive")
else
    actual=$(shasum -a 256 "$temp_dir/$archive")
fi
if [[ ${actual%% *} != "$expected" ]]; then
    echo "Checksum mismatch for $archive; installation stopped." >&2
    exit 1
fi

tar -xzf "$temp_dir/$archive" -C "$temp_dir" sitewarm
chmod 755 "$temp_dir/sitewarm"
"$temp_dir/sitewarm" --version
mv -f -- "$temp_dir/sitewarm" "$script_dir/.bin/sitewarm"
echo "Installed $script_dir/.bin/sitewarm"
