; extends

; add link highlights to standalone links
((inline) @markup.link.url
  (#lua-match? @markup.link.url "^https://[^%s]+$"))
