#!/usr/bin/env bash

DJ_CUSTOM_CHECK_HASH=
DJ_CUSTOM_CHECK_SNAPSHOT=

dj_custom_check_sha256() {
  local file=$1
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" 2>/dev/null | awk '{print $1}'
  else
    return 1
  fi
}

dj_custom_check_trust_read() {
  local state=$1 id=$2 trust state_device version hash
  DJ_CUSTOM_CHECK_HASH=
  dj_pr_task_id_valid "$id" || return 1
  [ -d "$state" ] && [ ! -L "$state" ] || return 1
  state_device=$(dj_pr_file_device "$state") || return 1
  trust="$state/$id.check-trust"
  dj_pr_private_file_valid "$trust" 600 "$state_device" || return 1
  exec 9< "$trust" || return 1
  IFS= read -r version <&9 || { exec 9<&-; return 1; }
  IFS= read -r hash <&9 || { exec 9<&-; return 1; }
  if IFS= read -r _extra <&9; then
    exec 9<&-
    return 1
  fi
  exec 9<&-
  [ "$version" = dj-custom-check-v1 ] || return 1
  [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || return 1
  DJ_CUSTOM_CHECK_HASH=$hash
}

dj_custom_check_registered() {
  local state=$1 id=$2 check hash state_device
  check="$state/$id.check.sh"
  dj_custom_check_trust_read "$state" "$id" || return 1
  state_device=$(dj_pr_file_device "$state") || return 1
  dj_pr_private_file_valid "$check" 700 "$state_device" || return 1
  hash=$(dj_custom_check_sha256 "$check") || return 1
  [ "$hash" = "$DJ_CUSTOM_CHECK_HASH" ]
}

dj_custom_check_snapshot_prepare() {
  local state=$1 id=$2 check hash state_device
  dj_custom_check_snapshot_cleanup
  check="$state/$id.check.sh"
  dj_custom_check_trust_read "$state" "$id" || return 1
  state_device=$(dj_pr_file_device "$state") || return 1
  dj_pr_private_file_valid "$check" 700 "$state_device" || return 1
  DJ_CUSTOM_CHECK_SNAPSHOT=$(mktemp "$state/.dj-custom-check.XXXXXX") || return 1
  cp "$check" "$DJ_CUSTOM_CHECK_SNAPSHOT" || { dj_custom_check_snapshot_cleanup; return 1; }
  chmod 0600 "$DJ_CUSTOM_CHECK_SNAPSHOT" || { dj_custom_check_snapshot_cleanup; return 1; }
  [ -f "$DJ_CUSTOM_CHECK_SNAPSHOT" ] && [ ! -L "$DJ_CUSTOM_CHECK_SNAPSHOT" ] \
    || { dj_custom_check_snapshot_cleanup; return 1; }
  [ "$(dj_pr_file_mode "$DJ_CUSTOM_CHECK_SNAPSHOT")" = 600 ] \
    || { dj_custom_check_snapshot_cleanup; return 1; }
  [ "$(dj_pr_file_device "$DJ_CUSTOM_CHECK_SNAPSHOT")" = "$state_device" ] \
    || { dj_custom_check_snapshot_cleanup; return 1; }
  [ "$(dj_pr_file_link_count "$DJ_CUSTOM_CHECK_SNAPSHOT")" = 1 ] \
    || { dj_custom_check_snapshot_cleanup; return 1; }
  hash=$(dj_custom_check_sha256 "$DJ_CUSTOM_CHECK_SNAPSHOT") \
    || { dj_custom_check_snapshot_cleanup; return 1; }
  [ "$hash" = "$DJ_CUSTOM_CHECK_HASH" ] || { dj_custom_check_snapshot_cleanup; return 1; }
}

dj_custom_check_snapshot_cleanup() {
  [ -z "$DJ_CUSTOM_CHECK_SNAPSHOT" ] || rm -f -- "$DJ_CUSTOM_CHECK_SNAPSHOT"
  DJ_CUSTOM_CHECK_SNAPSHOT=
}
