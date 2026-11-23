# conf.d runs before config.fish and in every shell, so other sources' conf.d
# snippets, Herdr popups and agents can all locate stol projects.
set -gx STOL_ROOT "$HOME/work"
set -gx STOL_PREFIX pcardenas
