; extends

(if_statement
  condition: (_) @fold
  consequence: (block) @fold)

(if_statement
  alternative: (elseif_statement) @fold)

(if_statement
  alternative: (else_statement) @fold)
