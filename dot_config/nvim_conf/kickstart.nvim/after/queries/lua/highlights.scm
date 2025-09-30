; extends

; still add regex highlight when concatenating, only does one level though
(function_call
  (method_index_expression
    method: (identifier) @_method
    (#any-of? @_method "find" "match" "gmatch" "gsub"))
  arguments: (arguments
    .
    (binary_expression
      left: (string
        content: (string_content) @string.regexp)?
      right: (string
        content: (string_content) @string.regexp)?)))
