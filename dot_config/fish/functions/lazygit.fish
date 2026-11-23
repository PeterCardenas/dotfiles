function lazygit --wraps lazygit
    set -l worktrees
    set -l excluded
    set -l stol_project (stol_project_dir "$PWD" 2>/dev/null)
    if test -n "$stol_project"; and test "$stol_project" = (path resolve -- "$PWD")
        # A stol project dir is not a checkout; skip .repo and the 00-* templates stol reflinks from.
        print_info "stol project detected, discovering worktrees..."
        set worktrees (git -C .repo worktree list --porcelain | string replace --filter --regex '^worktree ' '')
        set excluded "$stol_project/.repo" "$stol_project"/00-*
    else
        git rev-parse --is-inside-work-tree 2>/dev/null | read -l inside_worktree
        set -l git_status $pipestatus[1]

        if test $git_status -ne 0
            command lazygit $argv
            return
        end

        if test "$inside_worktree" = true
            command lazygit $argv
            return
        end

        # We're in a bare repo — list worktrees and let the user pick one
        print_info "Bare repo detected, discovering worktrees..."
        set worktrees (git worktree list --porcelain | string replace --filter --regex '^worktree ' '')

        # Filter out the bare repo root itself
        set -l bare_dir (git rev-parse --git-dir)
        print_info "Bare repo root: $bare_dir"
        set excluded $bare_dir
    end
    set -l choices
    for wt in $worktrees
        if not contains -- "$wt" $excluded
            print_info "Found worktree: $wt"
            set choices $choices $wt
        end
    end

    if test (count $choices) -eq 0
        print_error "No worktrees found."
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
    set -l dirs
    set -l max_len 0
    for i in (seq (count $choices))
        set -l wt $choices[$i]
        set -l branch (git -C $wt rev-parse --abbrev-ref HEAD 2>/dev/null; or echo "detached")
        set -l dir (basename $wt)
        set branches $branches $branch
        set dirs $dirs $dir
        if test (string length $branch) -gt $max_len
            set max_len (string length $branch)
        end
    end
    set -l entries
    for i in (seq (count $choices))
        set entries $entries (printf "%-"$max_len"s  %s" $branches[$i] $dirs[$i])
    end
    set -lx FZF_DEFAULT_OPTS "--height 40% --reverse --bind=ctrl-z:ignore $FZF_DEFAULT_OPTS"
    set -l selected (printf '%s\n' $entries | fzf --prompt="Select worktree> ")
    if test -n "$selected"
        # Extract branch from selection, find matching index
        set -l idx (contains -i -- $selected $entries)
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
