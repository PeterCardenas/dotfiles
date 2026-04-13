# Clear all previous abbreviations
abbr -e (abbr -l)

# Use SIGWINCH for async prompt repaint — Fish 4.x natively repaints on SIGWINCH,
# whereas SIGUSR1 + commandline -f repaint no longer works from signal handlers.
set -g async_prompt_signal_number SIGWINCH
