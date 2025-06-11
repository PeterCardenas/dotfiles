; extends

(if_statement
  consequence: (block) @fold
  (#offset! @fold -1 0 0 0))

(if_statement
  alternative: (elif_clause) @fold)

(if_statement
  alternative: (else_clause) @fold)
