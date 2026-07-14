#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"; rm -f /tmp/tmux-cursor-spend-999999' EXIT

mkdir -p "$tmp/bin" "$tmp/home/.config/cursor"

payload=$(printf '{"sub":"user_test"}' | base64 | tr -d '=\n' | tr '/+' '_-')
jq -n --arg token "x.${payload}.x" '{accessToken: $token}' >"$tmp/home/.config/cursor/auth.json"

cat >"$tmp/bin/id" <<'EOF'
#!/usr/bin/env bash
printf '999999\n'
EOF

cat >"$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_CURL_LOG"
case "$*" in
*GetAggregatedUsageEvents*)
  printf '{"totalCostCents":10000}'
  ;;
*usage-summary*)
  printf '{"individualUsage":{"overall":{"remaining":%s}}}' "$TEST_REMAINING_CENTS"
  ;;
*)
  exit 1
  ;;
esac
EOF

chmod +x "$tmp/bin/id" "$tmp/bin/curl"

assert_color() {
  local remaining_cents="$1"
  local expected_color="$2"
  local output

  rm -f /tmp/tmux-cursor-spend-999999
  curl_log="$tmp/curl.log"
  output=$(HOME="$tmp/home" PATH="$tmp/bin:$PATH" TEST_CURL_LOG="$curl_log" TEST_REMAINING_CENTS="$remaining_cents" \
    bash "$script_dir/executable_cursor_spend.sh")
  expected="󰆦 \$14.29/day | #[fg=${expected_color}]\$100.00"
  if [ "$output" != "$expected" ]; then
    printf 'expected %s for %s cents remaining, got: %s\n' "$expected_color" "$remaining_cents" "$output" >&2
    return 1
  fi
  if ! rg --quiet 'startDate' "$curl_log"; then
    printf 'expected Cursor usage requests to include a rolling-period start date\n' >&2
    return 1
  fi
  rolling_start_ms=$(date -u -d "7 days ago" +%s000)
  if ! rg --quiet "\"startDate\":\"${rolling_start_ms}\"" "$curl_log"; then
    printf 'expected Cursor usage requests to start seven days ago\n' >&2
    return 1
  fi
}

assert_color 500 '#f7768e'
assert_color 3000 '#ff9e64'
assert_color 6000 '#e0af68'
assert_color 10000 '#9ece6a'
