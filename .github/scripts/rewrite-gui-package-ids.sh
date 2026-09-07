#!/usr/bin/env bash
# Rewrite GUI/core package identifiers so builds do not collide with upstream reF1nd installs.
# Usage: rewrite-gui-package-ids.sh <android|desktop|core> <project-root> [releases-repo]
set -euo pipefail

TARGET="${1:?target required: android|desktop|core}"
ROOT="${2:?project root required}"
RELEASES_REPO="${3:-${GITHUB_REPOSITORY:-}}"

FROM_BRAND="reF1nd"
TO_BRAND="erics"
FROM_BRAND_LOWER="ref1nd"
TO_BRAND_LOWER="erics"

if [[ ! -d "$ROOT" ]]; then
  echo "project root not found: $ROOT" >&2
  exit 1
fi

replace_literal() {
  local file="$1"
  local from="$2"
  local to="$3"
  if [[ ! -f "$file" ]]; then
    echo "missing file for rewrite: $file" >&2
    exit 1
  fi
  if grep -F -q -- "$from" "$file"; then
    FROM_TEXT="$from" TO_TEXT="$to" perl -0pi -e 's/\Q$ENV{FROM_TEXT}\E/$ENV{TO_TEXT}/g' -- "$file"
  fi
}

replace_in_files() {
  local from="$1"
  local to="$2"
  shift 2
  local file
  for file in "$@"; do
    replace_literal "$file" "$from" "$to"
  done
}

set_releases_url() {
  local file="$1"
  if [[ -z "$RELEASES_REPO" ]]; then
    echo "releases repository is required to rewrite update URLs" >&2
    exit 1
  fi
  if [[ ! -f "$file" ]]; then
    echo "missing update checker file: $file" >&2
    exit 1
  fi
  RELEASES_REPO_TEXT="$RELEASES_REPO" perl -0pi -e \
    's#https://api\.github\.com/repos/[^/\s"]+/sing-box-releases/releases#https://api.github.com/repos/$ENV{RELEASES_REPO_TEXT}/releases#g' \
    -- "$file"
}

rewrite_android() {
  local gradle="$ROOT/app/build.gradle.kts"
  local updater="$ROOT/app/src/github/java/io/nekohasekai/sfa/vendor/GitHubUpdateChecker.kt"

  replace_literal "$gradle" "applicationId = \"io.${FROM_BRAND}.sfa\"" "applicationId = \"io.${TO_BRAND}.sfa\""
  set_releases_url "$updater"

  if ! grep -F -q "applicationId = \"io.${TO_BRAND}.sfa\"" "$gradle"; then
    echo "failed to rewrite Android applicationId" >&2
    exit 1
  fi
  if grep -F -q "io.${FROM_BRAND}.sfa" "$gradle"; then
    echo "Android applicationId still references ${FROM_BRAND}" >&2
    exit 1
  fi
  if ! grep -F -q "https://api.github.com/repos/${RELEASES_REPO}/releases" "$updater"; then
    echo "failed to rewrite Android releases URL" >&2
    exit 1
  fi

  echo "Android package id: io.${TO_BRAND}.sfa"
  echo "Android releases URL: https://api.github.com/repos/${RELEASES_REPO}/releases"
}

rewrite_desktop() {
  local files=(
    "$ROOT/electron-builder.yml"
    "$ROOT/package.json"
    "$ROOT/build/installer.nsh"
    "$ROOT/build/installer-data.ps1"
    "$ROOT/build/installer-preflight.ps1"
    "$ROOT/build/sing-box-daemon.service"
    "$ROOT/build/linux-after-install.sh"
    "$ROOT/build/linux-after-install-pacman.sh"
    "$ROOT/build/linux-after-remove.sh"
    "$ROOT/build/linux-after-remove-pacman.sh"
    "$ROOT/build/linux-before-remove.sh"
    "$ROOT/build/linux-before-remove-pacman.sh"
    "$ROOT/build/io.${FROM_BRAND}.sfl.policy"
    "$ROOT/build/io.${FROM_BRAND}.sfl.metainfo.xml"
    "$ROOT/src/main/appReports.ts"
    "$ROOT/src/main/applicationPaths.ts"
    "$ROOT/src/main/daemon.ts"
    "$ROOT/src/main/index.ts"
    "$ROOT/src/main/installationLayout.ts"
    "$ROOT/src/main/loginItem.ts"
    "$ROOT/src/main/updates.ts"
    "$ROOT/src/main/x11Tray.ts"
  )

  local file
  for file in "${files[@]}"; do
    if [[ ! -f "$file" ]]; then
      echo "missing desktop branding file: $file" >&2
      exit 1
    fi
  done

  replace_in_files "$FROM_BRAND" "$TO_BRAND" "${files[@]}"
  # package.json uses a lowercase brand in the npm package name.
  replace_literal "$ROOT/package.json" "$FROM_BRAND_LOWER" "$TO_BRAND_LOWER"

  # Keep update URL on this releases repository (brand rewrite alone would be wrong).
  set_releases_url "$ROOT/src/main/updates.ts"

  # Accept either the new brand or the historical fork suffix when comparing versions.
  replace_literal \
    "$ROOT/src/main/updates.ts" \
    "const forkSuffix = /^(.*)-${TO_BRAND}(?:\\.(\\d+))?\$/.exec(normalizedVersion);" \
    "const forkSuffix = /^(.*)-(?:${TO_BRAND}|${FROM_BRAND})(?:\\.(\\d+))?\$/.exec(normalizedVersion);"

  local policy_src="$ROOT/build/io.${FROM_BRAND}.sfl.policy"
  local policy_dst="$ROOT/build/io.${TO_BRAND}.sfl.policy"
  local meta_src="$ROOT/build/io.${FROM_BRAND}.sfl.metainfo.xml"
  local meta_dst="$ROOT/build/io.${TO_BRAND}.sfl.metainfo.xml"
  if [[ -f "$policy_src" ]]; then
    mv "$policy_src" "$policy_dst"
  fi
  if [[ -f "$meta_src" ]]; then
    mv "$meta_src" "$meta_dst"
  fi
  if [[ ! -f "$policy_dst" || ! -f "$meta_dst" ]]; then
    echo "failed to rename Linux policy/metainfo files" >&2
    exit 1
  fi

  local leftovers
  leftovers="$(
    grep -R -F -n --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=out --exclude-dir=release \
      -e "io.${FROM_BRAND}." \
      -e "sing-box-${FROM_BRAND}" \
      -e "sing-box-daemon-${FROM_BRAND}" \
      -e "Software\\${FROM_BRAND}\\" \
      -e "SOFTWARE\\${FROM_BRAND}\\" \
      "$ROOT/electron-builder.yml" "$ROOT/package.json" "$ROOT/build" "$ROOT/src/main" || true
  )"
  if [[ -n "$leftovers" ]]; then
    echo "desktop branding leftovers:" >&2
    echo "$leftovers" >&2
    exit 1
  fi

  if ! grep -F -q "appId: io.${TO_BRAND}.sfw" "$ROOT/electron-builder.yml"; then
    echo "failed to rewrite Windows appId" >&2
    exit 1
  fi
  if ! grep -F -q "appId: io.${TO_BRAND}.sfl" "$ROOT/electron-builder.yml"; then
    echo "failed to rewrite Linux appId" >&2
    exit 1
  fi
  if ! grep -F -q "https://api.github.com/repos/${RELEASES_REPO}/releases" "$ROOT/src/main/updates.ts"; then
    echo "failed to rewrite desktop releases URL" >&2
    exit 1
  fi
  if ! grep -F -q -- "-(?:${TO_BRAND}|${FROM_BRAND})" "$ROOT/src/main/updates.ts"; then
    echo "failed to broaden desktop version suffix matcher" >&2
    exit 1
  fi

  echo "Desktop Windows appId: io.${TO_BRAND}.sfw"
  echo "Desktop Linux appId: io.${TO_BRAND}.sfl"
  echo "Desktop productName: sing-box-${TO_BRAND}"
  echo "Desktop releases URL: https://api.github.com/repos/${RELEASES_REPO}/releases"
}

rewrite_core() {
  # Desktop installer embeds boxdd from the core checkout. Its hardcoded app/service
  # names must match the rewritten Electron productName or service install fails with:
  #   secure installation: open installed application: The system cannot find the file specified.
  local boxdd="$ROOT/experimental/boxdd"
  if [[ ! -d "$boxdd" ]]; then
    echo "missing experimental/boxdd in core tree: $ROOT" >&2
    exit 1
  fi

  local file
  local matched=0
  while IFS= read -r -d '' file; do
    if grep -F -q -- "$FROM_BRAND" "$file"; then
      replace_literal "$file" "$FROM_BRAND" "$TO_BRAND"
      matched=1
    fi
  done < <(find "$boxdd" -type f -name '*.go' -print0)

  if [[ "$matched" -ne 1 ]]; then
    echo "no ${FROM_BRAND} identifiers found under experimental/boxdd" >&2
    exit 1
  fi

  local leftovers
  leftovers="$(grep -R -F -n --include='*.go' -e "$FROM_BRAND" "$boxdd" || true)"
  if [[ -n "$leftovers" ]]; then
    echo "core boxdd branding leftovers:" >&2
    echo "$leftovers" >&2
    exit 1
  fi

  if ! grep -R -F -q -- "applicationExecutableName = \"sing-box-${TO_BRAND}.exe\"" "$boxdd"; then
    echo "failed to rewrite core applicationExecutableName" >&2
    exit 1
  fi
  if ! grep -R -F -q -- "serviceName = \"sing-box-daemon-${TO_BRAND}\"" "$boxdd"; then
    echo "failed to rewrite core serviceName" >&2
    exit 1
  fi
  if ! grep -R -F -q -- "updateProductName      = \"sing-box-${TO_BRAND}\"" "$boxdd"; then
    echo "failed to rewrite core updateProductName" >&2
    exit 1
  fi
  if ! grep -R -F -q -- "policyKitTakeOverAction       = \"io.${TO_BRAND}.sfl.take-over-service\"" "$boxdd"; then
    echo "failed to rewrite core policyKitTakeOverAction" >&2
    exit 1
  fi

  echo "Core application executable: sing-box-${TO_BRAND}.exe"
  echo "Core Windows service name: sing-box-daemon-${TO_BRAND}"
  echo "Core update product name: sing-box-${TO_BRAND}"
}

case "$TARGET" in
  android)
    rewrite_android
    ;;
  desktop)
    rewrite_desktop
    ;;
  core)
    rewrite_core
    ;;
  *)
    echo "unsupported target: $TARGET (expected android|desktop|core)" >&2
    exit 1
    ;;
esac
