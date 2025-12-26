; extends

(command
  name: (word) @_cmd
  (#eq? @_cmd "gh")
  argument: (word) @_api_arg
  (#eq? @_api_arg "api")
  argument: (word) @_graphql_arg
  (#eq? @_graphql_arg "graphql")
  argument: (word) @_field_query_flag
  (#eq? @_field_query_flag "-f")
  argument: (concatenation
    (word) @_query_flag
    (#eq? @_query_flag "query=")
    (single_quote_string) @injection.content
    (#set! injection.language "graphql")))
