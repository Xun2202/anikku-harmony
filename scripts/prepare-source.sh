#!/usr/bin/env bash
# Turn an official Anikku checkout into the Harmony Preview build tree:
#   1. apply every patch listed in patches/series (in order),
#   2. point the in-app updater at this repository,
#   3. set versionCode / versionName in app/build.gradle.kts,
#   4. commit each step so the build tree has a readable history.
#
# Usage: scripts/prepare-source.sh <anikku-src-dir> <upstream-tag> <patch-number>
# Env:   FORK_REPO  GitHub slug the in-app updater should poll (default Xun2202/anikku-harmony)
set -euo pipefail

src_dir="${1:?anikku source dir}"
upstream_tag="${2:?upstream tag, e.g. v0.2.0}"
patch_number="${3:?patch number, e.g. 1}"
fork_repo="${FORK_REPO:-Xun2202/anikku-harmony}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
patches_dir="$repo_root/patches"

if [[ ! "$upstream_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Unsupported upstream tag: $upstream_tag (only stable vX.Y.Z tags are supported)" >&2
  exit 1
fi
if [[ ! "$patch_number" =~ ^[1-9][0-9]?$ ]]; then
  echo "Patch number must be between 1 and 99, got: $patch_number" >&2
  exit 1
fi

upstream_version="${upstream_tag#v}"
harmony_version="${upstream_version}-harmony.${patch_number}"

cd "$src_dir"
git config user.name github-actions[bot]
git config user.email 41898282+github-actions[bot]@users.noreply.github.com

echo "==> Applying patches from $patches_dir/series"
while IFS= read -r patch || [[ -n "$patch" ]]; do
  [[ -z "$patch" || "$patch" == \#* ]] && continue
  echo "    $patch"
  # --3way lets git resolve context drift as long as the pre-image blobs exist in the checkout.
  if ! git apply --3way "$patches_dir/$patch"; then
    echo "Patch $patch does not apply to $upstream_tag; rebase it against the new upstream." >&2
    exit 1
  fi
  git commit -q -m "harmony: apply $patch"
done < "$patches_dir/series"

echo "==> Pointing the in-app updater at $fork_repo"
updater_file="app/src/main/java/eu/kanade/tachiyomi/data/updater/AppUpdateChecker.kt"
if [[ "$fork_repo" != "Xun2202/anikku-harmony" ]]; then
  sed -i "s#Xun2202/anikku-harmony#${fork_repo}#g" "$updater_file"
  git add "$updater_file"
  git commit -q -m "harmony: updater polls $fork_repo"
fi
grep -q "\"$fork_repo\"" "$updater_file"

echo "==> Setting version $harmony_version"
# versionCode = <upstream versionCode> * 100 + N keeps every harmony build of a newer upstream
# release above every build of an older one, so in-place upgrades always work.
upstream_version_code="$(sed -nE 's/^[[:space:]]*versionCode = ([0-9]+)$/\1/p' app/build.gradle.kts | head -n 1)"
if [[ -z "$upstream_version_code" ]]; then
  echo "Unable to read upstream versionCode from app/build.gradle.kts" >&2
  exit 1
fi
harmony_version_code=$((upstream_version_code * 100 + 10#$patch_number))
sed -i -E "0,/versionCode = [0-9]+/s//versionCode = $harmony_version_code/" app/build.gradle.kts
sed -i -E "0,/versionName = \"[^\"]+\"/s//versionName = \"$harmony_version\"/" app/build.gradle.kts
grep -q "versionCode = $harmony_version_code$" app/build.gradle.kts
grep -q "versionName = \"$harmony_version\"" app/build.gradle.kts
git add app/build.gradle.kts
git commit -q -m "harmony: set version $harmony_version (versionCode $harmony_version_code)"

echo "harmony_version=$harmony_version"
echo "harmony_version_code=$harmony_version_code"
