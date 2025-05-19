; extends

; force render markdown links
((text) @injection.content
  (#lua-match? @injection.content "^!%[.*%]%(.*%)$")
  (#set! injection.language "markdown"))
