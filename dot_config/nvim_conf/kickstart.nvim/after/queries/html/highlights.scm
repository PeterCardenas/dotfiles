; extends

; conceal comments for octo.nvim
; TODO: Add a custom directive to check if the comment is the only content on the line, in which case a conceal_line is used.
((comment) @conceal
  (#set! conceal ""))
