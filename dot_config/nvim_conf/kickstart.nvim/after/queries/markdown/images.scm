; extends

((paragraph
  (inline) @image.src)
  (#lua-match? @image.src "^https://[./a-z0-9%-]+$"))
