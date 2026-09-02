#!/usr/bin/env bash
# One-command onboarding for a freshly cloned Jarvis checkout on macOS: installs missing runtime
# dependencies, exposes the global `jarvis` command, verifies the setup, and prints the explicit
# next actions. Homebrew itself is a prerequisite and is never installed automatically. Existing
# tool versions are never upgraded.
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  SOURCE_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  case "$SOURCE" in
    /*) ;;
    *) SOURCE="$SOURCE_DIR/$SOURCE" ;;
  esac
done
ROOT="$(cd -P "$(dirname "$SOURCE")" && pwd)"
JARVIS_BIN="$ROOT/bin/jarvis"
JARVIS_LINK="$HOME/.local/bin/jarvis"

HOMEBREW_INSTALL_URL='https://brew.sh'
# shellcheck disable=SC2016 # single-quoted deliberately: printed verbatim, never executed here
HOMEBREW_INSTALL_CMD='/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
HERDR_INSTALL_CMD='curl -fsSL https://herdr.dev/install.sh | sh'
CLAUDE_INSTALL_CMD='curl -fsSL https://claude.ai/install.sh | bash -s stable'
# shellcheck disable=SC2016 # single-quoted deliberately: $HOME must expand at profile-load time, not now
PATH_EXPORT_LINE='export PATH="$HOME/.local/bin:$PATH"'

die() { echo "error: $*" >&2; exit 1; }
info() { echo "$*"; }

require_macos() {
  local os
  os=$(uname -s)
  [ "$os" = Darwin ] || die "bootstrap.sh supports macOS only (Darwin); detected: $os"
}

require_brew() {
  command -v brew >/dev/null 2>&1 && return 0
  {
    echo "Homebrew is required but was not found on PATH."
    echo "Install it first, then re-run bootstrap.sh:"
    echo "  $HOMEBREW_INSTALL_CMD"
    echo "Details: $HOMEBREW_INSTALL_URL"
  } >&2
  exit 1
}

ensure_brew_pkg() {
  local pkg=$1
  if command -v "$pkg" >/dev/null 2>&1; then
    info "ok: $pkg already installed ($(command -v "$pkg"))"
    return 0
  fi
  info "installing $pkg via Homebrew..."
  brew install "$pkg"
  command -v "$pkg" >/dev/null 2>&1 || die "$pkg installation did not put $pkg on PATH"
}

ensure_herdr() {
  if command -v herdr >/dev/null 2>&1; then
    info "ok: herdr already installed ($(command -v herdr))"
    return 0
  fi
  info "installing herdr: $HERDR_INSTALL_CMD"
  curl -fsSL https://herdr.dev/install.sh | sh
  command -v herdr >/dev/null 2>&1 || die "herdr installation did not put herdr on PATH"
}

ensure_claude() {
  if command -v claude >/dev/null 2>&1; then
    info "ok: claude already installed ($(command -v claude))"
    return 0
  fi
  info "installing Claude Code: $CLAUDE_INSTALL_CMD"
  curl -fsSL https://claude.ai/install.sh | bash -s stable
  command -v claude >/dev/null 2>&1 || die "Claude Code installation did not put claude on PATH"
}

ensure_path_export() {
  local zprofile="$HOME/.zprofile"
  if [ -f "$zprofile" ] && grep -Fqx "$PATH_EXPORT_LINE" "$zprofile"; then
    info "ok: PATH export already present in $zprofile"
    return 0
  fi
  printf '\n%s\n' "$PATH_EXPORT_LINE" >> "$zprofile"
  info "added PATH export to $zprofile"
}

# Confirm before replacing an unexpected file at $JARVIS_LINK. Only ever consulted when the
# destination is a regular file/directory, never a symlink (a stale symlink is always safe to
# repair without asking). Refuses without any mutation when stdin/stdout are not a terminal.
confirm_replace() {
  local path=$1 reply
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    return 1
  fi
  printf '%s exists and is not a symlink bootstrap.sh manages. Replace it? [y/N] ' "$path" >&2
  read -r reply || reply=''
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

ensure_symlink() {
  local local_bin="$HOME/.local/bin" tmp_link current
  mkdir -p "$local_bin"
  if [ -L "$JARVIS_LINK" ]; then
    current=$(readlink "$JARVIS_LINK")
    if [ "$current" = "$JARVIS_BIN" ]; then
      info "ok: $JARVIS_LINK already points to $JARVIS_BIN"
      return 0
    fi
    info "repairing $JARVIS_LINK (was: $current)"
  elif [ -e "$JARVIS_LINK" ]; then
    confirm_replace "$JARVIS_LINK" || die "refusing to replace $JARVIS_LINK without confirmation"
  fi
  tmp_link="$local_bin/.jarvis.bootstrap.$$"
  ln -s "$JARVIS_BIN" "$tmp_link"
  mv "$tmp_link" "$JARVIS_LINK"
  info "linked $JARVIS_LINK -> $JARVIS_BIN"
}

verify() {
  echo
  echo "Verifying installation:"
  local tool
  for tool in git jq herdr claude; do
    command -v "$tool" >/dev/null 2>&1 || die "verification failed: $tool not found on PATH"
    echo "  $tool: $(command -v "$tool")"
  done
  [ -L "$JARVIS_LINK" ] || die "verification failed: $JARVIS_LINK is not a symlink"
  [ "$(readlink "$JARVIS_LINK")" = "$JARVIS_BIN" ] \
    || die "verification failed: $JARVIS_LINK does not point to $JARVIS_BIN"
  echo "  jarvis symlink: $JARVIS_LINK -> $JARVIS_BIN"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*)
      echo "  PATH: $HOME/.local/bin is already on PATH" ;;
    *)
      echo "  PATH: $HOME/.local/bin added to ~/.zprofile (open a new terminal, or run: source ~/.zprofile)" ;;
  esac
  "$JARVIS_LINK" status || die "verification failed: jarvis status did not run cleanly"
}

main() {
  require_macos
  require_brew

  ensure_brew_pkg git
  ensure_brew_pkg jq
  ensure_herdr
  ensure_claude

  ensure_path_export
  ensure_symlink

  verify

  echo
  echo "Next actions:"
  echo "  Authenticate: claude"
  echo "  Start Jarvis: jarvis claude"
}

main "$@"
