function lazygit --wraps lazygit
    git rev-parse --is-inside-work-tree 2>/dev/null | read -l inside_worktree
    set -l git_status $pipestatus[1]

    if test $git_status -ne 0
        print_warn "Not a git repository, launching lazygit anyway"
        command lazygit $argv
        return
    end

    if test "$inside_worktree" = true
        print_info "Inside a work tree, launching lazygit directly"
        command lazygit $argv
        return
    end

    # We're in a bare repo — list worktrees and let the user pick one
    print_info "Bare repo detected, discovering worktrees..."
    set -l worktrees (git worktree list --porcelain | string replace --filter --regex '^worktree ' '')

    # Filter out the bare repo root itself
    set -l bare_dir (git rev-parse --git-dir)
    print_info "Bare repo root: $bare_dir"
    set -l choices
    for wt in $worktrees
        if test "$wt" != "$bare_dir"
            print_info "Found worktree: $wt"
            set choices $choices $wt
        end
    end

    if test (count $choices) -eq 0
        print_error "No worktrees found in this bare repo."
        return 1
    end

    if test (count $choices) -eq 1
        print_info "Only one worktree, selecting: $choices[1]"
        cd $choices[1]; and command lazygit $argv
        return
    end

    print_info "Multiple worktrees found, opening picker..."
    if set -q TMUX
        set -l pane_id (tmux display-message -p -F "#{pane_id}")
        tmux set-option -t $pane_id -p @disable_vertical_pane_navigation yes
    end
    set -l branches
    for wt in $choices
        set -l branch (git -C $wt rev-parse --abbrev-ref HEAD 2>/dev/null; or echo "detached")
        set branches $branches $branch
    end
    set -lx FZF_DEFAULT_OPTS "--height 40% --reverse --bind=ctrl-z:ignore $FZF_DEFAULT_OPTS"
    set -l selected (printf '%s\n' $branches | fzf --prompt="Select worktree> ")
    if test -n "$selected"
        # Find the matching worktree path
        set -l idx (contains -i -- $selected $branches)
        set -l worktree_path $choices[$idx]
        print_info "Selected worktree: $worktree_path"
        cd $worktree_path; and command lazygit $argv
    else
        print_warn "No worktree selected, aborting"
    end
    if set -q TMUX
        tmux set-option -t $pane_id -p -u @disable_vertical_pane_navigation
    end
end
