; Hack to prevent above from highlighting command arguments as strings
; TODO: Remove when the following issue is resolved https://github.com/ram02z/tree-sitter-fish/issues/31
(double_quote_string
  (command_substitution) @variable)
