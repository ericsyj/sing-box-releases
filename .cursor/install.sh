#!/usr/bin/env bash
# Idempotent Cloud Agent setup for the sing-box release pipeline.
#
# This repository has no runnable service; it is a GitHub Actions release
# pipeline plus the rewrite-gui-package-ids.sh helper. The development
# experience is authoring and validating those workflows and shell scripts,
# so setup installs the linters/validators used to check them before pushing:
#
#   - actionlint : validate GitHub Actions workflow YAML (and embedded shell)
#   - shellcheck : lint shell scripts (also used by actionlint)
#   - yamllint   : lint workflow/build-info YAML/JSON style
#
# It must stay non-interactive and safe to run repeatedly.
set -euo pipefail

ACTIONLINT_VERSION="1.7.7"
ACTIONLINT_SHA256="023070a287cd8cccd71515fedc843f1985bf96c436b7effaecce67290e7e0757"
INSTALL_DIR="/usr/local/bin"

log() { printf '==> %s\n' "$*"; }

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

log "Installing system linters via apt (shellcheck, yamllint)"
export DEBIAN_FRONTEND=noninteractive
as_root apt-get update -y
as_root apt-get install -y --no-install-recommends shellcheck yamllint ca-certificates curl

install_actionlint() {
  if command -v actionlint >/dev/null 2>&1 &&
     actionlint --version 2>/dev/null | head -1 | grep -qx "$ACTIONLINT_VERSION"; then
    log "actionlint ${ACTIONLINT_VERSION} already installed"
    return
  fi

  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  local tarball="actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz"
  local url="https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/${tarball}"

  log "Downloading actionlint ${ACTIONLINT_VERSION}"
  curl -fsSL "$url" -o "$tmp/$tarball"
  echo "${ACTIONLINT_SHA256}  $tmp/$tarball" | sha256sum -c -

  tar -xzf "$tmp/$tarball" -C "$tmp" actionlint
  as_root install -m 0755 "$tmp/actionlint" "${INSTALL_DIR}/actionlint"
}

install_actionlint

log "Installed tool versions:"
printf '  shellcheck : %s\n' "$(shellcheck --version | awk '/^version:/ {print $2}')"
printf '  yamllint   : %s\n' "$(yamllint --version | awk '{print $2}')"
printf '  actionlint : %s\n' "$(actionlint --version | head -1)"

log "Setup complete"
