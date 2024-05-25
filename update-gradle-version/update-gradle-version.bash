#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 gradle-version-number nix-file-to-modify"
  echo "Example: $0 8.7 flake.nix"
  exit 1
fi

gradle_version="$1"
nix_file="$2"

url="https://services.gradle.org/distributions/gradle-${gradle_version}-bin.zip"

{
    read -r gradle_hash
    read -r gradle_path
} < <(nix-prefetch-url "$url" --type sha256 --print-path)

gradle_native_prefix="gradle-$gradle_version/lib/native-platform-"
gradle_native_suffix=".jar"
tmp=$(mktemp)
zipinfo -1 "$gradle_path" "$gradle_native_prefix*$gradle_native_suffix" > "$tmp"
gradle_native=$(head -n1 < "$tmp")
gradle_native=${gradle_native#"$gradle_native_prefix"}
gradle_native=${gradle_native%"$gradle_native_suffix"}

rm -f "$tmp"

sed -i  -e "s/version = \".*\"; # updater: gradle-version/version = \"$gradle_version\"; # updater: gradle-version/" \
        -e "s/nativeVersion = \".*\"; # updater: gradle-native-version/nativeVersion = \"$gradle_native\"; # updater: gradle-native-version/" \
        -e "s/sha256 = \".*\"; # updater: gradle-sha256/sha256 = \"$gradle_hash\"; # updater: gradle-sha256/" \
        "$nix_file"

