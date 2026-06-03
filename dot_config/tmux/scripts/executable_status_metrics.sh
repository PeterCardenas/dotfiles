#!/usr/bin/env bash
export LC_ALL=C

short=false
[ "$1" = "--short" ] && short=true

scripts_dir="${TMUX_SCRIPTS_DIR:-$HOME/.config/tmux/scripts}"

cursor_cmd=("$scripts_dir/cursor_spend.sh")
claude_cmd=("$scripts_dir/claude_spend.sh")
cpu_cmd=("$scripts_dir/cpu.sh")
ram_cmd=("$scripts_dir/ram.sh")

if $short; then
  cursor_cmd+=(--short)
  claude_cmd+=(--short)
  ram_cmd+=(--short)
fi

run_segment() {
  "$@" 2>/dev/null
}

join_segments() {
  local separator="$1"
  shift

  local result=""
  local segment
  for segment in "$@"; do
    [ -n "$segment" ] || continue
    if [ -n "$result" ]; then
      result="${result}${separator}${segment}"
    else
      result="$segment"
    fi
  done

  printf '%s' "$result"
}

cursor_segment=$(run_segment "${cursor_cmd[@]}")
claude_segment=$(run_segment "${claude_cmd[@]}")
cpu_value=$(run_segment "${cpu_cmd[@]}")
ram_value=$(run_segment "${ram_cmd[@]}")

# Only render separators between segments that actually have content.
segments=(
  "${cursor_segment:+#[fg=#c0caf5]${cursor_segment}}"
  "${claude_segment:+#[fg=#c0caf5]${claude_segment}}"
  "${cpu_value:+#[fg=#ff9e64]󰍛 #[fg=#c0caf5]${cpu_value}}"
  "${ram_value:+#[fg=#7dcfff]󰘚 #[fg=#c0caf5]${ram_value}}"
)

separator=' #[fg=#565f89]· '
$short && separator=' '

join_segments "$separator" "${segments[@]}"
