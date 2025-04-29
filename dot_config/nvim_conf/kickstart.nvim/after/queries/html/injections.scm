; extends

((text) @injection.content
  (#lua-match? @injection.content "^!%[.*%]%(.*%)$")
  (#set! injection.language "markdown"))
