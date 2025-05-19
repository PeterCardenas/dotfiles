; extends

; add conceal line to comments when they are the only thing on the line
((comment) @conceal
  (#lua-match? @conceal "<!%-%-[^-<!>]*%-%->")
  (#set! conceal ""))
