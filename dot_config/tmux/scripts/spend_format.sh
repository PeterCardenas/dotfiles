# Shared spend formatting for the tmux status bar. Sourced, not executed.

# Compact dollar amount for the narrow status bar.
# Keeps one decimal under $10 so small spend does not collapse to "$0",
# drops cents up to $1000, and switches to a "k" suffix above that.
format_short_money() {
  # Thresholds add half of the printed precision so an amount that rounds up
  # into the next tier (9.99, 999.6) renders in that tier instead of overflowing.
  awk -v amount="$1" 'BEGIN {
    if (amount + 0.5 >= 1000) printf "$%.1fk", amount / 1000
    else if (amount + 0.05 < 10) printf "$%.1f", amount
    else printf "$%.0f", amount
  }'
}
