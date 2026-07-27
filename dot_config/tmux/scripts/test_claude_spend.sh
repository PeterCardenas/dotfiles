#!/usr/bin/env bash
# Tests for executable_claude_spend.sh.
#
# Main regression: a PID file owned by a live nvim must never be rolled into the
# daily aggregate. nvim rewrites that file from its in-memory per-date totals, so
# an early roll gets undone and then rolled a second time when nvim exits, which
# double-counted every nvim alive across the UTC date change.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
script="$script_dir/executable_claude_spend.sh"
tmp=$(mktemp -d)
pids=()
trap 'for p in "${pids[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null || true; done; rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"
export PATH="$tmp/bin:$PATH"
export XDG_DATA_HOME="$tmp/data"
export XDG_CACHE_HOME="$tmp/cache"
spend_dir="$tmp/data/claude-spend"

failures=0
check() {
  local label=$1 expected=$2 actual=$3
  if [ "$expected" = "$actual" ]; then
    printf 'ok   %s\n' "$label"
  else
    printf 'FAIL %s\n       expected: %s\n       actual:   %s\n' "$label" "$expected" "$actual"
    failures=$((failures + 1))
  fi
}

# `kill -0` is a bash builtin so liveness cannot be faked; use real background
# processes for that and shim `ps` to control the reported process name.
write_ps_shim() {
  cat >"$tmp/bin/ps" <<EOF
#!/usr/bin/env bash
# invoked as: ps -o comm= -p <pid>
pid=\${*: -1}
case "\$pid" in
$1
*) exit 1 ;;
esac
EOF
  chmod +x "$tmp/bin/ps"
}

reset_state() {
  rm -rf "$tmp/data" "$tmp/cache"
  mkdir -p "$spend_dir" "$tmp/cache/claude-spend"
}

start_proc() {
  # stdout/stderr must be detached, otherwise the background process holds the
  # command-substitution pipe open and the caller blocks until it exits.
  sleep 300 >/dev/null 2>&1 &
  local pid=$!
  pids+=("$pid")
  printf '%s' "$pid"
}

yesterday=$(date -u -d '1 day ago' +%Y-%m-%d 2>/dev/null || date -u -v-1d +%Y-%m-%d)

# --- 1. A live nvim's PID file is never rolled, even with no entry for today ---
reset_state
live_pid=$(start_proc)
write_ps_shim "$live_pid) printf 'nvim\n' ;;"
printf '%s 100.0000\n' "$yesterday" >"$spend_dir/$live_pid"

"$script" --local >/dev/null
check "live nvim: PID file survives the scan" "yes" \
  "$([ -f "$spend_dir/$live_pid" ] && echo yes || echo no)"
check "live nvim: nothing rolled into daily-$yesterday" "absent" \
  "$([ -f "$spend_dir/daily-$yesterday" ] && cat "$spend_dir/daily-$yesterday" || echo absent)"

# nvim keeps running and flushes again, then finally exits.
printf '%s 100.0000\n' "$yesterday" >"$spend_dir/$live_pid"
write_ps_shim "$live_pid) exit 1 ;;"
kill "$live_pid" 2>/dev/null || true
wait "$live_pid" 2>/dev/null || true
"$script" --local >/dev/null
check "after exit: rolled exactly once (was 200.0000)" "100.0000" \
  "$(cat "$spend_dir/daily-$yesterday")"

# --- 2. A dead PID file rolls in once and is removed ---
reset_state
write_ps_shim "*) exit 1 ;;"
printf '%s 7.5000\n' "$yesterday" >"$spend_dir/999999999"
"$script" --local >/dev/null
check "dead PID: rolled into daily" "7.5000" "$(cat "$spend_dir/daily-$yesterday")"
check "dead PID: file removed" "no" \
  "$([ -f "$spend_dir/999999999" ] && echo yes || echo no)"
"$script" --local >/dev/null
check "dead PID: rescan does not re-roll" "7.5000" "$(cat "$spend_dir/daily-$yesterday")"

# --- 3. A recycled PID (alive, but not nvim) is cleaned up ---
reset_state
other_pid=$(start_proc)
write_ps_shim "$other_pid) printf 'sleep\n' ;;"
printf '%s 3.0000\n' "$yesterday" >"$spend_dir/$other_pid"
"$script" --local >/dev/null
check "recycled PID: rolled in" "3.0000" "$(cat "$spend_dir/daily-$yesterday")"
check "recycled PID: file removed" "no" \
  "$([ -f "$spend_dir/$other_pid" ] && echo yes || echo no)"

# --- 4. An unreachable peer keeps the last good total instead of reporting $0 ---
cat >"$tmp/bin/ssh" <<'EOF'
#!/usr/bin/env bash
exit 255
EOF
chmod +x "$tmp/bin/ssh"

reset_state
write_ps_shim "*) exit 1 ;;"
now=$(date +%s)
printf '%s\n5.0000 50.0000\n%s' "$((now - 60))" "$((now - 60))" \
  >"$tmp/cache/claude-spend/tmux-spend-remote"
out=$("$script")
check "peer down, recently seen: last good total retained" "yes" \
  "$(grep -q '\$5.00 | \$50.00' <<<"$out" && echo yes || echo no)"

# Beyond remote_max_stale (600s) the cached value is no longer trusted.
reset_state
printf '%s\n5.0000 50.0000\n%s' "$((now - 700))" "$((now - 700))" \
  >"$tmp/cache/claude-spend/tmux-spend-remote"
out=$("$script")
check "peer down, stale beyond cutoff: drops to empty" "" "$out"

if [ "$failures" -gt 0 ]; then
  printf '\n%d test(s) failed\n' "$failures"
  exit 1
fi
printf '\nall tests passed\n'
