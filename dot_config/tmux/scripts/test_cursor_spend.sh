#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"; rm -f /tmp/tmux-cursor-spend-999999 /tmp/tmux-cursor-spend-999999-short' EXIT

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
  expected="󰆦 \$100.00 | #[fg=${expected_color}]\$100.00"
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

assert_short() {
  local expected="$1"
  local output

  rm -f /tmp/tmux-cursor-spend-999999-short
  output=$(HOME="$tmp/home" PATH="$tmp/bin:$PATH" TEST_CURL_LOG="$tmp/curl.log" TEST_REMAINING_CENTS=10000 \
    bash "$script_dir/executable_cursor_spend.sh" --short)
  if [ "$output" != "$expected" ]; then
    printf 'expected short output %s, got: %s\n' "$expected" "$output" >&2
    return 1
  fi
}

assert_short_money() {
  local amount="$1"
  local expected="$2"
  local output

  output=$(format_short_money "$amount")
  if [ "$output" != "$expected" ]; then
    printf 'expected format_short_money %s to be %s, got: %s\n' "$amount" "$expected" "$output" >&2
    return 1
  fi
}

assert_color 500 '#f7768e'
assert_color 3000 '#ff9e64'
assert_color 6000 '#e0af68'
assert_color 10000 '#9ece6a'

# Narrow status bar drops cents; the stubbed API reports $100.00 month-to-date.
assert_short '󰆦 #[fg=#9ece6a]$100'

. "$script_dir/spend_format.sh"
assert_short_money 0.42 '$0.4'
assert_short_money 9.94 '$9.9'
assert_short_money 9.99 '$10'
assert_short_money 12.34 '$12'
assert_short_money 999.4 '$999'
assert_short_money 1234.5 '$1.2k'
