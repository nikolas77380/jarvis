#!/usr/bin/env bash
# Detect temporary provider quota failures and persist their automatic-resume deadline.

quota_message_matches() {
  grep -Eiq "monthly spend limit|session limit resets|usage[- ]credits|rate limit.*reset|quota.*reset"
}

quota_resume_epoch() {
  local text=$1 now=${2:-$(date +%s)} iso clock zone day epoch
  iso=$(printf '%s\n' "$text" | sed -nE 's/.*([0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}(:[0-9]{2})?([+-][0-9]{2}:[0-9]{2}|Z)).*/\1/p' | head -1)
  if [ -n "$iso" ]; then
    date -j -f '%Y-%m-%dT%H:%M:%S%z' "${iso/Z/+0000}" +%s 2>/dev/null \
      || date -d "$iso" +%s 2>/dev/null
    return
  fi
  clock=$(printf '%s\n' "$text" | sed -nE 's/.*reset(s)?[[:space:]]+([0-9]{1,2}:[0-9]{2}(am|pm)).*/\2/ip' | head -1)
  zone=$(printf '%s\n' "$text" | sed -nE 's/.*\(([A-Za-z0-9._+-]+\/[A-Za-z0-9._+-]+)\).*/\1/p' | head -1)
  [ -n "$clock" ] || return 1
  zone=${zone:-UTC}
  day=$(TZ="$zone" date +%Y-%m-%d)
  epoch=$(TZ="$zone" date -j -f '%Y-%m-%d %I:%M%p' "$day $clock" +%s 2>/dev/null \
    || TZ="$zone" date -d "$day $clock" +%s 2>/dev/null) || return 1
  if [ "$epoch" -le "$now" ]; then
    # A recovery poll can first see the message shortly after its reset passed. Resume now instead
    # of postponing it for a day; a clock more than twelve hours behind means the next occurrence.
    if [ $((now - epoch)) -lt 43200 ]; then printf '%s\n' "$now"; return; fi
    day=$(TZ="$zone" date -j -v+1d -f '%Y-%m-%d' "$day" +%Y-%m-%d 2>/dev/null \
      || TZ="$zone" date -d "$day +1 day" +%Y-%m-%d 2>/dev/null) || return 1
    epoch=$(TZ="$zone" date -j -f '%Y-%m-%d %I:%M%p' "$day $clock" +%s 2>/dev/null \
      || TZ="$zone" date -d "$day $clock" +%s 2>/dev/null) || return 1
  fi
  printf '%s\n' "$epoch"
}

quota_meta_write() {
  local key=$1 kind=$2 engine=$3 epoch=$4 excerpt=$5 file tmp
  mkdir -p "$HARNESS_STATE/quota"
  file="$HARNESS_STATE/quota/$key.meta"
  tmp=$(mktemp "$HARNESS_STATE/quota/.quota.XXXXXX")
  printf 'schema=harness-quota-resume.v1\nkey=%s\nkind=%s\nengine=%s\nblocked_reason=quota\nresume_at=%s\ndetected_at=%s\nexcerpt=%s\n' \
    "$key" "$kind" "$engine" "$epoch" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    "$(printf '%s' "$excerpt" | tr '\n=' '  ' | cut -c1-240)" > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$file"
  printf '%s\n' "$file"
}
