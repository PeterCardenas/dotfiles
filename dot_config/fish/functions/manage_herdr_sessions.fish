function manage_herdr_sessions -d "Navigate Herdr workspaces"
    set -l workspace_json (command herdr workspace list); or return 1
    set -l server_log ~/.config/herdr/herdr-server.log
    test -r "$server_log"; or set server_log /dev/null
    set -l rows
    set -l name_width 0

    for row in (jq -R -n -r --argjson workspace_data "$workspace_json" '
        ([inputs | select(contains("workspace focused")) | capture("workspace focused[^\n]*workspace_id=\"(?<id>[^\"]+)\"")? | .id]
            | to_entries | reduce .[] as $entry ({}; .[$entry.value] = $entry.key)) as $recent
        | $workspace_data.result.workspaces as $workspaces
        | $workspaces
        | sort_by(-($recent[.workspace_id] // -1), .number)
        | .[]
        | select(.focused != true)
        | . as $workspace
        | select(.worktree.is_linked_worktree != false or .worktree.repo_key == null or
            (any($workspaces[]; .worktree.repo_key == $workspace.worktree.repo_key and .worktree.is_linked_worktree == true) | not))
        | [.workspace_id, .label, .agent_status]
        | @tsv
    ' "$server_log")
        set -l fields (string split \t -- "$row")
        set -l color 169 177 214
        switch $fields[3]
            case working; set color 158 206 106
            case blocked; set color 224 175 104
            case idle done; set color 247 118 142
        end
        set -l width (string length --visible -- "$fields[2]")
        if test "$width" -gt "$name_width"
            set name_width $width
        end
        set -l display (printf '\e[38;2;%s;%s;%sm%s\e[0m' $color "$fields[2]")
        set -a rows (printf '%s\t%s' "$fields[1]" "$display")
    end

    set -l preview_percent 60
    set -l columns (tput cols 2>/dev/null)
    if string match -qr '^[1-9][0-9]*$' -- "$columns"
        # Keep fzf's row marker and padding outside the label, and reserve at least 60% for the preview.
        set preview_percent (math "max(60, min(99, floor(100 * ($columns - $name_width - 5) / $columns)))")
    end

    set -l selection (printf '%s\n' $rows | fzf --ansi --cycle --wrap=word --layout=reverse --delimiter='\t' --with-nth=2 --preview-window="right,$preview_percent%,border-left,nowrap,follow,<65(down,50%,border-top)" --preview-label=' Preview ' --preview 'preview_herdr_target workspace {1}')
    test -n "$selection"; or return

    set -l fields (string split \t -- "$selection")
    command herdr workspace focus "$fields[1]"
end
