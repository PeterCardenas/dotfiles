#     ____      ____
#    / __/___  / __/
#   / /_/_  / / /_
#  / __/ / /_/ __/
# /_/   /___/_/ key-bindings.fish
#
# - $FZF_TMUX_OPTS
# - $FZF_CTRL_T_COMMAND
# - $FZF_CTRL_T_OPTS
# - $FZF_CTRL_R_OPTS
# - $FZF_ALT_C_COMMAND
# - $FZF_ALT_C_OPTS

# Key bindings
# ------------
# Function is called at the end of the file
function rg_fzf_files
    set INITIAL_QUERY $argv
    # TODO try to use toggle-raw to view matching results in context of all results
    set -lx FZF_DEFAULT_OPTS "--height 40% --reverse --bind=ctrl-z:ignore $FZF_DEFAULT_OPTS"
    set result (
            rg --files --hidden 2> /dev/null | \
            fzf --query "$INITIAL_QUERY" \
                --bind "change:reload:sleep 0.1; rg --files --hidden 2> /dev/null | fzf --query {q} || true"
        )

    if test -n "$result"
        echo $result
    end
end

function __bazel_find_targets --description "More performant but more limited method for finding targets"
    set cmd (commandline -xpc)
    set target_scope
    if set -q BAZEL_FZF_TARGET_SCOPE
        set target_scope
        for scope in $BAZEL_FZF_TARGET_SCOPE
            set target_scope $target_scope "$scope/...:*"
        end
    else
        set target_scope "...:*"
    end

    set -lx FZF_DEFAULT_OPTS "--height 40% --reverse --bind=ctrl-z:ignore $FZF_DEFAULT_OPTS"
    set result (if contains -- build $cmd; or contains -- run $cmd
        buildozer 'print label' $target_scope
    else # Should be bazel test here
        buildozer 'print label kind' $target_scope | rg '_test' | cut -d ' ' -f1
    end | sort | fzf)

    if test -n "$result"
        echo $result
    end
end

function __should_find_bazel_targets
    set cmd (commandline -xpc)
    if not contains -- bazel $cmd
        return 1
    end
    if contains -- build $cmd; or contains -- run $cmd; or contains -- test $cmd
        return 0
    end
    return 1
end

function __find_python_files
    set -lx FZF_DEFAULT_OPTS "--height 40% --reverse --bind=ctrl-z:ignore $FZF_DEFAULT_OPTS"
    set result (rg --files --hidden --glob '*.py' 2> /dev/null | \
        fzf --query "$INITIAL_QUERY" \
        --bind "change:reload:sleep 0.1; rg --files --hidden --glob '*.py' 2> /dev/null | fzf --query {q} || true")
    echo $result
end

function __is_running_python
    set cmd (commandline -xpc)
    # Handle prefixes like `env`
    if string match -r -q -- python "$cmd[1]"
        return 0
    end
    return 1
end

if not set -q ctrl_t_commands
    set -g ctrl_t_commands
end
dict set ctrl_t_commands __should_find_bazel_targets __bazel_find_targets
dict set ctrl_t_commands __is_running_python __find_python_files

function fzf-file-widget -d "List files and folders"
    set -l found_ctrl_t_command false
    for checker in (dict keys ctrl_t_commands)
        if $checker
            set found_ctrl_t_command true
            set -l ctrl_t_command (dict get ctrl_t_commands $checker)
            commandline -i ($ctrl_t_command)
            break
        end
    end
    if not $found_ctrl_t_command
        commandline -i (rg_fzf_files)
    end
    commandline -f repaint
end

function fzf-history-widget -d "Show command history"
    begin
        set -lx FZF_DEFAULT_OPTS "--height 40% $FZF_DEFAULT_OPTS --bind=ctrl-r:toggle-sort,ctrl-z:ignore $FZF_CTRL_R_OPTS +m"

        history -z | eval fzf --read0 --print0 -q '(commandline)' | read -lz result
        and commandline -- $result
    end
    commandline -f repaint
end

function fzf-cd-widget -d "Change directory"
    set -l commandline (__fzf_parse_commandline)
    set -l dir $commandline[1]
    set -l fzf_query $commandline[2]
    set -l prefix $commandline[3]

    test -n "$FZF_ALT_C_COMMAND"; or set -l FZF_ALT_C_COMMAND "
    command find -L \$dir -mindepth 1 \\( -path \$dir'*/\\.*' -o -fstype 'sysfs' -o -fstype 'devfs' -o -fstype 'devtmpfs' \\) -prune \
    -o -type d -print 2> /dev/null | sed 's@^\./@@'"
    begin
        set -lx FZF_DEFAULT_OPTS "--height 40% --reverse --bind=ctrl-z:ignore $FZF_DEFAULT_OPTS $FZF_ALT_C_OPTS"
        eval "$FZF_ALT_C_COMMAND | "fzf' +m --query "'$fzf_query'"' | read -l result

        if [ -n "$result" ]
            cd -- $result

            # Remove last token from commandline.
            commandline -t ""
            commandline -it -- $prefix
        end
    end

    commandline -f repaint
end

function fzf-widget -a widget_name
    set -l pane_id (tmux display-message -p -F "#{pane_id}")
    tmux set-option -t $pane_id -p @disable_vertical_pane_navigation yes
    switch $widget_name
        case file
            fzf-file-widget
        case history
            fzf-history-widget
        case cd
            fzf-cd-widget
    end
    tmux set-option -t $pane_id -p -u @disable_vertical_pane_navigation
end

bind \ct "fzf-widget file"
bind \ec "fzf-widget cd"

if bind -M insert >/dev/null 2>&1
    bind -M insert \ct "fzf-widget file"
    bind -M insert \cr "fzf-widget history"
    bind -M insert \ec "fzf-widget cd"
end

function __fzf_parse_commandline -d 'Parse the current command line token and return split of existing filepath, fzf query, and optional -option= prefix'
    set -l commandline (commandline -t)

    # strip -option= from token if present
    set -l prefix (string match -r -- '^-[^\s=]+=' $commandline)
    set commandline (string replace -- "$prefix" '' $commandline)

    # eval is used to do shell expansion on paths
    eval set commandline $commandline

    if [ -z "$commandline" ]
        # Default to current directory with no --query
        set dir '.'
        set fzf_query ''
    else
        set dir (__fzf_get_dir $commandline)

        if [ "$dir" = "." -a (string sub -l 1 -- $commandline) != '.' ]
            # if $dir is "." but commandline is not a relative path, this means no file path found
            set fzf_query $commandline
        else
            # Also remove trailing slash after dir, to "split" input properly
            set fzf_query (string replace -r "^$dir/?" -- '' "$commandline")
        end
    end

    echo $dir
    echo $fzf_query
    echo $prefix
end

function __fzf_get_dir -d 'Find the longest existing filepath from input string'
    set dir $argv

    # Strip all trailing slashes. Ignore if $dir is root dir (/)
    if [ (string length -- $dir) -gt 1 ]
        set dir (string replace -r '/*$' -- '' $dir)
    end

    # Iteratively check if dir exists and strip tail end of path
    while [ ! -d "$dir" ]
        # If path is absolute, this can keep going until ends up at /
        # If path is relative, this can keep going until entire input is consumed, dirname returns "."
        set dir (dirname -- "$dir")
    end

    echo $dir
end
