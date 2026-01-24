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
  argument: (single_quote_string) @injection.content
  ; remove when following issue is resolved: https://github.com/ram02z/tree-sitter-fish/issues/31
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.language "jq"))
