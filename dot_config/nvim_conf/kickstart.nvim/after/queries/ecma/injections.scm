; extends

; highlight graphql strings as graphql
((comment) @_graphql-marker
  (#lua-match? @_graphql-marker "^/%*%s*GraphQL%s*%*/$")
  (#set! injection.language "graphql")
  (template_string
    (string_fragment) @injection.content))
