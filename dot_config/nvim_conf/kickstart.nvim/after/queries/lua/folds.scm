; extends

; TODO: Doesn't work when comments come before the block.
(if_statement
  consequence: (block) @fold
  (#offset! @fold -1 0 0 0))

(if_statement
  alternative: (elseif_statement) @fold)

(if_statement
  alternative: (else_statement) @fold)
