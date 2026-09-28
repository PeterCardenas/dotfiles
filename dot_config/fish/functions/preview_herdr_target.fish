function preview_herdr_target -d "Preview a Herdr space or agent" -a kind target
    switch $kind
        case workspace
            set target (command herdr pane list --workspace "$target" | jq -r '([.result.panes[] | select(.focused)][0] // .result.panes[0]).pane_id // empty')
        case agent
        case '*'
            return 1
    end

    test -n "$target"; or return
    command herdr pane read "$target" --source recent --lines 200 --format ansi
end
