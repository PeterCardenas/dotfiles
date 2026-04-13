; extends

(command
  name: (word) @_cmd
  (#eq? @_cmd "gh")
  .
  argument: (word) @_api_arg
  (#eq? @_api_arg "api")
  .
  argument: (word) @_graphql_arg
  (#eq? @_graphql_arg "graphql")
  argument: (word) @_field_query_flag
  (#eq? @_field_query_flag "-f")
  .
  argument: (concatenation
    (word) @_query_flag
    (#eq? @_query_flag "query=")
    .
    (single_quote_string) @injection.content
    ; remove when following issue is resolved: https://github.com/ram02z/tree-sitter-fish/issues/31
    (#offset! @injection.content 0 1 0 -1)
    (#set! injection.language "graphql")))

(command
  name: (word) @_cmd
  (#eq? @_cmd "gh")
  argument: (word) @_field_query_flag
  (#eq? @_field_query_flag "--jq")
  .
  argument: (single_quote_string) @injection.content
  ; remove and merge with below when following issue is resolved: https://github.com/ram02z/tree-sitter-fish/issues/31
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.language "jq"))

(command
  name: (word) @_cmd
  (#eq? @_cmd "gh")
  argument: (word) @_field_query_flag
  (#eq? @_field_query_flag "--jq")
  .
  argument: (word) @injection.content
  (#set! injection.language "jq"))

; TODO: figure out a way to deduplicate from above
(command
  name: (word) @_cmd
  (#eq? @_cmd "command")
  .
  argument: (word) @_gh_arg
  (#eq? @_gh_arg "gh")
  .
  argument: (word) @_api_arg
  (#eq? @_api_arg "api")
  .
  argument: (word) @_graphql_arg
  (#eq? @_graphql_arg "graphql")
  argument: (word) @_field_query_flag
  (#eq? @_field_query_flag "-f")
  .
  argument: (concatenation
    (word) @_query_flag
    (#eq? @_query_flag "query=")
    .
    (single_quote_string) @injection.content
    ; remove when following issue is resolved: https://github.com/ram02z/tree-sitter-fish/issues/31
    (#offset! @injection.content 0 1 0 -1)
    (#set! injection.language "graphql")))

(command
  name: (word) @_cmd
  (#eq? @_cmd "command")
  .
  argument: (word) @_gh_arg
  (#eq? @_gh_arg "gh")
  argument: (word) @_field_query_flag
  (#eq? @_field_query_flag "--jq")
  .
  argument: (single_quote_string) @injection.content
  ; remove when following issue is resolved: https://github.com/ram02z/tree-sitter-fish/issues/31
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.language "jq"))

(command
  name: (word) @_cmd
  (#eq? @_cmd "jq")
  argument: [
    (single_quote_string)
    (double_quote_string)
  ] @injection.content
  ; remove when following issue is resolved: https://github.com/ram02z/tree-sitter-fish/issues/31
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.language "jq"))

; jq [flags/args] 'expression' (after any word argument)
(command
  name: (word) @_cmd
  (#eq? @_cmd "jq")
  argument: (word) @_word
  .
  argument: [
    (single_quote_string)
    (double_quote_string)
  ] @injection.content
  ; remove when following issue is resolved: https://github.com/ram02z/tree-sitter-fish/issues/31
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.language "jq"))

; grep/egrep/rg/ag 'pattern' (pattern as first argument)
(command
  name: (word) @_cmd
  (#any-of? @_cmd "grep" "egrep" "rg" "ag")
  .
  argument: [
    (single_quote_string)
    (double_quote_string)
  ] @injection.content
  ; remove when following issue is resolved: https://github.com/ram02z/tree-sitter-fish/issues/31
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.language "regex"))

; grep/egrep/rg/ag [flags] 'pattern' (pattern after flags)
(command
  name: (word) @_cmd
  (#any-of? @_cmd "grep" "egrep" "rg" "ag")
  argument: (word) @_flag
  (#match? @_flag "^-")
  .
  argument: [
    (single_quote_string)
    (double_quote_string)
  ] @injection.content
  ; remove when following issue is resolved: https://github.com/ram02z/tree-sitter-fish/issues/31
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.language "regex"))

; string match/replace -r 'pattern' (short flag with r directly before pattern)
(command
  name: (word) @_cmd
  (#eq? @_cmd "string")
  argument: (word) @_flag
  (#match? @_flag "^-[^-]*r")
  .
  argument: [
    (single_quote_string)
    (double_quote_string)
  ] @injection.content
  ; remove when following issue is resolved: https://github.com/ram02z/tree-sitter-fish/issues/31
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.language "regex"))

; string match/replace --regex 'pattern'
(command
  name: (word) @_cmd
  (#eq? @_cmd "string")
  argument: (word) @_flag
  (#eq? @_flag "--regex")
  .
  argument: [
    (single_quote_string)
    (double_quote_string)
  ] @injection.content
  ; remove when following issue is resolved: https://github.com/ram02z/tree-sitter-fish/issues/31
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.language "regex"))

; string match/replace -r ... -X 'pattern' (short regex flag not directly before pattern)
(command
  name: (word) @_cmd
  (#eq? @_cmd "string")
  argument: (word) @_rflag
  (#match? @_rflag "^-[^-]*r")
  argument: (word) @_other
  (#match? @_other "^-")
  .
  argument: [
    (single_quote_string)
    (double_quote_string)
  ] @injection.content
  ; remove when following issue is resolved: https://github.com/ram02z/tree-sitter-fish/issues/31
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.language "regex"))

; string match/replace --regex ... -X 'pattern' (long regex flag not directly before pattern)
(command
  name: (word) @_cmd
  (#eq? @_cmd "string")
  argument: (word) @_rflag
  (#eq? @_rflag "--regex")
  argument: (word) @_other
  (#match? @_other "^-")
  .
  argument: [
    (single_quote_string)
    (double_quote_string)
  ] @injection.content
  ; remove when following issue is resolved: https://github.com/ram02z/tree-sitter-fish/issues/31
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.language "regex"))

; find -regex/-iregex 'pattern'
(command
  name: (word) @_cmd
  (#eq? @_cmd "find")
  argument: (word) @_flag
  (#any-of? @_flag "-regex" "-iregex")
  .
  argument: [
    (single_quote_string)
    (double_quote_string)
  ] @injection.content
  ; remove when following issue is resolved: https://github.com/ram02z/tree-sitter-fish/issues/31
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.language "regex"))

; tmux shell command — directly after subcommand (e.g., tmux run-shell 'cmd')
(command
  name: (word) @_cmd
  (#eq? @_cmd "tmux")
  argument: (word) @_subcmd
  (#any-of? @_subcmd "new-session" "new-window" "split-window" "respawn-window"
    "respawn-pane" "display-popup" "run-shell" "if-shell" "pipe-pane"
    "neww" "splitw" "popup" "run")
  .
  argument: [
    (single_quote_string)
    (double_quote_string)
  ] @injection.content
  ; remove when following issue is resolved: https://github.com/ram02z/tree-sitter-fish/issues/31
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.language "bash"))

; tmux shell command — after flags (e.g., tmux new-session -d -s name 'cmd')
(command
  name: (word) @_cmd
  (#eq? @_cmd "tmux")
  argument: (word) @_subcmd
  (#any-of? @_subcmd "new-session" "new-window" "split-window" "respawn-window"
    "respawn-pane" "display-popup" "run-shell" "if-shell" "pipe-pane"
    "neww" "splitw" "popup" "run")
  argument: (_) @_arg
  .
  argument: [
    (single_quote_string)
    (double_quote_string)
  ] @injection.content
  ; remove when following issue is resolved: https://github.com/ram02z/tree-sitter-fish/issues/31
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.language "bash"))

; nvim/vim -c 'command' (directly after -c flag)
(command
  name: (word) @_cmd
  (#any-of? @_cmd "nvim" "vim")
  argument: (word) @_flag
  (#eq? @_flag "-c")
  .
  argument: [
    (single_quote_string)
    (double_quote_string)
  ] @injection.content
  ; remove when following issue is resolved: https://github.com/ram02z/tree-sitter-fish/issues/31
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.language "vim"))

; nvim/vim [flags] -c 'command' (-c after other flags)
(command
  name: (word) @_cmd
  (#any-of? @_cmd "nvim" "vim")
  argument: (word) @_other
  (#match? @_other "^-")
  argument: (word) @_flag
  (#eq? @_flag "-c")
  .
  argument: [
    (single_quote_string)
    (double_quote_string)
  ] @injection.content
  ; remove when following issue is resolved: https://github.com/ram02z/tree-sitter-fish/issues/31
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.language "vim"))

; nvim/vim '+command' (first argument)
(command
  name: (word) @_cmd
  (#any-of? @_cmd "nvim" "vim")
  .
  argument: (single_quote_string) @injection.content
  (#match? @injection.content "^'+")
  ; remove when following issue is resolved: https://github.com/ram02z/tree-sitter-fish/issues/31
  (#offset! @injection.content 0 2 0 -1)
  (#set! injection.language "vim"))

; nvim/vim [flags] '+command' (after flags)
(command
  name: (word) @_cmd
  (#any-of? @_cmd "nvim" "vim")
  argument: (word) @_flag
  (#match? @_flag "^-")
  .
  argument: (single_quote_string) @injection.content
  (#match? @injection.content "^'+")
  ; remove when following issue is resolved: https://github.com/ram02z/tree-sitter-fish/issues/31
  (#offset! @injection.content 0 2 0 -1)
  (#set! injection.language "vim"))
