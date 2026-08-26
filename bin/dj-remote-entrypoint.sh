#!/usr/bin/env bash
# Fixed remote entrypoint for bin/dj-on.sh.
#
# Install this tracked file as dj-remote-entrypoint.sh on the remote account's
# non-interactive SSH PATH. It accepts protocol metadata plus a base64-encoded
# NUL argv stream, validates one genuine tracked executable in <root>/bin/dj-*.sh,
# then stages it for the Jarvis-owned remote job worker. It never accepts a
# shell command string.
#
# The readiness-owning dj-remote-doctor.sh runs in this plain SSH bootstrap so
# check mode can inspect worker gaps without changing them and --fix can repair
# them. Every other command is staged after the worker is ready. On Darwin, a
# missing Aqua session fails before staging with the doctor-actionable
# console-login diagnostic. Linux uses the same queue and worker shape without
# an Aqua requirement.
#
# stdin is captured as bounded job input. The completed worker result is relayed
# with stdout and stderr kept separate and its exit status preserved. An SSH
# disconnect remains unknown completion to dj-on.sh, which preserves OpenSSH's
# exit 255 behavior. The shared library header owns job fields, bounds, PATH,
# LaunchAgent contract, and worker environment.
set -eu

PROTOCOL=1
DOCTOR_SHA256=7bb13d9fad8455978bf109d4681a3aa3cb170565c8a74be4ec7b520427db14c2
REAL_SOURCE=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "${BASH_SOURCE[0]}" 2>/dev/null) ||
  REAL_SOURCE=$(realpath "${BASH_SOURCE[0]}" 2>/dev/null) ||
  REAL_SOURCE=${BASH_SOURCE[0]}
SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$REAL_SOURCE")" && pwd -P)

# shellcheck source=bin/dj-remote-job-lib.sh
. "$SCRIPT_DIR/dj-remote-job-lib.sh"

die() { printf 'error: %s\n' "$1" >&2; exit "${2:-64}"; }

base64_decode_to() { # <encoded> <destination>
  local encoded=$1 destination=$2
  if printf '%s' "$encoded" | base64 --decode > "$destination" 2>/dev/null; then return 0; fi
  if printf '%s' "$encoded" | base64 -D > "$destination" 2>/dev/null; then return 0; fi
  return 1
}

decode_text() { # <label> <encoded> <destination>
  local label=$1 encoded=$2 destination=$3 bytes controls
  base64_decode_to "$encoded" "$destination" || die "invalid base64 for $label"
  bytes=$(LC_ALL=C wc -c < "$destination" | tr -d ' ')
  [ "$bytes" -gt 0 ] || die "$label is empty"
  controls=$(dj_remote_job_has_forbidden_text_bytes "$destination")
  [ "$controls" -eq 0 ] || die "$label contains forbidden control bytes"
}

path_is_ancestor() { # <ancestor> <path>
  [ "$1" != "$2" ] || return 1
  case "$2" in "$1"/*) return 0 ;; esac
  return 1
}

sha256_file() { # <path>
  local path=$1 digest extra
  if [ -x /usr/bin/shasum ]; then
    read -r digest extra < <(/usr/bin/shasum -a 256 "$path") || return 1
  elif [ -x /usr/bin/sha256sum ]; then
    read -r digest extra < <(/usr/bin/sha256sum "$path") || return 1
  elif [ -x /bin/sha256sum ]; then
    read -r digest extra < <(/bin/sha256sum "$path") || return 1
  else
    return 1
  fi
  case "$digest" in *[!0-9a-f]*|'') return 1 ;; esac
  [ "${#digest}" -eq 64 ] || return 1
  printf '%s\n' "$digest"
}

[ "$#" -eq 4 ] || die "remote entrypoint expects protocol, root, home, and argv"
[ "$1" = "$PROTOCOL" ] || die "incompatible remote protocol: local=$1 remote=$PROTOCOL"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/dj-remote-entrypoint.XXXXXX") || die "cannot create protocol staging directory" 70
trap 'rm -rf -- "$TMP"' EXIT

decode_text "remote root" "$2" "$TMP/root"
decode_text "remote home" "$3" "$TMP/home"
base64_decode_to "$4" "$TMP/argv" || die "invalid base64 for argv"
ROOT=$(<"$TMP/root")
HOME_PATH=$(<"$TMP/home")
ROOT=$(dj_remote_job_canonical_existing_dir "$ROOT") || die "remote root is not a safe existing directory"
HOME_PATH=$(dj_remote_job_canonical_home "$HOME_PATH") || die "remote home is not a safe directory"
[ -f "$ROOT/AGENTS.md" ] && [ ! -L "$ROOT/AGENTS.md" ] || die "remote root is not a Jarvis checkout"
[ -d "$ROOT/bin" ] && [ ! -L "$ROOT/bin" ] || die "remote root has no safe bin directory"
if path_is_ancestor "$ROOT" "$HOME_PATH" || path_is_ancestor "$HOME_PATH" "$ROOT" || [ "$ROOT" = "$HOME_PATH" ]; then
  die "remote root and home must be separate, non-overlapping directories"
fi

ARGV=()
while IFS= read -r -d '' arg; do ARGV+=("$arg"); done < "$TMP/argv"
[ "${#ARGV[@]}" -ge 1 ] || die "argv contains no command"
COMMAND=${ARGV[0]}
case "$COMMAND" in dj-*.sh) ;; *) die "command is outside the dj-*.sh namespace: $COMMAND" ;; esac
case "$COMMAND" in */*|*..*) die "command contains a path or traversal: $COMMAND" ;; esac
COMMAND_PATH="$ROOT/bin/$COMMAND"
[ -f "$COMMAND_PATH" ] && [ ! -L "$COMMAND_PATH" ] && [ -x "$COMMAND_PATH" ] \
  || die "command is not a genuine executable in the configured remote root: $COMMAND"
unset HOME
ACCOUNT_HOME=$(CDPATH='' cd ~ 2>/dev/null && pwd -P) || die "cannot resolve the remote account home"
dj_remote_job_compose_operator_path "$ACCOUNT_HOME" >/dev/null
GIT_BIN=$(dj_remote_job_operator_tool git 2>/dev/null || true)
if [ -n "$GIT_BIN" ]; then
  "$GIT_BIN" -C "$ROOT" ls-files --error-unmatch "bin/$COMMAND" >/dev/null 2>&1 \
    || die "command is not tracked by the configured remote root: $COMMAND"
elif [ "$COMMAND" = dj-remote-doctor.sh ]; then
  ACTUAL_DOCTOR_SHA256=$(sha256_file "$COMMAND_PATH") \
    || die "required tool git is unavailable and the doctor bootstrap identity cannot be verified"
  [ "$ACTUAL_DOCTOR_SHA256" = "$DOCTOR_SHA256" ] \
    || die "required tool git is unavailable and the doctor does not match the trusted bootstrap identity"
else
  die "required tool git does not resolve on the remote operator PATH; install git there or put a wrapper for it in ~/.local/bin using the recipe in docs/remote-secondmates.md"
fi
if [ "$COMMAND" = dj-remote-doctor.sh ]; then
  dj_remote_job_build_child_path "$ROOT" >/dev/null
  DOCTOR_ENV=(
    /usr/bin/env -i
    "PATH=$DJ_REMOTE_JOB_CHILD_PATH"
    "HOME=$ACCOUNT_HOME"
    "DJ_HOME=$HOME_PATH"
    "DJ_ROOT_OVERRIDE=$ROOT"
    DJ_REMOTE_DOCTOR_BOOTSTRAP=1
  )
  if [ -n "${DJ_REMOTE_JOB_PLATFORM_OVERRIDE:-}" ]; then
    DOCTOR_ENV+=("DJ_REMOTE_JOB_PLATFORM_OVERRIDE=$DJ_REMOTE_JOB_PLATFORM_OVERRIDE")
  fi
  if [ -n "${DJ_REMOTE_JOB_STATE_ROOT:-}" ]; then
    DOCTOR_ENV+=("DJ_REMOTE_JOB_STATE_ROOT=$DJ_REMOTE_JOB_STATE_ROOT")
  fi
  trap - EXIT
  rm -rf -- "$TMP"
  exec "${DOCTOR_ENV[@]}" "$COMMAND_PATH" "${ARGV[@]:1}"
fi

if ! dj_remote_job_ensure_worker "$ROOT" "$ACCOUNT_HOME"; then
  die "${DJ_REMOTE_JOB_ERROR:-remote job worker is unavailable; run dj-on.sh <route> dj-remote-doctor.sh --fix}"
fi
if ! JOB_ID=$(dj_remote_job_stage "$ACCOUNT_HOME" "$ROOT" "$HOME_PATH" "$COMMAND" "${ARGV[@]:1}"); then
  die "${DJ_REMOTE_JOB_ERROR:-cannot stage remote job}" 70
fi
if ! dj_remote_job_wait "$ACCOUNT_HOME" "$JOB_ID"; then
  die "${DJ_REMOTE_JOB_ERROR:-remote job did not complete}" 70
fi
cat "$DJ_REMOTE_JOB_STDOUT"
cat "$DJ_REMOTE_JOB_STDERR" >&2
RESULT=$DJ_REMOTE_JOB_EXIT
dj_remote_job_reap "$ACCOUNT_HOME" "$JOB_ID" || true
trap - EXIT
rm -rf -- "$TMP"
exit "$RESULT"
