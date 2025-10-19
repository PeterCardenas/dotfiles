; extends

; still add regex highlight when concatenating, currently handling two concatenations
(function_call
  (method_index_expression
    method: (identifier) @_method
    (#any-of? @_method "find" "match" "gmatch" "gsub"))
  arguments: (arguments
    .
    (binary_expression
      left: (string
        content: (string_content) @injection.content
        (#set! injection.language "luap")
        (#set! injection.include-children))?
      right: (string
        content: (string_content) @injection.content
        (#set! injection.language "luap")
        (#set! injection.include-children))?)))

(function_call
  (method_index_expression
    method: (identifier) @_method
    (#any-of? @_method "find" "match" "gmatch" "gsub"))
  arguments: (arguments
    .
    (binary_expression
      left: (string
        content: (string_content) @injection.content
        (#set! injection.language "luap")
        (#set! injection.include-children))?
      right: (binary_expression
        left: (string
          content: (string_content) @injection.content
          (#set! injection.language "luap")
          (#set! injection.include-children))?
        right: (string
          content: (string_content) @injection.content
          (#set! injection.language "luap")
          (#set! injection.include-children))))))
