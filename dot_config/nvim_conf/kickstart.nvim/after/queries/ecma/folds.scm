; extends

(if_statement
  consequence: (statement_block) @fold
  (#offset! @fold 0 0 -1 0))

(if_statement
  alternative: (else_clause) @fold
  (#offset! @fold 0 0 -1 0))
