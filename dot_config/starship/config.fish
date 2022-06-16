# Starship setup
# TODO Fix issue when shared and warp use the same modules
if test (uname -s) = Darwin
    alias using_warp="ps -p (ps -p $fish_pid -o ppid | sed -n '2 p') -o args | grep Warp"
    set -l starship_dir "$HOME"/.config/starship
    if using_warp
        set -gx STARSHIP_CONFIG "$starship_dir"/config-warp.toml
        : > $STARSHIP_CONFIG
        cat "$starship_dir"/shared-globals.toml >> $STARSHIP_CONFIG
        cat "$starship_dir"/warp-globals.toml >> $STARSHIP_CONFIG
        cat "$starship_dir"/warp-modules.toml >> $STARSHIP_CONFIG
    else
        set -gx STARSHIP_CONFIG "$starship_dir"/config.toml
        : > $STARSHIP_CONFIG
        cat "$starship_dir"/shared-globals.toml >> $STARSHIP_CONFIG
        cat "$starship_dir"/standard-globals.toml >> $STARSHIP_CONFIG
        cat "$starship_dir"/standard-modules.toml >> $STARSHIP_CONFIG
    end
    cat "$starship_dir"/shared-modules.toml >> $STARSHIP_CONFIG
end
